import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../models/redmine_issue.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../ui_utils.dart';

Future<void> showIssueDetail(BuildContext context, RedmineIssue issue) =>
    showDialog<void>(context: context, builder: (_) => IssueDetailDialog(issue: issue));

/// Issue details: opens with the list data and loads history/attachments.
class IssueDetailDialog extends StatefulWidget {
  const IssueDetailDialog({super.key, required this.issue});

  final RedmineIssue issue;

  @override
  State<IssueDetailDialog> createState() => _IssueDetailDialogState();
}

class _IssueDetailDialogState extends State<IssueDetailDialog> {
  RedmineIssue? _full;
  String? _error;

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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Sp.s24),
      child: Container(
        width: screen.width * 0.85,
        constraints: BoxConstraints(maxHeight: screen.height * 0.88),
        decoration: surfaceCard(dark: dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  if (issue.trackerName.isNotEmpty) ...[
                    LabelPill(issue.trackerName),
                    const SizedBox(width: Sp.s8),
                  ],
                  Text('#${issue.id}', style: AppText.caption(dark: dark)),
                  const SizedBox(width: Sp.s8),
                  LabelPill(issue.statusName, color: AppColors.warmGray500),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => openRedmineLink(context, '/issues/${issue.id}'),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Abrir no Redmine'),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: SelectableText(issue.subject, style: AppText.cardTitle(dark: dark)),
            ),
            Container(height: 1, color: border),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final main = _mainContent(issue, dark);
                  final side = _attributes(issue, dark);
                  if (constraints.maxWidth < 700) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [main, const SizedBox(height: Sp.s24), side],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: main,
                        ),
                      ),
                      Container(width: 1, color: border),
                      SizedBox(
                        width: 260,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
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
      ),
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
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: body,
        listBullet: body,
        tableBody: body,
        h1: AppText.cardTitle(dark: dark),
        h2: AppText.bodyLarge(dark: dark).copyWith(fontWeight: FontWeight.w600),
        h3: AppText.bodySemibold(dark: dark),
        h4: AppText.bodySemibold(dark: dark),
        a: body.copyWith(color: AppColors.notionBlue),
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: AppColors.border(dark: dark),
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.border(dark: dark),
          borderRadius: BorderRadius.circular(AppRadius.micro),
        ),
        checkbox: body.copyWith(color: AppColors.mutedText(dark: dark)),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
        ),
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
          style: TextButton.styleFrom(foregroundColor: AppColors.notionBlue),
          onPressed: () => openRedmineLink(context, attachments[name] ?? '$uri'),
          icon: const Icon(Icons.image_outlined, size: 16),
          label: Text(alt?.isNotEmpty == true ? alt! : name),
        );
      },
    );
  }

  Widget _section(String title, bool dark) => Padding(
        padding: const EdgeInsets.only(top: Sp.s16, bottom: Sp.s8),
        child: Text(
          title.toUpperCase(),
          style: AppText.microLabel(dark: dark).copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _mainContent(RedmineIssue issue, bool dark) {
    final attachments = (issue.json['attachments'] as List? ?? const []).cast<Map>();
    final children = (issue.json['children'] as List? ?? const []).cast<Map>();
    final journals = (issue.json['journals'] as List? ?? const []).cast<Map>().reversed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DESCRIÇÃO',
          style: AppText.microLabel(dark: dark).copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: Sp.s8),
        if (issue.description.trim().isEmpty)
          Text('Sem descrição.', style: AppText.captionLight(dark: dark))
        else
          _markdown(issue.description, issue, dark),
        if (attachments.isNotEmpty) ...[
          _section('Anexos', dark),
          for (final a in attachments)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.notionBlue,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => openRedmineLink(context, a['content_url'] as String? ?? ''),
              icon: const Icon(Icons.attach_file, size: 16),
              label: Text('${a['filename']}'),
            ),
        ],
        if (children.isNotEmpty) ...[
          _section('Subtarefas', dark),
          for (final c in children)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.s4),
              child: Text('#${c['id']}  ${c['subject']}', style: AppText.body(dark: dark)),
            ),
        ],
        _section('Histórico', dark),
        if (_full == null && _error == null)
          const LinearProgressIndicator(minHeight: 2)
        else if (_error != null)
          Text(
            'Não foi possível carregar o histórico: $_error',
            style: AppText.caption(dark: dark).copyWith(color: AppColors.orange),
          )
        else if (journals.isEmpty)
          Text('Sem histórico.', style: AppText.captionLight(dark: dark))
        else
          for (final j in journals) _journal(j, dark),
      ],
    );
  }

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
