import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/handoff_rule.dart';
import '../../models/redmine_issue.dart';
import '../../models/team.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'issue_detail_dialog.dart';
import 'send_steps.dart';
import 'time_entry_fields.dart';

/// Comments on another issue (usually the QA one) mentioning notes of
/// [source], its subtasks or its siblings covered by the rule, optionally
/// changing its status and assignee. [source] must be loaded with
/// `include=journals,relations,children`.
Future<void> showHandoffDialog(
  BuildContext context,
  RedmineIssue source,
  List<HandoffRule> rules, {
  int? noteIndex,
}) =>
    showAppDialog<void>(
      context,
      (_) => _HandoffDialog(source: source, rules: rules, noteIndex: noteIndex),
    );

class _HandoffDialog extends StatefulWidget {
  const _HandoffDialog({required this.source, required this.rules, this.noteIndex});

  final RedmineIssue source;
  final List<HandoffRule> rules;
  final int? noteIndex;

  @override
  State<_HandoffDialog> createState() => _HandoffDialogState();
}

class _HandoffDialogState extends State<_HandoffDialog> {
  final _api = RedmineApiService();
  final _comment = TextEditingController();
  final _manualId = TextEditingController();

  late HandoffRule _rule = widget.rules.first;

  /// Issues whose notes can be picked: [source] first, then its subtasks and
  /// siblings (loaded with their journals).
  late final List<RedmineIssue> _noteIssues = [widget.source];
  bool _loadingNotes = true;
  final List<int> _notesFailed = [];

  /// Picked notes as (issue id, `#note-N` index).
  late final Set<(int, int)> _selected = {
    if (widget.noteIndex ?? _notesOf(widget.source).lastOrNull?.$1 case final index?)
      (widget.source.id, index),
  };

  /// Issues showing all their notes instead of the latest few.
  final Set<int> _expanded = {};

  /// Issues linked by parent/subtasks/relations, closest first ([nearbyIssues]).
  List<RedmineIssue>? _candidates;
  List<(int, String)>? _statuses;
  String? _loadError;

  int? _targetId;
  int _targetSeq = 0;
  RedmineIssue? _target;
  List<TeamMember>? _members;
  String? _targetError;

  /// Null = keep the target's current value.
  int? _statusId;
  int? _assigneeId;
  bool _sending = false;

  // Code review closing steps, each shown only when the rule configures it.
  List<(int, String)>? _activities;
  final _hours = TextEditingController();
  final _timeComment = TextEditingController();
  late int _timeIssueId = widget.source.id;
  late int? _timeActivityId = _rule.timeActivityId;
  RedmineIssue? _parent;

  /// Status of each of the rule's status steps (editable here).
  late List<int?> _stepStatus = [for (final s in _rule.statusSteps) s.statusId];

  /// (step, issue) the user (un)checked; the rest follow [defaultChecked].
  final Map<(int, int), bool> _stepPicked = {};

  /// Distance from the opened issue found by the search (0 = itself).
  Map<int, int> _depth = const {};
  List<(int, String)>? _trackers;

  /// Outcome per step key (`qa`, `time`, `dev:<id>`, `business`). Done steps
  /// never run again, so retrying can't post the QA comment twice.
  final Map<String, StepResult> _results = {};

  /// Last update of the opened issue: the hours default to the time since then.
  late final DateTime? _lastUpdate = () {
    final journals = (widget.source.json['journals'] as List? ?? const []).cast<Map>();
    return DateTime.tryParse('${journals.lastOrNull?['created_on']}') ?? widget.source.updatedOn;
  }();

  @override
  void initState() {
    super.initState();
    _render();
    if (_rule.logTime && _lastUpdate != null) {
      _hours.text = elapsedHm(_lastUpdate, DateTime.now());
    }
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    _manualId.dispose();
    _hours.dispose();
    _timeComment.dispose();
    super.dispose();
  }

  /// Journals with notes, as (1-based index in the issue = `#note-N`, journal).
  static List<(int, Map)> _notesOf(RedmineIssue issue) => [
        for (final (i, j) in (issue.json['journals'] as List? ?? const []).cast<Map>().indexed)
          if ('${j['notes'] ?? ''}'.trim().isNotEmpty) (i + 1, j),
      ];

  void _render() {
    _comment.text = _selected.isEmpty
        ? ''
        : renderHandoffNote(
            _rule,
            trackerName: widget.source.trackerName,
            issueId: widget.source.id,
            subject: widget.source.subject,
            notes: _selected.toList(),
          );
  }

  void _toggle(int issueId, int index) => setState(() {
        if (!_selected.remove((issueId, index))) _selected.add((issueId, index));
        _render();
      });

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    final source = widget.source;
    final targetTracker = _rule.targetTrackerId;

    Future<RedmineIssue?> fetchLinked(int id) async {
      try {
        final data = await _api.getJson(settings, '/issues/$id.json?include=relations,children');
        return RedmineIssue(data['issue'] as Map<String, dynamic>);
      } catch (_) {
        return null; // e.g. a private issue: just not followed
      }
    }

    try {
      // The opened issue already covers its own tracker.
      final trackers = {targetTracker, for (final s in _rule.statusSteps) s.trackerId}
          .nonNulls
          .where((t) => t != source.refId('tracker'))
          .toSet();
      final results = await Future.wait<Object?>([
        _api.getJson(settings, '/issue_statuses.json'),
        nearbyIssues(source, fetchLinked, trackerIds: trackers, maxDepth: trackers.isEmpty ? 2 : 4),
        _api
            .listNamed(
                settings, '/enumerations/time_entry_activities.json', 'time_entry_activities')
            .catchError((Object _) => const <(int, String)>[]),
        _api
            .listNamed(settings, '/trackers.json', 'trackers')
            .catchError((Object _) => const <(int, String)>[]),
      ]);
      if (!mounted) return;
      final nearby = (results[1] as List<({RedmineIssue issue, int depth})>)
        ..sort((a, b) => a.depth != b.depth ? a.depth - b.depth : a.issue.id - b.issue.id);
      setState(() {
        _statuses = [
          for (final s in ((results[0] as Map)['issue_statuses'] as List).cast<Map>())
            (s['id'] as int, '${s['name']}'),
        ];
        _candidates = [for (final n in nearby) n.issue];
        _activities = results[2] as List<(int, String)>;
        _trackers = results[3] as List<(int, String)>;
        _depth = {source.id: 0, for (final n in nearby) n.issue.id: n.depth};
        _parent = _candidates!.where((i) => i.id == source.refId('parent')).firstOrNull;
      });
      final matching = _matching;
      if (_targetId == null && matching.length == 1) _selectTarget(matching.single.id);

      // Note sources: subtasks and the siblings the rule covers, never the
      // target type. Siblings come from the parent, fetched by the search.
      final parent = _parent;
      List<Map> children(RedmineIssue? i) => (i?.json['children'] as List? ?? const []).cast<Map>();
      int? trackerOf(Map ref) => (ref['tracker'] as Map?)?['id'] as int?;
      bool isTarget(Map ref) => targetTracker != null && trackerOf(ref) == targetTracker;
      final sourceIds = [
        for (final c in children(source))
          if (!isTarget(c)) c['id'] as int,
        for (final c in children(parent))
          if (c['id'] != source.id && !isTarget(c) && _rule.appliesTo(trackerOf(c))) c['id'] as int,
      ];

      // A failing issue only loses its own notes (listed in [_notesFailed]).
      Future<RedmineIssue?> withJournals(int id) async {
        try {
          final data = await _api.getJson(settings, '/issues/$id.json?include=journals');
          return RedmineIssue(data['issue'] as Map<String, dynamic>);
        } catch (_) {
          _notesFailed.add(id);
          return null;
        }
      }

      // ponytail: one request per subtask/sibling; batch if stories get large.
      final loaded = await Future.wait([for (final id in sourceIds) withJournals(id)]);
      if (!mounted) return;
      setState(() => _noteIssues.addAll(loaded.nonNulls));
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingNotes = false);
    }
  }

  List<RedmineIssue> get _matching => [
        for (final c in _candidates ?? const <RedmineIssue>[])
          if (_rule.targetTrackerId == null || c.refId('tracker') == _rule.targetTrackerId) c,
      ];

  /// Loads the target (current status/assignee, project) and its project's
  /// members, then preloads the rule defaults.
  Future<void> _selectTarget(int id) async {
    final settings = context.read<AppState>().settings;
    final seq = ++_targetSeq;
    setState(() {
      _targetId = id;
      _target = null;
      _members = null;
      _targetError = null;
      _statusId = _rule.statusId;
      _assigneeId = _rule.assigneeId;
    });
    try {
      final data = await _api.getJson(settings, '/issues/$id.json');
      final target = RedmineIssue(data['issue'] as Map<String, dynamic>);
      final members = await _api.listProjectMembers(settings, target.refId('project')!);
      if (!mounted || seq != _targetSeq) return;
      setState(() {
        _target = target;
        _members = members;
      });
    } catch (error) {
      if (mounted && seq == _targetSeq) {
        setState(() => _targetError = '$error'.replaceFirst('Exception: ', ''));
      }
    }
  }

  void _useManualId() {
    final id = int.tryParse(_manualId.text.trim().replaceFirst('#', ''));
    if (id != null) _selectTarget(id);
  }

  bool _isTarget(RedmineIssue i) =>
      _rule.targetTrackerId != null && i.refId('tracker') == _rule.targetTrackerId;

  /// Every issue found so far (opened, subtasks, siblings, linked), closest first.
  List<RedmineIssue> get _known => ({
        for (final i in [...?_candidates, ..._noteIssues]) i.id: i,
      }.values.toList()
        ..sort((a, b) {
          final da = _depth[a.id] ?? 9, db = _depth[b.id] ?? 9;
          return da != db ? da - db : a.id - b.id;
        }));

  /// Issues where the hours can be logged: the opened one first, then the
  /// others the rule covers (parent, subtasks, siblings).
  List<RedmineIssue> get _timeIssues => [
        for (final i in _known)
          if (_rule.appliesTo(i.refId('tracker')) && !_isTarget(i)) i,
      ];

  /// Issues of one step's tracker.
  List<RedmineIssue> _stepIssues(int trackerId) => [
        for (final i in _known)
          if (i.refId('tracker') == trackerId) i
      ];

  bool _stepChecked(int step, RedmineIssue issue, Set<int> defaults) =>
      _stepPicked[(step, issue.id)] ?? defaults.contains(issue.id);

  Set<int> _stepDefaults(List<RedmineIssue> issues) => defaultChecked(
        [for (final i in issues) (id: i.id, depth: _depth[i.id] ?? 9)],
        widget.source.id,
        {for (final n in _selected) n.$1},
      );

  bool get _hoursBlocked => _rule.logTime && timeEntryBlocked(_hours, _timeActivityId);

  /// Steps of this send, in order: (key, summary, run). `run` returns a
  /// warning ('' = all fine) or throws when the step failed.
  List<SendStep> _steps(AppSettings settings) {
    final target = _target;
    final hours = parseHours(_hours.text);
    final statusNames = {for (final (id, name) in _statuses ?? const <(int, String)>[]) id: name};
    String notApplied(int id) =>
        'o Redmine não aplicou a situação de #$id (workflow ou sem permissão)';
    Future<String> moveTo(int issueId, int statusId) async =>
        await _api.setIssueStatus(settings, issueId, statusId)
            ? ''
            : throw Exception(notApplied(issueId));

    // An issue checked in two steps only moves in the first one.
    final moved = <int>{};
    final statusSteps = [
      for (final (k, step) in _rule.statusSteps.indexed)
        if (_stepStatus.elementAtOrNull(k) case final status?)
          if (_stepIssues(step.trackerId) case final issues)
            for (final i in issues)
              if (_stepChecked(k, i, _stepDefaults(issues)) && moved.add(i.id))
                (
                  'status:$k:${i.id}',
                  '#${i.id} em ${statusNames[status] ?? status}',
                  () => moveTo(i.id, status),
                ),
    ];

    return [
      if (target != null)
        (
          'qa',
          'Trâmite enviado para #${target.id}',
          () async {
            final extra = {
              'notes': _comment.text.trim(),
              if (_assigneeId != null) 'assigned_to_id': _assigneeId,
            };
            if (_statusId == null) {
              await _api.putJson(settings, '/issues/${target.id}.json', {'issue': extra});
              return '';
            }
            final applied =
                await _api.setIssueStatus(settings, target.id, _statusId!, extra: extra);
            return applied ? '' : 'Comentário enviado, mas ${notApplied(target.id)}.';
          },
        ),
      if (_rule.logTime && hours != null && _timeActivityId != null)
        (
          'time',
          '${fmtHours(hours)} h lançadas em #$_timeIssueId',
          () async {
            await _api.postJson(settings, '/time_entries.json', {
              'time_entry': {
                'issue_id': _timeIssueId,
                'hours': hours,
                'activity_id': _timeActivityId,
                if (_timeComment.text.trim().isNotEmpty) 'comments': _timeComment.text.trim(),
              },
            });
            return '';
          },
        ),
      ...statusSteps,
    ];
  }

  /// Runs the steps not done yet (see [runSendSteps]). All fine → closes with
  /// a summary; otherwise each step shows ✓/⚠/✗ and "Tentar de novo" redoes
  /// only the failures.
  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final steps = _steps(context.read<AppState>().settings);
    setState(() => _sending = true);
    final clean = await runSendSteps(steps, _results, () {
      if (mounted) setState(() {});
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (clean) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Feito: ${steps.map((s) => s.$2).join(' · ')}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 18);

    return AppDialog(
      title: Row(
        children: [Text('${_rule.name} · '), IssueNumber(widget.source.id)],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.rules.length > 1) ...[
            LabeledField(
              label: 'Regra',
              child: SelectBox<HandoffRule>(
                value: _rule,
                items: [
                  for (final r in widget.rules) DropdownMenuItem(value: r, child: Text(r.name)),
                ],
                onChanged: (r) => setState(() {
                  _rule = r!;
                  _statusId = r.statusId;
                  _assigneeId = r.assigneeId;
                  _timeActivityId = r.timeActivityId;
                  _stepStatus = [for (final s in r.statusSteps) s.statusId];
                  _stepPicked.clear();
                  _render();
                }),
              ),
            ),
            gap,
          ],
          LabeledField(label: 'Trâmites', child: _notePicker(dark)),
          gap,
          LabeledField(label: 'Atividade destino', child: _targetPicker(dark)),
          if (_targetId != null) ...[gap, _targetFields(dark)],
          gap,
          LabeledField(
            label: 'Comentário',
            child: TextField(
              controller: _comment,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_rule.logTime) ...[
            gap,
            LabeledField(label: 'Lançar horas', child: _timeSection(dark)),
          ],
          for (final (k, step) in _rule.statusSteps.indexed) ...[
            gap,
            LabeledField(
              label: 'Alterar situação: ${_trackerName(step.trackerId)}',
              child: _stepSection(k, step.trackerId, dark),
            ),
          ],
          if (_results.isNotEmpty) ...[gap, StepResultsList(_results)],
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        _sendButton(),
      ],
    );
  }

  /// "Enviar" until something ran; then "Tentar de novo" for what is left,
  /// or "Fechar" when every step is done (some with a warning).
  Widget _sendButton() {
    final pending = [
      // watch, not read: this runs during build.
      for (final (key, _, _) in _steps(context.watch<AppState>().settings))
        if (_results[key]?.done != true) key,
    ];
    final qaReady = _results['qa']?.done == true ||
        (_target != null && _selected.isNotEmpty && _comment.text.trim().isNotEmpty);
    if (_results.isNotEmpty && pending.isEmpty) {
      return FilledButton(
          onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar'));
    }
    return FilledButton.icon(
      onPressed: !qaReady || _hoursBlocked || _sending || pending.isEmpty ? null : _send,
      icon: _sending
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send, size: 16),
      label: Text(
        _results.isNotEmpty
            ? 'Tentar de novo'
            : _target == null
                ? 'Enviar'
                : 'Enviar para #${_target!.id}',
      ),
    );
  }

  Widget _timeSection(bool dark) {
    final devs = _timeIssues;
    return TimeEntryFields(
      hours: _hours,
      comment: _timeComment,
      activities: _activities,
      activityId: _timeActivityId,
      onActivity: (v) => setState(() => _timeActivityId = v),
      onChanged: () => setState(() {}),
      since: _lastUpdate,
      issuePicker: SearchSelect(
        value: _timeIssueId,
        options: [for (final d in devs) (d.id, '#${d.id} · ${d.subject}')],
        hint: 'Tarefa…',
        onChanged: (v) => setState(() => _timeIssueId = v ?? widget.source.id),
      ),
    );
  }

  String _trackerName(int id) =>
      _trackers?.where((t) => t.$1 == id).firstOrNull?.$2 ??
      _known.where((i) => i.refId('tracker') == id).firstOrNull?.trackerName ??
      'tipo #$id';

  /// One status step: the new status, then a checkbox per issue of its tracker.
  Widget _stepSection(int step, int trackerId, bool dark) {
    if (_candidates == null && _loadError == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final issues = _stepIssues(trackerId);
    final defaults = _stepDefaults(issues);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_statuses != null)
          SearchSelect(
            value: _stepStatus.elementAtOrNull(step),
            options: _statuses!,
            none: 'Não alterar',
            onChanged: (v) => setState(() => _stepStatus[step] = v),
          ),
        const SizedBox(height: 6),
        if (issues.isEmpty)
          Text(
            'Nenhuma atividade de ${_trackerName(trackerId)} nas tarefas ligadas '
            '(pai, subtarefas, relações).',
            style: AppText.captionLight(dark: dark),
          ),
        for (final i in issues)
          _checkRow(
            i,
            _stepChecked(step, i, defaults),
            (v) => setState(() => _stepPicked[(step, i.id)] = v),
            dark,
          ),
      ],
    );
  }

  /// Checkbox + tracker + copyable #id + subject + current status + eye.
  Widget _checkRow(RedmineIssue issue, bool value, ValueChanged<bool> onChanged, bool dark) {
    return Row(
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        if (issue.trackerName.isNotEmpty) ...[
          Tag.hashed(issue.trackerName),
          const SizedBox(width: 8),
        ],
        IssueNumber(
          issue.id,
          style: AppText.microLabel(dark: dark).copyWith(color: AppColors.accent(dark: dark)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            issue.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(dark: dark),
          ),
        ),
        if (issue.json['status'] != null) ...[
          const SizedBox(width: 8),
          Tag(issue.statusName),
        ],
        const SizedBox(width: 8),
        _viewButton(issue),
      ],
    );
  }

  /// Notes grouped by issue, newest first; the latest few unless expanded
  /// (picked ones always show).
  Widget _notePicker(bool dark) {
    const latest = 3;
    final groups = [
      for (final issue in _noteIssues)
        if (_notesOf(issue).reversed.toList() case final notes when notes.isNotEmpty)
          (issue, notes),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (issue, notes) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Row(
              children: [
                if (issue.trackerName.isNotEmpty) ...[
                  Tag.hashed(issue.trackerName),
                  const SizedBox(width: 8),
                ],
                Expanded(child: _issueHeader(issue, dark)),
              ],
            ),
          ),
          for (final (k, (index, journal)) in notes.indexed)
            if (k < latest || _expanded.contains(issue.id) || _selected.contains((issue.id, index)))
              _noteRow(issue.id, index, journal, dark),
          if (notes.length > latest && !_expanded.contains(issue.id))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded.add(issue.id)),
                child: Text('Mostrar todas as notas (${notes.length})'),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (_notesFailed.isNotEmpty)
          Text(
            'Não foi possível carregar as notas de ${_notesFailed.map((id) => '#$id').join(', ')}.',
            style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          ),
        if (_loadingNotes)
          const LinearProgressIndicator(minHeight: 2)
        else if (groups.isEmpty)
          Text(
            'Nenhuma nota nesta tarefa, nas subtarefas ou nas irmãs.',
            style: AppText.captionLight(dark: dark),
          ),
      ],
    );
  }

  Widget _noteRow(int issueId, int index, Map journal, bool dark) {
    final selected = _selected.contains((issueId, index));
    return InkWell(
      onTap: () => _toggle(issueId, index),
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: (_) => _toggle(issueId, index)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    '#note-$index · ${(journal['user'] as Map?)?['name'] ?? '?'} · '
                    '${fmtDateTime(DateTime.tryParse('${journal['created_on']}'))}',
                    style: AppText.microLabel(dark: dark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${journal['notes']}'.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(dark: dark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the task in its own modal on top of this one; closing it comes back here.
  Widget _viewButton(RedmineIssue issue) => IconBtn(
        compact: true,
        icon: Icons.visibility_outlined,
        tooltip: 'Ver tarefa',
        onPressed: () => showIssueDetail(context, issue),
      );

  /// "#id · subject" with a copyable number and the [_viewButton].
  Widget _issueHeader(RedmineIssue issue, bool dark) {
    final style = AppText.bodySemibold(dark: dark);
    return Row(
      children: [
        IssueNumber(issue.id, style: style),
        Expanded(
          child: Text(
            ' · ${issue.subject}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 8),
        _viewButton(issue),
      ],
    );
  }

  Widget _targetPicker(bool dark) {
    final matching = _matching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null)
          Text(
            'Não foi possível buscar as tarefas ligadas: $_loadError',
            style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          )
        else if (_candidates == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (matching.isEmpty)
          Text(
            'Nenhuma atividade ${_rule.targetTrackerId == null ? '' : 'do tipo configurado '}'
            'nas tarefas ligadas (pai, subtarefas, relações) — informe o #id.',
            style: AppText.captionLight(dark: dark),
          )
        else
          for (final c in matching) _candidateRow(c, dark),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _manualId,
                decoration: const InputDecoration(hintText: 'Outro #id', isDense: true),
                onSubmitted: (_) => _useManualId(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _useManualId, child: const Text('Usar')),
          ],
        ),
      ],
    );
  }

  Widget _candidateRow(RedmineIssue c, bool dark) {
    final selected = c.id == _targetId;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s8),
      child: Material(
        color: selected ? AppColors.accentSoft(dark: dark) : AppColors.field(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          side: BorderSide(
            color: selected ? AppColors.accent(dark: dark) : AppColors.border(dark: dark),
          ),
        ),
        child: InkWell(
          onTap: () => _selectTarget(c.id),
          borderRadius: BorderRadius.circular(AppRadius.standard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                if (c.trackerName.isNotEmpty) ...[
                  Tag.hashed(c.trackerName),
                  const SizedBox(width: 10),
                ],
                IssueNumber(
                  c.id,
                  style: AppText.microLabel(dark: dark).copyWith(
                    color: AppColors.accent(dark: dark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(dark: dark),
                  ),
                ),
                const SizedBox(width: 10),
                Tag(c.statusName),
                const SizedBox(width: 8),
                Text(c.assigneeName ?? 'Ninguém', style: AppText.microLabel(dark: dark)),
                const SizedBox(width: 8),
                _viewButton(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Status and assignee of the target, preloaded with the rule defaults.
  Widget _targetFields(bool dark) {
    final target = _target;
    if (_targetError != null) {
      return Text(
        'Não foi possível carregar #$_targetId: $_targetError',
        style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
      );
    }
    if (target == null || _statuses == null || _members == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    // The rule's default assignee may not be a member of this project.
    final members = [
      ..._members!,
      if (_assigneeId != null && !_members!.any((m) => m.id == _assigneeId))
        TeamMember(id: _assigneeId!, name: _rule.assigneeName ?? '#$_assigneeId'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _issueHeader(target, dark),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Status',
          child: SearchSelect(
            value: _statusId,
            options: _statuses!,
            none: 'Manter o atual (${target.statusName})',
            onChanged: (v) => setState(() => _statusId = v),
          ),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Responsável',
          child: SearchSelect(
            value: _assigneeId,
            options: [for (final m in members) (m.id, m.name)],
            none: 'Manter o atual (${target.assigneeName ?? 'ninguém'})',
            onChanged: (v) => setState(() => _assigneeId = v),
          ),
        ),
      ],
    );
  }
}

/// Issues linked to [source] by parent, subtasks and relations (both ways),
/// visited level by level. Stops at the first level where every tracker of
/// [trackerIds] has been found (the closest win) or after [maxDepth] levels.
/// [fetch] returns the issue with `include=relations,children`, or null to skip it.
// ponytail: at most [maxIssues] fetches; raise it if links run wider.
Future<List<({RedmineIssue issue, int depth})>> nearbyIssues(
  RedmineIssue source,
  Future<RedmineIssue?> Function(int id) fetch, {
  Set<int> trackerIds = const {},
  int maxDepth = 4,
  int maxIssues = 60,
}) async {
  Iterable<int> neighbors(RedmineIssue i) => [
        if (i.refId('parent') case final parent?) parent,
        for (final c in (i.json['children'] as List? ?? const []).cast<Map>()) c['id'] as int,
        for (final r in (i.json['relations'] as List? ?? const []).cast<Map>())
          (r['issue_id'] == i.id ? r['issue_to_id'] : r['issue_id']) as int,
      ];
  final seen = {source.id};
  final found = <({RedmineIssue issue, int depth})>[];
  var fetched = 0;
  var frontier = [source];
  for (var depth = 1; depth <= maxDepth && frontier.isNotEmpty && fetched < maxIssues; depth++) {
    final ids = [
      for (final i in frontier)
        for (final id in neighbors(i))
          if (seen.add(id)) id,
    ].take(maxIssues - fetched).toList();
    fetched += ids.length;
    frontier = (await Future.wait(ids.map(fetch))).nonNulls.toList();
    found.addAll([for (final i in frontier) (issue: i, depth: depth)]);
    final foundAll = trackerIds.every((t) => found.any((n) => n.issue.refId('tracker') == t));
    if (trackerIds.isNotEmpty && foundAll) break;
  }
  return found;
}

/// Pre-checked issues of one status step: the opened issue and those with a
/// picked note; when none of them has the step's tracker, the closest issue.
Set<int> defaultChecked(
  List<({int id, int depth})> issues,
  int sourceId,
  Set<int> withNotes,
) {
  final own = {
    for (final i in issues)
      if (i.id == sourceId || withNotes.contains(i.id)) i.id,
  };
  if (own.isNotEmpty || issues.isEmpty) return own;
  final closest = issues.reduce((a, b) => b.depth < a.depth ? b : a);
  return {closest.id};
}
