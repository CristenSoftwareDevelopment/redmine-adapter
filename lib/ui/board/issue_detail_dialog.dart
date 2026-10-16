import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/claude_action.dart';
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
import 'handoff_dialog.dart';
import 'tramite_dialog.dart';

Future<void> showIssueDetail(BuildContext context, RedmineIssue issue) =>
    showAppDialog<void>(context, (_) => IssueDetailDialog(issue: issue));

/// Issue details: opens with the list data and loads history/attachments.
class IssueDetailDialog extends StatefulWidget {
  const IssueDetailDialog({super.key, required this.issue});

  final RedmineIssue issue;

  @override
  State<IssueDetailDialog> createState() => _IssueDetailDialogState();
}

enum _Tab { description, history, time, attachments, children, relations }

class _IssueDetailDialogState extends State<IssueDetailDialog> {
  RedmineIssue? _full;
  String? _error;

  /// Long descriptions used to push the history out of sight: one tab each.
  _Tab _tab = _Tab.description;

  /// Time logged on this issue (only what the user's role may see).
  List<TimeEntry>? _time;
  String? _timeError;

  /// Parent and related issues by id (relations only carry ids).
  Map<int, RedmineIssue>? _linked;
  String? _linkedError;

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
        '/issues/${widget.issue.id}.json?include=journals,attachments,children,relations',
      );
      if (!mounted) return;
      setState(() => _full = RedmineIssue(data['issue'] as Map<String, dynamic>));
      _fetchLinked(_full!);
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// Parent + related issues, read in one call for subject, tracker and status.
  Future<void> _fetchLinked(RedmineIssue issue) async {
    final ids = {issue.refId('parent'), for (final (_, id) in _relations(issue)) id}.nonNulls;
    if (ids.isEmpty) return setState(() => _linked = const {});
    try {
      final list = await RedmineApiService().getAllPages(
        context.read<AppState>().settings,
        '/issues.json?issue_id=${ids.join(',')}&status_id=*',
        'issues',
      );
      if (!mounted) return;
      setState(() => _linked = {for (final j in list) j['id'] as int: RedmineIssue(j)});
    } catch (error) {
      if (mounted) setState(() => _linkedError = '$error'.replaceFirst('Exception: ', ''));
    }
  }

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
    final rules = _rules(issue);
    final claude = context.watch<AppState>().settings.claudeActions;

    return AppDialog(
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      title: Row(
        children: [const Text('Tarefa '), IssueNumber(issue.id)],
      ),
      headActions: [
        // One button per automation, each with its own icon.
        for (final a in claude)
          OutlinedButton.icon(
            onPressed: () => _openClaude(a, issue),
            icon: Icon(actionIcon(a.icon, Icons.terminal), size: 16),
            label: Text(a.name),
          ),
        for (final r in rules)
          OutlinedButton.icon(
            // Needs the journals and relations of the full issue. For a send to
            // another issue, the clicked rule comes first so the dialog opens on it.
            onPressed: _full == null
                ? null
                : r.sameIssue
                    ? () => showTramiteDialog(context, _full!, r)
                    : () => showHandoffDialog(context, _full!, [
                          r,
                          ...rules.where((o) => o != r && !o.sameIssue),
                        ]),
            icon: Icon(actionIcon(r.icon, Icons.send_outlined), size: 16),
            label: Text(r.name),
          ),
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
            // Selection per column (header, tab content, attributes): Flutter selects
            // by geometry, so one area over side-by-side columns mixed them up.
            child: PageSelectionArea(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
            )),
          ),
          Container(height: 1, color: border),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabs = Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
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
                      tabs,
                      Expanded(
                        child: SelectionArea(
                          child: SingleChildScrollView(
                            key: ValueKey(_tab),
                            padding: const EdgeInsets.all(22),
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
                          tabs,
                          // Each tab scrolls on its own and starts at the top.
                          Expanded(
                            child: SelectionArea(
                              child: SingleChildScrollView(
                                key: ValueKey(_tab),
                                padding: const EdgeInsets.all(22),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, color: border),
                    SizedBox(
                      width: 280,
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

  /// Opens a terminal with Claude Code in the action's folder and the prompt
  /// typed (nothing runs until Enter).
  Future<void> _openClaude(ClaudeAction action, RedmineIssue issue) async {
    final messenger = ScaffoldMessenger.of(context);
    final prompt = renderClaudePrompt(action.template, issueId: issue.id, subject: issue.subject);
    Future<bool> open(Uri link) async {
      try {
        return await launchUrl(link);
      } catch (_) {
        return false;
      }
    }

    var ok = false;
    if (action.openInApp) {
      // Experimental: the app gets the prompt as plain text and the folder is
      // picked there; the clipboard keeps the text in case the box comes empty.
      await Clipboard.setData(ClipboardData(text: prompt));
      ok = await open(claudeDesktopLink(prompt));
      final where = action.cwd.isEmpty ? 'a pasta do projeto' : 'a pasta ${action.cwd}';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Abrindo no Claude Desktop: escolha $where e envie (texto copiado).'
                : action.cwd.isEmpty
                    ? 'Não foi possível abrir o Claude Desktop (texto copiado).'
                    : 'Não foi possível abrir o Claude Desktop; abrindo no terminal.',
          ),
        ),
      );
    }
    if (!ok && (!action.openInApp || action.cwd.isNotEmpty)) {
      ok = await open(claudeDeepLink(action.cwd, prompt));
    }
    if (!ok && action.openInApp && action.cwd.isEmpty) return; // already told
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir o Claude Code. Rode `claude` no terminal e envie um prompt '
            'uma vez para registrar o link.',
          ),
        ),
      );
      return;
    }
    // e.g. "Em andamento" when the review starts.
    final statusId = action.statusId;
    if (statusId == null || issue.refId('status') == statusId || !mounted) return;
    String message;
    try {
      final applied = await RedmineApiService().setIssueStatus(
        context.read<AppState>().settings,
        issue.id,
        statusId,
      );
      message = applied
          ? 'Situação de #${issue.id} atualizada.'
          : 'O Redmine não aplicou a situação de #${issue.id}: '
              'transição não permitida pelo workflow ou sem permissão.';
      if (applied) _fetch();
    } catch (error) {
      message = 'Falha ao mudar a situação de #${issue.id}: '
          '${'$error'.replaceFirst('Exception: ', '')}';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// "Enviar trâmite" rules configured for this issue's tracker.
  List<HandoffRule> _rules(RedmineIssue issue) => [
        for (final r in context.watch<AppState>().settings.handoffRules)
          if (r.appliesTo(issue.refId('tracker'))) r,
      ];

  List<Map> _list(RedmineIssue issue, String key) =>
      (issue.json[key] as List? ?? const []).cast<Map>();

  Widget _tabBar(RedmineIssue issue) {
    final journals = _list(issue, 'journals');
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    final links = _relations(issue).length + (issue.refId('parent') == null ? 0 : 1);
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
        if (links > 0) (_Tab.relations, 'Relações ($links)', Icons.link),
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
        '${a['filename']}': a,
    };
    final body = AppText.body(dark: dark).copyWith(height: 1.5);
    final heading = AppText.bodySemibold(dark: dark).copyWith(fontWeight: FontWeight.w700);
    final well = AppColors.well(dark: dark);
    return LineBreakSelection(
      child: MarkdownBody(
        data: text,
        // Selection comes from the dialog's SelectionArea.
        selectable: false,
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
          // Transparent, not just unset: the package merges this into its default
          // code style, whose per-glyph background (the card color) paints over the
          // selection highlight. Code blocks keep their box (codeblockDecoration).
          code: AppText.mono(dark: dark).copyWith(backgroundColor: Colors.transparent),
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
        // Inline: attachments need the API key, so they're downloaded by the
        // app; the old link stays as the fallback when that fails.
        imageBuilder: (uri, title, alt) {
          final name = uri.pathSegments.isEmpty ? '$uri' : uri.pathSegments.last;
          final attachment = attachments[name] ?? {'filename': name, 'content_url': '$uri'};
          final url = '${attachment['content_url']}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AuthImage(
              url: url,
              maxHeight: 320,
              // Opens among the issue's attachments, so the arrows reach the others.
              onTap: () => attachments.containsKey(name)
                  ? showAttachmentPreview(
                      context,
                      attachments.values.toList(),
                      index: attachments.keys.toList().indexOf(name),
                    )
                  : showAttachmentPreview(context, [attachment]),
              fallback: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.accent(dark: dark)),
                onPressed: () => openRedmineLink(context, url),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(alt?.isNotEmpty == true ? alt! : name),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tabContent(RedmineIssue issue, bool dark) {
    final attachments = _list(issue, 'attachments');
    final children = _list(issue, 'children');
    // Newest first, keeping the 1-based position Redmine uses in `#note-N`.
    final journals = _list(issue, 'journals').indexed.toList().reversed;

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
          children: [for (final (i, j) in journals) _journal(j, i + 1, issue, dark)],
        );
      case _Tab.time:
        return _timeContent(dark);
      case _Tab.attachments:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < attachments.length; i++) _attachmentRow(attachments, i, dark),
          ],
        );
      case _Tab.children:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final c in children) _childRow(RedmineIssue(c.cast()), dark)],
        );
      case _Tab.relations:
        if (_linkedError != null) {
          return Text(
            'Não foi possível carregar as relações: $_linkedError',
            style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          );
        }
        final linked = _linked;
        if (linked == null) return const LinearProgressIndicator(minHeight: 2);
        // Issues the user can't see come back missing: shown by number only.
        RedmineIssue of(int id) => linked[id] ?? RedmineIssue({'id': id});
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (issue.refId('parent') case final parent?)
              _childRow(of(parent), dark, label: 'Tarefa pai'),
            for (final (label, id) in _relations(issue)) _childRow(of(id), dark, label: label),
          ],
        );
    }
  }

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
                      Text(
                        [
                          fmtFileSize(a['filesize'] as num?),
                          if ((a['author'] as Map?)?['name'] case final author?) '$author',
                          fmtDateTime(DateTime.tryParse('${a['created_on']}')),
                        ].where((t) => t.isNotEmpty).join(' · '),
                        style: AppText.microLabel(dark: dark),
                      ),
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

  /// Subtask/related issue row; opens it in its own modal on top of this one.
  /// [label] names the link (e.g. "Bloqueia"); the status shows when known.
  Widget _childRow(RedmineIssue child, bool dark, {String? label}) {
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
                if (label != null) ...[
                  SizedBox(width: 110, child: Text(label, style: AppText.microLabel(dark: dark))),
                  const SizedBox(width: 6),
                ],
                if (child.trackerName.isNotEmpty) ...[
                  Tag.hashed(child.trackerName),
                  const SizedBox(width: 10),
                ],
                IssueNumber(
                  child.id,
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
                if (child.json['status'] != null) ...[
                  const SizedBox(width: 10),
                  Tag(child.statusName),
                ],
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

  Widget _journal(Map journal, int index, RedmineIssue issue, bool dark) {
    // Only sends to another issue cite a note.
    final rules = [
      for (final r in _rules(issue))
        if (!r.sameIssue) r
    ];
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
                        text: '  ${fmtDateTime(DateTime.tryParse('${journal['created_on']}'))}'
                            '  ·  #note-$index',
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
          if (notes.isNotEmpty && rules.isNotEmpty)
            IconBtn(
              icon: Icons.send_outlined,
              tooltip: 'Enviar este trâmite',
              compact: true,
              onPressed: () => showHandoffDialog(context, issue, rules, noteIndex: index),
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
