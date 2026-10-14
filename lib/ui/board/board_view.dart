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

  bool _listMode = false;
  bool _moreFilters = false;
  final _searchCtl = TextEditingController();
  String _search = '';
  int? _assigneeId; // null = everyone, 0 = unassigned

  @override
  void initState() {
    super.initState();
    _load();
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
      await _api.putJson(settings, '/issues/${issue.id}.json', {
        'issue': {'status_id': targetId},
      });
      final fresh = await _api.getJson(settings, '/issues/${issue.id}.json');
      if (fresh['issue']['status']['id'] != targetId) {
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

  List<RedmineIssue> get _visible {
    final q = searchKey(_search.trim()).replaceFirst('#', '');
    return [
      for (final i in _issues ?? const <RedmineIssue>[])
        if ((_assigneeId == null || (i.assigneeId ?? 0) == _assigneeId) &&
            (q.isEmpty || searchKey(i.subject).contains(q) || '${i.id}'.startsWith(q)))
          i,
    ];
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
    final hidden = _listMode ? 0 : visible.where((i) => !columnIds.contains(i.statusId)).length;
    final count = visible.length - hidden;
    final assignees = <int, String>{
      for (final i in _issues ?? const <RedmineIssue>[])
        if (i.assigneeId != null) i.assigneeId!: i.assigneeName ?? '?',
    };
    final sortedAssignees = assignees.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: widget.query.name,
          subtitle: 'Explore as tarefas da consulta e encontre o que precisa.',
          actions: [if (!_listMode) _columnsMenu(columnIds)],
        ),
        FiltersPanel(
          controls: [
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
              selected: _listMode,
              onChanged: (v) => setState(() => _listMode = v),
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
                  LabeledField(
                    label: 'Responsável',
                    child: SelectBox<int?>(
                      value: _assigneeId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todos os responsáveis')),
                        const DropdownMenuItem(value: 0, child: Text('Sem responsável')),
                        for (final a in sortedAssignees)
                          DropdownMenuItem(value: a.key, child: Text(a.value)),
                      ],
                      onChanged: (v) => setState(() => _assigneeId = v),
                    ),
                  ),
                ],
          summary: FilterSummary(
            text: [
              '$count tarefa${count == 1 ? '' : 's'}',
              if (hidden > 0) '$hidden em colunas ocultas',
            ].join(' · '),
            chips: [
              if (_assigneeId != null)
                _assigneeId == 0 ? 'Sem responsável' : (assignees[_assigneeId] ?? ''),
              if (_search.trim().isNotEmpty) 'Busca: ${_search.trim()}',
            ],
            onClear: () => setState(() {
              _assigneeId = null;
              _search = '';
              _searchCtl.clear();
            }),
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
              : _listMode
                  ? _list(visible, dark)
                  : _board(visible, dark),
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

  // ── Board ──────────────────────────────────────────────────────────────────

  Widget _board(List<RedmineIssue> visible, bool dark) {
    final names = {
      for (final i in visible) i.statusId: i.statusName,
      for (final s in _statuses) s['id'] as int: '${s['name']}',
    };
    final columns = [
      for (final id in _columnIds) {'id': id, 'name': names[id] ?? '#$id'},
    ];
    final closed = _closedStatusIds;
    final multiProject = visible.map((i) => i.projectName).toSet().length > 1;

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
            ),
        ],
      ),
    );
  }

  Widget _column(
    Map<String, dynamic> status,
    List<RedmineIssue> issues,
    Set<int> closed,
    bool multiProject,
    bool dark,
  ) {
    final id = status['id'] as int;
    final name = '${status['name']}';
    final (_, dotColor) = AppColors.tone(Tag.hashed(name).tone, dark: dark);
    return Container(
      // Keys keep the dragged card mounted when columns change mid-drag.
      key: ValueKey(id),
      width: 270,
      margin: const EdgeInsets.only(right: 14),
      child: DragTarget<RedmineIssue>(
        onWillAcceptWithDetails: (d) => d.data.statusId != id,
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
              Expanded(
                child: issues.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Text(
                          'Nenhuma tarefa',
                          textAlign: TextAlign.center,
                          style: AppText.microLabel(dark: dark),
                        ),
                      )
                    : ListView.builder(
                        itemCount: issues.length,
                        itemBuilder: (context, index) {
                          final issue = issues[index];
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
                                  width: 246,
                                  child: Transform.rotate(angle: 0.03, child: card),
                                ),
                              ),
                              childWhenDragging: Opacity(opacity: 0.35, child: card),
                              child: card,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
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
          return ListView.builder(
            itemCount: visible.length + 1,
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
              final issue = visible[index - 1];
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
                          Text(
                            '#${issue.id}',
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
                      child: Align(alignment: Alignment.centerLeft, child: Tag(issue.statusName)),
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
                    Text(
                      '#${issue.id}',
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
