const defaultNotificationTitleTemplate = 'Redmine • {queryName}';
const defaultNotificationBodyTemplate =
    'Mudou de {previousCount} para {currentCount} ({diff}) às {time}';
const defaultThemeMode = 'system';

class AppSettings {
  AppSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.defaultPollSeconds,
    this.alertCooldownSeconds = 600,
    this.notificationTitleTemplate = defaultNotificationTitleTemplate,
    this.notificationBodyTemplate = defaultNotificationBodyTemplate,
    this.themeMode = defaultThemeMode,
    this.notificationIncreaseTitleTemplate,
    this.notificationIncreaseBodyTemplate,
    this.notificationDecreaseTitleTemplate,
    this.notificationDecreaseBodyTemplate,
    this.monitorStartHour,
    this.monitorEndHour,
  });

  final String baseUrl;
  final String apiKey;
  final int defaultPollSeconds;
  final int alertCooldownSeconds;
  final String notificationTitleTemplate;
  final String notificationBodyTemplate;
  final String themeMode;

  final String? notificationIncreaseTitleTemplate;
  final String? notificationIncreaseBodyTemplate;
  final String? notificationDecreaseTitleTemplate;
  final String? notificationDecreaseBodyTemplate;

  /// Optional monitoring time window. null = always monitor.
  /// Supports overnight ranges (e.g. startHour=22, endHour=6).
  final int? monitorStartHour;
  final int? monitorEndHour;

  /// Returns true if monitoring is allowed at [hour] (0-23).
  bool isWithinSchedule(int hour) {
    final start = monitorStartHour;
    final end = monitorEndHour;
    if (start == null || end == null) return true;
    if (start <= end) {
      return hour >= start && hour < end;
    } else {
      // Overnight: e.g. start=22, end=6 → allowed 22,23,0,1,2,3,4,5
      return hour >= start || hour < end;
    }
  }

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    int? defaultPollSeconds,
    int? alertCooldownSeconds,
    String? notificationTitleTemplate,
    String? notificationBodyTemplate,
    String? themeMode,
    Object? notificationIncreaseTitleTemplate = _sentinel,
    Object? notificationIncreaseBodyTemplate = _sentinel,
    Object? notificationDecreaseTitleTemplate = _sentinel,
    Object? notificationDecreaseBodyTemplate = _sentinel,
    Object? monitorStartHour = _sentinel,
    Object? monitorEndHour = _sentinel,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      defaultPollSeconds: defaultPollSeconds ?? this.defaultPollSeconds,
      alertCooldownSeconds: alertCooldownSeconds ?? this.alertCooldownSeconds,
      notificationTitleTemplate:
          notificationTitleTemplate ?? this.notificationTitleTemplate,
      notificationBodyTemplate: notificationBodyTemplate ?? this.notificationBodyTemplate,
      themeMode: themeMode ?? this.themeMode,
      notificationIncreaseTitleTemplate: notificationIncreaseTitleTemplate == _sentinel
          ? this.notificationIncreaseTitleTemplate
          : notificationIncreaseTitleTemplate as String?,
      notificationIncreaseBodyTemplate: notificationIncreaseBodyTemplate == _sentinel
          ? this.notificationIncreaseBodyTemplate
          : notificationIncreaseBodyTemplate as String?,
      notificationDecreaseTitleTemplate: notificationDecreaseTitleTemplate == _sentinel
          ? this.notificationDecreaseTitleTemplate
          : notificationDecreaseTitleTemplate as String?,
      notificationDecreaseBodyTemplate: notificationDecreaseBodyTemplate == _sentinel
          ? this.notificationDecreaseBodyTemplate
          : notificationDecreaseBodyTemplate as String?,
      monitorStartHour: monitorStartHour == _sentinel
          ? this.monitorStartHour
          : monitorStartHour as int?,
      monitorEndHour: monitorEndHour == _sentinel
          ? this.monitorEndHour
          : monitorEndHour as int?,
    );
  }
}

const _sentinel = Object();
