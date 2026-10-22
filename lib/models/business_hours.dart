/// One working period on some weekdays, e.g. seg–sex 08:00–12:00.
class BusinessPeriod {
  const BusinessPeriod(
      {this.days = const {1, 2, 3, 4, 5}, this.start = 8 * 60, this.end = 12 * 60});

  /// `DateTime.weekday` values (1 = segunda … 7 = domingo).
  final Set<int> days;

  /// Minutes of the day; [end] exclusive. `end <= start` is ignored.
  final int start;
  final int end;

  bool get valid => end > start && days.isNotEmpty;

  BusinessPeriod copyWith({Set<int>? days, int? start, int? end}) =>
      BusinessPeriod(days: days ?? this.days, start: start ?? this.start, end: end ?? this.end);

  Map<String, dynamic> toJson() => {'days': days.toList()..sort(), 'start': start, 'end': end};

  static BusinessPeriod fromJson(Map json) => BusinessPeriod(
        days: (json['days'] as List? ?? const []).whereType<int>().toSet(),
        start: json['start'] as int? ?? 8 * 60,
        end: json['end'] as int? ?? 12 * 60,
      );
}

/// Working periods (Configurações › Expediente), each on its own weekdays, so
/// days can differ. Hours counted for a trâmite are split into these and overtime.
class BusinessHours {
  const BusinessHours({
    this.periods = const [
      BusinessPeriod(start: 8 * 60, end: 12 * 60),
      BusinessPeriod(start: 13 * 60, end: 18 * 60),
    ],
  });

  final List<BusinessPeriod> periods;

  /// Working (start, end) of [weekday], sorted and merged, so overlapping
  /// periods never count twice.
  List<(int, int)> intervalsOn(int weekday) {
    final list = [
      for (final p in periods)
        if (p.valid && p.days.contains(weekday)) (p.start, p.end)
    ]..sort((a, b) => a.$1 - b.$1);
    final merged = <(int, int)>[];
    for (final (s, e) in list) {
      if (merged.isNotEmpty && s <= merged.last.$2) {
        final (ls, le) = merged.removeLast();
        merged.add((ls, e > le ? e : le));
      } else {
        merged.add((s, e));
      }
    }
    return merged;
  }

  /// Working minutes on [weekday].
  int minutesOn(int weekday) => intervalsOn(weekday).fold(0, (sum, i) => sum + i.$2 - i.$1);

  /// Wall-clock time between [from] and [to], split into business hours and
  /// overtime. Walks day by day, intersecting that day's periods; the gap
  /// between two periods of a day (lunch) is a break and counts as neither.
  ({Duration business, Duration extra}) split(DateTime from, DateTime to) {
    if (!to.isAfter(from)) return (business: Duration.zero, extra: Duration.zero);
    var business = Duration.zero;
    var pause = Duration.zero;
    for (var day = DateTime(from.year, from.month, from.day);
        day.isBefore(to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      // Part of [from, to] inside start..end (minutes) of this day.
      Duration overlap(int start, int end) {
        final a = DateTime(day.year, day.month, day.day, 0, start);
        final b = DateTime(day.year, day.month, day.day, 0, end);
        final s = a.isAfter(from) ? a : from;
        final e = b.isBefore(to) ? b : to;
        return e.isAfter(s) ? e.difference(s) : Duration.zero;
      }

      final intervals = intervalsOn(day.weekday);
      for (final (i, (start, end)) in intervals.indexed) {
        business += overlap(start, end);
        if (i > 0) pause += overlap(intervals[i - 1].$2, start);
      }
    }
    return (business: business, extra: to.difference(from) - business - pause);
  }

  Map<String, dynamic> toJson() => {'periods': periods.map((p) => p.toJson()).toList()};

  /// Also reads the first format: `{weekdays: [..], periods: [[start, end], ..]}`.
  static BusinessHours fromJson(Map<String, dynamic> json) {
    final legacyDays = (json['weekdays'] as List?)?.whereType<int>().toSet();
    return BusinessHours(periods: [
      for (final p in json['periods'] as List? ?? const [])
        if (p is Map)
          BusinessPeriod.fromJson(p)
        else if (p is List && p.length == 2 && p[0] is int && p[1] is int)
          BusinessPeriod(days: legacyDays ?? const {1, 2, 3, 4, 5}, start: p[0], end: p[1]),
    ]);
  }
}
