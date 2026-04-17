class MonitorLog {
  MonitorLog({
    this.id,
    required this.level,
    required this.message,
    this.queryName,
    required this.createdAt,
    this.responseBody,
  });

  final int? id;
  final String level;
  final String message;
  final String? queryName;
  final DateTime createdAt;

  /// Raw JSON response body from the API, stored only for 'success' entries.
  final String? responseBody;

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'level': level,
      'message': message,
      'query_name': queryName,
      'created_at': createdAt.toIso8601String(),
      'response_body': responseBody,
    };
  }

  static MonitorLog fromDbMap(Map<String, Object?> map) {
    return MonitorLog(
      id: map['id'] as int,
      level: map['level'] as String,
      message: map['message'] as String,
      queryName: map['query_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      responseBody: map['response_body'] as String?,
    );
  }
}
