// Design tokens + ThemeData for Redmine Monitor.
//
// Dark theme = the approved prototype (slate surfaces, aqua accent #46D4BD).
// Light theme = the same identity on light surfaces, with a darker accent
// (#0B7A6A) so accent text keeps >= 4.5:1 contrast on white.
// Widgets read colors through the theme-aware accessors below
// (`AppColors.accent(dark: dark)` …), never through hard-coded hex values.

import 'package:flutter/material.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  static const Color white = Color(0xFFFFFFFF);

  // Accent
  static Color accent({required bool dark}) =>
      dark ? const Color(0xFF46D4BD) : const Color(0xFF0B7A6A);
  static Color onAccent({required bool dark}) => dark ? const Color(0xFF092B26) : white;
  static Color accentHover({required bool dark}) =>
      dark ? const Color(0xFF6CE2CD) : const Color(0xFF096A5C);

  /// Selected nav item / unread icon box.
  static Color accentSoft({required bool dark}) =>
      dark ? const Color(0xFF213630) : const Color(0xFFE3F4F0);

  /// Filter chips.
  static Color chip({required bool dark}) =>
      dark ? const Color(0xFF223B35) : const Color(0xFFDDF1EC);

  /// Active tab inside [AppTabs].
  static Color tabActive({required bool dark}) =>
      dark ? const Color(0xFF2D403B) : const Color(0xFFD5EDE7);

  // Surfaces
  static Color page({required bool dark}) =>
      dark ? const Color(0xFF101419) : const Color(0xFFF3F5F8);
  static Color sidebar({required bool dark}) =>
      dark ? const Color(0xFF141920) : const Color(0xFFF8FAFC);
  static Color panel({required bool dark}) => dark ? const Color(0xFF191F27) : white;
  static Color field({required bool dark}) => dark ? const Color(0xFF202833) : white;
  static Color fieldHover({required bool dark}) =>
      dark ? const Color(0xFF26323E) : const Color(0xFFF1F4F7);

  /// Table headers.
  static Color sunken({required bool dark}) =>
      dark ? const Color(0xFF161C23) : const Color(0xFFEEF1F5);

  /// Tab tracks, code blocks.
  static Color well({required bool dark}) =>
      dark ? const Color(0xFF11171E) : const Color(0xFFE9EDF2);

  /// Table footers (totals).
  static Color footer({required bool dark}) =>
      dark ? const Color(0xFF202A32) : const Color(0xFFEEF1F5);
  static Color column({required bool dark}) =>
      dark ? const Color(0xFF151C24) : const Color(0xFFEEF1F5);
  static Color columnBorder({required bool dark}) =>
      dark ? const Color(0xFF252F3A) : const Color(0xFFDFE4EA);
  static Color hover({required bool dark}) =>
      dark ? const Color(0xFF1D2630) : const Color(0xFFEEF2F6);
  static Color cellHover({required bool dark}) =>
      dark ? const Color(0xFF244139) : const Color(0xFFDCEFEA);
  static Color cellSelected({required bool dark}) =>
      dark ? const Color(0xFF25483F) : const Color(0xFFCDEAE3);
  static Color iconBox({required bool dark}) =>
      dark ? const Color(0xFF253B43) : const Color(0xFFE3EEF2);
  static Color iconBoxIcon({required bool dark}) =>
      dark ? const Color(0xFF8CCCDC) : const Color(0xFF2B6B7D);

  // Lines and text
  static Color border({required bool dark}) =>
      dark ? const Color(0xFF2B3440) : const Color(0xFFDFE4EA);
  static Color borderStrong({required bool dark}) =>
      dark ? const Color(0xFF526477) : const Color(0xFFB8C2CE);
  static Color dialogBorder({required bool dark}) =>
      dark ? const Color(0xFF405361) : const Color(0xFFCBD3DC);
  static Color text({required bool dark}) =>
      dark ? const Color(0xFFEDF2F7) : const Color(0xFF111820);
  static Color mutedText({required bool dark}) =>
      dark ? const Color(0xFF96A3B3) : const Color(0xFF5B6878);
  static Color sectionText({required bool dark}) =>
      dark ? const Color(0xFFC8D6E2) : const Color(0xFF2B3A4A);
  static Color statIcon({required bool dark}) =>
      dark ? const Color(0xFF6C8999) : const Color(0xFF8798A8);
  static Color danger({required bool dark}) =>
      dark ? const Color(0xFFFFAAA6) : const Color(0xFFB4232C);

  /// Left border of log rows, per level.
  static Color logLevel(String level) => switch (level) {
        'success' => const Color(0xFF58AD87),
        'error' => const Color(0xFFCC7B89),
        'alert' => const Color(0xFFA78CCC),
        'warn' => const Color(0xFFD7A75A),
        _ => const Color(0xFF587AAB),
      };

  /// (background, foreground) of a soft [Tag].
  static (Color, Color) tone(TagTone tone, {required bool dark}) => dark
      ? switch (tone) {
          TagTone.neutral => (const Color(0xFF283340), const Color(0xFFB9C8D7)),
          TagTone.green => (const Color(0xFF223C32), const Color(0xFF95DFB6)),
          TagTone.amber => (const Color(0xFF403725), const Color(0xFFE9C78E)),
          TagTone.red => (const Color(0xFF422C33), const Color(0xFFF4A6B7)),
          TagTone.purple => (const Color(0xFF342C46), const Color(0xFFC5AFEA)),
          TagTone.blue => (const Color(0xFF263A4B), const Color(0xFF9BC7ED)),
          TagTone.accent => (const Color(0xFF223B35), const Color(0xFF46D4BD)),
        }
      : switch (tone) {
          TagTone.neutral => (const Color(0xFFE8EDF2), const Color(0xFF3D4B5C)),
          TagTone.green => (const Color(0xFFDDF3E7), const Color(0xFF1E6B45)),
          TagTone.amber => (const Color(0xFFFBF0DA), const Color(0xFF7A5410)),
          TagTone.red => (const Color(0xFFFBE3E7), const Color(0xFF9B2335)),
          TagTone.purple => (const Color(0xFFEEE7FA), const Color(0xFF5B3F8F)),
          TagTone.blue => (const Color(0xFFE1EEF9), const Color(0xFF1F5A8A)),
          TagTone.accent => (const Color(0xFFDDF1EC), const Color(0xFF0B7A6A)),
        };
}

enum TagTone { neutral, green, amber, red, purple, blue, accent }

// ─── Radii ───────────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();

  static const double micro = 4;
  static const double subtle = 5; // tags, chips
  static const double standard = 8; // controls, icon boxes
  static const double comfortable = 12; // panels
  static const double dialog = 14;
  static const double pill = 9999;
}

// ─── Typography ──────────────────────────────────────────────────────────────

class AppText {
  AppText._();

  static const String fontFamily = 'Inter';

  static TextStyle _t(double size, FontWeight weight, Color color,
          {double height = 1.5, double spacing = 0}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color,
      );

  /// h1 — page title.
  static TextStyle pageTitle({bool dark = false}) =>
      _t(28, FontWeight.w700, AppColors.text(dark: dark), height: 1.2, spacing: -0.7);

  /// 29px KPI value.
  static TextStyle kpi({bool dark = false}) =>
      _t(29, FontWeight.w700, AppColors.text(dark: dark), height: 1.15, spacing: -1);

  /// h2 — panel and section titles.
  static TextStyle cardTitle({bool dark = false}) =>
      _t(17, FontWeight.w700, AppColors.text(dark: dark), height: 1.35);

  /// Dialog titles and emphasized headings.
  static TextStyle bodyLarge({bool dark = false}) =>
      _t(17, FontWeight.w600, AppColors.text(dark: dark), height: 1.4);

  static TextStyle body({bool dark = false}) =>
      _t(14, FontWeight.w400, AppColors.text(dark: dark), height: 1.6);

  static TextStyle bodyMedium({bool dark = false}) =>
      _t(14, FontWeight.w500, AppColors.text(dark: dark), height: 1.6);

  static TextStyle bodySemibold({bool dark = false}) =>
      _t(14, FontWeight.w600, AppColors.text(dark: dark), height: 1.6);

  static TextStyle navButton({bool dark = false}) =>
      _t(13, FontWeight.w500, AppColors.text(dark: dark), height: 1.35);

  /// 12px medium — field labels.
  static TextStyle caption({bool dark = false}) =>
      _t(12, FontWeight.w500, AppColors.mutedText(dark: dark), height: 1.45);

  /// 13px regular — subtitles and helper text.
  static TextStyle captionLight({bool dark = false}) =>
      _t(13, FontWeight.w400, AppColors.mutedText(dark: dark), height: 1.6);

  /// 11px tag text — color set by the caller.
  static TextStyle badge() => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  /// 12px meta text — timestamps, hints.
  static TextStyle microLabel({bool dark = false}) =>
      _t(12, FontWeight.w400, AppColors.mutedText(dark: dark), height: 1.6);

  /// Monospace for code. 'monospace' alone is not a real family on macOS and
  /// falls back to the proportional font, so name real ones per platform.
  static TextStyle mono({bool dark = false}) => TextStyle(
        fontFamily: 'Menlo',
        fontFamilyFallback: const ['SF Mono', 'Consolas', 'Monaco', 'Courier New', 'monospace'],
        fontSize: 12.5,
        height: 1.5,
        color: AppColors.sectionText(dark: dark),
      );

  /// 10px spaced uppercase label (sidebar sections).
  static TextStyle sectionLabel({bool dark = false}) =>
      _t(10, FontWeight.w600, AppColors.mutedText(dark: dark), height: 1.3, spacing: 1.5);
}

// ─── Spacing ─────────────────────────────────────────────────────────────────

class Sp {
  Sp._();
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;
}

// ─── Decoration helpers ───────────────────────────────────────────────────────

/// Flat panel: surface, 1px border, radius 12, no shadow.
BoxDecoration surfaceCard({bool dark = false}) => BoxDecoration(
      color: AppColors.panel(dark: dark),
      border: Border.all(color: AppColors.border(dark: dark)),
      borderRadius: BorderRadius.circular(AppRadius.comfortable),
    );

// ─── ThemeData builder ────────────────────────────────────────────────────────

ThemeData buildAppTheme({required bool dark}) {
  final accent = AppColors.accent(dark: dark);
  final onAccent = AppColors.onAccent(dark: dark);
  final text = AppColors.text(dark: dark);
  final muted = AppColors.mutedText(dark: dark);
  final border = AppColors.border(dark: dark);
  final panel = AppColors.panel(dark: dark);
  final controlShape = WidgetStateProperty.all(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        borderSide: BorderSide(color: color, width: width),
      );
  const buttonText = TextStyle(fontFamily: AppText.fontFamily, fontSize: 14);

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: AppColors.page(dark: dark),
    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      // Without these, M3 falls back to `secondary` and progress tracks become
      // the same color as the bar (no visible motion).
      secondaryContainer: AppColors.accentSoft(dark: dark),
      onSecondaryContainer: accent,
      surface: panel,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      error: AppColors.danger(dark: dark),
      surfaceContainerHighest: AppColors.field(dark: dark),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: border,
      circularTrackColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(AppRadius.comfortable),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field(dark: dark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      focusedBorder: inputBorder(accent, 1.5),
      errorBorder: inputBorder(AppColors.danger(dark: dark)),
      focusedErrorBorder: inputBorder(AppColors.danger(dark: dark), 1.5),
      labelStyle: AppText.caption(dark: dark).copyWith(fontSize: 13),
      floatingLabelStyle: AppText.caption(dark: dark).copyWith(color: accent),
      hintStyle: AppText.captionLight(dark: dark),
      helperStyle: AppText.microLabel(dark: dark),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return border;
          if (states.contains(WidgetState.hovered)) return AppColors.accentHover(dark: dark);
          return accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? muted : onAccent,
        ),
        textStyle: WidgetStateProperty.all(buttonText.copyWith(fontWeight: FontWeight.w700)),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        // Desktop defaults to compact density (-8px); keep 40px like the fields.
        visualDensity: VisualDensity.standard,
        shape: controlShape,
        elevation: WidgetStateProperty.all(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.fieldHover(dark: dark)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.all(text),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color:
                states.contains(WidgetState.hovered) ? AppColors.borderStrong(dark: dark) : border,
          ),
        ),
        textStyle: WidgetStateProperty.all(buttonText.copyWith(fontWeight: FontWeight.w500)),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        // Desktop defaults to compact density (-8px); keep 40px like the fields.
        visualDensity: VisualDensity.standard,
        shape: controlShape,
        elevation: WidgetStateProperty.all(0),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(accent),
        textStyle: WidgetStateProperty.all(
          buttonText.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
        shape: controlShape,
        overlayColor: WidgetStateProperty.all(accent.withValues(alpha: 0.08)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStateProperty.all(muted)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? onAccent : const Color(0xFFE5F7F2),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : (dark ? const Color(0xFF3A4755) : const Color(0xFFC5CED8)),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(onAccent),
      side: BorderSide(color: AppColors.borderStrong(dark: dark), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.field(dark: dark),
      labelStyle: AppText.badge().copyWith(color: text, fontSize: 12),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.subtle)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.dialogBorder(dark: dark)),
        borderRadius: BorderRadius.circular(AppRadius.dialog),
      ),
      titleTextStyle: AppText.cardTitle(dark: dark),
      contentTextStyle: AppText.body(dark: dark),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.dialogBorder(dark: dark)),
        borderRadius: BorderRadius.circular(AppRadius.dialog),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      textStyle: AppText.body(dark: dark),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(panel),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        side: WidgetStateProperty.all(BorderSide(color: border)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF26323E) : const Color(0xFF1F2933),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontFamily: AppText.fontFamily, fontSize: 12, color: Colors.white),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF24483C) : const Color(0xFFE3F4F0),
      contentTextStyle: TextStyle(
        fontFamily: AppText.fontFamily,
        fontSize: 13,
        color: dark ? const Color(0xFFDBFFF1) : const Color(0xFF0B4A40),
      ),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: dark ? const Color(0xFF4D7B68) : const Color(0xFF9ED5C8)),
        borderRadius: BorderRadius.circular(10),
      ),
      behavior: SnackBarBehavior.floating,
      width: 440,
      elevation: 8,
    ),
    textTheme: TextTheme(
      headlineSmall: AppText.cardTitle(dark: dark),
      titleLarge: AppText.cardTitle(dark: dark),
      titleMedium: AppText.bodySemibold(dark: dark),
      titleSmall: AppText.bodyMedium(dark: dark),
      bodyLarge: AppText.body(dark: dark),
      bodyMedium: AppText.body(dark: dark),
      bodySmall: AppText.captionLight(dark: dark),
      labelLarge: AppText.navButton(dark: dark),
      labelMedium: AppText.caption(dark: dark),
      labelSmall: AppText.badge(),
    ),
  );
}
