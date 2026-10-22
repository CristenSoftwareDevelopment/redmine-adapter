import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../models/app_settings.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../components.dart';
import 'redmine_markdown.dart';

/// A file picked or pasted, uploaded with the next update of the issue.
typedef PendingFile = ({String name, Uint8List bytes});

/// Uploads [files] and returns the issue update's `uploads`. Call it inside the
/// send step: a retry uploads again, and Redmine drops uploads never attached.
Future<List<Map<String, String>>> uploadFiles(
  AppSettings settings,
  List<PendingFile> files,
) async =>
    [
      for (final f in files)
        {'token': await RedmineApiService().upload(settings, f.name, f.bytes), 'filename': f.name},
    ];

/// Comment/description box like Redmine's: "Editar" / "Pré-visualizar" tabs, a
/// formatting bar and attachments. "Anexar arquivos" picks files; pasting copied
/// files attaches them, and a pasted image (e.g. a screenshot) is attached and
/// placed inline as `![](name)`. The preview resolves images from the issue's
/// [attachments] and from [files] not uploaded yet. [files] is changed in
/// place; [onChanged] runs after any change.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.controller,
    required this.files,
    required this.onChanged,
    this.attachments = const [],
    this.hint,
    this.minLines = 4,
    this.maxLines = 12,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final List<PendingFile> files;
  final VoidCallback onChanged;
  final List<Map> attachments;
  final String? hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _focus = FocusNode();
  bool _preview = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Copied files, else the text, else an image. Text before image: apps like
  /// Excel copy cells as text plus a picture. False = nothing attached.
  Future<bool> _paste() async {
    try {
      if (!kIsWeb) {
        // Copied links also come as URLs here: only existing files count.
        final paths = [
          for (final p in await Pasteboard.files())
            if (FileSystemEntity.isFileSync(p)) p,
        ];
        if (paths.isNotEmpty) {
          for (final p in paths) {
            widget.files.add(
                (name: p.split(Platform.pathSeparator).last, bytes: await File(p).readAsBytes()));
          }
          widget.onChanged();
          return true;
        }
      }
      if (await Clipboard.hasStrings()) return false;
      final image = await Pasteboard.image;
      if (image == null || image.isEmpty) return false;
      final name = 'clipboard-${DateTime.now().millisecondsSinceEpoch}.${_imageExtension(image)}';
      widget.files.add((name: name, bytes: image));
      final v = widget.controller.value;
      final at = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
      widget.controller.value = v.replaced(at, '![]($name)');
      widget.onChanged();
      return true;
    } catch (_) {
      return false; // no clipboard plugin (tests) or unreadable: plain text paste
    }
  }

  Future<void> _pick() async {
    final picked = await openFiles();
    if (picked.isEmpty) return;
    for (final f in picked) {
      widget.files.add((name: f.name, bytes: await f.readAsBytes()));
    }
    widget.onChanged();
  }

  /// A formatting button: edits the text, then gives the focus back.
  void _format(TextEditingValue Function(TextEditingValue value) edit) {
    widget.controller.value = edit(widget.controller.value);
    _focus.requestFocus();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.mutedText(dark: dark);
    Widget tool(String tooltip, Widget child, TextEditingValue Function(TextEditingValue) edit) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: _preview ? null : () => _format(edit),
            borderRadius: BorderRadius.circular(AppRadius.subtle),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(
                      size: 17, color: _preview ? AppColors.border(dark: dark) : muted),
                  child: child,
                ),
              ),
            ),
          ),
        );
    Widget heading(int level) => tool(
          'Título $level',
          Text(
            'H$level',
            style: AppText.microLabel(dark: dark).copyWith(
              fontWeight: FontWeight.w700,
              color: _preview ? AppColors.border(dark: dark) : muted,
            ),
          ),
          (v) => prefixLines(v, '${'#' * level} '),
        );
    final gap = Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.border(dark: dark),
    );
    final text = widget.controller.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppTabs<bool>(
              tabs: const [
                (false, 'Editar', Icons.edit_outlined),
                (true, 'Pré-visualizar', Icons.visibility_outlined),
              ],
              selected: _preview,
              onChanged: (v) => setState(() => _preview = v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    tool('Negrito', const Icon(Icons.format_bold), (v) => wrapSelection(v, '**')),
                    tool('Itálico', const Icon(Icons.format_italic), (v) => wrapSelection(v, '*')),
                    tool('Riscado', const Icon(Icons.format_strikethrough),
                        (v) => wrapSelection(v, '~~')),
                    tool('Código', const Icon(Icons.code), (v) => wrapSelection(v, '`')),
                    gap,
                    heading(1),
                    heading(2),
                    heading(3),
                    gap,
                    tool('Lista', const Icon(Icons.format_list_bulleted),
                        (v) => prefixLines(v, '* ')),
                    tool('Lista numerada', const Icon(Icons.format_list_numbered),
                        (v) => prefixLines(v, '1. ')),
                    tool('Citação', const Icon(Icons.format_quote), (v) => prefixLines(v, '> ')),
                    tool('Bloco de código', const Icon(Icons.data_object), codeBlock),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_preview)
          Container(
            constraints: BoxConstraints(minHeight: widget.minLines * 22.0 + 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.field(dark: dark),
              border: Border.all(color: AppColors.border(dark: dark)),
              borderRadius: BorderRadius.circular(AppRadius.standard),
            ),
            child: text.trim().isEmpty
                ? Text('Nada para pré-visualizar.', style: AppText.captionLight(dark: dark))
                : RedmineMarkdown(text, attachments: widget.attachments, pending: widget.files),
          )
        else
          Actions(
            actions: {PasteTextIntent: _PasteAttachments(_paste)},
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              decoration: InputDecoration(hintText: widget.hint),
              onChanged: (_) => widget.onChanged(),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: 'Também dá para colar arquivos e prints (Ctrl/Cmd+V)',
              child: TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('Anexar arquivos'),
              ),
            ),
            for (final f in widget.files)
              InputChip(
                label: Text(f.name),
                visualDensity: VisualDensity.compact,
                onDeleted: () {
                  widget.files.remove(f);
                  widget.onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Selection (or cursor) as a valid range: an unset selection means the end.
TextSelection _range(TextEditingValue v) =>
    v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);

/// Wraps the selection in [before] and [after] (default: [before] again), e.g.
/// `**bold**`, keeping it selected. Without a selection the markers go in with
/// the cursor between them.
TextEditingValue wrapSelection(TextEditingValue v, String before, [String? after]) {
  final sel = _range(v);
  final inside = sel.textInside(v.text);
  final start = sel.start + before.length;
  return TextEditingValue(
    text: '${sel.textBefore(v.text)}$before$inside${after ?? before}${sel.textAfter(v.text)}',
    selection: TextSelection(baseOffset: start, extentOffset: start + inside.length),
  );
}

/// Puts [prefix] (`# `, `* `, `> `…) at the start of each selected line, or of
/// the cursor's line.
TextEditingValue prefixLines(TextEditingValue v, String prefix) {
  final sel = _range(v);
  final text = v.text;
  final from = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
  final end = text.indexOf('\n', sel.end);
  final to = end == -1 ? text.length : end;
  final block = text.substring(from, to).split('\n').map((l) => '$prefix$l').join('\n');
  return TextEditingValue(
    text: text.replaceRange(from, to, block),
    selection: sel.isCollapsed
        ? TextSelection.collapsed(offset: sel.start + prefix.length)
        : TextSelection(baseOffset: from, extentOffset: from + block.length),
  );
}

/// Fenced code block around the selection, starting on its own line.
TextEditingValue codeBlock(TextEditingValue v) {
  final start = _range(v).start;
  final atLineStart = start == 0 || v.text[start - 1] == '\n';
  return wrapSelection(v, '${atLineStart ? '' : '\n'}```\n', '\n```');
}

String _imageExtension(Uint8List b) => switch (b) {
      [0xFF, 0xD8, ...] => 'jpg',
      [0x42, 0x4D, ...] => 'bmp',
      _ => 'png',
    };

/// Overrides the text field's paste: tries attachments first and falls back to
/// the field's own paste when there's nothing to attach.
class _PasteAttachments extends Action<PasteTextIntent> {
  _PasteAttachments(this.attach);

  final Future<bool> Function() attach;

  @override
  Object? invoke(PasteTextIntent intent) {
    final fallback = callingAction; // only set during this call
    attach().then((attached) {
      if (!attached) fallback?.invoke(intent);
    });
    return null;
  }
}
