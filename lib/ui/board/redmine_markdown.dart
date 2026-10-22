import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../services/theme_service.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'attachment_preview.dart';
import 'note_editor.dart';

/// Redmine text (Markdown/CommonMark) as Redmine shows it. Inline images are
/// the issue's [attachments] (downloaded with the API key; the link is the
/// fallback) or [pending] files not uploaded yet (a pasted print in a preview).
class RedmineMarkdown extends StatelessWidget {
  const RedmineMarkdown(
    this.text, {
    super.key,
    this.attachments = const [],
    this.pending = const [],
  });

  final String text;
  final List<Map> attachments;
  final List<PendingFile> pending;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final byName = {for (final a in attachments) '${a['filename']}': a};
    final local = {for (final f in pending) f.name: f.bytes};
    final body = AppText.body(dark: dark).copyWith(height: 1.5);
    final heading = AppText.bodySemibold(dark: dark).copyWith(fontWeight: FontWeight.w700);
    return LineBreakSelection(
      child: MarkdownBody(
        data: text,
        // Selection comes from the surrounding SelectionArea.
        selectable: false,
        // Blocks (code, quotes) take the full width, like in Redmine.
        fitContent: false,
        // Redmine's CommonMark uses hard breaks: every newline is a line break.
        softLineBreak: true,
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
            color: AppColors.well(dark: dark),
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
          if (local[name] case final bytes?) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(bytes, alignment: Alignment.centerLeft),
              ),
            );
          }
          final attachment = byName[name] ?? {'filename': name, 'content_url': '$uri'};
          final url = '${attachment['content_url']}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AuthImage(
              url: url,
              maxHeight: 320,
              // Opens among the issue's attachments, so the arrows reach the others.
              onTap: () => byName.containsKey(name)
                  ? showAttachmentPreview(
                      context,
                      byName.values.toList(),
                      index: byName.keys.toList().indexOf(name),
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
}
