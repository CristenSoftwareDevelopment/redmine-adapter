class QueryHealth {
  QueryHealth({
    required this.queryId,
    required this.queryName,
    required this.enabled,
    this.lastCheckedAt,
    this.lastCount,
    this.lastStatus = 'unknown',
    this.lastMessage,
  });

  final int queryId;
  final String queryName;
  final bool enabled;
  final DateTime? lastCheckedAt;
  final int? lastCount;
  final String lastStatus;
  final String? lastMessage;
}
