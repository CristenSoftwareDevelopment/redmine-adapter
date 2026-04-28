/// Controls when an alert is fired for a monitored query.
/// - `any`: fire on any count change (default)
/// - `increase`: fire only when count increases
/// - `decrease`: fire only when count decreases
const alertOnAny = 'any';
const alertOnIncrease = 'increase';
const alertOnDecrease = 'decrease';

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
    this.alertOn = alertOnAny,
    this.lastCount,
    this.lastCheckedAt,
    this.notificationTitleTemplate,
    this.notificationBodyTemplate,
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
  final String alertOn;
  final int? lastCount;
  final DateTime? lastCheckedAt;

  /// Optional per-query notification templates. When set, override global settings.
  final String? notificationTitleTemplate;
  final String? notificationBodyTemplate;

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
    String? alertOn,
    int? lastCount,
    DateTime? lastCheckedAt,
    Object? notificationTitleTemplate = _sentinel,
    Object? notificationBodyTemplate = _sentinel,
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
      alertOn: alertOn ?? this.alertOn,
      lastCount: lastCount ?? this.lastCount,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      notificationTitleTemplate: notificationTitleTemplate == _sentinel
          ? this.notificationTitleTemplate
          : notificationTitleTemplate as String?,
      notificationBodyTemplate: notificationBodyTemplate == _sentinel
          ? this.notificationBodyTemplate
          : notificationBodyTemplate as String?,
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
      'alert_on': alertOn,
      'last_count': lastCount,
      'last_checked_at': lastCheckedAt?.toIso8601String(),
      'notification_title_template': notificationTitleTemplate,
      'notification_body_template': notificationBodyTemplate,
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
      alertOn: map['alert_on'] as String? ?? alertOnAny,
      lastCount: map['last_count'] as int?,
      lastCheckedAt: map['last_checked_at'] == null
          ? null
          : DateTime.tryParse(map['last_checked_at'] as String),
      notificationTitleTemplate: map['notification_title_template'] as String?,
      notificationBodyTemplate: map['notification_body_template'] as String?,
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
