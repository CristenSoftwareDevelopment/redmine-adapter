import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitored_query.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'query_form_dialog.dart';

/// "Consultas" page: header with "Nova consulta", name search and one row per query.
class QueriesCard extends StatefulWidget {
  const QueriesCard({super.key});

  @override
  State<QueriesCard> createState() => _QueriesCardState();
}

class _QueriesCardState extends State<QueriesCard> {
  final _search = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final q = searchKey(_filter.trim());
    final filtered = state.queries.where((x) => searchKey(x.name).contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Consultas',
          subtitle: 'Defina o que acompanhar, quando verificar e como ser notificado.',
          actions: [
            FilledButton.icon(
              onPressed: () => openQueryForm(context),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Nova consulta'),
            ),
          ],
        ),
        FiltersPanel(
          controls: [
            SearchField(
              controller: _search,
              hint: 'Buscar consulta pelo nome…',
              onChanged: (v) => setState(() => _filter = v),
            ),
          ],
          summary: FilterSummary(
            text: '${filtered.length} consulta${filtered.length == 1 ? '' : 's'}',
            chips: [if (_filter.trim().isNotEmpty) 'Busca: ${_filter.trim()}'],
            onClear: () => setState(() {
              _search.clear();
              _filter = '';
            }),
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.queries.isEmpty)
                const EmptyState(text: 'Nenhuma consulta cadastrada ainda.')
              else if (filtered.isEmpty)
                const EmptyState(text: 'Nenhuma consulta encontrada.')
              else
                for (final query in filtered) _QueryRow(query: query),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the query form; saves a new or edited query.
Future<void> openQueryForm(BuildContext context, [MonitoredQuery? query]) async {
  final state = context.read<AppState>();
  final result = await showAppDialog<MonitoredQuery>(
    context,
    (_) => QueryFormDialog(initial: query),
  );
  if (result == null) return;
  if (result.id == null) {
    await state.addQuery(result);
  } else {
    await state.updateQuery(result);
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({required this.query});

  final MonitoredQuery query;

  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  String get _interval => query.pollSeconds % 60 == 0
      ? 'A cada ${query.pollSeconds ~/ 60} min'
      : 'A cada ${query.pollSeconds}s';

  String get _schedule {
    final days = query.scheduleWeekdays;
    final dayText = days.length == 5 && days.every((d) => d <= 5)
        ? 'Seg–Sex'
        : days.map((d) => _days[(d - 1).clamp(0, 6)]).join(', ');
    String h(int v) => '${v.toString().padLeft(2, '0')}h';
    return '$dayText ${h(query.scheduleStartHour)}–${h(query.scheduleEndHour)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final rules = query.alertRules;
    final source =
        SavedQuery.idFromEndpoint(query.endpoint) != null ? 'Consulta salva' : 'URL manual';

    return ListRow(
      leading: IconBox(icon: query.pinned ? Icons.push_pin_outlined : Icons.search),
      title: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(query.name),
          Tag(
            query.enabled ? 'Ativa' : 'Pausada',
            tone: query.enabled ? TagTone.green : TagTone.amber,
          ),
          if (query.lastError != null)
            Tooltip(
              message: 'Falhou em ${fmtDateTime(query.lastErrorAt)}\n${query.lastError}',
              child: const Tag('Falhou', tone: TagTone.red, icon: Icons.error_outline),
            ),
          if (query.pinned) const Tag('Board', tone: TagTone.accent),
        ],
      ),
      meta: [
        Text('${query.lastCount ?? '-'} tarefas · $_interval · $_schedule'),
        Text(
          [
            rules.isEmpty ? 'Sem regras (nunca notifica)' : rules.map((r) => r.label).join(' · '),
            source,
            'Última verificação ${fmtDateTime(query.lastCheckedAt)}',
          ].join(' · '),
        ),
      ],
      actions: [
        IconBtn(
          compact: true,
          icon: Icons.open_in_new,
          tooltip: 'Abrir consulta no Redmine',
          onPressed: () => openRedmineLink(context, query.directUrl),
        ),
        IconBtn(
          compact: true,
          icon: Icons.edit_outlined,
          tooltip: 'Editar consulta',
          onPressed: () => openQueryForm(context, query),
        ),
        PopupMenuButton<_QueryAction>(
          tooltip: 'Ações da consulta',
          onSelected: (action) => _handleAction(state, action),
          itemBuilder: (_) => [
            _item(
              _QueryAction.runNow,
              Icons.play_circle_outline,
              'Executar agora',
              enabled: query.id != null,
            ),
            _item(
              _QueryAction.toggle,
              query.enabled ? Icons.pause_circle_outline : Icons.play_arrow,
              query.enabled ? 'Pausar' : 'Ativar',
            ),
            _item(
              _QueryAction.pin,
              query.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              query.pinned ? 'Desafixar board' : 'Fixar como board',
              enabled: query.id != null,
            ),
            _item(_QueryAction.duplicate, Icons.copy_outlined, 'Duplicar'),
            const PopupMenuDivider(),
            _item(_QueryAction.delete, Icons.delete_outline, 'Excluir'),
          ],
          // The popup handles the tap; the button is only the visual.
          child: IgnorePointer(
            child: IconBtn(
              compact: true,
              icon: Icons.more_horiz,
              tooltip: 'Ações da consulta',
              onPressed: () {},
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<_QueryAction> _item(
    _QueryAction value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) =>
      PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
      );

  Future<void> _handleAction(AppState state, _QueryAction action) async {
    switch (action) {
      case _QueryAction.runNow:
        if (query.id != null) await state.runQueryNow(query.id!);
      case _QueryAction.toggle:
        await state.toggleQueryEnabled(query);
      case _QueryAction.pin:
        await state.togglePinned(query);
      case _QueryAction.duplicate:
        await state.duplicateQuery(query);
      case _QueryAction.delete:
        if (query.id != null) await state.deleteQuery(query.id!);
    }
  }
}

enum _QueryAction { runNow, toggle, pin, duplicate, delete }
