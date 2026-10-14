/// One Redmine time entry (`/time_entries.json`).
class TimeEntry {
  const TimeEntry({
    required this.userId,
    required this.userName,
    required this.day,
    required this.hours,
    required this.activity,
    this.issueId,
    this.comments = '',
  });

  final int userId;
  final String userName;

  /// Date only (local midnight).
  final DateTime day;
  final double hours;
  final String activity;
  final int? issueId;
  final String comments;

  static TimeEntry fromJson(Map<String, dynamic> json) {
    final spentOn = DateTime.parse(json['spent_on'] as String);
    return TimeEntry(
      userId: (json['user'] as Map)['id'] as int,
      userName: (json['user'] as Map)['name'] as String? ?? '?',
      day: DateTime(spentOn.year, spentOn.month, spentOn.day),
      hours: (json['hours'] as num).toDouble(),
      activity: (json['activity'] as Map?)?['name'] as String? ?? '-',
      issueId: (json['issue'] as Map?)?['id'] as int?,
      comments: json['comments'] as String? ?? '',
    );
  }
}

/// Total hours per key, e.g. `sumHours(entries, (e) => (e.userId, e.day))`.
Map<K, double> sumHours<K>(Iterable<TimeEntry> entries, K Function(TimeEntry) key) {
  final totals = <K, double>{};
  for (final e in entries) {
    totals.update(key(e), (v) => v + e.hours, ifAbsent: () => e.hours);
  }
  return totals;
}

/// Hours as `7,5` (pt-BR decimal comma), trailing `,0` dropped.
String fmtHours(double hours) {
  final text = hours.toStringAsFixed(1).replaceAll('.', ',');
  return text.endsWith(',0') ? text.substring(0, text.length - 2) : text;
}
