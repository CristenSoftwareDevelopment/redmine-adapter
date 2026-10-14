import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../models/redmine_issue.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';

Future<void> showIssueDetail(BuildContext context, RedmineIssue issue) =>
    showAppDialog<void>(context, (_) => IssueDetailDialog(issue: issue));

/// Issue details: opens with the list data and loads history/attachments.
class IssueDetailDialog extends StatefulWidget {
  const IssueDetailDialog({super.key, required this.issue});

  final RedmineIssue issue;

  @override
  State<IssueDetailDialog> createState() => _IssueDetailDialogState();
}

enum _Tab { description, history, time, attachments, children }

class _IssueDetailDialogState extends State<IssueDetailDialog> {
  RedmineIssue? _full;
  String? _error;

  /// Long descriptions used to push the history out of sight: one tab each.
  _Tab _tab = _Tab.description;

  /// Time logged on this issue (only what the user's role may see).
  List<TimeEntry>? _time;
  String? _timeError;

  static const _fieldLabels = {
    'status_id': 'Status',
    'assigned_to_id': 'Responsável',
    'priority_id': 'Prioridade',
    'tracker_id': 'Tipo',
    'subject': 'Título',
    'description': 'Descrição',
    'done_ratio': '% concluído',
    'fixed_version_id': 'Versão',
    'estimated_hours': 'Estimativa',
    'start_date': 'Início',
    'due_date': 'Prazo',
    'category_id': 'Categoria',
    'parent_id': 'Tarefa pai',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchTime();
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
      final data = await RedmineApiService().getJson(
        context.read<AppState>().settings,
        '/issues/${widget.issue.id}.json?include=journals,attachments,children',
      );
      if (mounted) setState(() => _full = RedmineIssue(data['issue'] as Map<String, dynamic>));
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final issue = _full ?? widget.issue;
    final border = AppColors.border(dark: dark);
    final screen = MediaQuery.sizeOf(context);

    return AppDialog(
      width: screen.width * 0.85,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      title: Text('Tarefa #${issue.id}'),
      headActions: [
        FilledButton.icon(
          onPressed: () => openRedmineLink(context, '/issues/${issue.id}'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Abrir no Redmine'),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  issue.subject,
                  style: AppText.cardTitle(dark: dark).copyWith(height: 1.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (issue.trackerName.isNotEmpty) Tag.hashed(issue.trackerName),
                    Tag(issue.statusName),
                    Tag(issue.priorityName),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: border),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabs = Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                  child: Align(alignment: Alignment.centerLeft, child: _tabBar(issue)),
                );
                final content = _tabContent(issue, dark);
                final side = _attributes(issue, dark);
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      tabs,
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey(_tab),
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [content, const SizedBox(height: Sp.s24), side],
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
                          tabs,
                          // Each tab scrolls on its own and starts at the top.
                          Expanded(
                            child: SingleChildScrollView(
                              key: ValueKey(_tab),
                              padding: const EdgeInsets.all(22),
                              child: content,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: border),
                    SizedBox(
                      width: 280,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: side,
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

  List<Map> _list(RedmineIssue issue, String key) =>
      (issue.json[key] as List? ?? const []).cast<Map>();

  Widget _tabBar(RedmineIssue issue) {
    final journals = _list(issue, 'journals');
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    return AppTabs<_Tab>(
      tabs: [
        (_Tab.description, 'Descrição', Icons.description_outlined),
        (
          _Tab.history,
          _full == null ? 'Histórico' : 'Histórico (${journals.length})',
          Icons.history,
        ),
        (
          _Tab.time,
          _time == null
              ? 'Tempo gasto'
              : 'Tempo gasto (${fmtHours(_time!.fold(0.0, (sum, e) => sum + e.hours))} h)',
          Icons.schedule,
        ),
        if (attachments.isNotEmpty)
          (_Tab.attachments, 'Anexos (${attachments.length})', Icons.attach_file),
        if (children.isNotEmpty)
          (_Tab.children, 'Subtarefas (${children.length})', Icons.account_tree_outlined),
      ],
      selected: _tab,
      onChanged: (t) => setState(() => _tab = t),
    );
  }

  /// Redmine text (Markdown/CommonMark). Inline images need authentication,
  /// so they become links to the attachment, opened in the browser.
  Widget _markdown(String text, RedmineIssue issue, bool dark) {
    final attachments = {
      for (final a in (issue.json['attachments'] as List? ?? const []).cast<Map>())
        '${a['filename']}': '${a['content_url']}',
    };
    final body = AppText.body(dark: dark).copyWith(height: 1.5);
    final heading = AppText.bodySemibold(dark: dark).copyWith(fontWeight: FontWeight.w700);
    final well = AppColors.well(dark: dark);
    return MarkdownBody(
      data: text,
      selectable: true,
      // Blocks (code, quotes) take the full width, like in Redmine.
      fitContent: false,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        listBullet: body,
        tableBody: body,
        blockSpacing: 10,
        h1: heading.copyWith(fontSize: 20, height: 1.4),
        h2: heading.copyWith(fontSize: 17, height: 1.4),
        h3: heading.copyWith(fontSize: 15.5, height: 1.4),
        h4: heading,
        h1Padding: const EdgeInsets.only(top: 12),
        h2Padding: const EdgeInsets.only(top: 10),
        h3Padding: const EdgeInsets.only(top: 8),
        a: body.copyWith(color: AppColors.accent(dark: dark)),
        code: AppText.mono(dark: dark).copyWith(backgroundColor: well),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: well,
          border: Border.all(color: AppColors.border(dark: dark)),
          borderRadius: BorderRadius.circular(AppRadius.standard),
        ),
        checkbox: body.copyWith(color: AppColors.mutedText(dark: dark)),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border(dark: dark), width: 3)),
        ),
      ),
      onTapLink: (_, href, __) {
        if (href != null) openRedmineLink(context, href);
      },
      imageBuilder: (uri, title, alt) {
        final name = uri.pathSegments.isEmpty ? '$uri' : uri.pathSegments.last;
        return TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.accent(dark: dark)),
          onPressed: () => openRedmineLink(context, attachments[name] ?? '$uri'),
          icon: const Icon(Icons.image_outlined, size: 16),
          label: Text(alt?.isNotEmpty == true ? alt! : name),
        );
      },
    );
  }

  Widget _tabContent(RedmineIssue issue, bool dark) {
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    final journals = _list(issue, 'journals').reversed;

    switch (_tab) {
      case _Tab.description:
        return issue.description.trim().isEmpty
            ? Text('Sem descrição.', style: AppText.captionLight(dark: dark))
            : _markdown(issue.description, issue, dark);
      case _Tab.history:
        if (_full == null && _error == null) return const LinearProgressIndicator(minHeight: 2);
        if (_error != null) {
          return Text(
            'Não foi possível carregar o histórico: $_error',
            style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          );
        }
        if (journals.isEmpty) {
          return Text('Sem histórico.', style: AppText.captionLight(dark: dark));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final j in journals) _journal(j, dark)],
        );
      case _Tab.time:
        return _timeContent(dark);
      case _Tab.attachments:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in attachments)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent(dark: dark),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => openRedmineLink(context, a['content_url'] as String? ?? ''),
                icon: const Icon(Icons.attach_file, size: 16),
                label: Text('${a['filename']}'),
              ),
          ],
        );
      case _Tab.children:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final c in children) _childRow(RedmineIssue(c.cast()), dark)],
        );
    }
  }

  /// Subtask row; opens the subtask in its own modal on top of this one.
  Widget _childRow(RedmineIssue child, bool dark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s8),
      child: Material(
        color: AppColors.field(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          side: BorderSide(color: AppColors.border(dark: dark)),
        ),
        child: InkWell(
          onTap: () => showIssueDetail(context, child),
          hoverColor: AppColors.cellHover(dark: dark),
          borderRadius: BorderRadius.circular(AppRadius.standard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (child.trackerName.isNotEmpty) ...[
                  Tag.hashed(child.trackerName),
                  const SizedBox(width: 10),
                ],
                Text(
                  '#${child.id}',
                  style: AppText.microLabel(dark: dark).copyWith(
                    color: AppColors.accent(dark: dark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    child.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(dark: dark),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.mutedText(dark: dark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Totals per person, then each entry (newest first).
  Widget _timeContent(bool dark) {
    final entries = _time;
    if (_timeError != null) {
      return Text(
        'Não foi possível carregar o tempo gasto: $_timeError',
        style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
      );
    }
    if (entries == null) return const LinearProgressIndicator(minHeight: 2);
    if (entries.isEmpty) {
      return Text(
        'Nenhum tempo lançado que você possa ver nesta tarefa.',
        style: AppText.captionLight(dark: dark),
      );
    }
    final total = entries.fold<double>(0, (sum, e) => sum + e.hours);
    final byPerson = sumHours(entries, (e) => e.userName).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(
              'Total ${fmtHours(total)} h · ${entries.length} lançamento${entries.length == 1 ? '' : 's'}',
              tone: TagTone.green,
            ),
            for (final p in byPerson) Tag('${p.key} · ${fmtHours(p.value)} h'),
          ],
        ),
        const SizedBox(height: Sp.s16),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(name: e.userName, size: 26),
                const SizedBox(width: Sp.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: e.userName, style: AppText.bodySemibold(dark: dark)),
                            TextSpan(
                              text: [
                                '  ${fmtDate(_ymd(e.day))}',
                                e.activity,
                                if (e.issueId != null && e.issueId != widget.issue.id)
                                  'subtarefa #${e.issueId}',
                              ].join(' · '),
                              style: AppText.microLabel(dark: dark),
                            ),
                          ],
                        ),
                      ),
                      if (e.comments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Sp.s4),
                          child: Text(e.comments, style: AppText.body(dark: dark)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.s12),
                Text('${fmtHours(e.hours)} h', style: AppText.bodySemibold(dark: dark)),
              ],
            ),
          ),
      ],
    );
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _journal(Map journal, bool dark) {
    final author = (journal['user'] as Map?)?['name'] as String? ?? '?';
    final notes = (journal['notes'] as String? ?? '').trim();
    final details = (journal['details'] as List? ?? const [])
        .map((d) => _fieldLabels[(d as Map)['name']] ?? d['name'])
        .toSet()
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: author, size: 26),
          const SizedBox(width: Sp.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: author, style: AppText.bodySemibold(dark: dark)),
                      TextSpan(
                        text: '  ${fmtDateTime(DateTime.tryParse('${journal['created_on']}'))}',
                        style: AppText.microLabel(dark: dark),
                      ),
                    ],
                  ),
                ),
                if (details.isNotEmpty)
                  Text('Alterou: $details', style: AppText.microLabel(dark: dark)),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: Sp.s4),
                  _markdown(notes, _full ?? widget.issue, dark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attributes(RedmineIssue issue, bool dark) {
    final j = issue.json;
    String hours(Object? v) => v == null ? '-' : '${(v as num).toStringAsFixed(1)} h';
    String fieldValue(Map f) =>
        f['value'] is List ? (f['value'] as List).join(', ') : '${f['value'] ?? ''}';
    final customFields = [
      for (final f in (j['custom_fields'] as List? ?? const []).cast<Map>())
        if (fieldValue(f).isNotEmpty) ('${f['name']}', fieldValue(f)),
    ];
    final rows = <(String, String)>[
      ('Status', issue.statusName),
      ('Prioridade', issue.priorityName),
      ('Responsável', issue.assigneeName ?? 'Ninguém'),
      ('Autor', issue.nameOf('author') ?? '-'),
      ('Projeto', issue.projectName),
      if (issue.nameOf('fixed_version') != null) ('Versão', issue.nameOf('fixed_version')!),
      if (issue.nameOf('category') != null) ('Categoria', issue.nameOf('category')!),
      ('Início', fmtDate(j['start_date'] as String?)),
      ('Prazo', fmtDate(j['due_date'] as String?)),
      ('Estimativa', hours(j['estimated_hours'])),
      ('Tempo gasto', hours(j['total_spent_hours'] ?? j['spent_hours'])),
      ('Criada', fmtDateTime(DateTime.tryParse('${j['created_on']}'))),
      ('Atualizada', fmtDateTime(issue.updatedOn)),
      ...customFields,
    ];
    final done = (j['done_ratio'] as num? ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.microLabel(dark: dark)),
                const SizedBox(height: 2),
                Text(value, style: AppText.bodyMedium(dark: dark)),
              ],
            ),
          ),
        Text('% concluído', style: AppText.microLabel(dark: dark)),
        const SizedBox(height: Sp.s4),
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
      ],
    );
  }
}
