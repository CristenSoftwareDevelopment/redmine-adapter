import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/monitored_query.dart';

class RedmineApiService {
  static const Duration _requestTimeout = Duration(seconds: 60);
  static const String _proxyBaseUrl = String.fromEnvironment(
    'REDMINE_PROXY_URL',
    defaultValue: 'http://localhost:4311',
  );

  /// Absolute URL for a Redmine path (keeps already-absolute URLs).
  static String absoluteUrl(String baseUrl, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base${path.startsWith('/') ? path : '/$path'}';
  }

  /// Fetches the current user's full name from GET /my/account.json.
  /// Throws an [Exception] if the credentials are invalid or the request fails.
  Future<String> fetchAccountName({
    required String baseUrl,
    required String apiKey,
  }) async {
    final uri = Uri.parse(absoluteUrl(baseUrl, '/my/account.json'));

    late http.Response response;
    try {
      response = await _send(apiKey, uri);
    } on RetryableRequestException catch (e) {
      throw Exception('Falha de rede: ${e.message}');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Credenciais inválidas (HTTP ${response.statusCode}).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Erro ao conectar ao Redmine (HTTP ${response.statusCode}).');
    }

    final dynamic decoded = jsonDecode(response.body);
    final user = decoded['user'];
    if (user == null) throw Exception('Resposta inesperada do Redmine.');

    final firstname = user['firstname'] as String? ?? '';
    final lastname = user['lastname'] as String? ?? '';
    final fullName = '$firstname $lastname'.trim();
    if (fullName.isEmpty) throw Exception('Nome de usuário não encontrado.');
    return fullName;
  }

  /// GET [pathAndQuery] (relative to the configured base URL) and decode JSON.
  Future<dynamic> getJson(AppSettings settings, String pathAndQuery) async {
    final response = await _send(
      settings.apiKey,
      Uri.parse(absoluteUrl(settings.baseUrl, pathAndQuery)),
    );
    _ensureOk(response);
    return jsonDecode(response.body);
  }

  /// PUT a JSON [body] to [path]. Redmine answers 204 on success, 422 with
  /// `errors` on validation failure.
  Future<void> putJson(
    AppSettings settings,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      settings.apiKey,
      Uri.parse(absoluteUrl(settings.baseUrl, path)),
      method: 'PUT',
      body: body,
    );
    _ensureOk(response);
  }

  /// Fetches every page of a paginated collection ([key] is the JSON list key,
  /// e.g. `issues`, `time_entries`).
  // ponytail: capped at [cap] items; raise it if boards/reports need more.
  Future<List<Map<String, dynamic>>> getAllPages(
    AppSettings settings,
    String pathAndQuery,
    String key, {
    int cap = 500,
  }) async {
    final items = <Map<String, dynamic>>[];
    while (items.length < cap) {
      final page = await getJson(
        settings,
        withParams(Uri.parse(pathAndQuery), {
          'limit': '100',
          'offset': '${items.length}',
        }).toString(),
      );
      final batch = (page[key] as List? ?? const []).cast<Map<String, dynamic>>();
      items.addAll(batch);
      final total = page['total_count'] as int? ?? items.length;
      if (batch.isEmpty || items.length >= total) break;
    }
    return items;
  }

  /// Saved issue queries visible to the user, labelled with their project.
  Future<List<SavedQuery>> listSavedQueries(AppSettings settings) async {
    final [queries, projects] = await Future.wait([
      getAllPages(settings, '/queries.json', 'queries'),
      getAllPages(settings, '/projects.json', 'projects', cap: 2000),
    ]);
    final projectNames = {
      for (final p in projects) p['id'] as int: p['name'] as String,
    };
    return [
      for (final q in queries)
        SavedQuery(
          id: q['id'] as int,
          name: q['name'] as String,
          projectId: q['project_id'] as int?,
          projectName: projectNames[q['project_id']],
          isPublic: q['is_public'] == true,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 422) {
      Object? errors;
      try {
        errors = jsonDecode(response.body)['errors'];
      } catch (_) {}
      if (errors is List) throw Exception(errors.join('; '));
    }
    final body = response.body;
    final extra =
        body.isEmpty ? '' : ' - ${body.length > 160 ? '${body.substring(0, 160)}...' : body}';
    throw Exception('HTTP ${response.statusCode}$extra');
  }

  Future<FetchCountResult> fetchCountDetailed({
    required AppSettings settings,
    required MonitoredQuery query,
  }) async {
    final uri = _buildUri(
      baseUrl: settings.baseUrl,
      endpoint: query.endpoint,
    );

    const maxAttempts = 3;
    Object? lastError;
    late int durationMs;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final stopwatch = Stopwatch()..start();
      try {
        final response = await _send(settings.apiKey, uri);
        durationMs = stopwatch.elapsedMilliseconds;
        final count = _parseCount(response: response, query: query);
        return FetchCountResult(
          count: count,
          uri: uri,
          durationMs: durationMs,
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } on RetryableRequestException catch (error) {
        lastError = error;
        if (attempt == maxAttempts) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      } on Exception catch (error) {
        lastError = error;
        break;
      } finally {
        stopwatch.stop();
      }
    }

    throw Exception('Falha ao consultar ${query.name}: $lastError');
  }

  int _parseCount({
    required http.Response response,
    required MonitoredQuery query,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body;
      final extra =
          body.isEmpty ? '' : ' - ${body.length > 160 ? '${body.substring(0, 160)}...' : body}';
      throw Exception('HTTP ${response.statusCode} ao consultar ${query.name}$extra');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'Resposta não está em JSON. Verifique se a consulta aponta para /issues.json e se a API key está válida.',
      );
    }
    final value = _readPath(decoded, query.countPath);

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    throw Exception(
      'Não foi possível ler contagem em "${query.countPath}" para ${query.name}',
    );
  }

  /// Single HTTP entry point: web goes through the local CORS proxy,
  /// desktop/mobile hit Redmine directly. 5xx and network failures throw
  /// [RetryableRequestException].
  Future<http.Response> _send(
    String apiKey,
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    try {
      final http.Response response;
      if (kIsWeb) {
        response = await http
            .post(
              Uri.parse('$_proxyBaseUrl/redmine-proxy/fetch'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'url': uri.toString(),
                'apiKey': apiKey,
                'method': method,
                if (body != null) 'body': body,
              }),
            )
            .timeout(_requestTimeout);
      } else {
        final headers = {
          'Accept': 'application/json',
          'X-Redmine-API-Key': apiKey,
        };
        response = await (method == 'PUT'
                ? http.put(
                    uri,
                    headers: {...headers, 'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  )
                : http.get(uri, headers: headers))
            .timeout(_requestTimeout);
      }

      if (response.statusCode >= 500) {
        throw RetryableRequestException(
          kIsWeb
              ? 'Proxy retornou ${response.statusCode}.'
              : 'Servidor Redmine retornou ${response.statusCode}.',
        );
      }
      return response;
    } on http.ClientException catch (error) {
      throw RetryableRequestException(
        kIsWeb
            ? 'Falha de rede no proxy (${error.message}). Verifique se o proxy local está rodando em $_proxyBaseUrl.'
            : 'Falha de rede ao consultar Redmine: ${_describeNetworkError(uri: uri, message: error.message)}',
      );
    } on TimeoutException {
      throw RetryableRequestException('Timeout ao consultar Redmine.');
    }
  }

  Uri _buildUri({
    required String baseUrl,
    required String endpoint,
  }) {
    final uri = Uri.parse(absoluteUrl(baseUrl, endpoint));
    final withLimit =
        uri.queryParameters.containsKey('limit') ? uri : withParams(uri, {'limit': '1'});
    return withLimit.replace(path: _ensureJsonPath(uri.path));
  }

  /// Sets [params] on [uri] keeping repeated keys (`f[]=a&f[]=b`) intact —
  /// `Uri.queryParameters` would keep only the last one.
  @visibleForTesting
  static Uri withParams(Uri uri, Map<String, String> params) {
    return uri.replace(queryParameters: {
      ...uri.queryParametersAll,
      for (final e in params.entries) e.key: [e.value],
    });
  }

  String _describeNetworkError({
    required Uri uri,
    required String message,
  }) {
    final normalizedMessage = message.toLowerCase();
    if (normalizedMessage.contains('failed host lookup') ||
        normalizedMessage.contains('could not resolve host') ||
        normalizedMessage.contains('name or service not known') ||
        normalizedMessage.contains('nodename nor servname provided')) {
      return 'não foi possível resolver o host "${uri.host}". Verifique a URL informada e, se necessário, sua VPN ou DNS.';
    }
    if (normalizedMessage.contains('semaforo expirou') ||
        normalizedMessage.contains('semáforo expirou')) {
      return 'não foi possível alcançar "${uri.host}". Verifique a URL, VPN, firewall ou se o servidor está acessível nesta rede.';
    }
    if (normalizedMessage.contains('connection refused')) {
      return 'conexão recusada por "${uri.host}". Verifique se o servidor está online e aceitando HTTPS.';
    }
    if (normalizedMessage.contains('handshake') ||
        normalizedMessage.contains('certificate') ||
        normalizedMessage.contains('certificado') ||
        normalizedMessage.contains('ssl') ||
        normalizedMessage.contains('tls')) {
      return 'falha de TLS/certificado ao acessar "${uri.host}". Verifique certificado HTTPS, inspeção SSL do antivírus/proxy corporativo ou relógio do Windows.';
    }
    if (normalizedMessage.contains('network is unreachable') ||
        normalizedMessage.contains('no route to host') ||
        normalizedMessage.contains('unreachable')) {
      return 'sem rota de rede até "${uri.host}". Verifique conexão, VPN, proxy corporativo ou firewall do Windows.';
    }
    if (normalizedMessage.contains('connection reset') ||
        normalizedMessage.contains('forcibly closed') ||
        normalizedMessage.contains('software caused connection abort')) {
      return 'a conexão com "${uri.host}" foi encerrada durante a requisição. Isso pode indicar proxy, antivírus, firewall ou TLS incompatível.';
    }
    if (normalizedMessage.contains('proxy')) {
      return 'houve falha de proxy ao acessar "${uri.host}". Verifique as configurações de proxy do Windows ou da rede corporativa.';
    }
    return '$message (${uri.host})';
  }

  String _ensureJsonPath(String path) {
    if (path.endsWith('.json')) {
      return path;
    }
    if (path.endsWith('/')) {
      return '${path.substring(0, path.length - 1)}.json';
    }
    return '$path.json';
  }

  dynamic _readPath(dynamic source, String path) {
    dynamic current = source;

    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic>) {
        current = current[segment];
      } else {
        return null;
      }
    }

    return current;
  }
}

class SavedQuery {
  SavedQuery({
    required this.id,
    required this.name,
    this.projectId,
    this.projectName,
    this.isPublic = false,
  });

  final int id;
  final String name;
  final int? projectId;
  final String? projectName;
  final bool isPublic;

  String get label => projectName == null ? name : '$projectName › $name';

  String get _issuesPath => projectId == null ? '/issues' : '/projects/$projectId/issues';
  String get endpoint => '$_issuesPath.json?query_id=$id';
  String get directUrl => '$_issuesPath?query_id=$id';

  /// `query_id` of a stored endpoint, or null for filter-only URLs.
  static int? idFromEndpoint(String? endpoint) =>
      int.tryParse(Uri.tryParse(endpoint ?? '')?.queryParameters['query_id'] ?? '');
}

class FetchCountResult {
  FetchCountResult({
    required this.count,
    required this.uri,
    required this.durationMs,
    required this.statusCode,
    required this.responseBody,
  });

  final int count;
  final Uri uri;
  final int durationMs;
  final int statusCode;
  final String responseBody;
}

class RetryableRequestException implements Exception {
  RetryableRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
