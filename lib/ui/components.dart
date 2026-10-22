// Building blocks of the app layout (page header, panels, filters, stats,
// rows, tags, tabs, dialogs). Screens compose these instead of styling
// containers by hand, so spacing and colors stay consistent.

import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../services/theme_service.dart';
import 'ui_utils.dart';

bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// Page title (28px) + subtitle, with optional actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.pageTitle(dark: dark),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 7),
                  Text(subtitle!, style: AppText.captionLight(dark: dark)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Bordered surface (radius 12) with a bottom gap, like the prototype `.panel`.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: surfaceCard(dark: _isDark(context)),
      child: child,
    );
  }
}

/// Panel title row: h2 + muted subtitle, trailing actions.
class PanelHead extends StatelessWidget {
  const PanelHead({super.key, required this.title, this.subtitle, this.trailing});

  final Widget title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 19),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(style: AppText.cardTitle(dark: dark), child: title),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(subtitle!, style: AppText.microLabel(dark: dark)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 14), trailing!],
        ],
      ),
    );
  }
}

/// Filter panel: controls on top, actions on the right, optional extra row
/// ("Mais filtros") and a summary line.
class FiltersPanel extends StatelessWidget {
  const FiltersPanel({
    super.key,
    required this.controls,
    this.actions = const [],
    this.extra,
    this.summary,
  });

  final List<Widget> controls;
  final List<Widget> actions;

  /// Shown below a divider when non-null (the caller decides if it's open).
  final List<Widget>? extra;
  final Widget? summary;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: controls,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
          if (extra != null)
            Container(
              margin: const EdgeInsets.only(top: 18),
              padding: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: extra!,
              ),
            ),
          if (summary != null) Padding(padding: const EdgeInsets.only(top: 15), child: summary),
        ],
      ),
    );
  }
}

/// "Mais filtros" / "Ocultar filtros" toggle.
class MoreFiltersButton extends StatelessWidget {
  const MoreFiltersButton({super.key, required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.tune, size: 17),
      label: Text(open ? 'Ocultar filtros' : 'Mais filtros'),
    );
  }
}

/// "N itens · [chip] [chip] · Limpar filtros ×"
class FilterSummary extends StatelessWidget {
  const FilterSummary({super.key, required this.text, this.chips = const [], this.onClear});

  final String text;
  final List<String> chips;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: AppText.microLabel(dark: dark)),
        for (final chip in chips) Tag(chip, tone: TagTone.accent),
        if (chips.isNotEmpty && onClear != null)
          TextButton.icon(
            onPressed: onClear,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Limpar filtros'),
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
      ],
    );
  }
}

/// Small label above a control.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption(dark: _isDark(context))),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

const controlHeight = 40.0;

/// Single-line text field exactly [controlHeight] tall, like the selects beside it.
/// The border only fills a fixed height when the field `expands` (padding or
/// `InputDecoration.constraints` keep the text's own height), so newlines are
/// filtered out instead of relying on `maxLines: 1`.
class LineField extends StatelessWidget {
  const LineField({
    super.key,
    this.controller,
    this.initialValue,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters = const [],
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> inputFormatters;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: controlHeight,
        child: TextFormField(
          controller: controller,
          initialValue: initialValue,
          expands: true,
          maxLines: null,
          keyboardType: keyboardType ?? TextInputType.text,
          textAlignVertical: TextAlignVertical.center,
          inputFormatters: [FilteringTextInputFormatter.deny('\n'), ...inputFormatters],
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onChanged: onChanged,
        ),
      );
}

/// Text field with a search icon, 40px tall.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.width = 320,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 17),
          prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: controlHeight),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          constraints: const BoxConstraints.tightFor(height: controlHeight),
        ),
      ),
    );
  }
}

/// Bordered 40px box for dropdowns and menu triggers, matching text fields.
class ControlBox extends StatelessWidget {
  const ControlBox({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Material(
      color: AppColors.field(dark: dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        side: BorderSide(color: AppColors.border(dark: dark)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: Container(
          height: controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: child),
        ),
      ),
    );
  }
}

/// Dropdown inside a [ControlBox].
class SelectBox<T> extends StatelessWidget {
  const SelectBox({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.minWidth = 190,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: ControlBox(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(AppRadius.standard),
            dropdownColor: AppColors.panel(dark: _isDark(context)),
            style: AppText.body(dark: _isDark(context)),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// Select with its own search box: the 40px field shows the choice; a click
/// opens a list with an empty search field (accent/case-insensitive). [none]
/// is the "nothing / keep" entry, mapped to null; without it, [hint] shows
/// until something is picked. The value is controlled: it's read on every build.
class SearchSelect extends StatefulWidget {
  const SearchSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.none,
    this.hint = 'Selecione…',
    this.typedId = false,
  });

  final int? value;
  final List<(int, String)> options;
  final ValueChanged<int?> onChanged;
  final String? none;
  final String hint;

  /// A number typed in the search (`123` or `#123`) that isn't an option can
  /// be picked as is (issue IDs outside the list).
  final bool typedId;

  @override
  State<SearchSelect> createState() => _SearchSelectState();
}

class _SearchSelectState extends State<SearchSelect> {
  final _menu = MenuController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// (value, label) entries; a saved id no longer listed still shows as `#id`.
  List<(int?, String)> get _entries {
    final v = widget.value;
    return [
      if (widget.none != null) (null, widget.none!),
      for (final (id, label) in widget.options) (id, label),
      if (v != null && !widget.options.any((o) => o.$1 == v)) (v, '#$v'),
    ];
  }

  void _pick(int? value) {
    _menu.close();
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final entries = _entries;
    final current = entries.where((e) => e.$1 == widget.value).firstOrNull;
    final q = searchKey(_search.text.trim());
    final typed = widget.typedId ? int.tryParse(_search.text.trim().replaceFirst('#', '')) : null;
    final shown = [
      if (typed != null && !entries.any((e) => e.$1 == typed)) (typed, '#$typed · usar este ID'),
      for (final e in entries)
        if (q.isEmpty || searchKey(e.$2).contains(q)) e,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 260.0;
        return MenuAnchor(
          controller: _menu,
          // Every opening starts with an empty search.
          onOpen: () => setState(_search.clear),
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 400)),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: SizedBox(
                width: width - 16,
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar…',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 17),
                    prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: controlHeight),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    constraints: BoxConstraints.tightFor(height: controlHeight),
                  ),
                  onChanged: (_) => setState(() {}),
                  // Enter takes the first match.
                  onSubmitted: (_) {
                    if (shown.isNotEmpty) _pick(shown.first.$1);
                  },
                ),
              ),
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Text('Nada encontrado.', style: AppText.captionLight(dark: dark)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                // The menu panel has its own scroll view; this list keeps a separate one.
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (value, label) in shown)
                        MenuItemButton(
                          onPressed: () => _pick(value),
                          leadingIcon: SizedBox(
                            width: 18,
                            child: value == widget.value
                                ? Icon(Icons.check, size: 16, color: AppColors.accent(dark: dark))
                                : null,
                          ),
                          child: SizedBox(
                            width: width - 64,
                            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => SizedBox(
            width: width,
            child: ControlBox(
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      current?.$2 ?? widget.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: current == null
                          ? AppText.captionLight(dark: dark)
                          : AppText.body(dark: dark),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: AppColors.mutedText(dark: dark)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [SelectionArea] whose copied pieces are joined like a browser does (see
/// [LineBreakSelection]). Put it around content without its own scroll view; for
/// scrolling content use `SelectionArea(child: scrollView(child: LineBreakSelection(…)))`
/// so dragging still auto-scrolls.
class PageSelectionArea extends StatelessWidget {
  const PageSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(child: LineBreakSelection(child: child));
}

/// Groups text blocks (e.g. a markdown body) for selection: copied blocks on
/// different lines are joined with a line break, and pieces on the same line
/// with a space, as a browser does. A bare [SelectionArea] glues them together.
/// Needs a [SelectionArea] above it.
class LineBreakSelection extends StatefulWidget {
  const LineBreakSelection({super.key, required this.child});

  final Widget child;

  @override
  State<LineBreakSelection> createState() => _LineBreakSelectionState();
}

class _LineBreakSelectionState extends State<LineBreakSelection> {
  final _delegate = _LineBreakSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _LineBreakSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    Rect? previous;
    for (final selectable in selectables) {
      final content = selectable.getSelectedContent();
      if (content == null || content.plainText.isEmpty) continue;
      final rect =
          MatrixUtils.transformRect(selectable.getTransformTo(null), Offset.zero & selectable.size);
      if (previous != null) buffer.write(rect.top >= previous.bottom - 1 ? '\n' : ' ');
      buffer.write(content.plainText);
      previous = rect;
    }
    return previous == null ? null : SelectedContent(plainText: buffer.toString());
  }
}

/// KPI card: label + icon, big value, note.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String label;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: surfaceCard(dark: dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppText.caption(dark: dark))),
              Icon(icon, size: 17, color: AppColors.statIcon(dark: dark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.kpi(dark: dark)),
          const SizedBox(height: 7),
          Text(note, style: AppText.microLabel(dark: dark).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Four equal columns (two when narrow), 14px gap.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 700 ? 2 : 4;
          const gap = 14.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final c in children) SizedBox(width: width, child: c)],
          );
        },
      ),
    );
  }
}

/// 34px rounded icon square at the start of list rows.
class IconBox extends StatelessWidget {
  const IconBox({super.key, required this.icon, this.highlighted = false});

  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: highlighted ? AppColors.cellSelected(dark: dark) : AppColors.iconBox(dark: dark),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Icon(
        icon,
        size: 17,
        color: highlighted ? AppColors.accent(dark: dark) : AppColors.iconBoxIcon(dark: dark),
      ),
    );
  }
}

/// List row separated by a top border: leading, title, meta lines, actions.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.leading,
    this.meta = const [],
    this.actions = const [],
    this.trailing,
    this.onTap,
    this.accentBorder,
    this.below,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> meta;
  final List<Widget> actions;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Colored left border (log levels).
  final Color? accentBorder;

  /// Extra content under the meta lines (e.g. technical details).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return InkWell(
      onTap: onTap,
      hoverColor: onTap == null ? Colors.transparent : AppColors.hover(dark: dark),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 17),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border(dark: dark)),
            left:
                accentBorder == null ? BorderSide.none : BorderSide(color: accentBorder!, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: AppText.bodyMedium(dark: dark),
                    child: title,
                  ),
                  for (final m in meta)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child:
                          DefaultTextStyle.merge(style: AppText.microLabel(dark: dark), child: m),
                    ),
                  if (below != null) below!,
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 14), trailing!],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 14),
              Wrap(spacing: 6, runSpacing: 6, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bordered square icon button (39px, or 33px [compact] for row actions).
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final size = compact ? 33.0 : 39.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: compact ? Colors.transparent : AppColors.field(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          side: BorderSide(color: AppColors.border(dark: dark)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.standard),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: 17,
              color: onPressed == null
                  ? AppColors.border(dark: dark)
                  : color ?? AppColors.text(dark: dark),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small soft tag (status, level, counts).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone = TagTone.neutral, this.icon});

  /// Tone picked by hash of [text], so the same name keeps its color
  /// (trackers, statuses) without hard-coding environment values.
  factory Tag.hashed(String text, {Key? key}) => Tag(
        text,
        key: key,
        tone: _hashTones[text.codeUnits.fold(0, (a, b) => a + b) % _hashTones.length],
      );

  static const _hashTones = [
    TagTone.green,
    TagTone.amber,
    TagTone.red,
    TagTone.purple,
    TagTone.blue,
  ];

  final String text;
  final TagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = AppColors.tone(tone, dark: _isDark(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.subtle)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.badge().copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact tab switcher on a sunken track (Board/Lista, Por tarefa/…).
class AppTabs<T> extends StatelessWidget {
  const AppTabs({super.key, required this.tabs, required this.selected, required this.onChanged});

  final List<(T, String, IconData?)> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.well(dark: dark),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label, icon) in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Material(
                color: value == selected ? AppColors.tabActive(dark: dark) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => onChanged(value),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            size: 15,
                            color: value == selected
                                ? AppColors.accent(dark: dark)
                                : AppColors.mutedText(dark: dark),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          label,
                          style: AppText.caption(dark: dark).copyWith(
                            color: value == selected ? AppColors.accent(dark: dark) : null,
                            fontWeight: value == selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Underlined tabs with an optional count chip (sections of the issue dialog).
class LineTabs<T> extends StatelessWidget {
  const LineTabs({super.key, required this.tabs, required this.selected, required this.onChanged});

  /// (value, label, icon, count).
  final List<(T, String, IconData?, String?)> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label, icon, count) in tabs)
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: InkWell(
              onTap: () => onChanged(value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 3,
                      color: value == selected ? AppColors.accent(dark: dark) : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 15,
                        color: value == selected
                            ? AppColors.accent(dark: dark)
                            : AppColors.mutedText(dark: dark),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label,
                      style: AppText.caption(dark: dark).copyWith(
                        fontSize: 13,
                        color: value == selected ? AppColors.accent(dark: dark) : null,
                        fontWeight: value == selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.well(dark: dark),
                          borderRadius: BorderRadius.circular(AppRadius.subtle),
                        ),
                        child: Text(
                          count,
                          style: AppText.badge().copyWith(color: AppColors.mutedText(dark: dark)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Folder-like tabs of the workspace (pages and boards). Sits at the bottom of
/// a bar with a bottom border: the selected tab has the page color and covers
/// that line, joining the content below. When they don't fit, arrows (and the
/// mouse wheel) scroll them; the selected tab is always scrolled into view.
class WorkspaceTabs<T> extends StatefulWidget {
  const WorkspaceTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    required this.onClose,
  });

  /// (value, label, icon).
  final List<(T, String, IconData?)> tabs;
  final T? selected;
  final ValueChanged<T> onChanged;

  /// The ×, or a middle click.
  final ValueChanged<T> onClose;

  @override
  State<WorkspaceTabs<T>> createState() => _WorkspaceTabsState<T>();
}

class _WorkspaceTabsState<T> extends State<WorkspaceTabs<T>> {
  static const _height = 42.0;
  final _scroll = ScrollController();
  final _selectedKey = GlobalKey();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    _reveal();
  }

  @override
  void didUpdateWidget(WorkspaceTabs<T> old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.tabs.length != widget.tabs.length) _reveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just enough to show the selected tab: only one of the two moves.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final tab = _selectedKey.currentContext;
        if (tab == null) return;
        const duration = Duration(milliseconds: 150);
        for (final policy in [
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ]) {
          Scrollable.ensureVisible(tab, duration: duration, alignmentPolicy: policy);
        }
      });

  /// Which arrows are enabled (none shown while everything fits).
  void _sync() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final back = p.pixels > p.minScrollExtent;
    final forward = p.pixels < p.maxScrollExtent;
    if (back != _canBack || forward != _canForward) {
      // Arrows showing up (or leaving) change the room for the tabs.
      if ((back || forward) != (_canBack || _canForward)) _reveal();
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _scrollTo(double offset, {bool animate = true}) {
    final p = _scroll.position;
    final target = offset.clamp(p.minScrollExtent, p.maxScrollExtent);
    animate
        ? _scroll.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
        : _scroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    Widget arrow(IconData icon, String tooltip, double direction, bool enabled) => IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: tooltip,
          onPressed: enabled
              ? () =>
                  _scrollTo(_scroll.offset + direction * _scroll.position.viewportDimension * 0.6)
              : null,
          icon: Icon(icon),
        );
    final overflow = _canBack || _canForward;

    return SizedBox(
      height: _height,
      child: Row(
        children: [
          if (overflow) arrow(Icons.chevron_left, 'Abas anteriores', -1, _canBack),
          Expanded(
            // Metrics change when tabs open/close or the window resizes.
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _sync();
                return false;
              },
              child: Listener(
                // A vertical mouse wheel scrolls the tabs sideways.
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && _scroll.hasClients) {
                    _scrollTo(_scroll.offset + event.scrollDelta.dy, animate: false);
                  }
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, (value, label, icon)) in widget.tabs.indexed)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: _tab(value, label, icon, dark),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (overflow) arrow(Icons.chevron_right, 'Próximas abas', 1, _canForward),
        ],
      ),
    );
  }

  Widget _tab(T value, String label, IconData? icon, bool dark) {
    final selected = value == widget.selected;
    final color = selected ? AppColors.accent(dark: dark) : AppColors.mutedText(dark: dark);
    final side = BorderSide(color: AppColors.border(dark: dark));
    const radius = BorderRadius.vertical(top: Radius.circular(AppRadius.standard));
    return GestureDetector(
      key: selected ? _selectedKey : null,
      onTertiaryTapUp: (_) => widget.onClose(value),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? AppColors.page(dark: dark) : AppColors.sunken(dark: dark),
          borderRadius: radius,
          // The selected tab's accent strip, as a border so it spans the tab
          // (a bare Container has no width in the sideways scroll view).
          border: Border(
            top: BorderSide(
              width: 3,
              color: selected ? AppColors.accent(dark: dark) : Colors.transparent,
            ),
          ),
        ),
        // On top of the hover color; the selected tab has no bottom line.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border(
            top: side,
            left: side,
            right: side,
            bottom: selected ? BorderSide.none : side,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => widget.onChanged(value),
            hoverColor: selected ? Colors.transparent : AppColors.fieldHover(dark: dark),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 7),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(dark: dark).copyWith(
                        fontSize: 13,
                        color: color,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => widget.onClose(value),
                    borderRadius: BorderRadius.circular(AppRadius.subtle),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        semanticLabel: 'Fechar aba',
                        color: AppColors.mutedText(dark: dark),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 40px date field: shows `dd-MM-yyyy` and opens the date picker; the ✕ clears.
/// [value] is Redmine's `YYYY-MM-DD`, or '' for no date.
class DateSelect extends StatelessWidget {
  const DateSelect({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Sem data',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final date = DateTime.tryParse(value);
    return ControlBox(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(ymd(picked));
      },
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.mutedText(dark: dark)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              date == null ? hint : fmtDate(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: date == null ? AppText.captionLight(dark: dark) : AppText.body(dark: dark),
            ),
          ),
          if (date != null)
            InkWell(
              onTap: () => onChanged(''),
              borderRadius: BorderRadius.circular(AppRadius.subtle),
              child: Tooltip(
                message: 'Limpar',
                child: Icon(Icons.close, size: 16, color: AppColors.mutedText(dark: dark)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 40px time field (24h) that opens the time picker; [value] in minutes of the day.
class TimeSelect extends StatelessWidget {
  const TimeSelect({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final time = TimeOfDay(hour: value ~/ 60 % 24, minute: value % 60);
    return ControlBox(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
      child: Row(
        children: [
          Icon(Icons.schedule, size: 15, color: AppColors.mutedText(dark: dark)),
          const SizedBox(width: 8),
          Text(
            MaterialLocalizations.of(context).formatTimeOfDay(time, alwaysUse24HourFormat: true),
            style: AppText.body(dark: dark),
          ),
        ],
      ),
    );
  }
}

/// Row of bordered buttons; the selected one is filled with the accent.
class SegmentButtons<T> extends StatelessWidget {
  const SegmentButtons({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String, IconData?)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (value, label, icon) in segments)
          Material(
            color: value == selected ? AppColors.accent(dark: dark) : AppColors.field(dark: dark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.standard),
              side: BorderSide(
                color:
                    value == selected ? AppColors.accent(dark: dark) : AppColors.border(dark: dark),
              ),
            ),
            child: InkWell(
              onTap: () => onChanged(value),
              borderRadius: BorderRadius.circular(AppRadius.standard),
              child: Container(
                height: controlHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 15,
                        color: value == selected
                            ? AppColors.onAccent(dark: dark)
                            : AppColors.text(dark: dark),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: AppText.caption(dark: dark).copyWith(
                        color: value == selected
                            ? AppColors.onAccent(dark: dark)
                            : AppColors.text(dark: dark),
                        fontWeight: value == selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Centered icon + message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon = Icons.search});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.all(38),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.mutedText(dark: dark)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: AppText.captionLight(dark: dark)),
        ],
      ),
    );
  }
}

/// Section heading inside forms: accent icon + text.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.accent(dark: dark)),
          const SizedBox(width: 9),
          Text(
            text,
            style: AppText.bodySemibold(dark: dark).copyWith(
              color: AppColors.sectionText(dark: dark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft accent box for important hints.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.accentSoft(dark: dark),
        border: Border.all(color: AppColors.chip(dark: dark)),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Text(
        text,
        style: AppText.microLabel(dark: dark).copyWith(
          color: dark ? const Color(0xFFB0DFD1) : const Color(0xFF0B4A40),
        ),
      ),
    );
  }
}

/// Shows [builder] over a blurred, dimmed backdrop. Opens in the nearest
/// navigator: inside a workspace tab it covers only that tab and stays open
/// while another tab is in front.
Future<T?> showAppDialog<T>(BuildContext context, WidgetBuilder builder) => showDialog<T>(
      context: context,
      useRootNavigator: false,
      barrierColor: _isDark(context) ? const Color(0xBB071018) : const Color(0x66101419),
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: builder(dialogContext),
      ),
    );

/// Dialog with fixed header (title + close) and footer, scrolling body.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.footer = const [],
    this.headActions = const [],
    this.width,
    this.bodyPadding = const EdgeInsets.all(22),
    this.scrollable = true,
  });

  final Widget title;
  final Widget body;
  final List<Widget> footer;
  final List<Widget> headActions;

  /// Null = 85% of the window (forms); small yes/no confirmations pass 460.
  final double? width;
  final EdgeInsetsGeometry bodyPadding;

  /// False when [body] manages its own scrolling.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final border = BorderSide(color: AppColors.border(dark: dark));
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(15),
      // Sized by the area it opens in (the tab), not the window.
      child: LayoutBuilder(
        builder: (context, area) => Container(
          width: width ?? area.maxWidth * 0.85,
          constraints: BoxConstraints(maxHeight: area.maxHeight * 0.9),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.panel(dark: dark),
            border: Border.all(color: AppColors.dialogBorder(dark: dark)),
            borderRadius: BorderRadius.circular(AppRadius.dialog),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 90, offset: Offset(0, 30)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
                decoration: BoxDecoration(border: Border(bottom: border)),
                child: Row(
                  children: [
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: AppText.cardTitle(dark: dark),
                        child: title,
                      ),
                    ),
                    // Wraps instead of overflowing when there are many actions.
                    if (headActions.isNotEmpty)
                      // Tight, so the close button stays at the right edge.
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: headActions,
                          ),
                        ),
                      ),
                    IconBtn(
                      icon: Icons.close,
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: scrollable
                    ? SingleChildScrollView(padding: bodyPadding, child: body)
                    : Padding(padding: bodyPadding, child: body),
              ),
              if (footer.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 17, 22, 17),
                  decoration: BoxDecoration(border: Border(top: border)),
                  // Right-aligned; pass a Spacer() to push an item to the left.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < footer.length; i++) ...[
                        if (i > 0) const SizedBox(width: 9),
                        footer[i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
