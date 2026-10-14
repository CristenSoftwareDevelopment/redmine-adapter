import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/team.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../ui_utils.dart';

/// Teams (groups of Redmine users) and their spent time per person and day.
/// Members come from project memberships, so no admin key is needed.
class TeamsView extends StatefulWidget {
  const TeamsView({super.key});

  @override
  State<TeamsView> createState() => _TeamsViewState();
}

class _TeamsViewState extends State<TeamsView> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final teams = state.teams;
    final selected = teams.where((t) => t.id == _selectedId).firstOrNull ?? teams.firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 240,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.border(dark: dark))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Sp.s16),
                child: FilledButton.icon(
                  onPressed: () => _edit(null),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.notionBlue),
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Novo time'),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final team in teams)
                      ListTile(
                        dense: true,
                        selected: team.id == selected?.id,
                        selectedColor: AppColors.notionBlue,
                        leading: const Icon(Icons.groups_outlined, size: 20),
                        title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${team.members.length} pessoa${team.members.length == 1 ? '' : 's'}',
                        ),
                        onTap: () => setState(() => _selectedId = team.id),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Mais ações',
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (action) =>
                              action == 'edit' ? _edit(team) : _confirmDelete(team),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(value: 'delete', child: Text('Excluir')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text(
                    'Crie um time e adicione pessoas para acompanhar as horas lançadas.',
                    style: AppText.captionLight(dark: dark),
                  ),
                )
              : _TeamReport(
                  // New members → fresh report.
                  key: ValueKey('${selected.id}:${selected.members.map((m) => m.id).join(',')}'),
                  team: selected,
                ),
        ),
      ],
    );
  }

  Future<void> _edit(Team? team) async {
    final state = context.read<AppState>();
    final result = await showDialog<Team>(
      context: context,
      builder: (_) => _TeamDialog(initial: team),
    );
    if (result != null) await state.saveTeam(result);
  }

  Future<void> _confirmDelete(Team team) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir time'),
        content: Text('Excluir "${team.name}"? Os lançamentos no Redmine não são afetados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteTeam(team.id!);
  }
}

// ─── Team dialog ──────────────────────────────────────────────────────────────

class _TeamDialog extends StatefulWidget {
  const _TeamDialog({this.initial});

  final Team? initial;

  @override
  State<_TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<_TeamDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final List<TeamMember> _members = [...?widget.initial?.members];
  final _api = RedmineApiService();
  List<({int id, String name})>? _projects;
  int? _projectId;
  List<TeamMember>? _projectMembers;
  bool _loadingMembers = false;
  String _filter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await _api.getAllPages(
        context.read<AppState>().settings,
        '/projects.json',
        'projects',
        cap: 2000,
      );
      if (!mounted) return;
      setState(() {
        _projects = [
          for (final p in projects) (id: p['id'] as int, name: p['name'] as String? ?? '?'),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// Project members via memberships (works for any member, no admin needed).
  Future<void> _loadMembers(int projectId) async {
    setState(() {
      _projectId = projectId;
      _projectMembers = null;
      _loadingMembers = true;
      _error = null;
    });
    try {
      final memberships = await _api.getAllPages(
        context.read<AppState>().settings,
        '/projects/$projectId/memberships.json',
        'memberships',
        cap: 2000,
      );
      if (!mounted || _projectId != projectId) return;
      // Group memberships have `group` instead of `user`: skipped.
      final byId = <int, TeamMember>{
        for (final m in memberships)
          if (m['user'] is Map)
            (m['user'] as Map)['id'] as int: TeamMember(
              id: (m['user'] as Map)['id'] as int,
              name: (m['user'] as Map)['name'] as String? ?? '?',
            ),
      };
      setState(() {
        _projectMembers = byId.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    } catch (error) {
      if (mounted && _projectId == projectId) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && _projectId == projectId) setState(() => _loadingMembers = false);
    }
  }

  Widget _projectPicker(bool dark) {
    final projects = _projects;
    if (projects == null) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Sp.s8),
          Text('Carregando projetos…', style: AppText.caption(dark: dark)),
        ],
      );
    }
    return DropdownMenu<int>(
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 300,
      label: const Text('Adicionar membros de um projeto'),
      hintText: 'Digite para buscar…',
      leadingIcon: const Icon(Icons.search, size: 18),
      dropdownMenuEntries: [
        for (final p in projects) DropdownMenuEntry(value: p.id, label: p.name),
      ],
      onSelected: (id) {
        if (id != null) _loadMembers(id);
      },
    );
  }

  List<Widget> _memberList(Set<int> memberIds, bool dark) {
    final q = searchKey(_filter.trim());
    final shown = [
      for (final m in _projectMembers!)
        if (q.isEmpty || searchKey(m.name).contains(q)) m,
    ];
    return [
      const SizedBox(height: Sp.s12),
      Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filtrar membros',
                prefixIcon: Icon(Icons.filter_list, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              for (final m in shown) {
                if (!memberIds.contains(m.id)) _members.add(m);
              }
            }),
            child: const Text('Marcar todos'),
          ),
        ],
      ),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Sp.s8),
          child: Text('Nenhum membro encontrado.', style: AppText.captionLight(dark: dark)),
        )
      else
        Flexible(
          flex: 2,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in shown)
                CheckboxListTile(
                  dense: true,
                  value: memberIds.contains(m.id),
                  onChanged: (checked) => _toggle(m, checked == true),
                  secondary: UserAvatar(name: m.name, size: 26),
                  title: Text(m.name),
                ),
            ],
          ),
        ),
    ];
  }

  void _toggle(TeamMember member, bool add) => setState(() {
        if (add) {
          _members.add(member);
        } else {
          _members.removeWhere((m) => m.id == member.id);
        }
      });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final memberIds = {for (final m in _members) m.id};

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Sp.s24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: surfaceCard(dark: dark),
        padding: const EdgeInsets.all(Sp.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Novo time' : 'Editar time',
              style: AppText.bodyLarge(dark: dark),
            ),
            const SizedBox(height: Sp.s16),
            TextField(
              controller: _name,
              autofocus: widget.initial == null,
              decoration: const InputDecoration(labelText: 'Nome do time'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Sp.s16),
            Text('Membros', style: AppText.caption(dark: dark)),
            const SizedBox(height: Sp.s8),
            if (_members.isEmpty)
              Text('Nenhum membro ainda.', style: AppText.captionLight(dark: dark))
            else
              // Chips and the member list share the height left in the dialog.
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in _members)
                        InputChip(
                          avatar: UserAvatar(name: m.name, size: 22),
                          label: Text(m.name),
                          onDeleted: () => setState(() => _members.remove(m)),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Sp.s16),
            _projectPicker(dark),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Sp.s8),
                child: Text(
                  _error!,
                  style: AppText.microLabel(dark: dark).copyWith(color: AppColors.orange),
                ),
              ),
            if (_loadingMembers)
              const Padding(
                padding: EdgeInsets.only(top: Sp.s12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_projectMembers != null) ..._memberList(memberIds, dark),
            const SizedBox(height: Sp.s24),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: AppColors.warmGray500),
                  child: const Text('Cancelar'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                            Team(
                              id: widget.initial?.id,
                              name: _name.text.trim(),
                              members: _members,
                            ),
                          ),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.notionBlue),
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Report ───────────────────────────────────────────────────────────────────

enum _Preset { today, thisWeek, lastWeek, thisMonth, custom }

const _presetLabels = {
  _Preset.today: 'Hoje',
  _Preset.thisWeek: 'Esta semana',
  _Preset.lastWeek: 'Semana passada',
  _Preset.thisMonth: 'Este mês',
  _Preset.custom: 'Período…',
};

const _weekdayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

class _TeamReport extends StatefulWidget {
  const _TeamReport({super.key, required this.team});

  final Team team;

  @override
  State<_TeamReport> createState() => _TeamReportState();
}

class _TeamReportState extends State<_TeamReport> {
  _Preset _preset = _Preset.thisWeek;
  late DateTimeRange _range = _rangeFor(_Preset.thisWeek);
  List<TimeEntry>? _entries;
  final Map<int, String> _subjects = {};
  bool _loading = false;
  int _loadSeq = 0;
  String? _error;

  int? _focusUser;
  DateTime? _focusDay;
  bool _byActivity = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange _rangeFor(_Preset preset) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    return switch (preset) {
      _Preset.today => DateTimeRange(start: today, end: today),
      _Preset.thisWeek => DateTimeRange(start: monday, end: today),
      _Preset.lastWeek => DateTimeRange(
          start: DateTime(monday.year, monday.month, monday.day - 7),
          end: DateTime(monday.year, monday.month, monday.day - 1),
        ),
      _Preset.thisMonth => DateTimeRange(start: DateTime(today.year, today.month), end: today),
      _Preset.custom => _range,
    };
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<DateTime> get _days => [
        for (var d = _range.start; !d.isAfter(_range.end); d = DateTime(d.year, d.month, d.day + 1))
          d,
      ];

  Future<void> _pick(_Preset preset) async {
    if (preset == _Preset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2010),
        lastDate: DateUtils.dateOnly(DateTime.now()),
        initialDateRange: _range,
      );
      if (picked == null) return;
      _range = DateTimeRange(
        start: DateUtils.dateOnly(picked.start),
        end: DateUtils.dateOnly(picked.end),
      );
    } else {
      _range = _rangeFor(preset);
    }
    setState(() {
      _preset = preset;
      _focusUser = null;
      _focusDay = null;
    });
    await _load();
  }

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    final api = RedmineApiService();
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // One extra day on each side: Redmine shifts from/to by the user's
      // time zone; withinDays below keeps only the requested days.
      final start = _range.start;
      final end = _range.end;
      final from = _ymd(DateTime(start.year, start.month, start.day - 1));
      final to = _ymd(DateTime(end.year, end.month, end.day + 1));
      final pages = await Future.wait([
        for (final m in widget.team.members)
          api.getAllPages(
            settings,
            '/time_entries.json?user_id=${m.id}&from=$from&to=$to',
            'time_entries',
            cap: 2000,
          ),
      ]);
      final entries = withinDays(
        [for (final page in pages) ...page.map(TimeEntry.fromJson)],
        start,
        end,
      );

      // Time entries only carry the issue id; fetch subjects 100 at a time.
      final missing = {
        for (final e in entries)
          if (e.issueId != null && !_subjects.containsKey(e.issueId)) e.issueId!,
      }.toList();
      for (var i = 0; i < missing.length; i += 100) {
        final chunk = missing.sublist(i, min(i + 100, missing.length));
        final issues = await api.getAllPages(
          settings,
          '/issues.json?status_id=*&issue_id=${chunk.join(',')}',
          'issues',
        );
        for (final issue in issues) {
          _subjects[issue['id'] as int] = issue['subject'] as String? ?? '';
        }
      }
      // The period may have changed while loading: only the latest load wins.
      if (mounted && seq == _loadSeq) setState(() => _entries = entries);
    } catch (error) {
      if (mounted && seq == _loadSeq) {
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entries = _entries;

    return ListView(
      padding: const EdgeInsets.all(Sp.s24),
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.team.name, style: AppText.cardTitle(dark: dark))),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: Sp.s12),
        Wrap(
          spacing: Sp.s8,
          runSpacing: Sp.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in _Preset.values)
              ChoiceChip(
                label: Text(_presetLabels[p]!),
                selected: _preset == p,
                onSelected: (_) => _pick(p),
              ),
            Text(
              '${fmtDate(_ymd(_range.start))} a ${fmtDate(_ymd(_range.end))}',
              style: AppText.caption(dark: dark),
            ),
          ],
        ),
        const SizedBox(height: Sp.s12),
        SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s12),
            child: Text(
              'Não foi possível carregar as horas: $_error',
              style: AppText.caption(dark: dark).copyWith(color: AppColors.orange),
            ),
          ),
        const SizedBox(height: Sp.s12),
        if (widget.team.members.isEmpty)
          Text(
            'Adicione pessoas ao time para ver as horas.',
            style: AppText.captionLight(dark: dark),
          )
        else if (entries != null) ...[
          _kpis(entries, dark),
          const SizedBox(height: Sp.s16),
          _matrix(entries, dark),
          const SizedBox(height: Sp.s16),
          _detail(entries, dark),
        ],
      ],
    );
  }

  Widget _kpis(List<TimeEntry> entries, bool dark) {
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final people = max(1, widget.team.members.length);
    final workdays = max(1, _days.where((d) => d.weekday <= 5).length);
    Widget kpi(String label, String value) => Container(
          width: 200,
          padding: const EdgeInsets.all(Sp.s16),
          decoration: surfaceCard(dark: dark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.microLabel(dark: dark)),
              const SizedBox(height: Sp.s4),
              Text(value, style: AppText.subHeading(dark: dark)),
            ],
          ),
        );
    return Wrap(
      spacing: Sp.s12,
      runSpacing: Sp.s12,
      children: [
        kpi('Total do time', '${fmtHours(total)} h'),
        kpi('Média por pessoa', '${fmtHours(total / people)} h'),
        kpi('Média por pessoa/dia útil', '${fmtHours(total / people / workdays)} h'),
        kpi('Lançamentos', '${entries.length}'),
      ],
    );
  }

  Widget _matrix(List<TimeEntry> entries, bool dark) {
    final byUserDay = sumHours(entries, (e) => (e.userId, e.day));
    final byUser = sumHours(entries, (e) => e.userId);
    final byDay = sumHours(entries, (e) => e.day);
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final days = _days;
    final border = AppColors.border(dark: dark);

    Widget cell(
      double? hours, {
      required double width,
      bool weekend = false,
      bool selected = false,
      bool bold = false,
      VoidCallback? onTap,
    }) {
      final h = hours ?? 0;
      return InkWell(
        onTap: onTap,
        child: Container(
          width: width,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: h > 0
                ? AppColors.notionBlue.withValues(alpha: 0.08 + 0.4 * min(h / 8, 1))
                : weekend
                    ? border
                    : null,
            border: Border.all(
              color: selected ? AppColors.notionBlue : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            h > 0 ? fmtHours(h) : '–',
            style: (bold ? AppText.bodySemibold(dark: dark) : AppText.body(dark: dark))
                .copyWith(fontSize: 13),
          ),
        ),
      );
    }

    Widget nameCell(Widget child, {VoidCallback? onTap, bool selected = false}) => InkWell(
          onTap: onTap,
          child: Container(
            width: 220,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s12),
            alignment: Alignment.centerLeft,
            color: selected ? AppColors.notionBlue.withValues(alpha: 0.08) : null,
            child: child,
          ),
        );

    return Container(
      decoration: surfaceCard(dark: dark),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
              child: Row(
                children: [
                  nameCell(Text('PESSOA', style: AppText.microLabel(dark: dark))),
                  for (final d in days)
                    SizedBox(
                      width: 64,
                      height: 40,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_weekdayLabels[d.weekday - 1],
                              style: AppText.microLabel(dark: dark)),
                          Text(
                            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                            style: AppText.microLabel(dark: dark),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: 72,
                    child: Center(child: Text('TOTAL', style: AppText.microLabel(dark: dark))),
                  ),
                ],
              ),
            ),
            for (final m in widget.team.members)
              Row(
                children: [
                  nameCell(
                    Row(
                      children: [
                        UserAvatar(name: m.name, size: 24),
                        const SizedBox(width: Sp.s8),
                        Expanded(
                          child: Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyMedium(dark: dark),
                          ),
                        ),
                      ],
                    ),
                    selected: _focusUser == m.id && _focusDay == null,
                    onTap: () => setState(() {
                      _focusUser = m.id;
                      _focusDay = null;
                    }),
                  ),
                  for (final d in days)
                    cell(
                      byUserDay[(m.id, d)],
                      width: 64,
                      weekend: d.weekday > 5,
                      selected: _focusUser == m.id && _focusDay == d,
                      onTap: () => setState(() {
                        _focusUser = m.id;
                        _focusDay = d;
                      }),
                    ),
                  cell(byUser[m.id], width: 72, bold: true),
                ],
              ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
              child: Row(
                children: [
                  nameCell(
                    Text('Total do time', style: AppText.bodySemibold(dark: dark)),
                    selected: _focusUser == null && _focusDay == null,
                    onTap: () => setState(() {
                      _focusUser = null;
                      _focusDay = null;
                    }),
                  ),
                  for (final d in days)
                    cell(
                      byDay[d],
                      width: 64,
                      weekend: d.weekday > 5,
                      bold: true,
                      selected: _focusUser == null && _focusDay == d,
                      onTap: () => setState(() {
                        _focusUser = null;
                        _focusDay = d;
                      }),
                    ),
                  cell(total, width: 72, bold: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(List<TimeEntry> entries, bool dark) {
    final focused = [
      for (final e in entries)
        if ((_focusUser == null || e.userId == _focusUser) &&
            (_focusDay == null || e.day == _focusDay))
          e,
    ];
    final who = _focusUser == null
        ? 'Time inteiro'
        : widget.team.members.firstWhere((m) => m.id == _focusUser).name;
    final when = _focusDay == null ? 'período todo' : fmtDate(_ymd(_focusDay!));

    String issueLabel(int? id) => id == null ? 'Sem tarefa' : '#$id  ${_subjects[id] ?? ''}';
    final groups = <String, List<TimeEntry>>{};
    for (final e in focused) {
      groups.putIfAbsent(_byActivity ? e.activity : issueLabel(e.issueId), () => []).add(e);
    }
    double sum(List<TimeEntry> list) => list.fold(0, (s, e) => s + e.hours);
    final sorted = groups.entries.toList()..sort((a, b) => sum(b.value).compareTo(sum(a.value)));

    return Container(
      decoration: surfaceCard(dark: dark),
      padding: const EdgeInsets.all(Sp.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Sp.s12,
            runSpacing: Sp.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$who · $when · ${fmtHours(sum(focused))} h',
                style: AppText.bodySemibold(dark: dark),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Por tarefa')),
                  ButtonSegment(value: true, label: Text('Por tipo de atividade')),
                ],
                selected: {_byActivity},
                onSelectionChanged: (v) => setState(() => _byActivity = v.first),
              ),
            ],
          ),
          Text(
            'Clique numa pessoa, dia ou célula da tabela para detalhar. Só aparecem as horas '
            "que seu papel no Redmine pode ver (permissão 'Ver tempo gasto').",
            style: AppText.microLabel(dark: dark),
          ),
          const SizedBox(height: Sp.s8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.s12),
              child: Text('Nenhum lançamento.', style: AppText.captionLight(dark: dark)),
            ),
          for (final group in sorted)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: Text(
                group.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyMedium(dark: dark),
              ),
              subtitle: Text(
                _byActivity
                    ? '${group.value.map((e) => e.issueId).toSet().length} tarefa(s)'
                    : group.value.map((e) => e.activity).toSet().join(', '),
                style: AppText.microLabel(dark: dark),
              ),
              trailing: Text(
                '${fmtHours(sum(group.value))} h',
                style: AppText.bodySemibold(dark: dark),
              ),
              children: [
                for (final e in group.value..sort((a, b) => a.day.compareTo(b.day)))
                  ListTile(
                    dense: true,
                    leading: UserAvatar(name: e.userName, size: 24),
                    title: Text(
                      _byActivity ? issueLabel(e.issueId) : e.activity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [fmtDate(_ymd(e.day)), if (e.comments.isNotEmpty) e.comments].join(' · '),
                    ),
                    trailing: Text('${fmtHours(e.hours)} h'),
                    onTap: e.issueId == null
                        ? null
                        : () => openRedmineLink(context, '/issues/${e.issueId}'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
