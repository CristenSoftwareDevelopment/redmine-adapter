import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitored_query.dart';
import '../../models/redmine_issue.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'issue_detail_dialog.dart';

/// Jira-like board (one column per status) or list of a query's issues.
/// Dragging a card to another column changes the issue status in Redmine.
class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.query});

  final MonitoredQuery query;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  final _api = RedmineApiService();
  final _hScroll = ScrollController();

  List<RedmineIssue>? _issues;
  List<Map<String, dynamic>> _statuses = const [];
  List<int> _priorityIds = const [];
  int _defaultPriority = 0;
  String? _error;
  bool _loading = false;
  int _loadSeq = 0;
  final Set<int> _moving = {};

  /// Statuses that had issues this session: automatic columns never vanish.
  final Set<int> _seen = {};

  /// Mode, filters and grouping; saved per board on every change.
  late BoardPrefs _prefs = widget.query.boardPrefs;
  bool _moreFilters = false;
  final _searchCtl = TextEditingController();
  String _search = '';

  /// Projects for the "Ágil" board scope.
  List<({int id, String name})>? _projects;

  bool get _agile => widget.query.id == agileQueryId;

  @override
  void initState() {
    super.initState();
    _load();
    if (_agile) {
      _api.listProjects(context.read<AppState>().settings).then((p) {
        if (mounted) setState(() => _projects = p);
      }, onError: (Object _) {});
    }
  }

  @override
  void didUpdateWidget(BoardView old) {
    super.didUpdateWidget(old);
    // New scope ("Ágil") or an edited query URL.
    if (old.query.endpoint != widget.query.endpoint) _load();
  }

  /// Saves a new scope for the "Ágil" board; the board reloads via [didUpdateWidget].
  void _setScope(AgileBoard Function(AgileBoard) change) {
    final state = context.read<AppState>();
    state.savePreferences(
      state.settings.copyWith(agileBoard: change(state.settings.agileBoard)),
    );
  }

  /// "Ágil" scope: project, assignee and open/all, filtered by Redmine.
  List<Widget> _scopeControls() {
    final board = context.watch<AppState>().settings.agileBoard;
    return [
      SizedBox(
        width: 260,
        child: SearchSelect(
          value: board.projectId,
          options: [
            for (final p in _projects ?? const <({int id, String name})>[]) (p.id, p.name),
            // The saved project shows by name even before the list loads.
            if (board.projectId != null &&
                !(_projects ?? const []).any((p) => p.id == board.projectId))
              (board.projectId!, board.projectName ?? '?'),
          ],
          none: 'Todos os projetos',
          onChanged: (id) => _setScope(
            (b) => b.copyWith(
              projectId: id,
              projectName: _projects?.where((p) => p.id == id).firstOrNull?.name,
            ),
          ),
        ),
      ),
      SelectBox<bool>(
        value: board.mine,
        minWidth: 170,
        items: const [
          DropdownMenuItem(value: true, child: Text('Minhas tarefas')),
          DropdownMenuItem(value: false, child: Text('Qualquer responsável')),
        ],
        onChanged: (v) => _setScope((b) => b.copyWith(mine: v)),
      ),
      SelectBox<bool>(
        value: board.openOnly,
        minWidth: 150,
        items: const [
          DropdownMenuItem(value: true, child: Text('Abertas')),
          DropdownMenuItem(value: false, child: Text('Todas as situações')),
        ],
        onChanged: (v) => _setScope((b) => b.copyWith(openOnly: v)),
      ),
    ];
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_statuses.isEmpty) {
        final [statuses, priorities] = await Future.wait([
          _api.getJson(settings, '/issue_statuses.json'),
          _api.getJson(settings, '/enumerations/issue_priorities.json'),
        ]);
        _statuses = (statuses['issue_statuses'] as List).cast<Map<String, dynamic>>();
        final prios = (priorities['issue_priorities'] as List).cast<Map<String, dynamic>>();
        _priorityIds = [for (final p in prios) p['id'] as int];
        _defaultPriority = max(0, prios.indexWhere((p) => p['is_default'] == true));
      }
      final issues = await _api.getAllPages(settings, widget.query.endpoint, 'issues');
      // A newer load (e.g. after another drag) owns the screen now.
      if (mounted && seq == _loadSeq) {
        setState(() {
          _issues = issues.map(RedmineIssue.new).toList();
          _seen.addAll(_issues!.map((i) => i.statusId));
        });
      }
    } catch (error) {
      if (mounted && seq == _loadSeq) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  /// Optimistic move; Redmine silently ignores transitions outside the
  /// workflow (still 204), so the issue is re-read to confirm.
  Future<void> _move(RedmineIssue issue, Map<String, dynamic> status) async {
    final settings = context.read<AppState>().settings;
    final messenger = ScaffoldMessenger.of(context);
    final previous = issue.json['status'];
    final targetId = status['id'] as int;
    setState(() {
      issue.json['status'] = {'id': targetId, 'name': status['name']};
      _moving.add(issue.id);
    });

    String? problem;
    try {
      if (!await _api.setIssueStatus(settings, issue.id, targetId)) {
        problem = 'O Redmine não aplicou a mudança de #${issue.id}: '
            'transição não permitida pelo workflow ou sem permissão.';
      }
    } catch (error) {
      problem = 'Falha ao mover #${issue.id}: ${'$error'.replaceFirst('Exception: ', '')}';
    }
    if (!mounted) return;
    setState(() {
      _moving.remove(issue.id);
      if (problem != null) issue.json['status'] = previous;
    });
    messenger.showSnackBar(
      SnackBar(content: Text(problem ?? '#${issue.id} movida para ${status['name']}.')),
    );
    // The issue may no longer match the query filters.
    if (problem == null) unawaited(_load());
  }

  void _savePrefs(BoardPrefs prefs) {
    setState(() => _prefs = prefs);
    context.read<AppState>().setBoardPrefs(widget.query, prefs);
  }

  void _setFilter(String key, List<int> ids) => _savePrefs(
        _prefs.copyWith(filters: {..._prefs.filters, key: ids}..removeWhere((_, v) => v.isEmpty)),
      );

  List<RedmineIssue> get _visible {
    final q = searchKey(_search.trim()).replaceFirst('#', '');
    return [
      for (final i in _issues ?? const <RedmineIssue>[])
        if (matchesBoardFilters(i, _prefs.filters) &&
            (q.isEmpty || searchKey(i.subject).contains(q) || '${i.id}'.startsWith(q)))
          i,
    ];
  }

  /// Values of [key] among the loaded issues (+ saved filter ids no longer
  /// present, so they can be unchecked), in display order.
  List<(int, String)> _valuesOf(String key, String missing) {
    final names = <int, String>{
      for (final id in _prefs.filters[key] ?? const <int>[]) id: id == 0 ? missing : '#$id',
      for (final i in _issues ?? const <RedmineIssue>[])
        i.refId(key) ?? 0: i.nameOf(key) ?? missing,
    };
    return [for (final e in names.entries) (e.key, e.value)]..sort(compareRefs);
  }

  Set<int> get _closedStatusIds => {
        for (final s in _statuses)
          if (s['is_closed'] == true) s['id'] as int,
      };

  List<int> get _columnIds => boardColumnIds(
        statusOrder: [for (final s in _statuses) s['id'] as int],
        saved: widget.query.boardStatusIds,
        seen: _seen,
      );

  Future<void> _setColumns(List<int>? ids) =>
      context.read<AppState>().setBoardStatuses(widget.query, ids);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final visible = _visible;
    final columnIds = _columnIds;
    final listMode = _prefs.listMode;
    final hidden = listMode ? 0 : visible.where((i) => !columnIds.contains(i.statusId)).length;
    final count = visible.length - hidden;
    final fieldValues = {for (final f in boardFields) f.key: _valuesOf(f.key, f.missing)};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: widget.query.name,
          subtitle: _agile
              ? 'Escolha o escopo e explore as tarefas, sem precisar de consulta salva.'
              : 'Explore as tarefas da consulta e encontre o que precisa.',
          actions: [if (!listMode) _columnsMenu(columnIds)],
        ),
        FiltersPanel(
          controls: [
            if (_agile) ..._scopeControls(),
            SearchField(
              controller: _searchCtl,
              hint: 'Buscar tarefa pelo título ou #id…',
              onChanged: (v) => setState(() => _search = v),
            ),
            AppTabs<bool>(
              tabs: const [
                (false, 'Board', Icons.view_kanban_outlined),
                (true, 'Lista', Icons.view_list_outlined),
              ],
              selected: listMode,
              onChanged: (v) => _savePrefs(_prefs.copyWith(listMode: v)),
            ),
            SelectBox<String?>(
              value: _prefs.groupBy,
              minWidth: 170,
              items: [
                const DropdownMenuItem(value: null, child: Text('Sem agrupamento')),
                for (final f in boardFields)
                  if (f.key != 'status')
                    DropdownMenuItem(value: f.key, child: Text('Agrupar por ${f.label}')),
              ],
              onChanged: (v) => _savePrefs(_prefs.copyWith(groupBy: v)),
            ),
          ],
          actions: [
            MoreFiltersButton(
              open: _moreFilters,
              onPressed: () => setState(() => _moreFilters = !_moreFilters),
            ),
            IconBtn(
              icon: Icons.refresh,
              tooltip: 'Atualizar tarefas',
              onPressed: _loading ? null : _load,
            ),
            IconBtn(
              icon: Icons.open_in_new,
              tooltip: 'Abrir consulta no Redmine',
              onPressed: () => openRedmineLink(context, widget.query.directUrl),
            ),
          ],
          extra: !_moreFilters
              ? null
              : [
                  for (final f in boardFields)
                    // A field with a single value filters nothing (e.g. one project).
                    if (fieldValues[f.key]!.length > 1)
                      _filterMenu(f.key, f.label, fieldValues[f.key]!),
                ],
          summary: FilterSummary(
            text: [
              '$count tarefa${count == 1 ? '' : 's'}',
              if (hidden > 0) '$hidden em colunas ocultas',
              // getAllPages stops at 500.
              if ((_issues?.length ?? 0) >= 500) 'mostrando as primeiras 500, refine o escopo',
            ].join(' · '),
            chips: [
              for (final f in boardFields)
                if (_prefs.filters[f.key] case final ids?)
                  '${f.label}: ${_names(fieldValues[f.key]!, ids)}',
              if (_search.trim().isNotEmpty) 'Busca: ${_search.trim()}',
            ],
            onClear: () {
              setState(() {
                _search = '';
                _searchCtl.clear();
              });
              if (_prefs.filters.isNotEmpty) _savePrefs(_prefs.copyWith(filters: const {}));
            },
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.danger(dark: dark)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Não foi possível carregar: $_error',
                    style: AppText.captionLight(dark: dark).copyWith(
                      color: AppColors.danger(dark: dark),
                    ),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Tentar de novo')),
              ],
            ),
          ),
        Expanded(
          child: _issues == null
              ? (_error == null
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox())
              : listMode
                  ? _list(visible, dark)
                  : _prefs.groupBy == null
                      ? _board(visible, dark)
                      : _lanes(visible, dark),
        ),
      ],
    );
  }

  /// Multiselect of the board columns; the choice is saved per board.
  Widget _columnsMenu(List<int> columnIds) {
    return MenuAnchor(
      menuChildren: [
        for (final s in _statuses)
          CheckboxMenuButton(
            value: columnIds.contains(s['id']),
            closeOnActivate: false,
            onChanged: (checked) => _setColumns(
              checked == true
                  ? [...columnIds, s['id'] as int]
                  : columnIds.where((id) => id != s['id']).toList(),
            ),
            child: Text('${s['name']}'),
          ),
        const Divider(height: 1),
        MenuItemButton(
          onPressed: () => _setColumns([for (final s in _statuses) s['id'] as int]),
          child: const Text('Mostrar todas'),
        ),
        MenuItemButton(
          onPressed: () => _setColumns(null),
          child: const Text('Só status com tarefas'),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.view_column_outlined, size: 17),
        label: Text('Colunas ${columnIds.length}/${_statuses.length}'),
      ),
    );
  }

  String _names(List<(int, String)> values, List<int> ids) => [
        for (final (id, name) in values)
          if (ids.contains(id)) name
      ].join(', ');

  /// Multiselect of one issue field; nothing checked = every value.
  Widget _filterMenu(String key, String label, List<(int, String)> values) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected = _prefs.filters[key] ?? const <int>[];
    return LabeledField(
      label: label,
      child: MenuAnchor(
        menuChildren: [
          for (final (id, name) in values)
            CheckboxMenuButton(
              value: selected.contains(id),
              closeOnActivate: false,
              onChanged: (checked) => _setFilter(
                key,
                checked == true ? [...selected, id] : selected.where((v) => v != id).toList(),
              ),
              child: Text(name),
            ),
          if (selected.isNotEmpty) ...[
            const Divider(height: 1),
            MenuItemButton(onPressed: () => _setFilter(key, const []), child: const Text('Todos')),
          ],
        ],
        builder: (context, controller, _) => ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 170, maxWidth: 280),
          child: ControlBox(
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    selected.isEmpty ? 'Todos' : _names(values, selected),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(dark: dark),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_drop_down, color: AppColors.mutedText(dark: dark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Board ──────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _columns(List<RedmineIssue> visible) {
    final names = {
      for (final i in visible) i.statusId: i.statusName,
      for (final s in _statuses) s['id'] as int: '${s['name']}',
    };
    return [
      for (final id in _columnIds) {'id': id, 'name': names[id] ?? '#$id'},
    ];
  }

  Widget _board(List<RedmineIssue> visible, bool dark) {
    final closed = _closedStatusIds;
    final multiProject = visible.map((i) => i.projectName).toSet().length > 1;

    final columns = _columns(visible);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = boardColumnWidth(constraints.maxWidth, columns.length);
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: ListView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 15),
            children: [
              for (final status in columns)
                _column(
                  status,
                  [
                    for (final i in visible)
                      if (i.statusId == status['id']) i,
                  ],
                  closed,
                  multiProject,
                  dark,
                  width: width,
                ),
            ],
          ),
        );
      },
    );
  }

  /// One lane per value of the grouped field, each with the status columns.
  /// Lanes share one horizontal scroll so the columns stay aligned.
  Widget _lanes(List<RedmineIssue> visible, bool dark) {
    final key = _prefs.groupBy!;
    final missing = boardFields.where((f) => f.key == key).firstOrNull?.missing ?? '-';
    final columns = _columns(visible);
    final closed = _closedStatusIds;
    final multiProject = visible.map((i) => i.projectName).toSet().length > 1;

    return LayoutBuilder(builder: (context, constraints) {
      final width = boardColumnWidth(constraints.maxWidth, columns.length);
      return Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 15),
          child: SizedBox(
            width: max(columns.length * (width + 14), 300),
            child: ListView(
              children: [
                for (final group in groupIssues(visible, key, missing)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
                    child: Row(
                      children: [
                        Text(group.name, style: AppText.bodySemibold(dark: dark)),
                        const SizedBox(width: 8),
                        Tag('${group.issues.length}'),
                      ],
                    ),
                  ),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final status in columns)
                          _column(
                            status,
                            [
                              for (final i in group.issues)
                                if (i.statusId == status['id']) i,
                            ],
                            closed,
                            multiProject,
                            dark,
                            width: width,
                            lane: group.id,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  /// Status column. Inside a [lane] it grows with its cards and only accepts
  /// cards of the same lane (a drop changes the status, not the grouped field).
  Widget _column(
    Map<String, dynamic> status,
    List<RedmineIssue> issues,
    Set<int> closed,
    bool multiProject,
    bool dark, {
    required double width,
    int? lane,
  }) {
    final id = status['id'] as int;
    final name = '${status['name']}';
    final (_, dotColor) = AppColors.tone(Tag.hashed(name).tone, dark: dark);
    final Widget cards = issues.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Nenhuma tarefa',
              textAlign: TextAlign.center,
              style: AppText.microLabel(dark: dark),
            ),
          )
        : lane != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final i in issues) _card(i, closed, multiProject, dark, width)],
              )
            : ListView.builder(
                itemCount: issues.length,
                itemBuilder: (context, index) =>
                    _card(issues[index], closed, multiProject, dark, width),
              );
    return Container(
      // Keys keep the dragged card mounted when columns change mid-drag.
      key: ValueKey(id),
      width: width,
      margin: const EdgeInsets.only(right: 14),
      child: DragTarget<RedmineIssue>(
        onWillAcceptWithDetails: (d) =>
            d.data.statusId != id && (lane == null || (d.data.refId(_prefs.groupBy!) ?? 0) == lane),
        onAcceptWithDetails: (d) => _move(d.data, status),
        builder: (context, candidates, _) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.column(dark: dark),
            borderRadius: BorderRadius.circular(AppRadius.comfortable),
            border: Border.all(
              color: candidates.isNotEmpty
                  ? AppColors.accent(dark: dark)
                  : AppColors.columnBorder(dark: dark),
              width: candidates.isNotEmpty ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 3, 2, 14),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(dark: dark).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.sectionText(dark: dark),
                        ),
                      ),
                    ),
                    if (closed.contains(id)) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check, size: 12, color: AppColors.mutedText(dark: dark)),
                    ],
                    const SizedBox(width: 8),
                    Tag('${issues.length}'),
                  ],
                ),
              ),
              if (lane == null) Expanded(child: cards) else cards,
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(RedmineIssue issue, Set<int> closed, bool multiProject, bool dark, double width) {
    final card = _IssueCard(
      issue: issue,
      priority: _priorityIcon(issue),
      closed: closed.contains(issue.statusId),
      showProject: multiProject,
      busy: _moving.contains(issue.id),
      dark: dark,
      onTap: () => showIssueDetail(context, issue),
    );
    return Padding(
      key: ValueKey(issue.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: Draggable<RedmineIssue>(
        data: issue,
        maxSimultaneousDrags: _moving.contains(issue.id) ? 0 : 1,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: width - 24,
            child: Transform.rotate(angle: 0.03, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      ),
    );
  }

  /// Arrow relative to the default priority of this Redmine (nothing fixed by name).
  Widget _priorityIcon(RedmineIssue issue) {
    final level = _priorityIds.indexOf(issue.priorityId ?? -1) - _defaultPriority;
    final (icon, tone) = switch (level) {
      < 0 => (Icons.arrow_downward, TagTone.blue),
      0 => (Icons.drag_handle, TagTone.amber),
      1 => (Icons.arrow_upward, TagTone.red),
      _ => (Icons.keyboard_double_arrow_up, TagTone.red),
    };
    final (_, color) = AppColors.tone(tone, dark: Theme.of(context).brightness == Brightness.dark);
    return Tooltip(
      message: 'Prioridade: ${issue.priorityName}',
      child: Icon(icon, size: 15, color: color),
    );
  }

  // ── List ───────────────────────────────────────────────────────────────────

  Widget _list(List<RedmineIssue> visible, bool dark) {
    final closed = _closedStatusIds;
    final border = BorderSide(color: AppColors.border(dark: dark));
    Widget headCell(String text, {double? width}) {
      final label = Text(text, style: AppText.microLabel(dark: dark).copyWith(fontSize: 11));
      return width == null ? Expanded(child: label) : SizedBox(width: width, child: label);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      decoration: surfaceCard(dark: dark),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 980;
          Widget row(List<Widget> cells, {Color? color}) => Container(
                color: color,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: cells),
              );
          // Grouped: a header row before each group's issues.
          final key = _prefs.groupBy;
          final missing = boardFields.where((f) => f.key == key).firstOrNull?.missing ?? '-';
          final List<Object> items = key == null
              ? visible
              : [
                  for (final g in groupIssues(visible, key, missing)) ...[
                    '${g.name}  ·  ${g.issues.length}',
                    ...g.issues,
                  ],
                ];
          return ListView.builder(
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return row(
                  [
                    headCell('Tarefa'),
                    headCell('Situação', width: 170),
                    headCell('Responsável', width: 190),
                    headCell('Tipo', width: 150),
                    headCell('Prioridade', width: 130),
                    if (wide) headCell('Atualizada', width: 150),
                  ],
                  color: AppColors.sunken(dark: dark),
                );
              }
              final item = items[index - 1];
              if (item is String) {
                return Container(
                  color: AppColors.column(dark: dark),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Text(item, style: AppText.bodySemibold(dark: dark)),
                );
              }
              final issue = item as RedmineIssue;
              return InkWell(
                onTap: () => showIssueDetail(context, issue),
                hoverColor: AppColors.cellHover(dark: dark),
                child: Container(
                  decoration: BoxDecoration(border: Border(top: border)),
                  child: row([
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IssueNumber(
                            issue.id,
                            style: AppText.microLabel(dark: dark).copyWith(
                              color: AppColors.accent(dark: dark),
                              decoration: closed.contains(issue.statusId)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            issue.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(dark: dark),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // Same path as dragging a card on the board.
                        child: PopupMenuButton<Map<String, dynamic>>(
                          tooltip: 'Alterar situação',
                          enabled: !_moving.contains(issue.id),
                          onSelected: (status) => _move(issue, status),
                          itemBuilder: (_) => [
                            for (final s in _statuses)
                              if (s['id'] != issue.statusId)
                                PopupMenuItem(value: s, child: Text('${s['name']}')),
                          ],
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Tag(issue.statusName)),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                                color: AppColors.mutedText(dark: dark),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: issue.assigneeName == null
                          ? Text('-', style: AppText.microLabel(dark: dark))
                          : Row(
                              children: [
                                UserAvatar(name: issue.assigneeName!, size: 24),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    issue.assigneeName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body(dark: dark),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    SizedBox(
                      width: 150,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: issue.trackerName.isEmpty
                            ? const SizedBox()
                            : Tag.hashed(issue.trackerName),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: Row(
                        children: [
                          _priorityIcon(issue),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              issue.priorityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(dark: dark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (wide)
                      SizedBox(
                        width: 150,
                        child: Text(
                          fmtDateTime(issue.updatedOn),
                          style: AppText.microLabel(dark: dark),
                        ),
                      ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.priority,
    required this.closed,
    required this.showProject,
    required this.busy,
    required this.dark,
    required this.onTap,
  });

  final RedmineIssue issue;
  final Widget priority;
  final bool closed;
  final bool showProject;
  final bool busy;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Material(
        color: AppColors.panel(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: AppColors.border(dark: dark)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showProject) ...[
                  Text(
                    issue.projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.microLabel(dark: dark).copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  issue.subject,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyMedium(dark: dark).copyWith(fontSize: 13),
                ),
                if (issue.trackerName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Tag.hashed(issue.trackerName),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    priority,
                    const SizedBox(width: 5),
                    IssueNumber(
                      issue.id,
                      style: AppText.microLabel(dark: dark).copyWith(
                        fontSize: 11,
                        decoration: closed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const Spacer(),
                    if (busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (issue.assigneeName != null)
                      UserAvatar(name: issue.assigneeName!, size: 26),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status columns stretch to fill [available] width (270–480 each, plus a
/// 14 px right margin); below 270 the board scrolls sideways.
double boardColumnWidth(double available, int columns) =>
    columns == 0 ? 270 : (available / columns - 14).clamp(270, 480);

/// Issue references the board can filter and group by.
const boardFields = [
  (key: 'fixed_version', label: 'Versão', missing: 'Sem versão'),
  (key: 'tracker', label: 'Tipo', missing: 'Sem tipo'),
  (key: 'status', label: 'Situação', missing: 'Sem situação'),
  (key: 'assigned_to', label: 'Responsável', missing: 'Sem responsável'),
  (key: 'author', label: 'Autor', missing: 'Sem autor'),
  (key: 'priority', label: 'Prioridade', missing: 'Sem prioridade'),
  (key: 'project', label: 'Projeto', missing: 'Sem projeto'),
  (key: 'category', label: 'Categoria', missing: 'Sem categoria'),
];

/// Every filtered field must match (empty list = any value); an issue
/// without the reference counts as id 0.
bool matchesBoardFilters(RedmineIssue issue, Map<String, List<int>> filters) =>
    filters.entries.every((f) => f.value.isEmpty || f.value.contains(issue.refId(f.key) ?? 0));

/// Case-insensitive, with digit runs compared as numbers: 3.79 < 3.80 < 3.100.
int compareNatural(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final pa = chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < min(pa.length, pb.length); i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = na != null && nb != null ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// Natural name order, with the "missing" value (id 0) last.
int compareRefs((int, String) a, (int, String) b) =>
    a.$1 == 0 ? (b.$1 == 0 ? 0 : 1) : (b.$1 == 0 ? -1 : compareNatural(a.$2, b.$2));

/// [issues] split by the [key] reference, groups in [compareRefs] order.
List<({int id, String name, List<RedmineIssue> issues})> groupIssues(
  List<RedmineIssue> issues,
  String key,
  String missing,
) {
  final groups = <(int, String), List<RedmineIssue>>{};
  for (final i in issues) {
    (groups[(i.refId(key) ?? 0, i.nameOf(key) ?? missing)] ??= []).add(i);
  }
  return [
    for (final ref in groups.keys.toList()..sort(compareRefs))
      (id: ref.$1, name: ref.$2, issues: groups[ref]!),
  ];
}

/// Status ids shown as board columns, in Redmine's status order.
/// [saved] is the user's choice for the board (null = automatic: every status
/// that had issues this session, in [seen]). Unknown ids that still have
/// issues go last.
List<int> boardColumnIds({
  required List<int> statusOrder,
  required List<int>? saved,
  required Set<int> seen,
}) {
  final wanted = saved?.toSet() ?? seen;
  return [
    for (final id in statusOrder)
      if (wanted.contains(id)) id,
    for (final id in seen)
      if (wanted.contains(id) && !statusOrder.contains(id)) id,
  ];
}
