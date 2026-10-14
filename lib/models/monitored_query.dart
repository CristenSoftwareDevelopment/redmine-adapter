import 'alert_rule.dart';

/// Default schedule: Mon–Fri (weekdays 1–5), 08:00–18:00.
const defaultScheduleWeekdays = [1, 2, 3, 4, 5];
const defaultScheduleStartHour = 8;
const defaultScheduleEndHour = 18;

/// Default and minimum poll interval per query.
const defaultPollSeconds = 300;
const minPollSeconds = 60;

class MonitoredQuery {
  MonitoredQuery({
    this.id,
    required this.name,
    required this.endpoint,
    required this.directUrl,
    this.countPath = 'total_count',
    this.pollSeconds = defaultPollSeconds,
    this.enabled = true,
    this.alertRules = const [AlertRule()],
    this.lastCount,
    this.lastCheckedAt,
    this.pinned = false,
    this.lastError,
    this.lastErrorAt,
    List<int>? scheduleWeekdays,
    int? scheduleStartHour,
    int? scheduleEndHour,
  })  : scheduleWeekdays = scheduleWeekdays ?? List.unmodifiable(defaultScheduleWeekdays),
        scheduleStartHour = scheduleStartHour ?? defaultScheduleStartHour,
        scheduleEndHour = scheduleEndHour ?? defaultScheduleEndHour;

  final int? id;
  final String name;
  final String endpoint;
  final String directUrl;
  final String countPath;
  final int pollSeconds;
  final bool enabled;

  /// Notification conditions, evaluated in order when the count changes.
  final List<AlertRule> alertRules;
  final int? lastCount;
  final DateTime? lastCheckedAt;

  /// Shown as a board in the sidebar.
  final bool pinned;

  /// Error of the last failed check; cleared on the next successful one.
  final String? lastError;
  final DateTime? lastErrorAt;

  /// Days of week on which monitoring runs (1=Mon … 7=Sun). Default: Mon–Fri.
  final List<int> scheduleWeekdays;

  /// Hour of day (0–23) at which monitoring window starts. Default: 8.
  final int scheduleStartHour;

  /// Hour of day (0–23) at which monitoring window ends (exclusive). Default: 18.
  final int scheduleEndHour;

  /// Returns true if [now] falls within this query's schedule.
  bool isWithinSchedule(DateTime now) {
    // Weekday check (DateTime.weekday: 1=Mon … 7=Sun)
    if (!scheduleWeekdays.contains(now.weekday)) return false;
    final h = now.hour;
    if (scheduleStartHour <= scheduleEndHour) {
      return h >= scheduleStartHour && h < scheduleEndHour;
    } else {
      // Overnight window
      return h >= scheduleStartHour || h < scheduleEndHour;
    }
  }

  MonitoredQuery copyWith({
    int? id,
    String? name,
    String? endpoint,
    String? directUrl,
    String? countPath,
    int? pollSeconds,
    bool? enabled,
    List<AlertRule>? alertRules,
    int? lastCount,
    DateTime? lastCheckedAt,
    bool? pinned,
    Object? lastError = _sentinel,
    Object? lastErrorAt = _sentinel,
    List<int>? scheduleWeekdays,
    int? scheduleStartHour,
    int? scheduleEndHour,
  }) {
    return MonitoredQuery(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      directUrl: directUrl ?? this.directUrl,
      countPath: countPath ?? this.countPath,
      pollSeconds: pollSeconds ?? this.pollSeconds,
      enabled: enabled ?? this.enabled,
      alertRules: alertRules ?? this.alertRules,
      lastCount: lastCount ?? this.lastCount,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      pinned: pinned ?? this.pinned,
      lastError: lastError == _sentinel ? this.lastError : lastError as String?,
      lastErrorAt: lastErrorAt == _sentinel ? this.lastErrorAt : lastErrorAt as DateTime?,
      scheduleWeekdays: scheduleWeekdays ?? this.scheduleWeekdays,
      scheduleStartHour: scheduleStartHour ?? this.scheduleStartHour,
      scheduleEndHour: scheduleEndHour ?? this.scheduleEndHour,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'direct_url': directUrl,
      'count_path': countPath,
      'poll_seconds': pollSeconds,
      'enabled': enabled ? 1 : 0,
      'alert_rules': AlertRule.listToJson(alertRules),
      'last_count': lastCount,
      'last_checked_at': lastCheckedAt?.toIso8601String(),
      'pinned': pinned ? 1 : 0,
      'last_error': lastError,
      'last_error_at': lastErrorAt?.toIso8601String(),
      'schedule_weekdays': scheduleWeekdays.join(','),
      'schedule_start_hour': scheduleStartHour,
      'schedule_end_hour': scheduleEndHour,
    };
  }

  static MonitoredQuery fromDbMap(Map<String, Object?> map) {
    return MonitoredQuery(
      id: map['id'] as int,
      name: map['name'] as String,
      endpoint: map['endpoint'] as String,
      directUrl: map['direct_url'] as String,
      countPath: map['count_path'] as String? ?? 'total_count',
      pollSeconds: map['poll_seconds'] as int? ?? defaultPollSeconds,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      alertRules: AlertRule.listFromJson(map['alert_rules'] as String?) ??
          [
            AlertRule.fromLegacy(
              map['alert_on'] as String?,
              map['notification_title_template'] as String?,
              map['notification_body_template'] as String?,
            ),
          ],
      lastCount: map['last_count'] as int?,
      lastCheckedAt: map['last_checked_at'] == null
          ? null
          : DateTime.tryParse(map['last_checked_at'] as String),
      pinned: (map['pinned'] as int? ?? 0) == 1,
      lastError: map['last_error'] as String?,
      lastErrorAt: map['last_error_at'] == null
          ? null
          : DateTime.tryParse(map['last_error_at'] as String),
      scheduleWeekdays: _parseWeekdays(map['schedule_weekdays'] as String?),
      scheduleStartHour: map['schedule_start_hour'] as int? ?? defaultScheduleStartHour,
      scheduleEndHour: map['schedule_end_hour'] as int? ?? defaultScheduleEndHour,
    );
  }

  static List<int> _parseWeekdays(String? raw) {
    if (raw == null || raw.trim().isEmpty) return List.unmodifiable(defaultScheduleWeekdays);
    final parts = raw.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    return parts.isEmpty ? List.unmodifiable(defaultScheduleWeekdays) : List.unmodifiable(parts);
  }
}

const _sentinel = Object();
