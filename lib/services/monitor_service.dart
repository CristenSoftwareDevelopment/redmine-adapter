import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';

import '../models/alert_event.dart';
import '../models/app_settings.dart';
import '../models/monitored_query.dart';
import 'database_service.dart';
import 'redmine_api_service.dart';

typedef AlertCallback = void Function(AlertEvent alert);
typedef QueryUpdateCallback = void Function();

class MonitorService {
  MonitorService({
    required this.databaseService,
    required this.redmineApiService,
    required AlertCallback onAlert,
    required QueryUpdateCallback onQueryUpdate,
  })  : _onAlert = onAlert,
        _onQueryUpdate = onQueryUpdate;

  final DatabaseService databaseService;
  final RedmineApiService redmineApiService;
  AlertCallback _onAlert;
  QueryUpdateCallback _onQueryUpdate;

  set onAlert(AlertCallback callback) {
    _onAlert = callback;
  }

  set onQueryUpdate(QueryUpdateCallback callback) {
    _onQueryUpdate = callback;
  }

  final Map<int, Timer> _timers = {};
  final Map<int, int?> _lastCounts = {};
  final Map<int, DateTime> _lastAlertAt = {};
  final Set<int> _running = HashSet<int>();
  final Set<int> _missingConfigLogged = {};
  Timer? _pruneTimer;

  static const _pruneInterval = Duration(minutes: 30);

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> start() async {
    await databaseService.pruneMonitorLogs();

    final settings = await databaseService.loadSettings();
    final queries = await databaseService.listQueries();
    final alerts = await databaseService.listAlerts(limit: 300);
    final enabledQueries = queries.where((q) => q.enabled && q.id != null).toList();
    _lastAlertAt
      ..clear()
      ..addEntries(alerts.map((a) => MapEntry(a.queryId, a.createdAt)));
    _missingConfigLogged.clear();
    await _log(
      level: 'info',
      message: 'Monitoracao iniciada com ${enabledQueries.length} consulta(s) ativa(s).',
    );

    _pruneTimer = Timer.periodic(_pruneInterval, (_) async {
      await databaseService.pruneMonitorLogs();
      _onQueryUpdate();
    });

    for (final query in enabledQueries) {
      _lastCounts[query.id!] = query.lastCount;
      final pollSeconds = query.pollSeconds ?? settings.defaultPollSeconds;
      final safeSeconds = pollSeconds < 10 ? 10 : pollSeconds;
      _timers[query.id!] = Timer.periodic(
        Duration(seconds: safeSeconds),
        (_) => _checkQuery(settings, query, source: 'timer'),
      );

      unawaited(_checkQuery(settings, query, source: 'startup'));
    }
  }

  Future<void> stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _lastCounts.clear();
    _lastAlertAt.clear();
    _running.clear();
    _missingConfigLogged.clear();
    await _log(level: 'info', message: 'Monitoracao parada.');
  }

  Future<void> runQueryNow(int queryId) async {
    final settings = await databaseService.loadSettings();
    final queries = await databaseService.listQueries();
    MonitoredQuery? query;
    for (final item in queries) {
      if (item.id == queryId) {
        query = item;
        break;
      }
    }

    if (query == null) {
      await _log(level: 'warn', message: 'Consulta nao encontrada para execucao manual.');
      return;
    }

    await _checkQuery(settings, query, source: 'manual');
  }

  Future<void> _checkQuery(
    AppSettings settings,
    MonitoredQuery query, {
    required String source,
  }) async {
    final queryId = query.id;
    if (queryId == null || _running.contains(queryId)) {
      return;
    }

    // Schedule restriction check
    if (!settings.isWithinSchedule(DateTime.now().hour)) {
      await _log(
        level: 'info',
        message: 'Fora do horario configurado (${settings.monitorStartHour}h–${settings.monitorEndHour}h). Consulta ignorada.',
        queryName: query.name,
      );
      return;
    }

    if (settings.baseUrl.trim().isEmpty || settings.apiKey.trim().isEmpty) {
      if (!_missingConfigLogged.contains(queryId)) {
        _missingConfigLogged.add(queryId);
        await _log(
          level: 'warn',
          message: 'Consulta ignorada por configuracao incompleta.',
          queryName: query.name,
        );
      }
      return;
    }

    _running.add(queryId);

    try {
      await _log(
        level: 'info',
        message: 'Executando monitoracao ($source).',
        queryName: query.name,
      );
      final result = await redmineApiService.fetchCountDetailed(
        settings: settings,
        query: query,
      );
      final currentCount = result.count;
      final previous = _lastCounts[queryId] ?? query.lastCount;

      final now = DateTime.now();
      await databaseService.updateQueryLastCheck(
        queryId: queryId,
        lastCount: currentCount,
        checkedAt: now,
      );
      _lastCounts[queryId] = currentCount;
      await _log(
        level: 'success',
        message:
            'Consulta executada com sucesso. Total atual: $currentCount. HTTP ${result.statusCode} em ${result.durationMs}ms.',
        queryName: query.name,
        responseBody: result.responseBody,
      );

      if (previous != null && previous != currentCount) {
        final diff = currentCount - previous;
        final shouldAlert = switch (query.alertOn) {
          'increase' => diff > 0,
          'decrease' => diff < 0,
          _ => true,
        };

        if (!shouldAlert) {
          await _log(
            level: 'info',
            message:
                'Alteracao detectada ($previous -> $currentCount), mas nao atende o criterio de alerta configurado (${query.alertOn}).',
            queryName: query.name,
          );
          _onQueryUpdate();
          return;
        }

        final lastAlertAt = _lastAlertAt[queryId];
        final cooldown = Duration(seconds: settings.alertCooldownSeconds);
        final shouldSkipByCooldown =
            lastAlertAt != null && DateTime.now().difference(lastAlertAt) < cooldown;
        if (shouldSkipByCooldown) {
          await _log(
            level: 'warn',
            message:
                'Alteracao detectada, mas dentro do cooldown de ${settings.alertCooldownSeconds}s.',
            queryName: query.name,
          );
          return;
        }

        final alert = AlertEvent(
          queryId: queryId,
          queryName: query.name,
          previousCount: previous,
          currentCount: currentCount,
          directUrl: _buildDirectUrl(settings.baseUrl, query.directUrl),
          createdAt: now,
        );

        final persistedAlert = await databaseService.addAlert(alert);
        _lastAlertAt[queryId] = now;
        await _log(
          level: 'alert',
          message:
              'Alteracao detectada: $previous -> $currentCount. Endpoint: ${result.uri}',
          queryName: query.name,
        );
        await SystemSound.play(SystemSoundType.alert);
        _onAlert(persistedAlert);
      }

      _onQueryUpdate();
    } catch (error) {
      await _log(
        level: 'error',
        message: 'Falha na consulta: $error',
        queryName: query.name,
      );
      _onQueryUpdate();
    } finally {
      _running.remove(queryId);
    }
  }

  Future<void> _log({
    required String level,
    required String message,
    String? queryName,
    String? responseBody,
  }) async {
    await databaseService.addMonitorLog(
      level: level,
      message: message,
      queryName: queryName,
      responseBody: responseBody,
    );
  }

  String _buildDirectUrl(String baseUrl, String directUrl) {
    if (directUrl.startsWith('http://') || directUrl.startsWith('https://')) {
      return directUrl;
    }
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = directUrl.startsWith('/') ? directUrl : '/$directUrl';
    return '$normalizedBase$normalizedPath';
  }
}
