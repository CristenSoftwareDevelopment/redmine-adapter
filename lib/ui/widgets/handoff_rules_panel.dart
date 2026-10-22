import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/handoff_rule.dart';
import '../../models/team.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../icon_picker.dart';

/// Settings panel with the "Enviar trâmite" rules shown in the issue dialog.
/// Saved right away, independent of the "Salvar configuração" button.
class HandoffRulesPanel extends StatelessWidget {
  const HandoffRulesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final rules = context.watch<AppState>().settings.handoffRules;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: const Text('Trâmites'),
            subtitle: 'Ações de trâmite na própria tarefa ou enviando para outra '
                '(ex. desenvolvimento → qualidade). Salvas na hora.',
            trailing: OutlinedButton.icon(
              onPressed: () => _edit(context, rules, null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Nova regra'),
            ),
          ),
          if (rules.isEmpty)
            const EmptyState(icon: Icons.send_outlined, text: 'Nenhuma regra ainda.')
          else
            for (var i = 0; i < rules.length; i++)
              ListRow(
                leading: IconBox(icon: actionIcon(rules[i].icon, Icons.send_outlined)),
                title: Text(rules[i].name),
                meta: [
                  Text(
                    rules[i].sameIssue
                        ? 'Trâmite na própria tarefa'
                        : 'Envia para outra tarefa · ${rules[i].template}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rules[i].assigneeName != null)
                    Text('Responsável padrão: ${rules[i].assigneeName}'),
                ],
                onTap: () => _edit(context, rules, i),
                actions: [
                  IconBtn(
                    icon: Icons.delete_outline,
                    tooltip: 'Excluir regra',
                    compact: true,
                    onPressed: () => _save(context, [...rules]..removeAt(i)),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, List<HandoffRule> rules, int? index) async {
    final rule = await showAppDialog<HandoffRule>(
      context,
      (_) => _HandoffRuleDialog(initial: index == null ? null : rules[index]),
    );
    if (rule == null || !context.mounted) return;
    await _save(
      context,
      // An edited rule keeps its place among the buttons.
      index == null ? [...rules, rule] : ([...rules]..[index] = rule.withOrder(rules[index].order)),
    );
  }

  Future<void> _save(BuildContext context, List<HandoffRule> rules) {
    final state = context.read<AppState>();
    return state.savePreferences(state.settings.copyWith(handoffRules: rules));
  }
}

/// Pops the edited [HandoffRule].
class _HandoffRuleDialog extends StatefulWidget {
  const _HandoffRuleDialog({this.initial});

  final HandoffRule? initial;

  @override
  State<_HandoffRuleDialog> createState() => _HandoffRuleDialogState();
}

class _HandoffRuleDialogState extends State<_HandoffRuleDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? 'Enviar para QA');
  late String? _icon = widget.initial?.icon;
  late bool _sameIssue = widget.initial?.sameIssue ?? false;
  late final _template =
      TextEditingController(text: widget.initial?.template ?? defaultHandoffTemplate);
  late final _multiTemplate =
      TextEditingController(text: widget.initial?.multiTemplate ?? defaultHandoffMultiTemplate);
  late final Set<int> _sources = {...?widget.initial?.sourceTrackerIds};
  late final Set<int> _showStatuses = {...?widget.initial?.statusIds};
  late int? _targetTracker = widget.initial?.targetTrackerId;
  late int? _status = widget.initial?.statusId;
  late int? _timeActivity = widget.initial?.timeActivityId;
  late bool _logTime = widget.initial?.logTime ?? false;
  late bool _bulk = widget.initial?.bulk ?? false;

  /// Status steps being edited; incomplete rows are dropped on save.
  late final List<({int? trackerId, int? statusId})> _steps = [
    for (final s in widget.initial?.statusSteps ?? const <({int trackerId, int statusId})>[])
      (trackerId: s.trackerId, statusId: s.statusId),
  ];
  List<(int, String)>? _activities;
  late TeamMember? _assignee = widget.initial?.assigneeId == null
      ? null
      : TeamMember(id: widget.initial!.assigneeId!, name: widget.initial!.assigneeName ?? '?');

  List<(int, String)>? _trackers;
  List<(int, String)>? _statuses;
  String? _error;

  /// The default assignee is picked among the members of a chosen project.
  final _api = RedmineApiService();
  List<({int id, String name})>? _projects;
  int? _projectId;
  List<TeamMember>? _projectMembers;
  String? _membersError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    _multiTemplate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<AppState>().settings;
    List<(int, String)> named(Object? json, String key) => [
          for (final t in ((json as Map)[key] as List).cast<Map>())
            (t['id'] as int, '${t['name']}'),
        ];
    try {
      final [trackers, statuses, projects, activities] = await Future.wait<Object?>([
        _api.getJson(settings, '/trackers.json'),
        _api.getJson(settings, '/issue_statuses.json'),
        _api.listProjects(settings),
        _api.listNamed(
            settings, '/enumerations/time_entry_activities.json', 'time_entry_activities'),
      ]);
      if (!mounted) return;
      setState(() {
        _trackers = named(trackers, 'trackers');
        _statuses = named(statuses, 'issue_statuses');
        _projects = projects as List<({int id, String name})>;
        _activities = activities as List<(int, String)>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadMembers(int projectId) async {
    setState(() {
      _projectId = projectId;
      _projectMembers = null;
      _membersError = null;
    });
    try {
      final members = await _api.listProjectMembers(
        context.read<AppState>().settings,
        projectId,
      );
      if (mounted && _projectId == projectId) setState(() => _projectMembers = members);
    } catch (error) {
      if (mounted && _projectId == projectId) {
        setState(() => _membersError = '$error'.replaceFirst('Exception: ', ''));
      }
    }
  }

  /// Options + [current] when it's no longer listed, so the dropdown keeps it.
  List<DropdownMenuItem<int?>> _items(List<(int, String)> options, int? current, String none) => [
        DropdownMenuItem(value: null, child: Text(none)),
        for (final (id, name) in options) DropdownMenuItem(value: id, child: Text(name)),
        if (current != null && !options.any((o) => o.$1 == current))
          DropdownMenuItem(value: current, child: Text('#$current')),
      ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 17);
    final members = <int, TeamMember>{
      if (_assignee != null) _assignee!.id: _assignee!,
      for (final m in _projectMembers ?? const <TeamMember>[]) m.id: m,
    }.values.toList();

    return AppDialog(
      title: Text(widget.initial == null ? 'Nova regra de trâmite' : 'Editar regra de trâmite'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Tipo',
            child: SegmentButtons<bool>(
              segments: const [
                (false, 'Enviar para outra tarefa', Icons.forward_to_inbox_outlined),
                (true, 'Trâmite na própria tarefa', Icons.edit_note),
              ],
              selected: _sameIssue,
              onChanged: (v) => setState(() {
                _sameIssue = v;
                // The note template makes no sense as the typed comment's default.
                if (v && _template.text.trim() == defaultHandoffTemplate) _template.clear();
              }),
            ),
          ),
          gap,
          LabeledField(
            label: 'Nome do botão',
            child: TextField(controller: _name, onChanged: (_) => setState(() {})),
          ),
          gap,
          LabeledField(
            label: 'Ícone do botão',
            child: IconPickerField(
              value: _icon,
              fallback: Icons.send_outlined,
              onChanged: (v) => setState(() => _icon = v),
            ),
          ),
          gap,
          if (_error != null)
            Text(
              'Não foi possível carregar tipos e status: $_error',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            )
          else if (_trackers == null || _statuses == null)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            LabeledField(
              label: 'Mostrar nas tarefas do tipo (nenhum marcado = todos)',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (id, name) in _trackers!)
                    FilterChip(
                      label: Text(name),
                      selected: _sources.contains(id),
                      onSelected: (on) =>
                          setState(() => on ? _sources.add(id) : _sources.remove(id)),
                    ),
                ],
              ),
            ),
            gap,
            LabeledField(
              label: 'Mostrar nas tarefas na situação (nenhuma marcada = todas)',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (id, name) in _statuses!)
                    FilterChip(
                      label: Text(name),
                      selected: _showStatuses.contains(id),
                      onSelected: (on) =>
                          setState(() => on ? _showStatuses.add(id) : _showStatuses.remove(id)),
                    ),
                ],
              ),
            ),
            gap,
            Wrap(
              spacing: 16,
              runSpacing: 17,
              children: [
                if (!_sameIssue)
                  LabeledField(
                    label: 'Tipo da atividade destino',
                    child: SelectBox<int?>(
                      value: _targetTracker,
                      items: _items(_trackers!, _targetTracker, 'Qualquer tipo'),
                      onChanged: (v) => setState(() => _targetTracker = v),
                    ),
                  ),
                LabeledField(
                  label: _sameIssue ? 'Situação padrão' : 'Status padrão',
                  child: SelectBox<int?>(
                    value: _status,
                    items: _items(_statuses!, _status, 'Manter o atual'),
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
              ],
            ),
          ],
          if (_projects != null) ...[
            gap,
            LabeledField(
              label: 'Projeto (para buscar o responsável padrão)',
              child: SearchSelect(
                value: _projectId,
                options: [for (final p in _projects!) (p.id, p.name)],
                hint: 'Projeto…',
                onChanged: (id) {
                  if (id != null) _loadMembers(id);
                },
              ),
            ),
          ],
          gap,
          LabeledField(
            label: 'Responsável padrão',
            child: SearchSelect(
              value: _assignee?.id,
              options: [for (final m in members) (m.id, m.name)],
              none: 'Manter o atual',
              onChanged: (id) => setState(
                () => _assignee = members.where((m) => m.id == id).firstOrNull,
              ),
            ),
          ),
          if (_membersError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Não foi possível carregar os membros: $_membersError',
                style: AppText.microLabel(dark: dark).copyWith(
                  color: AppColors.danger(dark: dark),
                ),
              ),
            )
          else if (_projectId != null && _projectMembers == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          gap,
          if (_sameIssue) ...[
            LabeledField(
              label: 'Comentário padrão (opcional; você completa na hora)',
              child: TextField(controller: _template, minLines: 2, maxLines: 6),
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Tooltip(message: 'a própria tarefa, ex. #484530', child: Tag('{{tarefa}}')),
                Tooltip(message: 'título da tarefa', child: Tag('{{titulo}}')),
              ],
            ),
          ] else ...[
            LabeledField(
              label: 'Comentário com uma nota',
              child: TextField(controller: _template, minLines: 2, maxLines: 6),
            ),
            gap,
            LabeledField(
              label: 'Comentário com várias notas (a linha com {{noteSelecionado}} se repete)',
              child: TextField(controller: _multiTemplate, minLines: 2, maxLines: 6),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in handoffPlaceholders.entries)
                  Tooltip(message: p.value, child: Tag(p.key)),
              ],
            ),
          ],
          // Same toggles for both kinds of rule.
          const Divider(height: 40),
          Row(
            children: [
              Switch(value: _bulk, onChanged: (v) => setState(() => _bulk = v)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Permitir aplicar também em subtarefas, irmãs e relacionadas (mesmo '
                  'comentário, situação, responsável e versão; as horas ficam só na principal)',
                  style: AppText.body(dark: dark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(value: _logTime, onChanged: (v) => setState(() => _logTime = v)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Registrar tempo gasto (horas sugeridas desde o último trâmite, editáveis no envio)',
                  style: AppText.body(dark: dark),
                ),
              ),
            ],
          ),
          if (_logTime && _activities != null) ...[
            gap,
            LabeledField(
              label: 'Atividade padrão',
              child: SelectBox<int?>(
                value: _timeActivity,
                items: _items(_activities!, _timeActivity, 'Escolher na hora'),
                onChanged: (v) => setState(() => _timeActivity = v),
              ),
            ),
          ],
          if (!_sameIssue && _trackers != null && _statuses != null && _activities != null) ...[
            const Divider(height: 40),
            const SectionTitle(icon: Icons.task_alt, text: 'Fechamento (opcional)'),
            Text(
              'Passos extras feitos no mesmo envio, ex. no fim do code review.',
              style: AppText.captionLight(dark: dark),
            ),
            gap,
            LabeledField(
              label: 'Alterar situação (as tarefas ligadas daquele tipo aparecem no envio)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, step) in _steps.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectBox<int?>(
                              value: step.trackerId,
                              items: _items(_trackers!, step.trackerId, 'Tipo de atividade…'),
                              onChanged: (v) => setState(
                                () => _steps[i] = (trackerId: v, statusId: step.statusId),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: AppColors.mutedText(dark: dark),
                            ),
                          ),
                          Expanded(
                            child: SelectBox<int?>(
                              value: step.statusId,
                              items: _items(_statuses!, step.statusId, 'Situação…'),
                              onChanged: (v) => setState(
                                () => _steps[i] = (trackerId: step.trackerId, statusId: v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconBtn(
                            icon: Icons.delete_outline,
                            tooltip: 'Remover alteração',
                            compact: true,
                            onPressed: () => setState(() => _steps.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _steps.add((trackerId: null, statusId: null))),
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Adicionar alteração'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    HandoffRule(
                      name: _name.text.trim(),
                      icon: _icon,
                      sourceTrackerIds: _sources.toList(),
                      statusIds: _showStatuses.toList(),
                      targetTrackerId: _targetTracker,
                      statusId: _status,
                      assigneeId: _assignee?.id,
                      assigneeName: _assignee?.name,
                      sameIssue: _sameIssue,
                      // A same-issue comment may start empty.
                      template: _sameIssue || _template.text.trim().isNotEmpty
                          ? _template.text.trim()
                          : defaultHandoffTemplate,
                      multiTemplate: _multiTemplate.text.trim().isEmpty
                          ? defaultHandoffMultiTemplate
                          : _multiTemplate.text.trim(),
                      logTime: _logTime,
                      bulk: _bulk,
                      timeActivityId: _timeActivity,
                      statusSteps: [
                        for (final step in _steps)
                          if (step case (trackerId: final t?, statusId: final st?))
                            (trackerId: t, statusId: st),
                      ],
                    ),
                  ),
          child: const Text('Salvar regra'),
        ),
      ],
    );
  }
}
