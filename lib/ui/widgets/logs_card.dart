import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitor_log.dart';
import '../../state/app_state.dart';

class LogsCard extends StatefulWidget {
  const LogsCard({super.key});

  @override
  State<LogsCard> createState() => _LogsCardState();
}

class _LogsCardState extends State<LogsCard> {
  final TextEditingController _searchController = TextEditingController();
  String _levelFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final search = _searchController.text.trim().toLowerCase();
    final logs = state.monitorLogs.where((log) {
      if (_levelFilter != 'all' && log.level != _levelFilter) {
        return false;
      }
      if (search.isEmpty) {
        return true;
      }
      final full = '${log.queryName ?? ''} ${log.message}'.toLowerCase();
      return full.contains(search);
    }).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Logs de monitoracao',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: state.monitorLogs.isEmpty ? null : state.clearMonitorLogs,
                  child: const Text('Limpar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar em logs',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('all', 'Todos'),
                _filterChip('info', 'Info'),
                _filterChip('error', 'Erro'),
                _filterChip('warn', 'Aviso'),
                _filterChip('alert', 'Alerta'),
                _filterChip('success', 'Sucesso'),
              ],
            ),
            const SizedBox(height: 10),
            if (logs.isEmpty)
              const Text('Sem execucoes registradas ainda.')
            else
              ...logs.map((log) => _LogTile(log: log)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _levelFilter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _levelFilter = value),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final MonitorLog log;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(context, log.level);
    final queryPrefix = log.queryName == null ? '' : '[${log.queryName}] ';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
                Text('$queryPrefix${log.message}'),
                const SizedBox(height: 2),
                Text(
                  '${log.level.toUpperCase()} • ${_fmtDate(log.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (log.responseBody != null)
            IconButton(
              tooltip: 'Ver resposta da API',
              icon: const Icon(Icons.data_object_outlined, size: 18),
              onPressed: () => _showResponseModal(context, log.responseBody!),
            ),
        ],
      ),
    );
  }

  void _showResponseModal(BuildContext context, String rawBody) {
    String formatted;
    try {
      final decoded = jsonDecode(rawBody);
      formatted = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      formatted = rawBody;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.data_object_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Resposta da API',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      formatted,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _levelColor(BuildContext context, String level) {
    final scheme = Theme.of(context).colorScheme;
    switch (level) {
      case 'error':
        return scheme.error;
      case 'warn':
        return Colors.orange;
      case 'alert':
        return Colors.deepPurple;
      case 'success':
        return Colors.green;
      case 'info':
        return scheme.primary;
      default:
        return scheme.outline;
    }
  }

  String _fmtDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
