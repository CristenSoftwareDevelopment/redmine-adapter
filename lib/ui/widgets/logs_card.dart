import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitor_log.dart';
import '../../models/query_health.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';

const _levels = {
  'info': ('Informação', TagTone.blue),
  'success': ('Sucesso', TagTone.green),
  'error': ('Erro', TagTone.red),
  'warn': ('Aviso', TagTone.amber),
  'alert': ('Alerta', TagTone.purple),
};

Tag _levelTag(String level) {
  final (label, tone) = _levels[level] ?? ('Sem execução', TagTone.neutral);
  return Tag(label, tone: tone);
}

/// "Logs e saúde": health per query, filters and the execution history.
class LogsCard extends StatefulWidget {
  const LogsCard({super.key});

  @override
  State<LogsCard> createState() => _LogsCardState();
}

class _LogsCardState extends State<LogsCard> {
  final _search = TextEditingController();
  String _level = '';
  bool _moreFilters = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        _search.clear();
        _level = '';
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final q = searchKey(_search.text.trim());
    final logs = [
      for (final log in state.monitorLogs)
        if ((_level.isEmpty || log.level == _level) &&
            (q.isEmpty || searchKey('${log.queryName ?? ''} ${log.message}').contains(q)))
          log,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Logs e saúde',
          subtitle: 'Acompanhe verificações e investigue falhas nas consultas.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelHead(
                title: Text('Saúde da monitoração'),
                subtitle: 'Último registro disponível por consulta.',
              ),
              if (state.queryHealth.isEmpty)
                const EmptyState(text: 'Sem consultas cadastradas.')
              else
                for (final item in state.queryHealth)
                  _HealthRow(
                    item: item,
                    onShowLogs: () => setState(() {
                      _search.text = item.queryName;
                    }),
                  ),
            ],
          ),
        ),
        FiltersPanel(
          controls: [
            SearchField(
              controller: _search,
              hint: 'Buscar na mensagem do log…',
              onChanged: (_) => setState(() {}),
            ),
          ],
          actions: [
            MoreFiltersButton(
              open: _moreFilters,
              onPressed: () => setState(() => _moreFilters = !_moreFilters),
            ),
          ],
          extra: !_moreFilters
              ? null
              : [
                  LabeledField(
                    label: 'Nível',
                    child: SelectBox<String>(
                      value: _level,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Todos os níveis')),
                        for (final e in _levels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
                      ],
                      onChanged: (v) => setState(() => _level = v ?? ''),
                    ),
                  ),
                ],
          summary: FilterSummary(
            text: '${logs.length} registro${logs.length == 1 ? '' : 's'}',
            chips: [
              if (_level.isNotEmpty) _levels[_level]!.$1,
              if (_search.text.trim().isNotEmpty) 'Busca: ${_search.text.trim()}',
            ],
            onClear: _clear,
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelHead(
                title: const Text('Histórico de execução'),
                trailing: TextButton(
                  onPressed: state.monitorLogs.isEmpty ? null : state.clearMonitorLogs,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger(dark: dark)),
                  child: const Text('Limpar histórico'),
                ),
              ),
              if (logs.isEmpty)
                const EmptyState(text: 'Nenhum registro corresponde à seleção.')
              else
                for (final log in logs) _LogRow(log: log),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.item, required this.onShowLogs});

  final QueryHealth item;
  final VoidCallback onShowLogs;

  @override
  Widget build(BuildContext context) {
    final failed = item.lastStatus == 'error';
    return ListRow(
      leading: IconBox(icon: failed ? Icons.monitor_heart_outlined : Icons.verified_user_outlined),
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(item.queryName), _levelTag(item.lastStatus)],
      ),
      meta: [
        Text(
          '${item.enabled ? 'Ativa' : 'Pausada'} · Última execução ${fmtDateTime(item.lastCheckedAt)}'
          ' · Contagem: ${item.lastCount ?? '-'}',
        ),
        if (item.lastMessage != null)
          Text(item.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
      actions: [
        OutlinedButton(onPressed: onShowLogs, child: const Text('Ver logs')),
      ],
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({required this.log});

  final MonitorLog log;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _details = false;

  String get _formattedBody {
    final raw = widget.log.responseBody!;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final log = widget.log;
    return ListRow(
      accentBorder: AppColors.logLevel(log.level),
      title: Text(log.message, style: AppText.body(dark: dark)),
      meta: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _levelTag(log.level),
            Text(
              [fmtDateTime(log.createdAt), if (log.queryName != null) log.queryName!].join(' · '),
            ),
          ],
        ),
      ],
      below: log.responseBody == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.mutedText(dark: dark),
                  ),
                  onPressed: () => setState(() => _details = !_details),
                  icon: Icon(_details ? Icons.expand_less : Icons.chevron_right, size: 16),
                  label: const Text('Detalhes técnicos'),
                ),
                if (_details)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.well(dark: dark),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _formattedBody,
                        style: AppText.mono(dark: dark),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
