import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_settings.dart';
import '../../models/claude_action.dart';
import '../../models/handoff_rule.dart';
import '../../models/redmine_issue.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../icon_picker.dart';
import '../ui_utils.dart';
import 'bulk_edit_dialog.dart';
import 'handoff_dialog.dart';
import 'issue_detail_dialog.dart';
import 'tramite_dialog.dart';

// Issue actions shared by the issue dialog and the ⋮ menu of board cards and
// list rows.

/// "Novo trâmite": the trâmite dialog with nothing preset.
/// Hours are optional here: the field starts empty (see the trâmite dialog).
const newTramiteRule =
    HandoffRule(name: 'Novo trâmite', sameIssue: true, template: '', logTime: true);

/// The issue with what the trâmite, handoff and version dialogs need.
Future<RedmineIssue> fetchFullIssue(AppSettings settings, int id) async {
  final data = await RedmineApiService().getJson(
    settings,
    '/issues/$id.json?include=journals,attachments,children,relations',
  );
  return RedmineIssue(data['issue'] as Map<String, dynamic>);
}

/// Claude actions and trâmite rules shown on [issue] by their tracker and
/// status filters, in button order ([AppSettings.orderedActions]).
List<Object> issueActions(AppSettings settings, RedmineIssue issue) {
  final tracker = issue.refId('tracker');
  return [
    for (final action in settings.orderedActions)
      if (switch (action) {
        ClaudeAction a => a.showsOn(tracker, issue.statusId),
        HandoffRule r => r.showsOn(tracker, issue.statusId),
        _ => false,
      })
        action,
  ];
}

/// Name of [id] among loaded `(id, name)` choices; `#id` when missing.
String optionName(List<(int, String)>? options, int id) =>
    options?.where((o) => o.$1 == id).firstOrNull?.$2 ?? '#$id';

/// [confirmChanges] lines for what [status], [assignee] and [version] (null =
/// kept) change on [issue]; [prefix] names it, e.g. "#12 ".
List<String> changeLines(
  RedmineIssue issue, {
  int? status,
  int? assignee,
  int? version,
  List<(int, String)>? statuses,
  List<(int, String)>? members,
  List<(int, String)>? versions,
  String prefix = '',
}) {
  String label(String l) => prefix.isEmpty ? l[0].toUpperCase() + l.substring(1) : '$prefix$l';
  return [
    if (status != null && status != issue.statusId)
      '${label('situação')}: ${issue.statusName} → ${optionName(statuses, status)}',
    if (assignee != null && assignee != issue.assigneeId)
      '${label('responsável')}: ${issue.assigneeName ?? 'ninguém'} → '
          '${optionName(members, assignee)}',
    if (version != null && version != issue.refId('fixed_version'))
      '${label('versão')}: ${issue.nameOf('fixed_version') ?? 'nenhuma'} → '
          '${optionName(versions, version)}',
  ];
}

/// Asks before an automation changes issues; [changes] are lines such as
/// "Situação: Nova → Em andamento". True = go ahead.
Future<bool> confirmChanges(BuildContext context, String title, List<String> changes) async =>
    await showAppDialog<bool>(context, (dialogContext) {
      final dark = Theme.of(dialogContext).brightness == Brightness.dark;
      return AppDialog(
        width: 460,
        title: Text(title),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Isto vai mudar:', style: AppText.captionLight(dark: dark)),
            const SizedBox(height: 10),
            for (final c in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('•  $c', style: AppText.body(dark: dark)),
              ),
          ],
        ),
        footer: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      );
    }) ??
    false;

/// Opens a terminal with Claude Code in the action's folder and the prompt
/// typed (nothing runs until Enter). When the action moves the issue to its
/// status, that is confirmed first (Cancelar opens nothing). True = the status
/// changed, so the caller refreshes.
Future<bool> runClaudeAction(BuildContext context, ClaudeAction action, RedmineIssue issue) async {
  final messenger = ScaffoldMessenger.of(context);
  final settings = context.read<AppState>().settings;
  final api = RedmineApiService();
  final statusId = action.statusId;
  final moves = statusId != null && statusId != issue.statusId;
  if (moves) {
    final statuses = await api
        .listNamed(settings, '/issue_statuses.json', 'issue_statuses')
        .catchError((Object _) => const <(int, String)>[]);
    if (!context.mounted) return false;
    final confirmed = await confirmChanges(context, '${action.name} · #${issue.id}', [
      'Situação: ${issue.statusName} → ${optionName(statuses, statusId)}',
    ]);
    if (!confirmed) return false;
  }

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
  if (!ok && action.openInApp && action.cwd.isEmpty) return false; // already told
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Não foi possível abrir o Claude Code. Rode `claude` no terminal e envie um prompt '
          'uma vez para registrar o link.',
        ),
      ),
    );
    return false;
  }
  // e.g. "Em andamento" when the review starts.
  if (!moves) return false;
  String message;
  var applied = false;
  try {
    applied = await api.setIssueStatus(settings, issue.id, statusId);
    message = applied
        ? 'Situação de #${issue.id} atualizada.'
        : 'O Redmine não aplicou a situação de #${issue.id}: '
            'transição não permitida pelo workflow ou sem permissão.';
  } catch (error) {
    message = 'Falha ao mudar a situação de #${issue.id}: '
        '${'$error'.replaceFirst('Exception: ', '')}';
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
  return applied;
}

/// ⋮ button of a board card or list row: the issue dialog's actions without
/// opening it. [statuses] + [onMove] add "Alterar situação" (the board's own
/// move); [onChanged] runs after anything changed (the board reloads).
class IssueActionsMenu extends StatefulWidget {
  const IssueActionsMenu({
    super.key,
    required this.issue,
    required this.onChanged,
    this.statuses = const [],
    this.onMove,
  });

  /// List data (no journals): dialogs that need more load the full issue.
  final RedmineIssue issue;
  final VoidCallback onChanged;
  final List<(int, String)> statuses;
  final ValueChanged<int>? onMove;

  @override
  State<IssueActionsMenu> createState() => _IssueActionsMenuState();
}

class _IssueActionsMenuState extends State<IssueActionsMenu> {
  /// Loading the full issue before a dialog opens.
  bool _busy = false;

  /// Opens a dialog that needs the full issue; true from it = something changed.
  Future<void> _withFull(Future<bool> Function(RedmineIssue full) open) async {
    final messenger = ScaffoldMessenger.of(context);
    final RedmineIssue full;
    setState(() => _busy = true);
    try {
      full = await fetchFullIssue(context.read<AppState>().settings, widget.issue.id);
    } catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text('Não foi possível carregar #${widget.issue.id}: '
            '${'$error'.replaceFirst('Exception: ', '')}'),
      ));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (await open(full)) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final issue = widget.issue;
    final settings = context.watch<AppState>().settings;
    final actions = issueActions(settings, issue);
    final rules = actions.whereType<HandoffRule>().toList();
    final onMove = widget.onMove;
    Widget item(IconData icon, String label, VoidCallback onPressed) => MenuItemButton(
          leadingIcon: Icon(icon, size: 17),
          onPressed: onPressed,
          child: Text(label),
        );

    return MenuAnchor(
      menuChildren: [
        item(
          Icons.open_in_full,
          'Abrir tarefa',
          () => showIssueDetail(context, issue, onChanged: widget.onChanged),
        ),
        item(
          Icons.edit_outlined,
          'Editar tarefa',
          () => showIssueDetail(context, issue, onChanged: widget.onChanged, edit: true),
        ),
        const Divider(height: 1),
        if (onMove != null && widget.statuses.isNotEmpty)
          SubmenuButton(
            leadingIcon: const Icon(Icons.swap_horiz, size: 17),
            menuChildren: [
              for (final (id, name) in widget.statuses)
                MenuItemButton(
                  leadingIcon: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.tone(Tag.hashed(name).tone, dark: dark).$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  trailingIcon: id == issue.statusId
                      ? Icon(Icons.check, size: 16, color: AppColors.accent(dark: dark))
                      : null,
                  onPressed: () {
                    if (id != issue.statusId) onMove(id);
                  },
                  child: Text(name),
                ),
            ],
            child: const Text('Alterar situação'),
          ),
        item(
          Icons.account_tree_outlined,
          'Alterar em massa',
          () => _withFull((full) => showBulkEditDialog(context, full)),
        ),
        item(
          Icons.add_comment_outlined,
          'Novo trâmite',
          () => _withFull((full) => showTramiteDialog(context, full, newTramiteRule)),
        ),
        if (actions.isNotEmpty) const Divider(height: 1),
        for (final action in actions)
          switch (action) {
            ClaudeAction a => item(actionIcon(a.icon, Icons.terminal), a.name, () async {
                if (await runClaudeAction(context, a, issue)) widget.onChanged();
              }),
            HandoffRule r => item(
                actionIcon(r.icon, Icons.send_outlined),
                r.name,
                () => _withFull(
                  (full) => r.sameIssue
                      ? showTramiteDialog(context, full, r)
                      : showHandoffDialog(context, full, [
                          r,
                          ...rules.where((o) => o != r && !o.sameIssue),
                        ]),
                ),
              ),
            _ => const SizedBox.shrink(),
          },
        const Divider(height: 1),
        item(
          Icons.open_in_new,
          'Abrir no Redmine',
          () => openRedmineLink(context, '/issues/${issue.id}'),
        ),
      ],
      builder: (context, controller, _) {
        const size = Size(28, 30);
        if (_busy) {
          return const SizedBox(
            width: 28,
            height: 30,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return IconButton(
          tooltip: 'Ações',
          isSelected: controller.isOpen,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.more_vert, size: 20),
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(size),
            minimumSize: const WidgetStatePropertyAll(size),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.selected)
                  ? AppColors.text(dark: dark)
                  : AppColors.mutedText(dark: dark),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.selected)
                  ? AppColors.fieldHover(dark: dark)
                  : Colors.transparent,
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        );
      },
    );
  }
}
