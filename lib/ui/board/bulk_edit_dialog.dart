import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/redmine_issue.dart';
import '../../models/team.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'issue_actions.dart';
import 'issue_tree.dart';
import 'send_steps.dart';

/// Changes status, assignee and/or version of [issue] and the linked issues
/// checked here ([IssueTree]: parent, siblings, related and subtasks), e.g. a
/// story and its tasks from the backlog to a sprint. [issue] must be loaded
/// with `include=relations`. True when every checked issue changed.
Future<bool> showBulkEditDialog(BuildContext context, RedmineIssue issue) async =>
    await showAppDialog<bool>(context, (_) => _BulkEditDialog(issue: issue)) ?? false;

class _BulkEditDialog extends StatefulWidget {
  const _BulkEditDialog({required this.issue});

  final RedmineIssue issue;

  @override
  State<_BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends State<_BulkEditDialog> {
  final _api = RedmineApiService();

  IssueTree? _tree;
  List<(int, String)>? _statuses;
  List<(int, String)>? _members;
  List<(int, String)>? _versions;
  String? _loadError;

  /// Null = keep each issue's own value.
  int? _statusId;
  int? _assigneeId;
  int? _versionId;

  /// The opened issue and its subtasks go together by default.
  final Set<int> _checked = {};
  bool _sending = false;
  final Map<String, StepResult> _results = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    final project = widget.issue.refId('project')!;
    try {
      final results = await Future.wait<Object?>([
        IssueTree.load(settings, widget.issue),
        _api.listNamed(settings, '/issue_statuses.json', 'issue_statuses'),
        _api.listProjectMembers(settings, project),
        _api.listVersions(settings, project),
      ]);
      if (!mounted) return;
      final tree = results[0] as IssueTree;
      setState(() {
        _tree = tree;
        _statuses = results[1] as List<(int, String)>;
        _members = [for (final m in results[2] as List<TeamMember>) (m.id, m.name)];
        _versions = results[3] as List<(int, String)>;
        _checked.addAll(tree.subtree(widget.issue.id));
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// One update per checked issue with only what differs from its own values.
  /// The key carries the choice, so changing it after a partial run applies again.
  List<SendStep> _steps(AppSettings settings) {
    final tree = _tree;
    if (tree == null) return const [];
    final choice = '$_statusId:$_assigneeId:$_versionId';
    final steps = <SendStep>[];
    for (final (:issue, depth: _, role: _) in tree.rows) {
      if (!_checked.contains(issue.id)) continue;
      final status = _statusId != null && _statusId != issue.statusId ? _statusId : null;
      final assignee = _assigneeId != issue.assigneeId ? _assigneeId : null;
      final version = _versionId != issue.refId('fixed_version') ? _versionId : null;
      if (status == null && assignee == null && version == null) continue;
      final extra = {
        if (assignee != null) 'assigned_to_id': assignee,
        if (version != null) 'fixed_version_id': version,
      };
      final what = [
        if (status != null) 'situação ${optionName(_statuses, status)}',
        if (assignee != null) 'responsável ${optionName(_members, assignee)}',
        if (version != null) 'versão ${optionName(_versions, version)}',
      ].join(', ');
      steps.add((
        'bulk:${issue.id}:$choice',
        '#${issue.id}: $what',
        () async {
          if (status == null) {
            await _api.putJson(settings, '/issues/${issue.id}.json', {'issue': extra});
            return '';
          }
          return await _api.setIssueStatus(settings, issue.id, status, extra: extra)
              ? ''
              : 'o Redmine não aplicou a situação (workflow ou sem permissão).';
        },
      ));
    }
    return steps;
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
      navigator.pop(true);
      messenger
          .showSnackBar(SnackBar(content: Text('Feito: ${steps.map((s) => s.$2).join(' · ')}.')));
    }
  }

  /// Something already changed: the opener reloads even on Cancelar.
  void _close() => Navigator.of(context).pop(_results.values.any((r) => r.done));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 18);
    // watch, not read: this runs during build.
    final pending = [
      for (final (key, _, _) in _steps(context.watch<AppState>().settings))
        if (_results[key]?.done != true) key,
    ];
    final tree = _tree;
    Widget field(String label, int? value, List<(int, String)> options, ValueChanged<int?> set) =>
        Expanded(
          child: LabeledField(
            label: label,
            child: SearchSelect(
              value: value,
              options: options,
              none: 'Manter',
              onChanged: (v) => setState(() => set(v)),
            ),
          ),
        );

    return AppDialog(
      title: Row(children: [const Text('Alterar em massa · '), IssueNumber(widget.issue.id)]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadError != null)
            Text(
              'Não foi possível carregar as tarefas e opções: $_loadError',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            )
          else if (tree == null)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            Row(
              children: [
                field('Situação', _statusId, _statuses!, (v) => _statusId = v),
                const SizedBox(width: 12),
                field('Responsável', _assigneeId, _members!, (v) => _assigneeId = v),
                const SizedBox(width: 12),
                field('Versão', _versionId, _versions!, (v) => _versionId = v),
              ],
            ),
            gap,
            LabeledField(
              label: 'Tarefas',
              child: IssueTreeList(
                tree: tree,
                checked: _checked,
                onChanged: () => setState(() {}),
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
            onPressed: pending.isEmpty || _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 16),
            label: Text(
              _results.isNotEmpty
                  ? 'Tentar de novo'
                  : pending.isEmpty
                      ? 'Aplicar'
                      : 'Aplicar em ${pending.length}',
            ),
          ),
      ],
    );
  }
}
