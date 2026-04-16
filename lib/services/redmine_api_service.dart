import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import '../models/monitored_query.dart';

class RedmineApiService {
  static const String _proxyBaseUrl = String.fromEnvironment(
    'REDMINE_PROXY_URL',
    defaultValue: 'http://localhost:4311',
  );

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
        'Resposta nao esta em JSON. Verifique se a consulta aponta para /issues.json e se a API key esta valida.',
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
      'Nao foi possivel ler contagem em "${query.countPath}" para ${query.name}',
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
      );

      if (response.statusCode >= 500) {
        throw RetryableRequestException('Servidor Redmine retornou ${response.statusCode}.');
      }
      return response;
    } on http.ClientException catch (error) {
      throw RetryableRequestException(
        kIsWeb
            ? 'Falha de rede no proxy (${error.message}). Verifique se o proxy local esta rodando em $_proxyBaseUrl.'
            : 'Falha de rede ao consultar Redmine (${error.message}).',
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
    return http.post(
      proxyUri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'url': targetUri.toString(),
        'apiKey': apiKey,
      }),
    );
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
  });

  final int count;
  final Uri uri;
  final int durationMs;
  final int statusCode;
}

class RetryableRequestException implements Exception {
  RetryableRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
