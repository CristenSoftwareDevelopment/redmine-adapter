class MonitorLog {
  MonitorLog({
    this.id,
    required this.level,
    required this.message,
    this.queryName,
    required this.createdAt,
  });

  final int? id;
  final String level;
  final String message;
  final String? queryName;
  final DateTime createdAt;

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'level': level,
      'message': message,
      'query_name': queryName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static MonitorLog fromDbMap(Map<String, Object?> map) {
    return MonitorLog(
      id: map['id'] as int,
      level: map['level'] as String,
      message: map['message'] as String,
      queryName: map['query_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
