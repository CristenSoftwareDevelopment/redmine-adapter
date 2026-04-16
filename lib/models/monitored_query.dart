/// Controls when an alert is fired for a monitored query.
/// - `any`: fire on any count change (default)
/// - `increase`: fire only when count increases
/// - `decrease`: fire only when count decreases
const alertOnAny = 'any';
const alertOnIncrease = 'increase';
const alertOnDecrease = 'decrease';

class MonitoredQuery {
  MonitoredQuery({
    this.id,
    required this.name,
    required this.endpoint,
    required this.directUrl,
    this.countPath = 'total_count',
    this.pollSeconds,
    this.enabled = true,
    this.alertOn = alertOnAny,
    this.lastCount,
    this.lastCheckedAt,
    this.notificationTitleTemplate,
    this.notificationBodyTemplate,
  });

  final int? id;
  final String name;
  final String endpoint;
  final String directUrl;
  final String countPath;
  final int? pollSeconds;
  final bool enabled;
  final String alertOn;
  final int? lastCount;
  final DateTime? lastCheckedAt;

  /// Optional per-query notification templates. When set, override global settings.
  final String? notificationTitleTemplate;
  final String? notificationBodyTemplate;

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
    };
  }

  static MonitoredQuery fromDbMap(Map<String, Object?> map) {
    return MonitoredQuery(
      id: map['id'] as int,
      name: map['name'] as String,
      endpoint: map['endpoint'] as String,
      directUrl: map['direct_url'] as String,
      countPath: map['count_path'] as String? ?? 'total_count',
      pollSeconds: map['poll_seconds'] as int?,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      alertOn: map['alert_on'] as String? ?? alertOnAny,
      lastCount: map['last_count'] as int?,
      lastCheckedAt: map['last_checked_at'] == null
          ? null
          : DateTime.tryParse(map['last_checked_at'] as String),
      notificationTitleTemplate: map['notification_title_template'] as String?,
      notificationBodyTemplate: map['notification_body_template'] as String?,
    );
  }
}

const _sentinel = Object();
