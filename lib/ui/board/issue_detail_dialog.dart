import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claude_action.dart';
import '../../models/custom_field.dart';
import '../../models/handoff_rule.dart';
import '../../models/redmine_issue.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../icon_picker.dart';
import '../ui_utils.dart';
import 'attachment_preview.dart';
import 'bulk_edit_dialog.dart';
import 'handoff_dialog.dart';
import 'issue_actions.dart';
import 'issue_fields.dart';
import 'note_editor.dart';
import 'redmine_markdown.dart';
import 'time_entry_fields.dart';
import 'tramite_dialog.dart';

/// [onChanged] runs after each change made from the dialog (e.g. the board
/// reloads); [edit] opens it already in edit mode.
Future<void> showIssueDetail(
  BuildContext context,
  RedmineIssue issue, {
  VoidCallback? onChanged,
  bool edit = false,
}) =>
    showAppDialog<void>(
      context,
      (_) => IssueDetailDialog(issue: issue, onChanged: onChanged, edit: edit),
    );

/// Issue details: opens with the list data and loads history/attachments.
class IssueDetailDialog extends StatefulWidget {
  const IssueDetailDialog({super.key, required this.issue, this.onChanged, this.edit = false});

  final RedmineIssue issue;
  final VoidCallback? onChanged;
  final bool edit;

  @override
  State<IssueDetailDialog> createState() => _IssueDetailDialogState();
}

enum _Tab { description, history, time, attachments, children, relations }

/// History filter: everything, journals with a note, journals with changes.
enum _History { all, comments, changes }

class _IssueDetailDialogState extends State<IssueDetailDialog> {
  RedmineIssue? _full;
  String? _error;

  /// Long descriptions used to push the history out of sight: one tab each.
  _Tab _tab = _Tab.description;
  _History _history = _History.all;

  /// Attachments tab: search by name/author, list or thumbnails.
  final _fileSearch = TextEditingController();
  bool _fileGrid = false;

  /// Time logged on this issue (only what the user's role may see).
  List<TimeEntry>? _time;
  String? _timeError;

  /// Parent and related issues by id (relations only carry ids).
  Map<int, RedmineIssue>? _linked;
  String? _linkedError;

  /// Other subtasks of the parent, shown in Relações.
  List<RedmineIssue> _siblings = const [];

  /// Names and choices of the fields, for [_optionsProject] (the issue's, or
  /// the one picked in edit mode).
  IssueOptions? _options;
  int? _optionsProject;

  /// Edit mode ("Editar"): every field in place, by its Redmine key
  /// (`status_id`, `due_date`, `cf_12`…). Saving sends only the keys that
  /// differ from [_original]; the description has its own editor.
  bool _editing = false;
  bool _saving = false;
  bool _refreshing = false;
  Map<String, Object?> _edit = {};
  Map<String, Object?> _original = {};
  final _editDescription = TextEditingController();
  final List<PendingFile> _editFiles = [];

  /// Custom fields shown in edit mode: the issue's, or the new tracker's.
  List<CustomFieldDef> _editFields = [];
  List<(int, String)>? _projects;

  static const _fieldLabels = {
    'status_id': 'Status',
    'assigned_to_id': 'Responsável',
    'priority_id': 'Prioridade',
    'tracker_id': 'Tipo',
    'project_id': 'Projeto',
    'subject': 'Título',
    'description': 'Descrição',
    'done_ratio': '% concluído',
    'fixed_version_id': 'Versão',
    'estimated_hours': 'Estimativa',
    'start_date': 'Início',
    'due_date': 'Prazo',
    'category_id': 'Categoria',
    'parent_id': 'Tarefa pai',
    'is_private': 'Privada',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchTime();
  }

  @override
  void dispose() {
    _editDescription.dispose();
    _fileSearch.dispose();
    super.dispose();
  }

  List<CustomFieldDef> get _defs => context.read<AppState>().settings.customFields;

  /// Line endings as typed in the editor, so an untouched text isn't "changed".
  static String _plain(String text) => text.replaceAll('\r\n', '\n');

  /// Values compared on save: lists by their items, null as empty.
  static String _norm(Object? v) => v is List ? v.join('\u0000') : '${v ?? ''}';

  static List<Map> _customFields(RedmineIssue issue) =>
      (issue.json['custom_fields'] as List? ?? const []).whereType<Map>().toList();

  /// Edit value of a custom field: List<String> when multiple, else String.
  static Object _customValue(Map field) {
    final value = field['value'];
    return field['multiple'] == true || value is List
        ? [for (final v in value as List? ?? const []) '$v']
        : '${value ?? ''}';
  }

  Map<String, Object?> _values(RedmineIssue issue) {
    final j = issue.json;
    final estimated = j['estimated_hours'] as num?;
    return {
      'subject': issue.subject,
      'project_id': issue.refId('project'),
      'tracker_id': issue.refId('tracker'),
      'status_id': issue.statusId,
      'priority_id': issue.priorityId,
      'assigned_to_id': issue.assigneeId,
      'fixed_version_id': issue.refId('fixed_version'),
      'category_id': issue.refId('category'),
      'parent_issue_id': '${issue.refId('parent') ?? ''}',
      'start_date': j['start_date'] as String? ?? '',
      'due_date': j['due_date'] as String? ?? '',
      'estimated_hours': estimated == null ? '' : fmtHours(estimated.toDouble()),
      'done_ratio': (j['done_ratio'] as num?)?.toInt() ?? 0,
      for (final f in _customFields(issue)) 'cf_${f['id']}': _customValue(f),
    };
  }

  void _set(String key, Object? value) => setState(() => _edit[key] = value);

  void _startEdit() {
    final issue = _full!;
    setState(() {
      _editing = true;
      _original = _values(issue);
      _edit = {..._original};
      _editFields = [for (final f in _customFields(issue)) customFieldDef(_defs, f)];
      _editDescription.text = _plain(issue.description);
      _editFiles.clear();
    });
    if (_projects == null) {
      RedmineApiService().listProjects(context.read<AppState>().settings).then(
            (list) =>
                mounted ? setState(() => _projects = [for (final p in list) (p.id, p.name)]) : null,
            onError: (Object _) => mounted ? setState(() => _projects = const []) : null,
          );
    }
  }

  void _cancelEdit() {
    setState(() => _editing = false);
    // A project picked while editing loaded its own choices.
    final project = _full?.refId('project');
    if (project != _optionsProject) _loadOptions(project);
  }

  Future<void> _loadOptions(int? project) async {
    _optionsProject = project;
    final options = project == null
        ? const IssueOptions()
        : await IssueOptions.load(context.read<AppState>().settings, project);
    if (mounted && project == _optionsProject) setState(() => _options = options);
  }

  /// Another project: its choices load, and version/category/assignee that
  /// don't exist there are cleared.
  Future<void> _changeProject(int? project) async {
    if (project == null) return;
    _set('project_id', project);
    await _loadOptions(project);
    final options = _options;
    if (!mounted || options == null || project != _optionsProject) return;
    bool has(List<(int, String)> list, String key) => list.any((o) => o.$1 == _edit[key]);
    setState(() {
      if (!has(options.versions, 'fixed_version_id')) _edit['fixed_version_id'] = null;
      if (!has(options.categories, 'category_id')) _edit['category_id'] = null;
      if (!has(options.members, 'assigned_to_id')) _edit['assigned_to_id'] = null;
    });
  }

  /// Another tracker: the custom fields become the saved ones known to be on
  /// it (starting at their default); without that info the current ones stay.
  void _changeTracker(int? tracker) {
    setState(() {
      _edit['tracker_id'] = tracker;
      final known = _defs.any((d) => d.trackerIds.isNotEmpty);
      if (tracker == _original['tracker_id'] || !known) {
        _editFields = [for (final f in _customFields(_full!)) customFieldDef(_defs, f)];
        return;
      }
      _editFields = [
        for (final d in _defs)
          if (d.trackerIds.contains(tracker)) d,
      ];
      for (final d in _editFields) {
        _edit.putIfAbsent('cf_${d.id}', () => d.multiple ? <String>[] : d.defaultValue ?? '');
      }
    });
  }

  /// One update with only what changed ('' clears). Status goes through
  /// [RedmineApiService.setIssueStatus], which checks the workflow.
  Future<void> _save() async {
    final issue = _full!;
    final settings = context.read<AppState>().settings;
    final messenger = ScaffoldMessenger.of(context);
    void fail(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

    final changes = <String, dynamic>{};
    final custom = <Map<String, Object?>>[];
    int? status;
    for (final key in _edit.keys) {
      final value = _edit[key];
      if (_norm(value) == _norm(_original[key])) continue;
      if (key == 'status_id') {
        status = value as int?;
      } else if (key.startsWith('cf_')) {
        final id = int.parse(key.substring(3));
        final float = _editFields.any((d) => d.id == id && d.format == 'float');
        custom.add({
          'id': id,
          'value': value is List
              ? value
              : float
                  ? '$value'.trim().replaceAll(',', '.')
                  : '$value'.trim(),
        });
      } else if (key == 'estimated_hours') {
        final text = '$value'.trim();
        final hours = parseHours(text);
        if (text.isNotEmpty && hours == null) return fail('Estimativa inválida: use 1,5 ou 1:30.');
        changes[key] = hours ?? '';
      } else if (key == 'parent_issue_id') {
        final text = '$value'.trim().replaceFirst('#', '');
        if (text.isNotEmpty && int.tryParse(text) == null) {
          return fail('Tarefa pai inválida: use o número, ex. 123.');
        }
        changes[key] = text.isEmpty ? '' : int.parse(text);
      } else if (key == 'subject') {
        if ('$value'.trim().isEmpty) return fail('O título não pode ficar vazio.');
        changes[key] = '$value'.trim();
      } else {
        changes[key] = value ?? '';
      }
    }
    if (custom.isNotEmpty) changes['custom_fields'] = custom;
    if (_editDescription.text != _plain(issue.description)) {
      changes['description'] = _editDescription.text;
    }
    if (changes.isEmpty && status == null && _editFiles.isEmpty) {
      return setState(() => _editing = false);
    }
    setState(() => _saving = true);
    try {
      final api = RedmineApiService();
      if (_editFiles.isNotEmpty) changes['uploads'] = await uploadFiles(settings, _editFiles);
      var applied = true;
      if (status != null) {
        applied = await api.setIssueStatus(settings, issue.id, status, extra: changes);
      } else {
        await api.putJson(settings, '/issues/${issue.id}.json', {'issue': changes});
      }
      if (!mounted) return;
      setState(() => _editing = false);
      _changed();
      messenger.showSnackBar(SnackBar(
        content: Text(applied
            ? 'Tarefa #${issue.id} atualizada.'
            : 'Salvo, mas o Redmine não aplicou a situação de #${issue.id}: '
                'transição não permitida pelo workflow ou sem permissão.'),
      ));
    } catch (error) {
      fail('Falha ao salvar #${issue.id}: ${'$error'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fetchTime() async {
    try {
      final entries = await RedmineApiService().getAllPages(
        context.read<AppState>().settings,
        // "~" = the issue or any of its subtasks, matching the total shown in "Tempo gasto".
        '/time_entries.json?f[]=issue_id&op[issue_id]=~&v[issue_id][]=${widget.issue.id}',
        'time_entries',
        cap: 2000,
      );
      if (!mounted) return;
      setState(() {
        _time = entries.map(TimeEntry.fromJson).toList()..sort((a, b) => b.day.compareTo(a.day));
      });
    } catch (error) {
      if (mounted) setState(() => _timeError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _fetch() async {
    try {
      final full = await fetchFullIssue(context.read<AppState>().settings, widget.issue.id);
      if (!mounted) return;
      final first = _full == null;
      setState(() => _full = full);
      if (first || full.refId('project') != _optionsProject) _loadOptions(full.refId('project'));
      if (first && widget.edit) _startEdit();
      _fetchLinked(full);
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// Something was changed from here: reload the issue and tell the opener.
  void _changed() {
    _fetch();
    _fetchTime();
    widget.onChanged?.call();
  }

  /// "Atualizar": the issue may have changed elsewhere (Redmine web, MCP…).
  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
      _timeError = null;
      _linkedError = null;
    });
    await (_fetch(), _fetchTime()).wait;
    widget.onChanged?.call();
    if (mounted) setState(() => _refreshing = false);
  }

  /// Parent, subtasks and related issues, read in one call for subject, tracker
  /// and status (`include=children` brings no status).
  Future<void> _fetchLinked(RedmineIssue issue) async {
    final parent = issue.refId('parent');
    final ids = {
      parent,
      for (final c in _list(issue, 'children')) c['id'] as int,
      for (final (_, id) in _relations(issue)) id,
    }.nonNulls;
    if (ids.isEmpty) {
      return setState(() {
        _linked = const {};
        _siblings = const [];
      });
    }
    final settings = context.read<AppState>().settings;
    final api = RedmineApiService();
    try {
      final (list, siblings) = await (
        api.getAllPages(settings, '/issues.json?issue_id=${ids.join(',')}&status_id=*', 'issues'),
        parent == null
            ? Future.value(const <Map<String, dynamic>>[])
            : api.getAllPages(settings, '/issues.json?parent_id=$parent&status_id=*', 'issues'),
      ).wait;
      if (!mounted) return;
      setState(() {
        _linked = {for (final j in list) j['id'] as int: RedmineIssue(j)};
        _siblings = [
          for (final j in siblings)
            if (j['id'] != issue.id) RedmineIssue(j),
        ];
      });
    } catch (error) {
      if (mounted) setState(() => _linkedError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// Opens a subtask/related issue on top of this one.
  void _open(RedmineIssue issue) => showIssueDetail(context, issue, onChanged: widget.onChanged);

  /// (label from this issue's side, other issue id) for each relation.
  List<(String, int)> _relations(RedmineIssue issue) => [
        for (final r in _list(issue, 'relations'))
          (
            relationLabel(r, issue.id),
            (r['issue_id'] == issue.id ? r['issue_to_id'] : r['issue_id']) as int,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final issue = _full ?? widget.issue;
    final border = AppColors.border(dark: dark);

    return AppDialog(
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      title: Row(
        children: [const Text('Tarefa '), IssueNumber(issue.id)],
      ),
      // Automations sit above the tabs ([_automations]); only the fixed ones here.
      headActions: [
        if (!_editing) ...[
          OutlinedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 16),
            label: const Text('Atualizar'),
          ),
          OutlinedButton.icon(
            onPressed: _full == null ? null : _startEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Editar'),
          ),
          OutlinedButton.icon(
            onPressed: _full == null ? null : () => _afterSend(showBulkEditDialog(context, _full!)),
            icon: const Icon(Icons.account_tree_outlined, size: 16),
            label: const Text('Alterar em massa'),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => openRedmineLink(context, '/issues/${issue.id}'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Abrir no Redmine'),
        ),
      ],
      footer: [
        if (_editing) ...[
          OutlinedButton(
            onPressed: _saving ? null : _cancelEdit,
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 16),
            label: const Text('Salvar'),
          ),
        ],
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
            // Selection per column (header, tab content, attributes): Flutter selects
            // by geometry, so one area over side-by-side columns mixed them up.
            child: PageSelectionArea(child: _heading(issue, dark)),
          ),
          Container(height: 1, color: border),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Automations wrap in a strip over the tabs (left column only).
                final automations = _automations(issue);
                final strip = Container(
                  padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                  child: Wrap(spacing: 8, runSpacing: 8, children: automations),
                );
                final tabs = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                  // Scrolls sideways when the tabs don't fit (narrow windows).
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _tabBar(issue),
                    ),
                  ),
                );
                // Line breaks between pieces when copying (see LineBreakSelection).
                final content = LineBreakSelection(child: _tabContent(issue, dark));
                final side = LineBreakSelection(child: _attributes(issue, dark));
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (automations.isNotEmpty) strip,
                      tabs,
                      Expanded(
                        child: SelectionArea(
                          child: SingleChildScrollView(
                            key: ValueKey(_tab),
                            padding: const EdgeInsets.all(20),
                            child: LineBreakSelection(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [content, const SizedBox(height: Sp.s24), side],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (automations.isNotEmpty) strip,
                          tabs,
                          // Each tab scrolls on its own and starts at the top.
                          Expanded(
                            child: SelectionArea(
                              child: SingleChildScrollView(
                                key: ValueKey(_tab),
                                padding: const EdgeInsets.all(26),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: border),
                    SizedBox(
                      width: _editing ? 340 : 300,
                      child: SelectionArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(22),
                          child: side,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Project, title (editable), tracker/status/priority tags and last update.
  Widget _heading(RedmineIssue issue, bool dark) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issue.projectName.isNotEmpty)
            Text(issue.projectName.toUpperCase(), style: AppText.sectionLabel(dark: dark)),
          const SizedBox(height: 8),
          if (_editing)
            fieldText(
              key: const ValueKey('subject'),
              value: '${_edit['subject'] ?? ''}',
              hint: 'Título',
              onChanged: (v) => _edit['subject'] = v,
            )
          else
            Text(
              issue.subject,
              style: AppText.cardTitle(dark: dark)
                  .copyWith(fontSize: 22, height: 1.45, letterSpacing: -0.3),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (issue.trackerName.isNotEmpty) Tag.hashed(issue.trackerName),
                    Tag(issue.statusName, icon: Icons.fiber_manual_record),
                    Tag(issue.priorityName, icon: Icons.flag_outlined),
                  ],
                ),
              ),
              if (issue.updatedOn != null)
                Text(
                  'Atualizada em ${fmtDateTime(issue.updatedOn)}',
                  style: AppText.microLabel(dark: dark),
                ),
            ],
          ),
        ],
      );

  /// A send dialog closed: true = everything was sent.
  Future<void> _afterSend(Future<bool> sent) async {
    if (await sent && mounted) _changed();
  }

  /// "Enviar trâmite" rules shown on this issue (tracker and status filters).
  List<HandoffRule> _rules(RedmineIssue issue) =>
      issueActions(context.watch<AppState>().settings, issue).whereType<HandoffRule>().toList();

  List<Map> _list(RedmineIssue issue, String key) =>
      (issue.json[key] as List? ?? const []).cast<Map>();

  Widget _tabBar(RedmineIssue issue) {
    final journals = _list(issue, 'journals');
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    final links =
        _relations(issue).length + (issue.refId('parent') == null ? 0 : 1) + _siblings.length;
    return LineTabs<_Tab>(
      tabs: [
        (_Tab.description, 'Descrição', Icons.description_outlined, null),
        (_Tab.history, 'Histórico', Icons.history, _full == null ? null : '${journals.length}'),
        (
          _Tab.time,
          'Tempo gasto',
          Icons.schedule,
          _time == null ? null : '${fmtHours(_time!.fold(0.0, (sum, e) => sum + e.hours))} h',
        ),
        if (attachments.isNotEmpty)
          (_Tab.attachments, 'Anexos', Icons.attach_file, '${attachments.length}'),
        if (children.isNotEmpty)
          (_Tab.children, 'Subtarefas', Icons.account_tree_outlined, '${children.length}'),
        if (links > 0) (_Tab.relations, 'Relações', Icons.link, '$links'),
      ],
      selected: _tab,
      onChanged: (t) => setState(() => _tab = t),
    );
  }

  /// Title of a tab's content, with a note below and an optional action.
  Widget _sectionHead(String title, bool dark, {String? note, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.cardTitle(dark: dark)),
                  if (note != null) Text(note, style: AppText.microLabel(dark: dark)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _markdown(String text, RedmineIssue issue) =>
      RedmineMarkdown(text, attachments: _list(issue, 'attachments'));

  Widget _tabContent(RedmineIssue issue, bool dark) {
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    // Newest first, keeping the 1-based position Redmine uses in `#note-N`.
    final journals = _list(issue, 'journals').indexed.toList().reversed;
    Widget error(String text) => Text(
          text,
          style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
        );

    switch (_tab) {
      case _Tab.description:
        final created = DateTime.tryParse('${issue.json['created_on']}');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(
              'Descrição da tarefa',
              dark,
              note: created == null ? null : 'Criada em ${fmtDateTime(created)}',
            ),
            if (_editing)
              NoteEditor(
                controller: _editDescription,
                files: _editFiles,
                attachments: attachments,
                onChanged: () => setState(() {}),
                hint: 'Descrição…',
                minLines: 12,
                maxLines: 30,
              )
            else if (issue.description.trim().isEmpty)
              Text('Sem descrição.', style: AppText.captionLight(dark: dark))
            else
              Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 870),
                  child: _markdown(issue.description, issue),
                ),
              ),
          ],
        );
      case _Tab.history:
        if (_full == null && _error == null) return const LinearProgressIndicator(minHeight: 2);
        if (_error != null) return error('Não foi possível carregar o histórico: $_error');
        final shown = [
          for (final (i, j) in journals)
            if (switch (_history) {
              _History.all => true,
              _History.comments => '${j['notes'] ?? ''}'.trim().isNotEmpty,
              _History.changes => (j['details'] as List? ?? const []).isNotEmpty,
            })
              (i, j),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(
              'Histórico da tarefa',
              dark,
              note: 'Comentários e alterações, do mais recente ao mais antigo',
              trailing: FilledButton.icon(
                onPressed: () => _afterSend(showTramiteDialog(context, _full!, newTramiteRule)),
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                label: const Text('Novo trâmite'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTabs<_History>(
                tabs: const [
                  (_History.all, 'Tudo', null),
                  (_History.comments, 'Comentários', Icons.chat_bubble_outline),
                  (_History.changes, 'Alterações', Icons.tune),
                ],
                selected: _history,
                onChanged: (h) => setState(() => _history = h),
              ),
            ),
            const SizedBox(height: Sp.s24),
            if (shown.isEmpty)
              Text(
                journals.isEmpty ? 'Sem histórico.' : 'Nada neste filtro.',
                style: AppText.captionLight(dark: dark),
              ),
            for (final (n, (i, j)) in shown.indexed)
              _journal(j, i + 1, issue, dark, last: n == shown.length - 1),
          ],
        );
      case _Tab.time:
        return _timeContent(issue, dark);
      case _Tab.attachments:
        final q = searchKey(_fileSearch.text.trim());
        final shown = [
          for (final (i, a) in attachments.indexed)
            if (q.isEmpty ||
                searchKey('${a['filename']} ${(a['author'] as Map?)?['name'] ?? ''}').contains(q))
              i,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead(
              'Anexos da tarefa',
              dark,
              note: '${attachments.length} arquivo${attachments.length == 1 ? '' : 's'}',
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              children: [
                SearchField(
                  controller: _fileSearch,
                  hint: 'Buscar por nome ou autor…',
                  width: 280,
                  onChanged: (_) => setState(() {}),
                ),
                AppTabs<bool>(
                  tabs: const [
                    (false, 'Lista', Icons.view_list_outlined),
                    (true, 'Miniaturas', Icons.grid_view),
                  ],
                  selected: _fileGrid,
                  onChanged: (grid) => setState(() => _fileGrid = grid),
                ),
              ],
            ),
            const SizedBox(height: Sp.s16),
            if (shown.isEmpty)
              const EmptyState(text: 'Nenhum anexo encontrado para esta busca.')
            else if (_fileGrid)
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 700
                    ? 3
                    : box.maxWidth >= 420
                        ? 2
                        : 1;
                final width = (box.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final i in shown)
                      SizedBox(width: width, child: _attachmentCard(attachments, i, dark)),
                  ],
                );
              })
            else
              for (final i in shown) _attachmentRow(attachments, i, dark),
          ],
        );
      case _Tab.children:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead('Subtarefas', dark),
            LinkedIssueList(onOpen: _open, rows: [
              for (final c in children) (null, _linked?[c['id']] ?? RedmineIssue(c.cast())),
            ]),
          ],
        );
      case _Tab.relations:
        if (_linkedError != null) {
          return error('Não foi possível carregar as relações: $_linkedError');
        }
        final linked = _linked;
        if (linked == null) return const LinearProgressIndicator(minHeight: 2);
        // Issues the user can't see come back missing: shown by number only.
        RedmineIssue of(int id) => linked[id] ?? RedmineIssue({'id': id});
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHead('Relações', dark),
            LinkedIssueList(onOpen: _open, rows: [
              if (issue.refId('parent') case final parent?) ('Tarefa pai', of(parent)),
              for (final (label, id) in _relations(issue)) (label, of(id)),
              for (final s in _siblings) ('Irmã', s),
            ]),
          ],
        );
    }
  }

  String _attachmentMeta(Map a) => [
        fmtFileSize(a['filesize'] as num?),
        if ((a['author'] as Map?)?['name'] case final author?) '$author',
        fmtDateTime(DateTime.tryParse('${a['created_on']}')),
      ].where((t) => t.isNotEmpty).join(' · ');

  /// Attachment row: thumbnail (images) or type icon, name, size, author and
  /// date. Click previews it in the app; the button keeps the browser route.
  Widget _attachmentRow(List<Map> all, int index, bool dark) {
    final a = all[index];
    final name = '${a['filename']}';
    final kind = previewKind(name, a['content_type'] as String?);
    final url = '${a['content_url'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s8),
      child: Material(
        color: AppColors.field(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          side: BorderSide(color: AppColors.border(dark: dark)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showAttachmentPreview(context, all, index: index),
          hoverColor: AppColors.cellHover(dark: dark),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: kind == AttachmentKind.image
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.subtle),
                          child: AuthImage(url: url, fit: BoxFit.cover),
                        )
                      : Icon(kindIcon(kind), color: AppColors.mutedText(dark: dark)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyMedium(dark: dark),
                      ),
                      const SizedBox(height: 2),
                      Text(_attachmentMeta(a), style: AppText.microLabel(dark: dark)),
                    ],
                  ),
                ),
                IconBtn(
                  icon: Icons.open_in_new,
                  tooltip: 'Abrir no navegador',
                  compact: true,
                  onPressed: () => openRedmineLink(context, url),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Thumbnail card of the "Miniaturas" view; click previews it.
  Widget _attachmentCard(List<Map> all, int index, bool dark) {
    final a = all[index];
    final name = '${a['filename']}';
    final kind = previewKind(name, a['content_type'] as String?);
    return Material(
      color: AppColors.field(dark: dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        side: BorderSide(color: AppColors.border(dark: dark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAttachmentPreview(context, all, index: index),
        hoverColor: AppColors.cellHover(dark: dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 110,
              child: kind == AttachmentKind.image
                  ? AuthImage(url: '${a['content_url'] ?? ''}', fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppColors.well(dark: dark),
                      child: Icon(kindIcon(kind), size: 30, color: AppColors.mutedText(dark: dark)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMedium(dark: dark),
                  ),
                  Text(
                    _attachmentMeta(a),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.microLabel(dark: dark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Total and top people, then a table of the entries (newest first).
  Widget _timeContent(RedmineIssue issue, bool dark) {
    final entries = _time;
    final head = _sectionHead(
      'Tempo gasto',
      dark,
      note: entries == null || entries.isEmpty
          ? null
          : '${entries.length} lançamento${entries.length == 1 ? '' : 's'}',
      trailing: FilledButton.icon(
        onPressed: () => _afterSend(showLogTimeDialog(context, issue)),
        icon: const Icon(Icons.more_time, size: 16),
        label: const Text('Lançar horas'),
      ),
    );
    Widget only(Widget child) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, child]);
    if (_timeError != null) {
      return only(Text(
        'Não foi possível carregar o tempo gasto: $_timeError',
        style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
      ));
    }
    if (entries == null) return only(const LinearProgressIndicator(minHeight: 2));
    if (entries.isEmpty) {
      return only(Text(
        'Nenhum tempo lançado que você possa ver nesta tarefa.',
        style: AppText.captionLight(dark: dark),
      ));
    }
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final byPerson = sumHours(entries, (e) => e.userName).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final estimated = (issue.json['estimated_hours'] as num?)?.toDouble();
    final border = AppColors.border(dark: dark);

    Widget row(List<Widget> cells, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration:
              BoxDecoration(color: color, border: Border(bottom: BorderSide(color: border))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: cells[0]),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: cells[1]),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: cells[2]),
              const SizedBox(width: 12),
              SizedBox(width: 70, child: Align(alignment: Alignment.topRight, child: cells[3])),
            ],
          ),
        );
    final strong = AppText.bodySemibold(dark: dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        StatGrid(
          children: [
            StatCard(
              label: 'Total registrado',
              value: '${fmtHours(total)} h',
              note: estimated == null
                  ? 'Sem estimativa definida'
                  : 'de ${fmtHours(estimated)} h estimadas',
              icon: Icons.schedule,
            ),
            for (final p in byPerson.take(3))
              StatCard(
                label: p.key,
                value: '${fmtHours(p.value)} h',
                note: {
                  for (final e in entries)
                    if (e.userName == p.key) e.activity
                }.join(', '),
                icon: Icons.person_outline,
              ),
          ],
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AppRadius.standard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row(
                [
                  for (final h in ['PROFISSIONAL', 'DATA', 'ATIVIDADE', 'HORAS'])
                    Text(h, style: AppText.sectionLabel(dark: dark)),
                ],
                color: AppColors.sunken(dark: dark),
              ),
              for (final e in entries)
                row([
                  Row(
                    children: [
                      UserAvatar(name: e.userName, size: 22),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.userName, style: AppText.body(dark: dark))),
                    ],
                  ),
                  Text(fmtDate(ymd(e.day)), style: AppText.body(dark: dark)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.activity, style: AppText.body(dark: dark)),
                      if (e.issueId != null && e.issueId != widget.issue.id)
                        Text('subtarefa #${e.issueId}', style: AppText.microLabel(dark: dark)),
                      if (e.comments.isNotEmpty)
                        Text(e.comments, style: AppText.microLabel(dark: dark)),
                    ],
                  ),
                  Text('${fmtHours(e.hours)} h', style: strong),
                ]),
              row(
                [
                  Text('Total', style: strong),
                  const SizedBox(),
                  const SizedBox(),
                  Text('${fmtHours(total)} h', style: strong)
                ],
                color: AppColors.footer(dark: dark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One change of a journal: label and old → new values, by name.
  ({String label, String? from, String? to}) _detail(Map d, RedmineIssue issue) {
    final options = _options ?? const IssueOptions();
    final name = '${d['name']}';
    final old = d['old_value'] == null ? null : '${d['old_value']}';
    final now = d['new_value'] == null ? null : '${d['new_value']}';
    switch (d['property']) {
      case 'cf':
        final id = int.tryParse(name);
        final field = _customFields(issue).where((f) => f['id'] == id).firstOrNull;
        final def = _defs.where((f) => f.id == id).firstOrNull;
        String? text(String? v) => v == null || v.isEmpty ? null : customFieldText(def, v, options);
        return (
          label: '${field?['name'] ?? def?.name ?? 'Campo #$name'}',
          from: text(old),
          to: text(now),
        );
      case 'attachment':
        return now != null
            ? (label: 'Anexou', from: null, to: now)
            : (label: 'Removeu o anexo', from: null, to: old);
      case 'relation':
        final (forward, _) = _relationLabels[name] ?? (name, name);
        return (
          label: 'Relação · $forward',
          from: old == null ? null : '#$old',
          to: now == null ? null : '#$now'
        );
      default:
        if (name == 'description') return (label: 'Descrição alterada', from: null, to: null);
        String? value(String? v) {
          if (v == null || v.isEmpty) return null;
          final id = int.tryParse(v);
          String named(List<(int, String)> list) => id == null ? v : optionName(list, id);
          return switch (name) {
            'status_id' => named(options.statuses),
            'assigned_to_id' => named(options.members),
            'priority_id' => named(options.priorities),
            'tracker_id' => named(options.trackers),
            'category_id' => named(options.categories),
            'fixed_version_id' => options.versionNames[id] ?? '#$v',
            'project_id' when id == issue.refId('project') => issue.projectName,
            'parent_id' || 'project_id' => '#$v',
            'start_date' || 'due_date' => fmtDate(v),
            'done_ratio' => '$v%',
            'estimated_hours' => '${fmtHours(double.tryParse(v) ?? 0)} h',
            'is_private' => v == '1' || v == 'true' ? 'Sim' : 'Não',
            _ => v,
          };
        }
        return (label: _fieldLabels[name] ?? name, from: value(old), to: value(now));
    }
  }

  /// Timeline entry: avatar on a vertical line, author, date and note number,
  /// the changes, and the note in a box.
  Widget _journal(Map journal, int index, RedmineIssue issue, bool dark, {required bool last}) {
    // Only sends to another issue cite a note.
    final rules = [
      for (final r in _rules(issue))
        if (!r.sameIssue) r
    ];
    final author = (journal['user'] as Map?)?['name'] as String? ?? '?';
    final notes = (journal['notes'] as String? ?? '').trim();
    final details = [
      for (final d in (journal['details'] as List? ?? const []).whereType<Map>()) _detail(d, issue),
    ];
    final value = AppText.caption(dark: dark).copyWith(color: AppColors.text(dark: dark));
    return Stack(
      children: [
        // The line stops at the last entry; Positioned avoids intrinsic sizing,
        // which the markdown inside can't do.
        if (!last)
          Positioned(
            left: 14,
            top: 34,
            bottom: 0,
            child: Container(width: 1, color: AppColors.border(dark: dark)),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: author, size: 29),
              const SizedBox(width: Sp.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: author, style: AppText.bodySemibold(dark: dark)),
                                TextSpan(
                                  text:
                                      '  ${fmtDateTime(DateTime.tryParse('${journal['created_on']}'))}',
                                  style: AppText.microLabel(dark: dark),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text('#note-$index', style: AppText.microLabel(dark: dark)),
                        if (notes.isNotEmpty && rules.isNotEmpty) ...[
                          const SizedBox(width: Sp.s8),
                          IconBtn(
                            icon: Icons.send_outlined,
                            tooltip: 'Enviar este trâmite',
                            compact: true,
                            onPressed: () => _afterSend(
                                showHandoffDialog(context, issue, rules, noteIndex: index)),
                          ),
                        ],
                      ],
                    ),
                    for (final d in details)
                      Text.rich(
                        TextSpan(
                          style: AppText.microLabel(dark: dark),
                          children: [
                            TextSpan(text: d.label),
                            if (d.from != null || d.to != null) ...[
                              const TextSpan(text: ':  '),
                              if (d.from != null) TextSpan(text: d.from, style: value),
                              if (d.from != null && d.to != null) const TextSpan(text: '  →  '),
                              if (d.to != null)
                                TextSpan(
                                  text: d.to,
                                  style: value.copyWith(fontWeight: FontWeight.w600),
                                ),
                              if (d.to == null) const TextSpan(text: '  →  (vazio)'),
                            ],
                          ],
                        ),
                      ),
                    if (notes.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: Sp.s8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.field(dark: dark),
                          border: Border.all(color: AppColors.border(dark: dark)),
                          borderRadius: BorderRadius.circular(AppRadius.standard),
                        ),
                        child: _markdown(notes, _full ?? widget.issue),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Select of edit mode bound to [key]; the issue's current [ref] joins the
  /// choices when missing (non-member, closed version…).
  Widget _select(
    String key,
    List<(int, String)> options, {
    String? ref,
    String? none,
    ValueChanged<int?>? onChanged,
  }) {
    final issue = _full ?? widget.issue;
    return SearchSelect(
      value: _edit[key] as int?,
      options: [
        ...options,
        if (ref != null)
          if (issue.refId(ref) case final id? when !options.any((o) => o.$1 == id))
            (id, issue.nameOf(ref) ?? '#$id'),
      ],
      none: none,
      onChanged: onChanged ?? (v) => _set(key, v),
    );
  }

  /// One button per automation (Claude actions and trâmite rules), with its
  /// icon, in the chosen order.
  List<Widget> _automations(RedmineIssue issue) {
    final actions = issueActions(context.watch<AppState>().settings, issue);
    final rules = actions.whereType<HandoffRule>().toList();
    Widget button(IconData icon, String name, VoidCallback? onPressed) => OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(name),
        );
    return [
      for (final action in actions)
        switch (action) {
          ClaudeAction a => button(actionIcon(a.icon, Icons.terminal), a.name, () async {
              if (await runClaudeAction(context, a, issue)) _changed();
            }),
          // Needs the journals and relations of the full issue. For a send to
          // another issue, the clicked rule comes first so the dialog opens on it.
          HandoffRule r => button(
              actionIcon(r.icon, Icons.send_outlined),
              r.name,
              _full == null
                  ? null
                  : r.sameIssue
                      ? () => _afterSend(showTramiteDialog(context, _full!, r))
                      : () => _afterSend(showHandoffDialog(context, _full!, [
                            r,
                            ...rules.where((o) => o != r && !o.sameIssue),
                          ])),
            ),
          _ => const SizedBox.shrink(),
        },
    ];
  }

  /// Side panel in sections. In edit mode each field shows its editor.
  Widget _attributes(RedmineIssue issue, bool dark) {
    final j = issue.json;
    final options = _options ?? const IssueOptions();
    final editing = _editing && _full != null;
    String hours(Object? v) => v == null ? '-' : '${fmtHours((v as num).toDouble())} h';
    Widget text(String v) => Text(v, style: AppText.bodyMedium(dark: dark));
    Widget field(String label, Widget view, [Widget? editor]) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: AppText.microLabel(dark: dark)),
              const SizedBox(height: 2),
              if (editing && editor != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: editor)
              else
                view,
            ],
          ),
        );
    var first = true;
    Widget section(String title, List<Widget> children) {
      final top = first;
      first = false;
      return Container(
        margin: EdgeInsets.only(top: top ? 0 : Sp.s8),
        padding: EdgeInsets.only(top: top ? 0 : 18),
        decoration: top
            ? null
            : BoxDecoration(border: Border(top: BorderSide(color: AppColors.border(dark: dark)))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(), style: AppText.sectionLabel(dark: dark)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
    }

    final done = (j['done_ratio'] as num? ?? 0).toDouble();
    final assignee = issue.assigneeName;
    final customFields = _customFields(issue);
    final unconfigured = editing && _editFields.any((f) => !_defs.any((d) => d.id == f.id));
    final trackerChanged = editing && _edit['tracker_id'] != _original['tracker_id'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editing && options.error != null) ...[
          Text(
            'Algumas opções não carregaram: ${options.error}',
            style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          ),
          const SizedBox(height: Sp.s12),
        ] else if (editing && _options == null) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: Sp.s12),
        ],
        section('Acompanhamento', [
          field('Status', text(issue.statusName),
              _select('status_id', options.statuses, ref: 'status')),
          field('Prioridade', text(issue.priorityName),
              _select('priority_id', options.priorities, ref: 'priority')),
          field(
            '% concluído',
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: done / 100,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(width: Sp.s8),
                Text('${done.round()}%', style: AppText.caption(dark: dark)),
              ],
            ),
            _select('done_ratio', [for (var p = 0; p <= 100; p += 10) (p, '$p%')]),
          ),
        ]),
        section('Responsáveis', [
          field(
            'Responsável',
            assignee == null
                ? text('Ninguém')
                : Row(
                    children: [
                      UserAvatar(name: assignee, size: 26),
                      const SizedBox(width: Sp.s8),
                      Expanded(child: text(assignee)),
                    ],
                  ),
            _select('assigned_to_id', options.members, ref: 'assigned_to', none: 'Ninguém'),
          ),
          field('Autor', text(issue.nameOf('author') ?? '-')),
        ]),
        section('Planejamento', [
          field(
            'Versão',
            text(issue.nameOf('fixed_version') ?? 'Nenhuma'),
            _select('fixed_version_id', options.versions, ref: 'fixed_version', none: 'Nenhuma'),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: field(
                  'Início',
                  text(fmtDate(j['start_date'] as String?)),
                  DateSelect(
                    value: '${_edit['start_date'] ?? ''}',
                    onChanged: (v) => _set('start_date', v),
                  ),
                ),
              ),
              const SizedBox(width: Sp.s12),
              Expanded(
                child: field(
                  'Prazo',
                  text(fmtDate(j['due_date'] as String?)),
                  DateSelect(
                    value: '${_edit['due_date'] ?? ''}',
                    onChanged: (v) => _set('due_date', v),
                  ),
                ),
              ),
            ],
          ),
          field(
            'Estimativa',
            text(hours(j['estimated_hours'])),
            fieldText(
              key: const ValueKey('estimated_hours'),
              value: '${_edit['estimated_hours'] ?? ''}',
              hint: '1:30 ou 1,5',
              onChanged: (v) => _edit['estimated_hours'] = v,
            ),
          ),
          field('Tempo gasto', text(hours(j['total_spent_hours'] ?? j['spent_hours']))),
          if (editing
              ? options.categories.isNotEmpty || issue.refId('category') != null
              : issue.nameOf('category') != null)
            field(
              'Categoria',
              text(issue.nameOf('category') ?? 'Nenhuma'),
              _select('category_id', options.categories, ref: 'category', none: 'Nenhuma'),
            ),
          if (editing || issue.refId('parent') != null)
            field(
              'Tarefa pai',
              text('#${issue.refId('parent')}'),
              fieldText(
                key: const ValueKey('parent_issue_id'),
                value: '${_edit['parent_issue_id'] ?? ''}',
                hint: 'Número, ex. 123',
                onChanged: (v) => _edit['parent_issue_id'] = v,
              ),
            ),
        ]),
        section('Dados da tarefa', [
          field(
            'Projeto',
            text(issue.projectName),
            _projects == null
                ? const LinearProgressIndicator(minHeight: 2)
                : _select('project_id', _projects!, ref: 'project', onChanged: _changeProject),
          ),
          field(
            'Tipo',
            text(issue.trackerName),
            _select('tracker_id', options.trackers, ref: 'tracker', onChanged: _changeTracker),
          ),
          if (editing) ...[
            if (trackerChanged && !_defs.any((d) => d.trackerIds.isNotEmpty))
              _hint('Os campos do novo tipo aparecem depois de salvar.', dark),
            for (final def in _editFields)
              field(
                def.name,
                const SizedBox(),
                customFieldEditor(
                  def: def,
                  value: _edit['cf_${def.id}'],
                  onChanged: (v) => _set('cf_${def.id}', v),
                  options: options,
                ),
              ),
            if (unconfigured)
              _hint(
                'Campos sem tipo configurado são editados como texto: defina em '
                'Configurações › Campos.',
                dark,
              ),
          ] else
            for (final f in customFields)
              if (customFieldText(customFieldDef(_defs, f), f['value'], options) case final value
                  when value.isNotEmpty)
                field('${f['name']}', text(value)),
        ]),
      ],
    );
  }

  Widget _hint(String text, bool dark) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.s12),
        child: Text(text, style: AppText.microLabel(dark: dark)),
      );
}

const _relationLabels = {
  'relates': ('Relacionada a', 'Relacionada a'),
  'duplicates': ('Duplica', 'Duplicada por'),
  'duplicated': ('Duplicada por', 'Duplica'),
  'blocks': ('Bloqueia', 'Bloqueada por'),
  'blocked': ('Bloqueada por', 'Bloqueia'),
  'precedes': ('Precede', 'Segue'),
  'follows': ('Segue', 'Precede'),
  'copied_to': ('Copiada para', 'Copiada de'),
  'copied_from': ('Copiada de', 'Copiada para'),
};

/// A Redmine relation as seen from [issueId]: `blocks` stored from #1 to #2
/// reads "Bloqueia" on #1 and "Bloqueada por" on #2.
String relationLabel(Map relation, int issueId) {
  final type = '${relation['relation_type']}';
  final (forward, reverse) = _relationLabels[type] ?? (type, type);
  return relation['issue_id'] == issueId ? forward : reverse;
}

/// Subtasks/related issues as aligned cards under one shared header:
/// relation, task (id, title, tracker), assignee, version and status. The
/// fixed columns take the width of their widest content (capped, like CSS
/// grid `auto`); when the task would get too narrow, assignee/version/status
/// move under it with short labels.
class LinkedIssueList extends StatelessWidget {
  const LinkedIssueList({super.key, required this.rows, required this.onOpen});

  /// (relation label, issue); a null label everywhere hides the column.
  final List<(String?, RedmineIssue)> rows;
  final ValueChanged<RedmineIssue> onOpen;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble() + 1;
      painter.dispose();
      return width;
    }

    final headStyle = AppText.sectionLabel(dark: dark);
    final labelStyle = AppText.microLabel(dark: dark);
    final metaStyle = AppText.body(dark: dark).copyWith(fontSize: 13, height: 1.4);
    final empty = Text('—', style: labelStyle);
    const gap = 16.0, minTask = 260.0, avatar = 20.0;
    String? status(RedmineIssue i) => i.json['status'] == null ? null : i.statusName;
    String? version(RedmineIssue i) => i.nameOf('fixed_version');

    double col(String head, Iterable<double> widths, double max) =>
        [textWidth(head, headStyle), ...widths].reduce((a, b) => a > b ? a : b).clamp(0, max);
    final relationW = rows.every((r) => r.$1 == null)
        ? 0.0
        : col('RELAÇÃO', [for (final (l, _) in rows) textWidth(l ?? '', labelStyle)], 130);
    final assigneeW = col(
        'RESPONSÁVEL',
        [
          for (final (_, i) in rows)
            if (i.assigneeName case final n?) avatar + 8 + textWidth(n, metaStyle),
        ],
        200);
    final versionW = col(
        'VERSÃO',
        [
          for (final (_, i) in rows)
            if (version(i) case final v?) textWidth(v, metaStyle),
        ],
        160);
    // Tag: 7px padding each side + 12px dot + 4px gap around the badge text.
    final statusW = col(
        'SITUAÇÃO',
        [
          for (final (_, i) in rows)
            if (status(i) case final s?) 30 + textWidth(s, AppText.badge()),
        ],
        170);
    final fixedW =
        (relationW > 0 ? relationW + gap : 0) + 3 * gap + assigneeW + versionW + statusW + 26;

    Widget assignee(RedmineIssue i) => switch (i.assigneeName) {
          final name? => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(name: name, size: avatar),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
                ),
              ],
            ),
          null => empty,
        };
    Widget versionCell(RedmineIssue i) => switch (version(i)) {
          // Tooltips keep cut-off names readable (the avatar has its own).
          final v? => Tooltip(
              message: v,
              child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
            ),
          null => empty,
        };
    Widget statusCell(RedmineIssue i) => switch (status(i)) {
          final s? => Tooltip(
              message: s,
              child: Tag(s, tone: Tag.hashed(s).tone, icon: Icons.fiber_manual_record),
            ),
          null => empty,
        };
    Widget task(RedmineIssue i) {
      // "[Desenvolvimento] Título" under a Desenvolvimento badge: drop the
      // repeated prefix on screen only.
      final prefix = '[${i.trackerName}]';
      final trimmed = i.trackerName.isNotEmpty && i.subject.startsWith(prefix)
          ? i.subject.substring(prefix.length).trimLeft()
          : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              IssueNumber(i.id, style: labelStyle.copyWith(color: AppColors.accent(dark: dark))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trimmed.isEmpty ? i.subject : trimmed,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyMedium(dark: dark).copyWith(height: 1.4),
                ),
              ),
            ],
          ),
          if (i.trackerName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Tag.hashed(i.trackerName),
          ],
        ],
      );
    }

    final chevron = Icon(Icons.chevron_right, size: 18, color: AppColors.mutedText(dark: dark));
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth - fixedW - 30 >= minTask;
      Widget cells(List<(double?, Widget)> columns) => Row(
            children: [
              for (final (index, (width, child)) in columns.indexed) ...[
                if (index > 0) const SizedBox(width: gap),
                width == null ? Expanded(child: child) : SizedBox(width: width, child: child),
              ],
            ],
          );
      Widget labeled(String label, Widget child) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(width: 6),
              Flexible(child: child),
            ],
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Padding(
              // Card border (1) + padding (14), so headers sit over their cells.
              padding: const EdgeInsets.fromLTRB(15, 0, 15 + 26, Sp.s8),
              child: cells([
                if (relationW > 0) (relationW, Text('RELAÇÃO', style: headStyle)),
                (null, Text('TAREFA', style: headStyle)),
                (assigneeW, Text('RESPONSÁVEL', style: headStyle)),
                (versionW, Text('VERSÃO', style: headStyle)),
                (statusW, Text('SITUAÇÃO', style: headStyle)),
              ]),
            ),
          for (final (label, i) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s8),
              child: _LinkCard(
                onTap: () => onOpen(i),
                child: Row(
                  children: [
                    Expanded(
                      child: wide
                          ? cells([
                              if (relationW > 0)
                                (relationW, Text(label ?? '', maxLines: 2, style: labelStyle)),
                              (null, task(i)),
                              (assigneeW, assignee(i)),
                              (versionW, versionCell(i)),
                              (
                                statusW,
                                Align(alignment: Alignment.centerLeft, child: statusCell(i))
                              ),
                            ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (label != null) ...[
                                  Text(label, style: labelStyle),
                                  const SizedBox(height: 4),
                                ],
                                task(i),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: gap,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    labeled('Resp.', assignee(i)),
                                    labeled('Versão', versionCell(i)),
                                    labeled('Situação', statusCell(i)),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    chevron,
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Card of [LinkedIssueList]: subtle border, stronger on
/// hover, accent ring on keyboard focus; Enter/Space open it like a tap.
class _LinkCard extends StatefulWidget {
  const _LinkCard({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  var _hover = false;
  var _focus = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadius.standard);
    return Material(
      color: AppColors.field(dark: dark),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: _focus
            ? BorderSide(
                color: AppColors.accent(dark: dark),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : BorderSide(
                color: _hover ? AppColors.borderStrong(dark: dark) : AppColors.border(dark: dark),
              ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _hover = v),
        onFocusChange: (v) => setState(() => _focus = v),
        hoverColor: AppColors.cellHover(dark: dark),
        focusColor: Colors.transparent,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: widget.child,
        ),
      ),
    );
  }
}
