import 'claude_action.dart';
import 'handoff_rule.dart';
import 'monitored_query.dart';

const defaultNotificationTitleTemplate = 'Redmine • {queryName}';
const defaultNotificationBodyTemplate =
    'Mudou de {previousCount} para {currentCount} ({diff}) às {time}';
const defaultThemeMode = 'system';
const defaultSidebarWidth = 280.0;

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
    this.handoffRules = const [],
    this.claudeActions = const [],
    this.agileBoard = const AgileBoard(),
    this.sidebarWidth = defaultSidebarWidth,
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

  /// "Enviar trâmite" actions of the issue dialog.
  final List<HandoffRule> handoffRules;

  /// "Claude Code" actions of the issue dialog.
  final List<ClaudeAction> claudeActions;

  /// Scope, columns and view of the built-in "Ágil" board.
  final AgileBoard agileBoard;

  /// Expanded sidebar width, resized by dragging its edge.
  final double sidebarWidth;

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
    List<HandoffRule>? handoffRules,
    List<ClaudeAction>? claudeActions,
    AgileBoard? agileBoard,
    double? sidebarWidth,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      accountName: accountName == _sentinel ? this.accountName : accountName as String?,
      notificationTitleTemplate: notificationTitleTemplate ?? this.notificationTitleTemplate,
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
      handoffRules: handoffRules ?? this.handoffRules,
      claudeActions: claudeActions ?? this.claudeActions,
      agileBoard: agileBoard ?? this.agileBoard,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    );
  }
}

const _sentinel = Object();
