import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/alert_event.dart';
import '../models/alert_rule.dart';
import '../models/app_settings.dart';
import '../models/monitor_log.dart';
import '../models/monitored_query.dart';
import '../models/query_health.dart';
import '../services/database_service.dart';
import '../services/monitor_service.dart';
import '../services/notifications/alert_notifier.dart';
import '../services/notifications/notification_template_service.dart';
import '../services/redmine_api_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    required DatabaseService databaseService,
  })  : _databaseService = databaseService,
        _monitorService = MonitorService(
          databaseService: databaseService,
          redmineApiService: RedmineApiService(),
          onAlert: (_) {},
          onQueryUpdate: () {},
        ) {
    _monitorService
      ..onAlert = _handleAlert
      ..onQueryUpdate = () {
        unawaited(refreshData());
      };
  }

  final DatabaseService _databaseService;
  final MonitorService _monitorService;
  final AlertNotifier _alertNotifier = AlertNotifier.instance;
  final NotificationTemplateService _templateService = NotificationTemplateService();

  AppSettings settings = AppSettings(baseUrl: '', apiKey: '');
  List<MonitoredQuery> queries = const [];
  List<AlertEvent> alerts = const [];
  List<MonitorLog> monitorLogs = const [];

  bool loading = true;
  bool monitoring = false;
  AlertEvent? lastAlert;
  String? initError;
  String? onboardingErrorMessage;

  /// Set to true when startup credential validation fails.
  bool invalidCredentials = false;

  String get databaseEnvironment => _databaseService.databaseEnvironment;

  bool get isProductionDatabase => _databaseService.isProductionDatabase;

  /// True when the app has not been configured yet (no baseUrl or apiKey),
  /// OR when stored credentials were rejected by Redmine on startup.
  bool get needsOnboarding =>
      settings.baseUrl.trim().isEmpty ||
      settings.apiKey.trim().isEmpty ||
      invalidCredentials;

  Future<void> init() async {
    try {
      await refreshData();

      // Seed default query on first run (empty DB).
      if (queries.isEmpty) {
        await _seedDefaultQuery();
        await refreshData();
      }

      // Validate stored credentials on every startup.
      if (settings.baseUrl.trim().isNotEmpty && settings.apiKey.trim().isNotEmpty) {
        try {
          final accountName = await RedmineApiService().fetchAccountName(
            baseUrl: settings.baseUrl,
            apiKey: settings.apiKey,
          );
          // Update account name if it changed.
          if (accountName != settings.accountName) {
            final updated = settings.copyWith(accountName: accountName);
            await _databaseService.saveSettings(updated);
            settings = updated;
          }
          invalidCredentials = false;
          onboardingErrorMessage = null;
        } catch (error) {
          final message = error.toString().replaceFirst('Exception: ', '');
          invalidCredentials = message.startsWith('Credenciais inválidas');
          onboardingErrorMessage = message;
          loading = false;
          notifyListeners();
          return;
        }
      }

      await _monitorService.start();
      monitoring = true;
      initError = null;
    } catch (error, stackTrace) {
      debugPrint('App initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      initError = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retryInit() async {
    loading = true;
    notifyListeners();
    await init();
  }

  Future<void> refreshData() async {
    settings = await _databaseService.loadSettings();
    queries = await _databaseService.listQueries();
    alerts = await _databaseService.listAlerts();
    monitorLogs = await _databaseService.listMonitorLogs();
    notifyListeners();
  }

  /// Inserts the built-in default query (open issues assigned to me).
  /// Called only once, when the database has no queries.
  Future<void> _seedDefaultQuery() async {
    final defaultQuery = MonitoredQuery(
      name: 'Issues atribuídas a mim',
      endpoint: '/issues.json?assigned_to_id=me&status_id=open',
      directUrl: '/issues?assigned_to_id=me&status_id=open',
      countPath: 'total_count',
    );
    await _databaseService.insertQuery(defaultQuery);
  }

  Future<void> saveSettings(AppSettings next) async {
    await _databaseService.saveSettings(next);
    settings = next;
    notifyListeners();

    if (monitoring) {
      await _monitorService.restart();
    }
  }

  /// Validates credentials against /my/account.json, saves settings with the
  /// resolved account name, then starts the monitor.
  /// Throws if credentials are invalid.
  Future<void> saveOnboardingSettings({
    required String baseUrl,
    required String apiKey,
  }) async {
    final accountName = await RedmineApiService().fetchAccountName(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final next = settings.copyWith(
      baseUrl: baseUrl,
      apiKey: apiKey,
      accountName: accountName,
    );
    await _databaseService.saveSettings(next);
    settings = next;
    invalidCredentials = false;
    onboardingErrorMessage = null;
    await _monitorService.restart();
    monitoring = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    final clearedSettings = settings.copyWith(
      baseUrl: '',
      apiKey: '',
      accountName: null,
    );
    await _databaseService.saveSettings(clearedSettings);
    settings = clearedSettings;
    invalidCredentials = false;
    onboardingErrorMessage = null;
    if (monitoring) {
      await _monitorService.stop();
      monitoring = false;
    }
    notifyListeners();
  }

  Future<void> addQuery(MonitoredQuery query) async {
    await _databaseService.insertQuery(query);
    await refreshData();
    if (monitoring) {
      await _monitorService.restart();
    }
  }

  Future<void> updateQuery(MonitoredQuery query) async {
    await _databaseService.updateQuery(query);
    await refreshData();
    if (monitoring) {
      await _monitorService.restart();
    }
  }

  Future<void> toggleQueryEnabled(MonitoredQuery query) async {
    await updateQuery(query.copyWith(enabled: !query.enabled));
  }

  /// Pins/unpins a query as a sidebar board without restarting the monitor.
  Future<void> togglePinned(MonitoredQuery query) async {
    await _databaseService.updateQuery(query.copyWith(pinned: !query.pinned));
    await refreshData();
  }

  Future<void> duplicateQuery(MonitoredQuery query) async {
    final duplicate = query.copyWith(
      id: null,
      name: '${query.name} (cópia)',
      lastCount: null,
      lastCheckedAt: null,
      lastError: null,
      lastErrorAt: null,
    );
    await addQuery(duplicate);
  }

  Future<void> runQueryNow(int queryId) async {
    await _monitorService.runQueryNow(queryId);
    await refreshData();
  }

  Future<void> deleteQuery(int id) async {
    await _databaseService.deleteQuery(id);
    await refreshData();
    if (monitoring) {
      await _monitorService.restart();
    }
  }

  Future<void> clearAlerts() async {
    await _databaseService.clearAlerts();
    await refreshData();
  }

  Future<void> markAlertRead(int id) async {
    await _databaseService.markAlertRead(id);
    await refreshData();
  }

  Future<void> deleteAlert(int id) async {
    await _databaseService.deleteAlert(id);
    await refreshData();
  }

  Future<void> clearMonitorLogs() async {
    await _databaseService.clearMonitorLogs();
    await refreshData();
  }

  Future<void> sendTestNotification() async {
    final now = DateTime.now();
    final fakeAlert = AlertEvent(
      queryId: -1,
      queryName: 'Consulta de teste',
      previousCount: 12,
      currentCount: 15,
      directUrl: settings.baseUrl,
      createdAt: now,
    );
    await _notify(fakeAlert);
  }

  Future<void> sendTestNotificationWithTemplates({
    required String titleTemplate,
    required String bodyTemplate,
  }) async {
    final now = DateTime.now();
    final fakeAlert = AlertEvent(
      queryId: -1,
      queryName: 'Consulta de teste',
      previousCount: 12,
      currentCount: 15,
      directUrl: settings.baseUrl,
      createdAt: now,
    );
    final title = _templateService.render(titleTemplate, fakeAlert);
    final body = _templateService.render(bodyTemplate, fakeAlert);
    await _alertNotifier.showAlert(alert: fakeAlert, title: title, body: body);
  }

  String exportBackupJson() {
    final payload = {
      'version': 3,
      'settings': {
        'baseUrl': settings.baseUrl,
        'apiKey': settings.apiKey,
        'accountName': settings.accountName,
        'themeMode': settings.themeMode,
        'notificationTitleTemplate': settings.notificationTitleTemplate,
        'notificationBodyTemplate': settings.notificationBodyTemplate,
        'notificationIncreaseTitleTemplate': settings.notificationIncreaseTitleTemplate,
        'notificationIncreaseBodyTemplate': settings.notificationIncreaseBodyTemplate,
        'notificationDecreaseTitleTemplate': settings.notificationDecreaseTitleTemplate,
        'notificationDecreaseBodyTemplate': settings.notificationDecreaseBodyTemplate,
      },
      'queries': queries
          .map((q) => {
                'name': q.name,
                'endpoint': q.endpoint,
                'directUrl': q.directUrl,
                'countPath': q.countPath,
                'pollSeconds': q.pollSeconds,
                'enabled': q.enabled,
                'alertRules': q.alertRules.map((r) => r.toJson()).toList(),
                'pinned': q.pinned,
                'scheduleWeekdays': q.scheduleWeekdays,
                'scheduleStartHour': q.scheduleStartHour,
                'scheduleEndHour': q.scheduleEndHour,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> copyBackupToClipboard() async {
    await Clipboard.setData(ClipboardData(text: exportBackupJson()));
  }

  Future<void> importBackupJson(String raw) async {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Backup inválido: JSON raiz precisa ser objeto.');
    }

    final version = parsed['version'] as int? ?? 1;
    if (version < 1 || version > 3) {
      throw FormatException('Versão de backup não suportada: $version');
    }

    final settingsMap = parsed['settings'];
    final queriesList = parsed['queries'];
    if (settingsMap is! Map<String, dynamic> || queriesList is! List) {
      throw const FormatException('Backup inválido: campos settings/queries ausentes.');
    }

    final importedSettings = AppSettings(
      baseUrl: (settingsMap['baseUrl'] ?? '').toString(),
      apiKey: (settingsMap['apiKey'] ?? '').toString(),
      accountName: settingsMap['accountName'] as String?,
      themeMode: (settingsMap['themeMode'] as String?) ?? defaultThemeMode,
      notificationTitleTemplate:
          (settingsMap['notificationTitleTemplate'] ?? defaultNotificationTitleTemplate)
              .toString(),
      notificationBodyTemplate:
          (settingsMap['notificationBodyTemplate'] ?? defaultNotificationBodyTemplate)
              .toString(),
      notificationIncreaseTitleTemplate:
          settingsMap['notificationIncreaseTitleTemplate'] as String?,
      notificationIncreaseBodyTemplate:
          settingsMap['notificationIncreaseBodyTemplate'] as String?,
      notificationDecreaseTitleTemplate:
          settingsMap['notificationDecreaseTitleTemplate'] as String?,
      notificationDecreaseBodyTemplate:
          settingsMap['notificationDecreaseBodyTemplate'] as String?,
    );

    await _databaseService.saveSettings(importedSettings);
    await _databaseService.clearAlerts();
    await _databaseService.clearQueries();
    for (final entry in queriesList) {
      if (entry is! Map) {
        continue;
      }
      final scheduleWeekdays = entry['scheduleWeekdays'] is List
          ? List<int>.from((entry['scheduleWeekdays'] as List).map((e) => e as int))
          : defaultScheduleWeekdays;
      final query = MonitoredQuery(
        name: (entry['name'] ?? 'Consulta').toString(),
        endpoint: (entry['endpoint'] ?? '').toString(),
        directUrl: (entry['directUrl'] ?? '').toString(),
        countPath: (entry['countPath'] ?? 'total_count').toString(),
        pollSeconds: int.tryParse('${entry['pollSeconds']}') ?? defaultPollSeconds,
        enabled: (entry['enabled'] ?? true) == true,
        alertRules: entry['alertRules'] is List
            ? (entry['alertRules'] as List)
                .map((r) => AlertRule.fromJson(Map<String, dynamic>.from(r as Map)))
                .toList()
            : [
                AlertRule.fromLegacy(
                  entry['alertOn'] as String?,
                  entry['notificationTitleTemplate'] as String?,
                  entry['notificationBodyTemplate'] as String?,
                ),
              ],
        pinned: entry['pinned'] == true,
        scheduleWeekdays: scheduleWeekdays,
        scheduleStartHour: entry['scheduleStartHour'] as int? ?? defaultScheduleStartHour,
        scheduleEndHour: entry['scheduleEndHour'] as int? ?? defaultScheduleEndHour,
      );
      await _databaseService.insertQuery(query);
    }

    if (monitoring) {
      await _monitorService.restart();
    }
    await refreshData();
  }

  List<QueryHealth> get queryHealth {
    return queries.map((query) {
      final latestLog = monitorLogs.firstWhere(
        (log) => log.queryName == query.name,
        orElse: () => MonitorLog(
          id: null,
          level: 'unknown',
          message: 'Sem execuções ainda.',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final failed = query.lastError != null;
      return QueryHealth(
        queryId: query.id ?? -1,
        queryName: query.name,
        enabled: query.enabled,
        lastCheckedAt: query.lastCheckedAt,
        lastCount: query.lastCount,
        lastStatus: failed ? 'error' : latestLog.level,
        lastMessage: failed
            ? query.lastError
            : (latestLog.id == null ? null : latestLog.message),
      );
    }).toList();
  }

  Future<void> startMonitoring() async {
    if (monitoring) {
      return;
    }
    await _monitorService.start();
    monitoring = true;
    await refreshData();
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    if (!monitoring) {
      return;
    }
    await _monitorService.stop();
    monitoring = false;
    await refreshData();
    notifyListeners();
  }

  Future<void> toggleMonitoring() async {
    if (monitoring) {
      await stopMonitoring();
    } else {
      await startMonitoring();
    }
  }

  void _handleAlert(AlertEvent alert) {
    lastAlert = alert;
    unawaited(_notify(alert));
    unawaited(refreshData());
  }

  /// Title/body exactly as shown in the OS notification. Alerts created
  /// before rules existed have no stored text and are rendered with globals.
  (String, String) alertText(AlertEvent alert) => alert.title != null
      ? (alert.title!, alert.body ?? '')
      : _templateService.resolve(settings, null, alert);

  Future<void> _notify(AlertEvent alert) async {
    final (title, body) = alertText(alert);
    await _alertNotifier.showAlert(alert: alert, title: title, body: body);
  }

  @override
  void dispose() {
    unawaited(_monitorService.stop());
    super.dispose();
  }
}
