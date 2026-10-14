/// Thin read view over an issue JSON returned by the Redmine API.
/// The map stays mutable so the board can move a card optimistically.
class RedmineIssue {
  RedmineIssue(this.json);

  final Map<String, dynamic> json;

  int get id => json['id'] as int;
  String get subject => json['subject'] as String? ?? '';
  String get description => json['description'] as String? ?? '';

  int get statusId => refId('status') ?? 0;
  String get statusName => nameOf('status') ?? '-';
  int? get priorityId => refId('priority');
  String get priorityName => nameOf('priority') ?? '-';
  int? get assigneeId => refId('assigned_to');
  String? get assigneeName => nameOf('assigned_to');
  String get trackerName => nameOf('tracker') ?? '';
  String get projectName => nameOf('project') ?? '';
  DateTime? get updatedOn => DateTime.tryParse(json['updated_on'] as String? ?? '');

  /// `name` of a `{id, name}` reference such as `status` or `fixed_version`.
  String? nameOf(String key) => (json[key] as Map?)?['name'] as String?;
  int? refId(String key) => (json[key] as Map?)?['id'] as int?;
}
