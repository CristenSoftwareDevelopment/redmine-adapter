import 'dart:convert';

/// Placeholders of [ClaudeAction.template], shown in the action editor.
const claudePlaceholders = {
  '{{numeroAtividade}}': 'número da tarefa, ex. 484530',
  '{{titulo}}': 'título da tarefa',
};

/// Opens Claude Code in [cwd] with a prompt built from the issue, e.g.
/// `/pano-cr refs #{{numeroAtividade}}`, via the `claude-cli://` deep link.
class ClaudeAction {
  const ClaudeAction({
    required this.name,
    required this.cwd,
    required this.template,
    this.statusId,
    this.icon,
    this.openInApp = false,
  });

  final String name;

  /// Absolute path of the project folder.
  final String cwd;
  final String template;

  /// Status the issue moves to when the action opens (e.g. "Em andamento"); null = keep.
  final int? statusId;

  /// Key of the button icon (see `actionIcons`); null = default.
  final String? icon;

  /// Experimental: open the Claude Desktop new-session page with the prompt
  /// ([claudeDesktopLink]) instead of a terminal; [cwd] is the fallback.
  final bool openInApp;

  Map<String, Object?> toJson() => {
        'name': name,
        'cwd': cwd,
        'template': template,
        'statusId': statusId,
        'icon': icon,
        'openInApp': openInApp,
      };

  static ClaudeAction fromJson(Map<String, dynamic> json) => ClaudeAction(
        name: json['name'] as String? ?? 'Claude Code',
        cwd: json['cwd'] as String? ?? '',
        template: json['template'] as String? ?? '',
        statusId: json['statusId'] as int?,
        icon: json['icon'] as String?,
        openInApp: json['openInApp'] == true,
      );

  static String listToJson(List<ClaudeAction> actions) =>
      jsonEncode(actions.map((a) => a.toJson()).toList());

  static List<ClaudeAction> listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => ClaudeAction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

String renderClaudePrompt(String template, {required int issueId, required String subject}) =>
    template.replaceAll('{{numeroAtividade}}', '$issueId').replaceAll('{{titulo}}', subject);

/// `claude-cli://open?cwd=…&q=…` (https://code.claude.com/docs/en/deep-links):
/// a terminal with Claude Code in [cwd] and [prompt] typed, waiting for Enter.
/// Built by hand: `Uri(queryParameters:)` would turn spaces into `+`.
Uri claudeDeepLink(String cwd, String prompt) => Uri.parse(
      'claude-cli://open?cwd=${Uri.encodeComponent(cwd)}&q=${Uri.encodeComponent(prompt)}',
    );

/// Claude Desktop new-session page with [prompt] typed, not sent.
/// Experimental: the docs only describe `claude://code/new` with SSH
/// parameters; there is no local-folder parameter, and the prompt arrives as
/// plain text (a leading `/` doesn't run as a command).
Uri claudeDesktopLink(String prompt) =>
    Uri.parse('claude://code/new?q=${Uri.encodeComponent(prompt)}');
