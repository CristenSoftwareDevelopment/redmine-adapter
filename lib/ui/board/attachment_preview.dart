import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';

enum AttachmentKind { image, text, markdown, pdf, video, none }

const _textExtensions = {
  'txt', 'log', 'json', 'xml', 'yaml', 'yml', 'sql', 'csv', 'tsv', 'ini', 'conf', 'env', //
  'diff', 'patch', 'dart', 'js', 'ts', 'jsx', 'tsx', 'php', 'java', 'kt', 'py', 'rb', 'go',
  'rs', 'c', 'h', 'cpp', 'cs', 'swift', 'sh', 'bat', 'ps1', 'css', 'scss', 'html', 'htm',
  'vue', 'gradle', 'properties', 'toml',
};
const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _videoExtensions = {'mp4', 'mov', 'm4v', 'webm'};

/// How an attachment can be shown in the app: by content type, then by
/// extension (Redmine often stores `application/octet-stream`).
AttachmentKind previewKind(String filename, String? contentType) {
  final type = (contentType ?? '').toLowerCase();
  final dot = filename.lastIndexOf('.');
  final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  if (ext == 'md' || type == 'text/markdown') return AttachmentKind.markdown;
  if (type.startsWith('image/') && type != 'image/svg+xml' || _imageExtensions.contains(ext)) {
    return AttachmentKind.image;
  }
  if (type == 'application/pdf' || ext == 'pdf') return AttachmentKind.pdf;
  if (type.startsWith('video/') || _videoExtensions.contains(ext)) return AttachmentKind.video;
  // Exact types only: Office files are `application/vnd.openxmlformats-…`.
  if (type.startsWith('text/') ||
      type == 'application/json' ||
      type.endsWith('+json') ||
      type == 'application/xml' ||
      type.endsWith('+xml') ||
      _textExtensions.contains(ext)) {
    return AttachmentKind.text;
  }
  return AttachmentKind.none;
}

IconData kindIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.text => Icons.description_outlined,
      AttachmentKind.markdown => Icons.article_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.video => Icons.movie_outlined,
      AttachmentKind.none => Icons.insert_drive_file_outlined,
    };

/// `1,2 MB` style size.
String fmtFileSize(num? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final text = unit == 0
      ? '${size.round()}'
      : size.toStringAsFixed(1).replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
  return '$text ${units[unit]}';
}

/// Previews [attachments] (Redmine attachment JSON: `filename`, `content_url`,
/// `content_type`, `filesize`…) starting at [index]; the arrows (buttons or
/// ← →) move between them without closing.
Future<void> showAttachmentPreview(
  BuildContext context,
  List<Map> attachments, {
  int index = 0,
}) =>
    showAppDialog<void>(
      context,
      (_) => _AttachmentPreview(attachments: attachments, initial: index),
    );

/// Image of the configured Redmine, downloaded with the API key (attachments
/// need it). [onTap] makes it clickable; errors fall back to [fallback].
class AuthImage extends StatelessWidget {
  const AuthImage({
    super.key,
    required this.url,
    this.maxHeight,
    this.fit = BoxFit.contain,
    this.onTap,
    this.fallback,
  });

  final String url;
  final double? maxHeight;
  final BoxFit fit;
  final VoidCallback? onTap;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppState>().settings;
    final Future<({Uint8List bytes, String? contentType})> bytes;
    try {
      bytes = RedmineApiService().getBytes(settings, url);
    } catch (_) {
      // Another host: shown as a plain public image, never with the API key.
      return _framed(Image.network(url, fit: fit, errorBuilder: (_, __, ___) => _error()));
    }
    return FutureBuilder(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error();
        final data = snapshot.data;
        if (data == null) {
          return SizedBox(
            height: maxHeight == null ? 120 : maxHeight! / 2,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _framed(Image.memory(data.bytes, fit: fit, errorBuilder: (_, __, ___) => _error()));
      },
    );
  }

  Widget _error() => fallback ?? const Icon(Icons.broken_image_outlined, size: 20);

  Widget _framed(Widget image) {
    final sized = maxHeight == null
        ? image
        : ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight!), child: image);
    if (onTap == null) return sized;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: sized),
    );
  }
}

class _AttachmentPreview extends StatefulWidget {
  const _AttachmentPreview({required this.attachments, required this.initial});

  final List<Map> attachments;
  final int initial;

  @override
  State<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<_AttachmentPreview> {
  late int _index = widget.initial.clamp(0, widget.attachments.length - 1);

  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.attachments.length - 1;

  void _go(int delta) {
    final next = _index + delta;
    if (next >= 0 && next < widget.attachments.length) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final attachment = widget.attachments[_index];
    final name = '${attachment['filename'] ?? 'anexo'}';
    final url = '${attachment['content_url'] ?? ''}';
    final kind = previewKind(name, attachment['content_type'] as String?);
    final size = fmtFileSize(attachment['filesize'] as num?);
    final screen = MediaQuery.sizeOf(context);
    final many = widget.attachments.length > 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: AppDialog(
          scrollable: false,
          bodyPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Icon(kindIcon(kind), size: 18, color: AppColors.mutedText(dark: dark)),
              const SizedBox(width: 8),
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (size.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(size, style: AppText.microLabel(dark: dark)),
              ],
            ],
          ),
          headActions: [
            if (many) ...[
              IconBtn(
                icon: Icons.chevron_left,
                tooltip: 'Anterior (←)',
                onPressed: _hasPrevious ? () => _go(-1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Text(
                  '${_index + 1} de ${widget.attachments.length}',
                  style: AppText.caption(dark: dark),
                ),
              ),
              IconBtn(
                icon: Icons.chevron_right,
                tooltip: 'Próximo (→)',
                onPressed: _hasNext ? () => _go(1) : null,
              ),
            ],
            IconBtn(
              icon: Icons.link,
              tooltip: 'Copiar link',
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: RedmineApiService.absoluteUrl(
                    context.read<AppState>().settings.baseUrl,
                    url,
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => openRedmineLink(context, url),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir no navegador'),
            ),
          ],
          body: SizedBox(
            height: screen.height * 0.72,
            // Keyed by URL: each attachment gets a fresh view (download, player).
            child: KeyedSubtree(
              key: ValueKey(url),
              child: switch (kind) {
                AttachmentKind.video => _VideoView(url: url),
                AttachmentKind.none =>
                  _unsupported(dark, 'Sem pré-visualização para este tipo de arquivo.'),
                _ => _BytesView(url: url, kind: kind, name: name),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// [detail] = the underlying error, shown small for diagnosis.
Widget _unsupported(bool dark, String text, [String? detail]) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined, size: 32, color: AppColors.mutedText(dark: dark)),
          const SizedBox(height: 10),
          Text(text, style: AppText.captionLight(dark: dark)),
          const SizedBox(height: 4),
          Text('Use "Abrir no navegador".', style: AppText.microLabel(dark: dark)),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child:
                  Text(detail, textAlign: TextAlign.center, style: AppText.microLabel(dark: dark)),
            ),
        ],
      ),
    );

/// Image, text, markdown or PDF from the downloaded bytes.
class _BytesView extends StatefulWidget {
  const _BytesView({required this.url, required this.kind, required this.name});

  final String url;
  final AttachmentKind kind;
  final String name;

  @override
  State<_BytesView> createState() => _BytesViewState();
}

class _BytesViewState extends State<_BytesView> {
  /// Bigger texts show only their beginning, so the UI stays responsive.
  static const _maxText = 2 * 1024 * 1024;

  late final _bytes = RedmineApiService().getBytes(
    context.read<AppState>().settings,
    widget.url,
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Não foi possível baixar o anexo: '
              '${'${snapshot.error}'.replaceFirst('Exception: ', '')}',
              style: AppText.caption(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            ),
          );
        }
        final bytes = snapshot.data?.bytes;
        if (bytes == null) return const Center(child: CircularProgressIndicator());
        switch (widget.kind) {
          case AttachmentKind.image:
            return InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, __, ___) =>
                      _unsupported(dark, 'Não foi possível abrir esta imagem.'),
                ),
              ),
            );
          case AttachmentKind.pdf:
            return PdfViewer.data(bytes, sourceName: widget.name);
          case AttachmentKind.markdown:
          case AttachmentKind.text:
            final cut = bytes.length > _maxText;
            final text =
                utf8.decode(cut ? bytes.sublist(0, _maxText) : bytes, allowMalformed: true);
            return SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cut)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Notice('Arquivo grande: mostrando os primeiros 2 MB.'),
                      ),
                    if (widget.kind == AttachmentKind.markdown)
                      LineBreakSelection(
                          child: MarkdownBody(
                        data: text,
                        selectable: false, // the SelectionArea around selects across blocks
                        fitContent: false,
                        // The default code style paints a background over the selection.
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          code: AppText.mono(dark: dark).copyWith(
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ))
                    else
                      Text(text, style: AppText.mono(dark: dark)),
                  ],
                ),
              ),
            );
          case AttachmentKind.video:
          case AttachmentKind.none:
            return const SizedBox();
        }
      },
    );
  }
}

/// Streams the video with the API key in the request header (no full download).
class _VideoView extends StatefulWidget {
  const _VideoView({required this.url});

  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  VideoPlayerController? _controller;
  String? _error;

  /// video_player has no Windows/Linux implementation, and on the web the key
  /// can't go in a request header.
  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (_supported) _open();
  }

  /// Downloaded first, then played from the file: streaming straight from
  /// Redmine failed on macOS (AVPlayer needs range requests and its own TLS
  /// rules; the download route may offer neither).
  Future<void> _open() async {
    final settings = context.read<AppState>().settings;
    try {
      final file = await RedmineApiService().downloadToTemp(settings, widget.url);
      if (!mounted) return;
      final controller = VideoPlayerController.file(file);
      setState(() => _controller = controller);
      controller.addListener(_onTick);
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final controller = _controller;
    if (!_supported) return _unsupported(dark, 'Vídeo não suportado nesta plataforma.');
    final error = _error ?? controller?.value.errorDescription;
    if (error != null) return _unsupported(dark, 'Não foi possível reproduzir o vídeo.', error);
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final playing = controller.value.isPlaying;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: GestureDetector(
                onTap: () => playing ? controller.pause() : controller.play(),
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 22, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: playing ? 'Pausar' : 'Reproduzir',
                onPressed: () => playing ? controller.pause() : controller.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(playedColor: AppColors.accent(dark: dark)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
