const defaultNotificationTitleTemplate = 'Redmine • {queryName}';
const defaultNotificationBodyTemplate =
    'Mudou de {previousCount} para {currentCount} ({diff}) às {time}';
const defaultThemeMode = 'system';

/// Global application settings (connection, notifications, appearance).
/// Per-query scheduling and polling are stored in [MonitoredQuery].
class AppSettings {
  AppSettings({
    required this.baseUrl,
    required this.apiKey,
    this.accountName,
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
  final String? accountName;
  final String notificationTitleTemplate;
  final String notificationBodyTemplate;
  final String themeMode;

  final String? notificationIncreaseTitleTemplate;
  final String? notificationIncreaseBodyTemplate;
  final String? notificationDecreaseTitleTemplate;
  final String? notificationDecreaseBodyTemplate;

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    Object? accountName = _sentinel,
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
      accountName: accountName == _sentinel ? this.accountName : accountName as String?,
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

const _sentinel = Object();
