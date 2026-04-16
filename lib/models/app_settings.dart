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
  });

  final String baseUrl;
  final String apiKey;
  final int defaultPollSeconds;
  final int alertCooldownSeconds;
  final String notificationTitleTemplate;
  final String notificationBodyTemplate;
  final String themeMode;

  /// Optional override for alerts triggered by an increase in count.
  final String? notificationIncreaseTitleTemplate;
  final String? notificationIncreaseBodyTemplate;

  /// Optional override for alerts triggered by a decrease in count.
  final String? notificationDecreaseTitleTemplate;
  final String? notificationDecreaseBodyTemplate;

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
    );
  }
}

// Sentinel used to distinguish "not provided" from explicit null in copyWith.
const _sentinel = Object();
