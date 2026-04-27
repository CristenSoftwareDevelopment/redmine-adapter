import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitor_log.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;

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

    return Container(
      decoration: surfaceCard(dark: dark),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Logs de monitoração',
                    style: AppText.cardTitle(dark: dark),
                  ),
                ),
                TextButton(
                  onPressed: state.monitorLogs.isEmpty ? null : state.clearMonitorLogs,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.notionBlue,
                  ),
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
                _filterChip('all', 'Todos', dark),
                _filterChip('info', 'Info', dark),
                _filterChip('error', 'Erro', dark),
                _filterChip('warn', 'Aviso', dark),
                _filterChip('alert', 'Alerta', dark),
                _filterChip('success', 'Sucesso', dark),
              ],
            ),
            const SizedBox(height: 10),
            if (logs.isEmpty)
              Text('Sem execuções registradas ainda.', style: AppText.captionLight(dark: dark))
            else
              ...logs.map((log) => _LogTile(log: log)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label, bool dark) {
    final selected = _levelFilter == value;
    final bg = selected
        ? AppColors.notionBlue
        : (dark ? AppColors.darkCard : AppColors.warmWhite);
    final textCol = selected ? AppColors.pureWhite : AppColors.warmGray500;
    final borderCol =
        selected ? AppColors.notionBlue : AppColors.whisperBorder;

    return GestureDetector(
      onTap: () => setState(() => _levelFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: borderCol),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textCol,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final MonitorLog log;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _levelColor(log.level);
    final queryPrefix = log.queryName == null ? '' : '[${log.queryName}] ';
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s8),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: Sp.s8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2825) : AppColors.warmWhite,
        border: Border(
          top: BorderSide(
              color: dark ? AppColors.darkBorder : AppColors.whisperBorder),
          right: BorderSide(
              color: dark ? AppColors.darkBorder : AppColors.whisperBorder),
          bottom: BorderSide(
              color: dark ? AppColors.darkBorder : AppColors.whisperBorder),
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$queryPrefix${log.message}',
                    style: AppText.body(dark: dark)),
                const SizedBox(height: Sp.s4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        log.level.toUpperCase(),
                        style: AppText.badge().copyWith(color: color),
                      ),
                    ),
                    const SizedBox(width: Sp.s8),
                    Text(
                      _fmtDate(log.createdAt),
                      style: AppText.microLabel(dark: dark),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (log.responseBody != null)
            IconButton(
              tooltip: 'Ver resposta da API',
              icon: const Icon(Icons.data_object_outlined,
                  size: 18, color: AppColors.warmGray500),
              onPressed: () =>
                  _showResponseModal(context, log.responseBody!, dark),
            ),
        ],
      ),
    ), // Container
    ), // ClipRRect
    ); // Padding
  }

  void _showResponseModal(BuildContext context, String rawBody, bool dark) {
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: surfaceCard(dark: dark),
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
                        style: AppText.bodyMedium(dark: dark),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                Divider(
                    color: dark
                        ? AppColors.darkBorder
                        : AppColors.whisperBorder),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      formatted,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                        color: dark
                            ? AppColors.warmGray300
                            : AppColors.warmGray500,
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

  Color _levelColor(String level) {
    switch (level) {
      case 'error':
        return AppColors.orange;
      case 'warn':
        return const Color(0xFFDD9900);
      case 'alert':
        return const Color(0xFF7B5EA7);
      case 'success':
        return AppColors.green;
      case 'info':
        return AppColors.notionBlue;
      default:
        return AppColors.warmGray500;
    }
  }

  String _fmtDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
