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

  /// Fetches the current user's full name from GET /my/account.json.
  /// Throws an [Exception] if the credentials are invalid or the request fails.
  Future<String> fetchAccountName({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalizedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$normalizedBase/my/account.json');

    late http.Response response;
    try {
      if (kIsWeb) {
        response = await _fetchViaProxy(uri, apiKey);
      } else {
        response = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'X-Redmine-API-Key': apiKey,
          },
        ).timeout(_requestTimeout);
      }
    } on http.ClientException catch (e) {
      throw Exception(
        'Falha de rede: ${_describeNetworkError(uri: uri, message: e.message)}',
      );
    } on TimeoutException {
      throw Exception(
        'Falha de rede: tempo limite ao acessar ${uri.host}. Verifique a URL e sua conexão.',
      );
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

  Future<int> fetchCount({
    required AppSettings settings,
    required MonitoredQuery query,
  }) async {
    final result = await fetchCountDetailed(settings: settings, query: query);
    return result.count;
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
        final response = await _request(settings: settings, uri: uri);
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
      final extra = body.isEmpty ? '' : ' - ${body.length > 160 ? '${body.substring(0, 160)}...' : body}';
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

  Future<http.Response> _request({
    required AppSettings settings,
    required Uri uri,
  }) async {
    try {
      if (kIsWeb) {
        final response = await _fetchViaProxy(uri, settings.apiKey);
        if (response.statusCode >= 500) {
          throw RetryableRequestException('Proxy retornou ${response.statusCode}.');
        }
        return response;
      }

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'X-Redmine-API-Key': settings.apiKey,
        },
      ).timeout(_requestTimeout);

      if (response.statusCode >= 500) {
        throw RetryableRequestException('Servidor Redmine retornou ${response.statusCode}.');
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
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    Uri uri;
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      uri = Uri.parse(endpoint);
    } else {
      final normalizedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
      uri = Uri.parse('$normalizedBase$normalizedEndpoint');
    }

    final queryParameters = <String, String>{...uri.queryParameters};
    queryParameters.putIfAbsent('limit', () => '1');

    return uri.replace(
      path: _ensureJsonPath(uri.path),
      queryParameters: queryParameters,
    );
  }

  Future<http.Response> _fetchViaProxy(Uri targetUri, String apiKey) async {
    final proxyUri = Uri.parse('$_proxyBaseUrl/redmine-proxy/fetch');
    return http
        .post(
          proxyUri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'url': targetUri.toString(),
            'apiKey': apiKey,
          }),
        )
        .timeout(_requestTimeout);
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
