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
    final enabledQueries = queries.where((q) => q.enabled && q.id != null).toList();
    _missingConfigLogged.clear();
    await _log(
      level: 'info',
      message: 'Monitoração iniciada com ${enabledQueries.length} consulta(s) ativa(s).',
    );

    _pruneTimer = Timer.periodic(_pruneInterval, (_) async {
      await databaseService.pruneMonitorLogs();
      _onQueryUpdate();
    });

    for (final query in enabledQueries) {
      _lastCounts[query.id!] = query.lastCount;
      final safeSeconds = query.pollSeconds.clamp(minPollSeconds, 86400);
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
    _running.clear();
    _missingConfigLogged.clear();
    await _log(level: 'info', message: 'Monitoração parada.');
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
      await _log(level: 'warn', message: 'Consulta não encontrada para execução manual.');
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

    // Per-query schedule check
    if (!query.isWithinSchedule(DateTime.now())) {
      await _log(
        level: 'info',
        message:
            'Fora do horário configurado (${_weekdaysLabel(query.scheduleWeekdays)} ${query.scheduleStartHour.toString().padLeft(2, '0')}h–${query.scheduleEndHour.toString().padLeft(2, '0')}h). Consulta ignorada.',
        queryName: query.name,
      );
      return;
    }

    if (settings.baseUrl.trim().isEmpty || settings.apiKey.trim().isEmpty) {
      if (!_missingConfigLogged.contains(queryId)) {
        _missingConfigLogged.add(queryId);
        await _log(
          level: 'warn',
          message: 'Consulta ignorada por configuração incompleta.',
          queryName: query.name,
        );
      }
      return;
    }

    _running.add(queryId);

    try {
      await _log(
        level: 'info',
        message: 'Executando monitoração ($source).',
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
                'Alteração detectada ($previous -> $currentCount), mas não atende o critério de alerta configurado (${query.alertOn}).',
            queryName: query.name,
          );
          _onQueryUpdate();
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
        await _log(
          level: 'alert',
          message:
              'Alteração detectada: $previous -> $currentCount. Endpoint: ${result.uri}',
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

  static const _dayNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  String _weekdaysLabel(List<int> days) {
    if (days.isEmpty) return '—';
    return days.map((d) => _dayNames[(d - 1).clamp(0, 6)]).join(', ');
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
