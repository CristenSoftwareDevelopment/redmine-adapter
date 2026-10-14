import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/redmine_issue.dart';
import '../../models/team.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../board/issue_detail_dialog.dart';
import '../components.dart';
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
    final teams = context.watch<AppState>().teams;
    final selected = teams.where((t) => t.id == _selectedId).firstOrNull ?? teams.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Times e horas',
          subtitle: 'Acompanhe as horas do time e explore os lançamentos de cada pessoa.',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Novo time'),
            ),
          ],
        ),
        if (selected == null)
          const Panel(
            child: EmptyState(
              icon: Icons.groups_outlined,
              text: 'Crie um time e adicione pessoas para acompanhar as horas lançadas.',
            ),
          )
        else
          _TeamReport(
            team: selected,
            teams: teams,
            onSelectTeam: (id) => setState(() => _selectedId = id),
            onEditTeam: () => _edit(selected),
          ),
      ],
    );
  }

  Future<void> _edit(Team? team) async {
    final state = context.read<AppState>();
    final result = await showAppDialog<Object>(context, (_) => _TeamDialog(initial: team));
    if (result is Team) {
      await state.saveTeam(result);
    } else if (result == #delete && team != null && mounted) {
      await _confirmDelete(team);
    }
  }

  Future<void> _confirmDelete(Team team) async {
    final state = context.read<AppState>();
    final ok = await showAppDialog<bool>(
      context,
      (dialogContext) => AppDialog(
        width: 460,
        title: const Text('Excluir time'),
        body: Text(
          'Excluir "${team.name}"? Os lançamentos no Redmine não são afetados.',
          style: AppText.captionLight(dark: Theme.of(dialogContext).brightness == Brightness.dark),
        ),
        footer: [
          OutlinedButton(
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

/// Pops a [Team] to save it, or `#delete` to delete the edited team.
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
    final q = searchKey(_filter.trim());
    final shown = [
      for (final m in _projectMembers ?? const <TeamMember>[])
        if (q.isEmpty || searchKey(m.name).contains(q)) m,
    ];

    return AppDialog(
      title: Text(widget.initial == null ? 'Novo time' : 'Editar time'),
      scrollable: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Nome do time',
            child: TextField(
              controller: _name,
              autofocus: widget.initial == null,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle(icon: Icons.groups_outlined, text: 'Membros'),
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
                        onDeleted: () => _toggle(m, false),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_projects == null && _error == null)
            Text('Carregando projetos…', style: AppText.captionLight(dark: dark))
          else if (_projects != null)
            DropdownMenu<int>(
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 300,
              label: const Text('Adicionar membros de um projeto'),
              hintText: 'Digite para buscar…',
              leadingIcon: const Icon(Icons.search, size: 17),
              dropdownMenuEntries: [
                for (final p in _projects!) DropdownMenuEntry(value: p.id, label: p.name),
              ],
              onSelected: (id) {
                if (id != null) _loadMembers(id);
              },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
              ),
            ),
          if (_loadingMembers)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_projectMembers != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SearchField(
                    width: double.infinity,
                    hint: 'Filtrar membros',
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
                padding: const EdgeInsets.only(top: 8),
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
                        contentPadding: EdgeInsets.zero,
                        value: memberIds.contains(m.id),
                        onChanged: (checked) => _toggle(m, checked == true),
                        secondary: UserAvatar(name: m.name, size: 26),
                        title: Text(m.name, style: AppText.body(dark: dark)),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
      footer: [
        if (widget.initial != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(#delete),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger(dark: dark)),
            child: const Text('Excluir time'),
          ),
          const Spacer(),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    Team(id: widget.initial?.id, name: _name.text.trim(), members: _members),
                  ),
          child: const Text('Salvar time'),
        ),
      ],
    );
  }
}

// ─── Report ───────────────────────────────────────────────────────────────────

enum _Preset { today, thisWeek, lastWeek, thisMonth, custom }

const _weekdayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

class _TeamReport extends StatefulWidget {
  const _TeamReport({
    required this.team,
    required this.teams,
    required this.onSelectTeam,
    required this.onEditTeam,
  });

  final Team team;
  final List<Team> teams;
  final ValueChanged<int> onSelectTeam;
  final VoidCallback onEditTeam;

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
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TeamReport old) {
    super.didUpdateWidget(old);
    // Another team (or new members): keep the period, reload the hours.
    String membersOf(Team t) => t.members.map((m) => m.id).join(',');
    if (old.team.id != widget.team.id || membersOf(old.team) != membersOf(widget.team)) {
      _focusUser = null;
      _focusDay = null;
      _expanded.clear();
      _load();
    }
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

  String _dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

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
        initialEntryMode: DatePickerEntryMode.input,
        helpText: 'Escolher período',
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
      _expanded.clear();
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
    final people = widget.team.members.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FiltersPanel(
          controls: [
            LabeledField(
              label: 'Time',
              child: SelectBox<int>(
                value: widget.team.id!,
                items: [
                  for (final t in widget.teams) DropdownMenuItem(value: t.id!, child: Text(t.name)),
                ],
                onChanged: (id) {
                  if (id != null) widget.onSelectTeam(id);
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: widget.onEditTeam,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Editar time'),
            ),
            LabeledField(
              label: 'Período',
              child: SegmentButtons<_Preset>(
                segments: const [
                  (_Preset.today, 'Hoje', null),
                  (_Preset.thisWeek, 'Esta semana', null),
                  (_Preset.lastWeek, 'Semana passada', null),
                  (_Preset.thisMonth, 'Este mês', null),
                  (_Preset.custom, 'Período…', Icons.calendar_today_outlined),
                ],
                selected: _preset,
                onChanged: _pick,
              ),
            ),
          ],
          actions: [
            IconBtn(
              icon: Icons.refresh,
              tooltip: 'Atualizar horas',
              onPressed: _loading ? null : _load,
            ),
          ],
          summary: FilterSummary(
            text: '${_dm(_range.start)} a ${fmtDate(_ymd(_range.end)).replaceAll('-', '/')}'
                ' · $people pessoa${people == 1 ? '' : 's'}',
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Não foi possível carregar as horas: $_error',
              style: AppText.captionLight(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            ),
          ),
        if (widget.team.members.isEmpty)
          const Panel(
            child: EmptyState(
              icon: Icons.person_add_alt,
              text: 'Adicione pessoas ao time para ver as horas.',
            ),
          )
        else if (entries != null) ...[
          _stats(entries),
          _table(entries, dark),
          _detail(entries, dark),
        ],
        Text(
          'Médias consideram dias de segunda a sexta, sem descontar feriados. Só aparecem as '
          "horas que seu papel no Redmine pode ver (permissão 'Ver tempo gasto').",
          style: AppText.microLabel(dark: dark).copyWith(fontSize: 11),
        ),
      ],
    );
  }

  Widget _stats(List<TimeEntry> entries) {
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final people = max(1, widget.team.members.length);
    final workdays = _days.where((d) => d.weekday <= 5).length;
    final contributors = entries.map((e) => e.userId).toSet().length;
    return StatGrid(
      children: [
        StatCard(
          label: 'Total do time',
          value: '${fmtHours(total)} h',
          note: 'No período selecionado',
          icon: Icons.schedule,
        ),
        StatCard(
          label: 'Média por pessoa',
          value: '${fmtHours(total / people)} h',
          note: 'Inclui pessoas sem lançamentos',
          icon: Icons.groups_outlined,
        ),
        StatCard(
          label: 'Média por pessoa / dia útil',
          value: workdays == 0 ? '—' : '${fmtHours(total / people / workdays)} h',
          note: '$workdays dia${workdays == 1 ? '' : 's'} de segunda a sexta',
          icon: Icons.calendar_today_outlined,
        ),
        StatCard(
          label: 'Lançamentos',
          value: '${entries.length}',
          note: '$contributors pessoa${contributors == 1 ? '' : 's'} com lançamentos',
          icon: Icons.format_list_bulleted,
        ),
      ],
    );
  }

  void _focus(int? user, DateTime? day) => setState(() {
        _focusUser = user;
        _focusDay = day;
        _expanded.clear();
      });

  Widget _table(List<TimeEntry> entries, bool dark) {
    final byUserDay = sumHours(entries, (e) => (e.userId, e.day));
    final byUser = sumHours(entries, (e) => e.userId);
    final byDay = sumHours(entries, (e) => e.day);
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final days = _days;
    final border = BorderSide(color: AppColors.border(dark: dark));
    final accent = AppColors.accent(dark: dark);
    const dayWidth = 72.0;
    const totalWidth = 84.0;

    Widget cell(
      String text, {
      required double width,
      double heat = 0,
      bool selected = false,
      bool bold = false,
      bool accentText = false,
      Color? background,
      VoidCallback? onTap,
      Alignment align = Alignment.centerRight,
      Widget? child,
    }) {
      return InkWell(
        onTap: onTap,
        hoverColor: AppColors.cellHover(dark: dark),
        child: Container(
          width: width,
          height: 48,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cellSelected(dark: dark)
                : background ?? (heat > 0 ? accent.withValues(alpha: heat) : null),
            border: Border(
              bottom: selected ? BorderSide(color: accent, width: 2) : BorderSide.none,
            ),
          ),
          child: child ??
              Text(
                text,
                style:
                    (bold ? AppText.bodySemibold(dark: dark) : AppText.body(dark: dark)).copyWith(
                  color: accentText ? accent : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
        ),
      );
    }

    Widget header(String text, double width, {Alignment align = Alignment.centerRight}) =>
        Container(
          width: width,
          height: 44,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(text, style: AppText.microLabel(dark: dark).copyWith(fontSize: 11)),
        );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHead(
            title: Text('Horas por pessoa'),
            subtitle: 'Clique no nome para ver o período completo, ou na célula para detalhar.',
            trailing: Tag('Horas decimais'),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // The name column grows so the table fills the panel when it fits.
              final nameWidth = max(
                220.0,
                constraints.maxWidth - days.length * dayWidth - totalWidth,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: AppColors.sunken(dark: dark),
                      child: Row(
                        children: [
                          header('PESSOA', nameWidth, align: Alignment.centerLeft),
                          for (final d in days)
                            header('${_weekdayLabels[d.weekday - 1]} ${_dm(d)}', dayWidth),
                          header('TOTAL', totalWidth),
                        ],
                      ),
                    ),
                    for (final m in widget.team.members)
                      Container(
                        decoration: BoxDecoration(border: Border(top: border)),
                        child: Row(
                          children: [
                            cell(
                              '',
                              width: nameWidth,
                              align: Alignment.centerLeft,
                              selected: _focusUser == m.id && _focusDay == null,
                              onTap: () => _focus(m.id, null),
                              child: Row(
                                children: [
                                  UserAvatar(name: m.name, size: 30),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.body(dark: dark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final d in days)
                              cell(
                                byUserDay[(m.id, d)] == null
                                    ? '—'
                                    : fmtHours(byUserDay[(m.id, d)]!),
                                width: dayWidth,
                                heat: min((byUserDay[(m.id, d)] ?? 0) / 14, 0.35),
                                selected: _focusUser == m.id && _focusDay == d,
                                onTap: () => _focus(m.id, d),
                              ),
                            cell(
                              fmtHours(byUser[m.id] ?? 0),
                              width: totalWidth,
                              bold: true,
                              accentText: true,
                              onTap: () => _focus(m.id, null),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.footer(dark: dark),
                        border: Border(top: border),
                      ),
                      child: Row(
                        children: [
                          cell(
                            'Total do time',
                            width: nameWidth,
                            bold: true,
                            align: Alignment.centerLeft,
                            onTap: () => _focus(null, null),
                          ),
                          for (final d in days)
                            cell(
                              fmtHours(byDay[d] ?? 0),
                              width: dayWidth,
                              bold: true,
                              selected: _focusUser == null && _focusDay == d,
                              onTap: () => _focus(null, d),
                            ),
                          cell(fmtHours(total), width: totalWidth, bold: true, accentText: true),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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

    final groups = <String, List<TimeEntry>>{};
    for (final e in focused) {
      groups.putIfAbsent(_byActivity ? e.activity : '${e.issueId}', () => []).add(e);
    }
    double sum(List<TimeEntry> list) => list.fold(0, (s, e) => s + e.hours);
    final sorted = groups.entries.toList()..sort((a, b) => sum(b.value).compareTo(sum(a.value)));

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(who),
                Tag('${fmtHours(sum(focused))} h', tone: TagTone.green),
              ],
            ),
            subtitle: _focusDay == null
                ? 'Lançamentos no período completo'
                : 'Lançamentos de ${fmtDate(_ymd(_focusDay!)).replaceAll('-', '/')}',
            trailing: AppTabs<bool>(
              tabs: const [(false, 'Por tarefa', null), (true, 'Por tipo de atividade', null)],
              selected: _byActivity,
              onChanged: (v) => setState(() {
                _byActivity = v;
                _expanded.clear();
              }),
            ),
          ),
          if (sorted.isEmpty)
            const EmptyState(text: 'Nenhum lançamento para esta seleção.')
          else
            for (final group in sorted) _groupRow(group.key, group.value, sum(group.value), dark),
        ],
      ),
    );
  }

  /// One task (or activity type); tap to list its time entries.
  Widget _groupRow(String key, List<TimeEntry> list, double hours, bool dark) {
    final issueId = _byActivity ? null : list.first.issueId;
    final expanded = _expanded.contains(key);
    final activities = list.map((e) => e.activity).toSet().join(' · ');
    final tasks = list.map((e) => e.issueId).toSet().length;
    final count = '${list.length} lançamento${list.length == 1 ? '' : 's'}';

    return ListRow(
      onTap: () => setState(() => expanded ? _expanded.remove(key) : _expanded.add(key)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_byActivity && issueId != null)
            InkWell(
              onTap: () => showIssueDetail(
                context,
                RedmineIssue({'id': issueId, 'subject': _subjects[issueId] ?? ''}),
              ),
              child: Text(
                '#$issueId',
                style: AppText.microLabel(dark: dark).copyWith(color: AppColors.accent(dark: dark)),
              ),
            ),
          Text(
            _byActivity
                ? key
                : issueId == null
                    ? 'Sem tarefa'
                    : (_subjects[issueId] ?? ''),
          ),
        ],
      ),
      meta: [
        Text(_byActivity
            ? '$tasks tarefa${tasks == 1 ? '' : 's'} · $count'
            : '$activities · $count'),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${fmtHours(hours)} h',
              style: AppText.bodySemibold(dark: dark).copyWith(fontSize: 15)),
          const SizedBox(width: 6),
          Icon(expanded ? Icons.expand_less : Icons.expand_more,
              size: 18, color: AppColors.mutedText(dark: dark)),
        ],
      ),
      below: !expanded
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  for (final e in list..sort((a, b) => a.day.compareTo(b.day)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          UserAvatar(name: e.userName, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${e.userName} · ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text(dark: dark),
                                    ),
                                  ),
                                  TextSpan(
                                    text: [
                                      fmtDate(_ymd(e.day)).replaceAll('-', '/'),
                                      _byActivity
                                          ? (e.issueId == null
                                              ? 'Sem tarefa'
                                              : '#${e.issueId} ${_subjects[e.issueId] ?? ''}')
                                          : e.activity,
                                      if (e.comments.isNotEmpty) e.comments,
                                    ].join(' · '),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.microLabel(dark: dark),
                            ),
                          ),
                          Text('${fmtHours(e.hours)} h', style: AppText.microLabel(dark: dark)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
