import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/monitored_query.dart';
import '../../models/redmine_issue.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(visible.length - hidden, hidden, columnIds, dark),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: AppColors.orange),
                const SizedBox(width: Sp.s8),
                Expanded(
                  child: Text(
                    'Não foi possível carregar: $_error',
                    style: AppText.caption(dark: dark).copyWith(color: AppColors.orange),
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Tentar de novo')),
              ],
            ),
          ),
        const SizedBox(height: Sp.s12),
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

  Widget _toolbar(int count, int hidden, List<int> columnIds, bool dark) {
    final assignees = <int, String>{
      for (final i in _issues ?? const <RedmineIssue>[])
        if (i.assigneeId != null) i.assigneeId!: i.assigneeName ?? '?',
    };
    final sortedAssignees = assignees.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    // Every control is 40px tall so the toolbar lines up.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Wrap(
        spacing: Sp.s12,
        runSpacing: Sp.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Buscar por título ou #id',
                prefixIcon: Icon(Icons.search, size: 18),
                prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: _toolbarHeight),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: Sp.s12),
                constraints: BoxConstraints.tightFor(height: _toolbarHeight),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          _ToolbarBox(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _assigneeId,
                isDense: true,
                style: AppText.body(dark: dark),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos os responsáveis')),
                  const DropdownMenuItem(value: 0, child: Text('Sem responsável')),
                  for (final a in sortedAssignees)
                    DropdownMenuItem(value: a.key, child: Text(a.value)),
                ],
                onChanged: (v) => setState(() => _assigneeId = v),
              ),
            ),
          ),
          SizedBox(
            height: _toolbarHeight,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, _toolbarHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.micro),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_kanban_outlined, size: 16),
                  label: Text('Board'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.view_list_outlined, size: 16),
                  label: Text('Lista'),
                ),
              ],
              selected: {_listMode},
              onSelectionChanged: (v) => setState(() => _listMode = v.first),
            ),
          ),
          if (!_listMode) _columnsMenu(columnIds, dark),
          Text(
            [
              '$count tarefa${count == 1 ? '' : 's'}',
              if (hidden > 0) '$hidden em colunas ocultas',
            ].join(' · '),
            style: AppText.caption(dark: dark),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            tooltip: 'Abrir consulta no Redmine',
            onPressed: () => openRedmineLink(context, widget.query.directUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
        ],
      ),
    );
  }

  /// Multiselect of the board columns; the choice is saved per board.
  Widget _columnsMenu(List<int> columnIds, bool dark) {
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
      builder: (context, controller, _) => _ToolbarBox(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_column_outlined, size: 18),
            const SizedBox(width: Sp.s8),
            Text(
              'Colunas ${columnIds.length}/${_statuses.length}',
              style: AppText.body(dark: dark),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        children: [
          for (final status in columns)
            _column(
              status,
              [
                for (final i in visible)
                  if (i.statusId == status['id']) i
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
    return Container(
      // Keys keep the dragged card mounted when empty columns appear mid-drag.
      key: ValueKey(id),
      width: 280,
      margin: const EdgeInsets.only(right: Sp.s12),
      child: DragTarget<RedmineIssue>(
        onWillAcceptWithDetails: (d) => d.data.statusId != id,
        onAcceptWithDetails: (d) => _move(d.data, status),
        builder: (context, candidates, _) => Container(
          decoration: BoxDecoration(
            color: dark ? AppColors.darkCard : const Color(0xFFF1F0EE),
            borderRadius: BorderRadius.circular(AppRadius.standard),
            border: Border.all(
              color: candidates.isNotEmpty ? AppColors.notionBlue : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${status['name']}'.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.microLabel(dark: dark).copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${issues.length}', style: AppText.microLabel(dark: dark)),
                    if (closed.contains(id)) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check, size: 12, color: AppColors.green),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                      padding: const EdgeInsets.only(bottom: Sp.s8),
                      child: Draggable<RedmineIssue>(
                        data: issue,
                        maxSimultaneousDrags: _moving.contains(issue.id) ? 0 : 1,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 264,
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

  Widget _priorityIcon(RedmineIssue issue) {
    final level = _priorityIds.indexOf(issue.priorityId ?? -1) - _defaultPriority;
    final (icon, color) = switch (level) {
      < 0 => (Icons.keyboard_arrow_down, AppColors.blue),
      0 => (Icons.drag_handle, const Color(0xFFDD9900)),
      1 => (Icons.keyboard_arrow_up, AppColors.orange),
      _ => (Icons.keyboard_double_arrow_up, const Color(0xFFDE350B)),
    };
    return Tooltip(
      message: 'Prioridade: ${issue.priorityName}',
      child: Icon(icon, size: 18, color: color),
    );
  }

  // ── List ───────────────────────────────────────────────────────────────────

  Widget _list(List<RedmineIssue> visible, bool dark) {
    final closed = _closedStatusIds;
    final border = AppColors.border(dark: dark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 980;
        Widget row(List<Widget> cells) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: 10),
              child: Row(children: cells),
            );
        Widget head(String text, double? width) {
          final label = Text(
            text.toUpperCase(),
            style: AppText.microLabel(dark: dark).copyWith(fontWeight: FontWeight.w700),
          );
          return width == null ? Expanded(child: label) : SizedBox(width: width, child: label);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          itemCount: visible.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                child: row([
                  head('#', 72),
                  head('Tipo', 120),
                  head('Status', 140),
                  if (wide) head('Prioridade', 120),
                  head('Título', null),
                  head('Responsável', 180),
                  if (wide) head('Atualizada', 150),
                ]),
              );
            }
            final issue = visible[index - 1];
            return InkWell(
              onTap: () => showIssueDetail(context, issue),
              child: Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                child: row([
                  SizedBox(
                    width: 72,
                    child: Text(
                      '#${issue.id}',
                      style: AppText.caption(dark: dark).copyWith(
                        decoration:
                            closed.contains(issue.statusId) ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  Container(
                    width: 120,
                    padding: const EdgeInsets.only(right: Sp.s8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: issue.trackerName.isEmpty
                          ? const SizedBox()
                          : LabelPill(issue.trackerName),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      issue.statusName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(dark: dark),
                    ),
                  ),
                  if (wide)
                    SizedBox(
                      width: 120,
                      child: Row(
                        children: [
                          _priorityIcon(issue),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              issue.priorityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption(dark: dark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Text(
                      issue.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyMedium(dark: dark),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: issue.assigneeName == null
                        ? Text('-', style: AppText.caption(dark: dark))
                        : Row(
                            children: [
                              UserAvatar(name: issue.assigneeName!, size: 22),
                              const SizedBox(width: Sp.s8),
                              Flexible(
                                child: Text(
                                  issue.assigneeName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption(dark: dark),
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
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppColors.darkSurface : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.standard),
          border: Border.all(color: AppColors.border(dark: dark)),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.standard),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Sp.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showProject) ...[
                    Text(
                      issue.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.microLabel(dark: dark),
                    ),
                    const SizedBox(height: Sp.s4),
                  ],
                  Text(
                    issue.subject,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMedium(dark: dark).copyWith(height: 1.35),
                  ),
                  if (issue.trackerName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    LabelPill(issue.trackerName),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      priority,
                      const SizedBox(width: 6),
                      Text(
                        '#${issue.id}',
                        style: AppText.microLabel(dark: dark).copyWith(
                          fontWeight: FontWeight.w600,
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
                        UserAvatar(name: issue.assigneeName!),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _toolbarHeight = 40.0;

/// Toolbar control frame matching the theme's text field.
class _ToolbarBox extends StatelessWidget {
  const _ToolbarBox({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final input = Theme.of(context).inputDecorationTheme;
    return Material(
      color: input.fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        side: input.enabledBorder?.borderSide ?? BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.micro),
        child: Container(
          height: _toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: Sp.s12),
          // widthFactor 1: hug the content instead of filling the Wrap line.
          child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: child),
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
