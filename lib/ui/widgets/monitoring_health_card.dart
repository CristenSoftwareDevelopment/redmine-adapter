import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/query_health.dart';
import '../../state/app_state.dart';

class MonitoringHealthCard extends StatelessWidget {
  const MonitoringHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final health = state.queryHealth;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saude da monitoracao',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (health.isEmpty)
              const Text('Sem consultas cadastradas.')
            else
              ...health.map((item) => _HealthTile(item: item)),
          ],
        ),
      ),
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.item});

  final QueryHealth item;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, item.lastStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.queryName, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('Status: ${item.lastStatus.toUpperCase()} • Ativa: ${item.enabled ? 'sim' : 'nao'}'),
                Text('Ultima execucao: ${_fmtDate(item.lastCheckedAt)} • Ultimo total: ${item.lastCount ?? '-'}'),
                if (item.lastMessage != null)
                  Text(
                    item.lastMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'error':
        return scheme.error;
      case 'warn':
        return Colors.orange;
      case 'alert':
        return Colors.deepPurple;
      case 'success':
        return Colors.green;
      default:
        return scheme.primary;
    }
  }

  String _fmtDate(DateTime? date) {
    if (date == null) {
      return '-';
    }
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
