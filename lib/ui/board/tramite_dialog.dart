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
import 'send_steps.dart';
import 'time_entry_fields.dart';

/// Trâmite on [issue] itself (a [HandoffRule] with `sameIssue`): status,
/// assignee, a comment typed now and the hours spent, in one send.
/// [issue] must be loaded with `include=journals`.
Future<void> showTramiteDialog(BuildContext context, RedmineIssue issue, HandoffRule rule) =>
    showAppDialog<void>(context, (_) => _TramiteDialog(issue: issue, rule: rule));

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
  final _hours = TextEditingController();
  final _timeComment = TextEditingController();

  /// Null = keep the issue's current value.
  late int? _statusId = widget.rule.statusId;
  late int? _assigneeId = widget.rule.assigneeId;
  late int? _timeActivityId = widget.rule.timeActivityId;

  List<(int, String)>? _statuses;
  List<TeamMember>? _members;
  List<(int, String)>? _activities;
  String? _loadError;
  bool _sending = false;
  final Map<String, StepResult> _results = {};

  /// Last update of the issue: the hours default to the time since then.
  late final DateTime? _lastUpdate = () {
    final journals = (widget.issue.json['journals'] as List? ?? const []).cast<Map>();
    return DateTime.tryParse('${journals.lastOrNull?['created_on']}') ?? widget.issue.updatedOn;
  }();

  @override
  void initState() {
    super.initState();
    if (widget.rule.logTime && _lastUpdate != null) {
      _hours.text = elapsedHm(_lastUpdate, DateTime.now());
    }
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    _hours.dispose();
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
      ]);
      if (!mounted) return;
      setState(() {
        _statuses = results[0] as List<(int, String)>;
        _members = results[1] as List<TeamMember>;
        _activities = results[2] as List<(int, String)>;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// The update (comment/status/assignee) then the hours; see [runSendSteps].
  List<SendStep> _steps(AppSettings settings) {
    final id = widget.issue.id;
    final notes = _comment.text.trim();
    final hours = parseHours(_hours.text);
    return [
      if (notes.isNotEmpty || _statusId != null || _assigneeId != null)
        (
          'update',
          'Trâmite em #$id',
          () async {
            final extra = {
              if (notes.isNotEmpty) 'notes': notes,
              if (_assigneeId != null) 'assigned_to_id': _assigneeId,
            };
            if (_statusId == null) {
              await _api.putJson(settings, '/issues/$id.json', {'issue': extra});
              return '';
            }
            return await _api.setIssueStatus(settings, id, _statusId!, extra: extra)
                ? ''
                : 'enviado, mas o Redmine não aplicou a situação (workflow ou sem permissão).';
          },
        ),
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
    ];
  }

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
    final issue = widget.issue;
    // watch, not read: this runs during build.
    final pending = [
      for (final (key, _, _) in _steps(context.watch<AppState>().settings))
        if (_results[key]?.done != true) key,
    ];
    // The rule's default assignee may not be a member of this project.
    final members = [
      for (final m in _members ?? const <TeamMember>[]) (m.id, m.name),
      if (_assigneeId != null && !(_members ?? const []).any((m) => m.id == _assigneeId))
        (_assigneeId!, widget.rule.assigneeName ?? '#$_assigneeId'),
    ];

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
          ],
          gap,
          LabeledField(
            label: 'Comentário',
            child: TextField(
              controller: _comment,
              autofocus: true,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(hintText: 'Escreva o trâmite…'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (widget.rule.logTime) ...[
            gap,
            LabeledField(
              label: 'Apontar horas',
              child: TimeEntryFields(
                hours: _hours,
                comment: _timeComment,
                activities: _activities,
                activityId: _timeActivityId,
                onActivity: (v) => setState(() => _timeActivityId = v),
                onChanged: () => setState(() {}),
                since: _lastUpdate,
              ),
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
        if (_results.isNotEmpty && pending.isEmpty)
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar'))
        else
          FilledButton.icon(
            onPressed: pending.isEmpty ||
                    widget.rule.logTime && timeEntryBlocked(_hours, _timeActivityId) ||
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
