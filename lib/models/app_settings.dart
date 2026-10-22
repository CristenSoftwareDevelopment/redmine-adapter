import 'business_hours.dart';
import 'claude_action.dart';
import 'custom_field.dart';
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
    this.customFields = const [],
    this.agileBoard = const AgileBoard(),
    this.sidebarWidth = defaultSidebarWidth,
    this.boardOrder = const [],
    this.businessHours = const BusinessHours(),
    this.overtimePaid = const {},
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

  /// Type and choices of each issue custom field (Configurações › Campos).
  final List<CustomFieldDef> customFields;

  /// Scope, columns and view of the built-in "Ágil" board.
  final AgileBoard agileBoard;

  /// Expanded sidebar width, resized by dragging its edge.
  final double sidebarWidth;

  /// Ids of the sidebar boards in the order the user dragged them (the Ágil
  /// board is [agileQueryId]).
  final List<int> boardOrder;

  /// Working days and periods: counted hours beyond them are overtime.
  final BusinessHours businessHours;

  /// Months (`yyyy-MM`) whose overtime was paid out; the others stay in the bank.
  final Set<String> overtimePaid;

  /// Claude actions and trâmite rules in button order: by their `order`, then
  /// the never ordered ones (Claude first, each in list order). Each item is a
  /// [ClaudeAction] or a [HandoffRule].
  List<Object> get orderedActions {
    const last = 1 << 30;
    final all = [
      for (final (i, a) in claudeActions.indexed) (a.order ?? last, 0, i, a as Object),
      for (final (i, r) in handoffRules.indexed) (r.order ?? last, 1, i, r as Object),
    ]..sort((a, b) => a.$1 != b.$1
        ? a.$1 - b.$1
        : a.$2 != b.$2
            ? a.$2 - b.$2
            : a.$3 - b.$3);
    return [for (final e in all) e.$4];
  }

  /// [boards] by their place in [boardOrder]; ones never dragged keep their
  /// order after those (`List.sort` isn't stable, hence the index).
  List<MonitoredQuery> sortBoards(List<MonitoredQuery> boards) {
    int rank(MonitoredQuery q) {
      final i = boardOrder.indexOf(q.id ?? 0);
      return i < 0 ? boardOrder.length : i;
    }

    final ranked = [for (final (i, q) in boards.indexed) (rank(q), i, q)]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final r in ranked) r.$3];
  }

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
    List<CustomFieldDef>? customFields,
    AgileBoard? agileBoard,
    double? sidebarWidth,
    List<int>? boardOrder,
    BusinessHours? businessHours,
    Set<String>? overtimePaid,
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
      customFields: customFields ?? this.customFields,
      agileBoard: agileBoard ?? this.agileBoard,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      boardOrder: boardOrder ?? this.boardOrder,
      businessHours: businessHours ?? this.businessHours,
      overtimePaid: overtimePaid ?? this.overtimePaid,
    );
  }
}

const _sentinel = Object();
