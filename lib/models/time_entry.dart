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

/// Entries whose `spent_on` is within [first]..[last] (inclusive).
///
/// Redmine's `from`/`to` filter is shifted by the user's time zone (asking
/// for the 13th can return the 14th), so callers fetch one extra day on each
/// side and keep only what really belongs to the range.
List<TimeEntry> withinDays(Iterable<TimeEntry> entries, DateTime first, DateTime last) => [
      for (final e in entries)
        if (!e.day.isBefore(first) && !e.day.isAfter(last)) e,
    ];

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

/// Typed hours: `1,5`, `1.5` or `1:30` → 1.5. Null when empty, invalid or ≤ 0.
double? parseHours(String text) {
  final t = text.trim();
  final hm = RegExp(r'^(\d+):([0-5]?\d)$').firstMatch(t);
  final hours = hm != null
      ? int.parse(hm[1]!) + int.parse(hm[2]!) / 60
      : double.tryParse(t.replaceAll(',', '.'));
  return hours == null || hours <= 0 ? null : hours;
}

/// [d] as `h:mm` to the minute, ready for [parseHours]; empty under a minute.
String fmtHm(Duration d) {
  final minutes = d.inMinutes;
  return minutes <= 0 ? '' : '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Overtime kept in the local database (Tempo gasto › Horas extras); the
/// Redmine time entry has the total hours.
class OvertimeEntry {
  const OvertimeEntry({this.id, required this.day, required this.hours, this.issueId, this.note = ''});

  final int? id;

  /// `yyyy-MM-dd`.
  final String day;
  final double hours;
  final int? issueId;
  final String note;

  /// `yyyy-MM`.
  String get month => day.substring(0, 7);

  static OvertimeEntry fromDbMap(Map<String, Object?> map) => OvertimeEntry(
        id: map['id'] as int?,
        day: map['day'] as String,
        hours: (map['hours'] as num).toDouble(),
        issueId: map['issue_id'] as int?,
        note: map['note'] as String? ?? '',
      );

  Map<String, Object?> toDbMap() =>
      {'day': day, 'hours': hours, 'issue_id': issueId, 'note': note};
}

/// Hours in the bank: overtime of the months not in [paid] (`yyyy-MM`).
double bankBalance(Iterable<OvertimeEntry> entries, Set<String> paid) =>
    entries.where((e) => !paid.contains(e.month)).fold(0.0, (sum, e) => sum + e.hours);
