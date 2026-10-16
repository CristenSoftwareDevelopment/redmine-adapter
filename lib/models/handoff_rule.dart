import 'dart:convert';

const defaultHandoffTemplate = '* Tramite de {{tipoAtividadeComentario}}: {{noteSelecionado}}';

/// Used with 2+ notes: the line with `{{noteSelecionado}}` repeats per note.
const defaultHandoffMultiTemplate =
    '* Tramites de {{tipoAtividadeComentario}}:\n  - {{noteSelecionado}}';

/// Placeholders of [HandoffRule.template], shown in the rule editor.
const handoffPlaceholders = {
  '{{tipoAtividadeComentario}}': 'tipo da tarefa de origem, em minúsculas',
  '{{noteSelecionado}}': 'nota escolhida, ex. #484530#note-9 (com várias, a linha se repete)',
  '{{tarefa}}': 'tarefa de origem, ex. #484530',
  '{{titulo}}': 'título da tarefa de origem',
};

/// "Send a dev note to QA": from an issue of [sourceTrackerIds], comment on
/// another issue (usually of [targetTrackerId]) mentioning notes of the dev work,
/// optionally changing that issue's status and assignee.
class HandoffRule {
  const HandoffRule({
    required this.name,
    this.sourceTrackerIds = const [],
    this.targetTrackerId,
    this.statusId,
    this.assigneeId,
    this.assigneeName,
    this.template = defaultHandoffTemplate,
    this.multiTemplate = defaultHandoffMultiTemplate,
    this.timeActivityId,
    this.statusSteps = const [],
    this.icon,
    this.sameIssue = false,
    this.logTime = false,
  });

  /// Button label, e.g. "Enviar para QA".
  final String name;

  /// Key of the button icon (see `actionIcons`); null = default.
  final String? icon;

  /// Update the opened issue itself (status, assignee, a typed comment and
  /// hours) instead of commenting on another one; target, note templates and
  /// status steps are then ignored.
  final bool sameIssue;

  /// Trackers where the action shows up; empty = every tracker.
  final List<int> sourceTrackerIds;

  /// Tracker of the suggested target issues; null = any.
  final int? targetTrackerId;

  /// Defaults preloaded in the send dialog; null = keep the target's current one.
  final int? statusId;
  final int? assigneeId;
  final String? assigneeName;

  final String template;
  final String multiTemplate;

  // Closing steps, e.g. at the end of a code review.

  /// Shows the hours section on send (prefilled since the last update).
  final bool logTime;

  /// Default time entry activity (e.g. "Code review"); null = picked on send.
  final int? timeActivityId;

  /// Issues of each tracker move to its status (e.g. Desenvolvimento → Em teste,
  /// Negócio → Resolvida); the dialog lists the linked issues of that tracker.
  final List<({int trackerId, int statusId})> statusSteps;

  bool appliesTo(int? trackerId) =>
      sourceTrackerIds.isEmpty || sourceTrackerIds.contains(trackerId);

  Map<String, Object?> toJson() => {
        'name': name,
        'icon': icon,
        'sameIssue': sameIssue,
        'sourceTrackerIds': sourceTrackerIds,
        'targetTrackerId': targetTrackerId,
        'statusId': statusId,
        'assigneeId': assigneeId,
        'assigneeName': assigneeName,
        'template': template,
        'multiTemplate': multiTemplate,
        'logTime': logTime,
        'timeActivityId': timeActivityId,
        'statusSteps': [
          for (final s in statusSteps) {'trackerId': s.trackerId, 'statusId': s.statusId},
        ],
      };

  static HandoffRule fromJson(Map<String, dynamic> json) => HandoffRule(
        name: json['name'] as String? ?? 'Enviar trâmite',
        icon: json['icon'] as String?,
        sameIssue: json['sameIssue'] == true,
        sourceTrackerIds: (json['sourceTrackerIds'] as List? ?? const []).whereType<int>().toList(),
        targetTrackerId: json['targetTrackerId'] as int?,
        statusId: json['statusId'] as int?,
        assigneeId: json['assigneeId'] as int?,
        assigneeName: json['assigneeName'] as String?,
        template: json['template'] as String? ?? defaultHandoffTemplate,
        multiTemplate: json['multiTemplate'] as String? ?? defaultHandoffMultiTemplate,
        // Before the toggle: same-issue rules always showed hours, the others
        // only with an activity.
        logTime: json['logTime'] as bool? ??
            (json['sameIssue'] == true || json['timeActivityId'] != null),
        timeActivityId: json['timeActivityId'] as int?,
        statusSteps: [
          for (final s in (json['statusSteps'] as List? ?? const []).whereType<Map>())
            if (s['trackerId'] is int && s['statusId'] is int)
              (trackerId: s['trackerId'] as int, statusId: s['statusId'] as int),
        ],
      );

  static String listToJson(List<HandoffRule> rules) =>
      jsonEncode(rules.map((r) => r.toJson()).toList());

  static List<HandoffRule> listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => HandoffRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Comment posted on the target issue. [notes] are (issue id, note index),
/// the index being the 1-based journal position Redmine uses in `#note-N`.
/// With 2+ notes [HandoffRule.multiTemplate] is used and each of its lines
/// with `{{noteSelecionado}}` repeats once per note. The other placeholders
/// refer to the issue the dialog was opened from.
String renderHandoffNote(
  HandoffRule rule, {
  required String trackerName,
  required int issueId,
  required String subject,
  required List<(int, int)> notes,
}) {
  final sorted = [...notes]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  final links = [for (final (id, index) in sorted) '#$id#note-$index'];
  return (links.length > 1 ? rule.multiTemplate : rule.template)
      .split('\n')
      .expand((line) => line.contains('{{noteSelecionado}}')
          ? links.map((link) => line.replaceAll('{{noteSelecionado}}', link))
          : [line])
      .join('\n')
      .replaceAll('{{tipoAtividadeComentario}}', trackerName.toLowerCase())
      .replaceAll('{{tarefa}}', '#$issueId')
      .replaceAll('{{titulo}}', subject);
}
