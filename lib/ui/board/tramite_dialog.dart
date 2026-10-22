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
import 'issue_actions.dart';
import 'issue_tree.dart';
import 'note_editor.dart';
import 'send_steps.dart';
import 'time_entry_fields.dart';

/// Trâmite on [issue] itself (a [HandoffRule] with `sameIssue`): status,
/// assignee, a comment typed now and the hours spent, in one send.
/// [issue] must be loaded with `include=journals`. True when everything was sent.
Future<bool> showTramiteDialog(BuildContext context, RedmineIssue issue, HandoffRule rule) async =>
    await showAppDialog<bool>(context, (_) => _TramiteDialog(issue: issue, rule: rule)) ?? false;

class _TramiteDialog extends StatefulWidget {
  const _TramiteDialog({required this.issue, required this.rule});

  final RedmineIssue issue;
  final HandoffRule rule;

  @override
  State<_TramiteDialog> createState() => _TramiteDialogState();
}

class _TramiteDialogState extends State<_TramiteDialog> {
  final _api = RedmineApiService();
  late final _comment = TextEditingController(
    text: widget.rule.template
        .replaceAll('{{tarefa}}', '#${widget.issue.id}')
        .replaceAll('{{titulo}}', widget.issue.subject),
  );
  final List<PendingFile> _files = [];
  final _hours = TextEditingController();
  final _extra = TextEditingController();
  final _timeComment = TextEditingController();

  /// Null = keep the issue's current value.
  late int? _statusId = widget.rule.statusId;
  late int? _assigneeId = widget.rule.assigneeId;
  int? _versionId;
  late int? _timeActivityId = widget.rule.timeActivityId;

  List<(int, String)>? _statuses;
  List<TeamMember>? _members;
  List<(int, String)>? _versions;
  List<(int, String)>? _activities;
  String? _loadError;

  /// Rules with `bulk`: linked issues that get the same update when checked.
  IssueTree? _tree;
  String? _treeError;
  final Set<int> _checked = {};
  bool _sending = false;
  final Map<String, StepResult> _results = {};

  /// Where the hours count from ([timeBases]); null while loading.
  List<TimeBase>? _bases;
  int? _base;

  @override
  void initState() {
    super.initState();
    if (widget.rule.logTime) _loadBases();
    _load();
    if (widget.rule.bulk) _loadTree();
  }

  /// Rules prefill the hours since the default base; the generic "Novo
  /// trâmite" starts empty (optional hours) but still offers the picker.
  Future<void> _loadBases() async {
    final (bases, base) = await loadTimeBases(context.read<AppState>().settings, widget.issue);
    if (!mounted) return;
    setState(() {
      _bases = bases;
      _base = base;
      final untouched = _hours.text.isEmpty && _extra.text.isEmpty;
      if (widget.rule != newTramiteRule && untouched && bases.isNotEmpty) {
        fillHoursFrom(context, bases[base].at, _hours, _extra);
      }
    });
  }

  Future<void> _loadTree() async {
    try {
      final tree = await IssueTree.load(context.read<AppState>().settings, widget.issue);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _checked.add(widget.issue.id);
      });
    } catch (error) {
      if (mounted) setState(() => _treeError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// Checked linked issues besides the opened one.
  List<RedmineIssue> get _extras => [
        if (_tree case final tree?)
          for (final r in tree.rows)
            if (r.issue.id != widget.issue.id && _checked.contains(r.issue.id)) r.issue,
      ];

  @override
  void dispose() {
    _comment.dispose();
    _hours.dispose();
    _extra.dispose();
    _timeComment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    try {
      final results = await Future.wait<Object?>([
        _api.listNamed(settings, '/issue_statuses.json', 'issue_statuses'),
        _api.listProjectMembers(settings, widget.issue.refId('project')!),
        _api
            .listNamed(
                settings, '/enumerations/time_entry_activities.json', 'time_entry_activities')
            .catchError((Object _) => const <(int, String)>[]),
        _api
            .listVersions(settings, widget.issue.refId('project')!)
            .catchError((Object _) => const <(int, String)>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _statuses = results[0] as List<(int, String)>;
        _members = results[1] as List<TeamMember>;
        _activities = results[2] as List<(int, String)>;
        _versions = results[3] as List<(int, String)>;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// The update (comment, attachments, status, assignee, version) on the
  /// opened issue and each checked extra, then the hours; see [runSendSteps].
  List<SendStep> _steps(AppSettings settings) {
    final id = widget.issue.id;
    final notes = _comment.text.trim();
    final hours = totalHours(_hours, _extra);
    final extraHours = parseHours(_extra.text);
    // Attachments go up again per issue: an upload token is used once.
    Future<String> apply(int issueId) async {
      final extra = {
        if (notes.isNotEmpty) 'notes': notes,
        if (_assigneeId != null) 'assigned_to_id': _assigneeId,
        if (_versionId != null) 'fixed_version_id': _versionId,
        if (_files.isNotEmpty) 'uploads': await uploadFiles(settings, _files),
      };
      if (_statusId == null) {
        await _api.putJson(settings, '/issues/$issueId.json', {'issue': extra});
        return '';
      }
      return await _api.setIssueStatus(settings, issueId, _statusId!, extra: extra)
          ? ''
          : 'enviado, mas o Redmine não aplicou a situação (workflow ou sem permissão).';
    }

    final update = notes.isNotEmpty ||
        _files.isNotEmpty ||
        _statusId != null ||
        _assigneeId != null ||
        _versionId != null;
    return [
      if (update) ('update', 'Trâmite em #$id', () => apply(id)),
      if (update)
        for (final i in _extras) ('update:${i.id}', 'Trâmite em #${i.id}', () => apply(i.id)),
      if (widget.rule.logTime && hours != null && _timeActivityId != null)
        (
          'time',
          '${fmtHours(hours)} h lançadas em #$id',
          () async {
            await _api.postJson(settings, '/time_entries.json', {
              'time_entry': {
                'issue_id': id,
                'hours': hours,
                'activity_id': _timeActivityId,
                if (_timeComment.text.trim().isNotEmpty) 'comments': _timeComment.text.trim(),
              },
            });
            return '';
          },
        ),
      if (widget.rule.logTime && hours != null && _timeActivityId != null && extraHours != null)
        overtimeStep(context, _results, extraHours, id, _timeComment.text.trim()),
    ];
  }

  /// Project members as choices, plus the rule's default assignee when it
  /// isn't a member of this project.
  List<(int, String)> get _memberOptions => [
        for (final m in _members ?? const <TeamMember>[]) (m.id, m.name),
        if (_assigneeId != null && !(_members ?? const []).any((m) => m.id == _assigneeId))
          (_assigneeId!, widget.rule.assigneeName ?? '#$_assigneeId'),
      ];

  /// Field changes this send makes (and where the comment repeats), asked
  /// before the first run.
  List<String> get _changes {
    List<String> lines(RedmineIssue issue, [String prefix = '']) => changeLines(
          issue,
          status: _statusId,
          assignee: _assigneeId,
          version: _versionId,
          statuses: _statuses,
          members: _memberOptions,
          versions: _versions,
          prefix: prefix,
        );
    final extras = _extras;
    return [
      ...lines(widget.issue),
      for (final i in extras) ...lines(i, '#${i.id} '),
      if (extras.isNotEmpty && _comment.text.trim().isNotEmpty)
        'Comentário também em ${extras.map((i) => '#${i.id}').join(', ')}',
    ];
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final changes = _changes;
    if (_results.isEmpty &&
        changes.isNotEmpty &&
        !await confirmChanges(context, '${widget.rule.name} · #${widget.issue.id}', changes)) {
      return;
    }
    if (!mounted) return;
    final steps = _steps(context.read<AppState>().settings);
    setState(() => _sending = true);
    final clean = await runSendSteps(steps, _results, () {
      if (mounted) setState(() {});
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (clean) {
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('Feito: ${steps.map((s) => s.$2).join(' · ')}.')),
      );
    }
  }

  /// Something already sent: the opener reloads even on Cancelar.
  void _close() => Navigator.of(context).pop(_results.values.any((r) => r.done));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 18);
    final issue = widget.issue;
    // watch, not read: this runs during build.
    final pending = [
      for (final (key, _, _) in _steps(context.watch<AppState>().settings))
        if (_results[key]?.done != true) key,
    ];
    final members = _memberOptions;

    return AppDialog(
      title: Row(children: [Text('${widget.rule.name} · '), IssueNumber(issue.id)]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(issue.subject, style: AppText.bodySemibold(dark: dark)),
          gap,
          if (_loadError != null)
            Text(
              'Não foi possível carregar situações e membros: $_loadError',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            )
          else if (_statuses == null || _members == null)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            LabeledField(
              label: 'Situação',
              child: SearchSelect(
                value: _statusId,
                options: _statuses!,
                none: 'Manter a atual (${issue.statusName})',
                onChanged: (v) => setState(() => _statusId = v),
              ),
            ),
            gap,
            LabeledField(
              label: 'Responsável',
              child: SearchSelect(
                value: _assigneeId,
                options: members,
                none: 'Manter o atual (${issue.assigneeName ?? 'ninguém'})',
                onChanged: (v) => setState(() => _assigneeId = v),
              ),
            ),
            gap,
            LabeledField(
              label: 'Versão',
              child: SearchSelect(
                value: _versionId,
                options: _versions ?? const [],
                none: 'Manter a atual (${issue.nameOf('fixed_version') ?? 'nenhuma'})',
                onChanged: (v) => setState(() => _versionId = v),
              ),
            ),
            if (widget.rule.bulk) ...[
              gap,
              LabeledField(
                label: 'Aplicar também em',
                child: _treeError != null
                    ? Text(
                        'Não foi possível carregar as tarefas ligadas: $_treeError',
                        style: AppText.microLabel(dark: dark)
                            .copyWith(color: AppColors.danger(dark: dark)),
                      )
                    : _tree == null
                        ? const LinearProgressIndicator(minHeight: 2)
                        : IssueTreeList(
                            tree: _tree!,
                            checked: _checked,
                            locked: {issue.id},
                            onChanged: () => setState(() {}),
                          ),
              ),
            ],
          ],
          gap,
          LabeledField(
            label: 'Comentário',
            child: NoteEditor(
              controller: _comment,
              files: _files,
              attachments: (issue.json['attachments'] as List? ?? const []).cast<Map>(),
              autofocus: true,
              hint: 'Escreva o trâmite…',
              onChanged: () => setState(() {}),
            ),
          ),
          if (widget.rule.logTime) ...[
            gap,
            LabeledField(
              label: 'Apontar horas',
              child: TimeEntryFields(
                hours: _hours,
                extra: _extra,
                comment: _timeComment,
                activities: _activities,
                activityId: _timeActivityId,
                onActivity: (v) => setState(() => _timeActivityId = v),
                onChanged: () => setState(() {}),
                bases: _bases,
                base: _base,
                onBase: (i) => setState(() => _base = i),
              ),
            ),
          ],
          if (_results.isNotEmpty) ...[gap, StepResultsList(_results)],
        ],
      ),
      footer: [
        OutlinedButton(onPressed: _close, child: const Text('Cancelar')),
        if (_results.isNotEmpty && pending.isEmpty)
          FilledButton(onPressed: _close, child: const Text('Fechar'))
        else
          FilledButton.icon(
            onPressed: pending.isEmpty ||
                    widget.rule.logTime && timeEntryBlocked(_hours, _timeActivityId, _extra) ||
                    _sending
                ? null
                : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 16),
            label: Text(_results.isNotEmpty ? 'Tentar de novo' : 'Enviar'),
          ),
      ],
    );
  }
}
