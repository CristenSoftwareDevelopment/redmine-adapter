class AlertEvent {
  AlertEvent({
    this.id,
    required this.queryId,
    required this.queryName,
    required this.previousCount,
    required this.currentCount,
    required this.directUrl,
    required this.createdAt,
    this.isRead = false,
  });

  final int? id;
  final int queryId;
  final String queryName;
  final int previousCount;
  final int currentCount;
  final String directUrl;
  final DateTime createdAt;
  final bool isRead;

  int get diff => currentCount - previousCount;

  AlertEvent copyWith({bool? isRead}) {
    return AlertEvent(
      id: id,
      queryId: queryId,
      queryName: queryName,
      previousCount: previousCount,
      currentCount: currentCount,
      directUrl: directUrl,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'query_id': queryId,
      'query_name': queryName,
      'previous_count': previousCount,
      'current_count': currentCount,
      'direct_url': directUrl,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead ? 1 : 0,
    };
  }

  static AlertEvent fromDbMap(Map<String, Object?> map) {
    return AlertEvent(
      id: map['id'] as int,
      queryId: map['query_id'] as int,
      queryName: map['query_name'] as String,
      previousCount: map['previous_count'] as int,
      currentCount: map['current_count'] as int,
      directUrl: map['direct_url'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isRead: (map['is_read'] as int? ?? 0) == 1,
    );
  }
}
