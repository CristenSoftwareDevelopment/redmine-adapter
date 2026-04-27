// Design system + theme service for Redmine Monitor.
//
// All design tokens (colors, typography, radii, shadows, spacing) and the
// Flutter ThemeData builder live here. Import this file from every UI file.
//
// Dark-mode muted text
// ─────────────────────
// gray300 (#A39E98) was too low-contrast on dark surfaces (#1A1917 / #242220).
// Dark-mode muted text now uses darkMuted (#C8C4BF) for readable contrast
// while staying visually secondary relative to primary white (#FFFFFF).

import 'package:flutter/material.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Core
  static const Color black      = Color(0xF2000000); // rgba(0,0,0,0.95)
  static const Color white      = Color(0xFFFFFFFF);
  static const Color blue       = Color(0xFF0075DE);
  static const Color blueActive = Color(0xFF005BAB);
  static const Color blueFocus  = Color(0xFF097FE8);

  // Warm neutrals — light
  static const Color warmWhite = Color(0xFFF6F5F4);
  static const Color warmDark  = Color(0xFF31302E);
  static const Color gray500   = Color(0xFF615D59); // muted text, light mode
  static const Color gray300   = Color(0xFFA39E98); // placeholder / hint

  // Warm neutrals — dark (higher luminance for legibility on dark surfaces)
  static const Color darkMuted = Color(0xFFC8C4BF); // muted text, dark mode

  // Badge
  static const Color badgeBlueBg   = Color(0xFFF2F9FF);
  static const Color badgeBlueText = Color(0xFF097FE8);

  // Semantic
  static const Color teal     = Color(0xFF2A9D99);
  static const Color green    = Color(0xFF1AAE39);
  static const Color orange   = Color(0xFFDD5B00);
  static const Color pink     = Color(0xFFFF64C8);
  static const Color deepNavy = Color(0xFF213183);

  // Borders
  static const Color borderLight = Color(0x1A000000); // rgba(0,0,0,0.10)
  static const Color borderInput = Color(0xFFDDDDDD);

  // Interactive states
  static const Color hoverBg   = Color(0x0D000000); // rgba(0,0,0,0.05)
  static const Color pressedBg = Color(0x1A000000); // rgba(0,0,0,0.10)

  // Dark-mode surfaces
  static const Color darkSurface = Color(0xFF1A1917);
  static const Color darkCard    = Color(0xFF242220);
  static const Color darkBorder  = Color(0x26FFFFFF); // rgba(255,255,255,0.15)

  // ── Legacy aliases (kept for backward compat — prefer canonical names) ──────
  static const Color notionBlue    = blue;
  static const Color notionBlack   = black;
  static const Color pureWhite     = white;
  static const Color warmGray500   = gray500;
  static const Color warmGray300   = gray300;
  static const Color focusBlue     = blueFocus;
  static const Color whisperBorder = borderLight;
  static const Color inputBorder   = borderInput;

  /// Muted text color that adapts to brightness.
  static Color mutedText({required bool dark}) => dark ? darkMuted : gray500;

  /// Border color that adapts to brightness.
  static Color border({required bool dark}) => dark ? darkBorder : borderLight;
}

// ─── Shadows ─────────────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  /// 4-layer soft card shadow (max opacity 0.04)
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 18,   offset: Offset(0, 4)),
    BoxShadow(color: Color(0x07000000), blurRadius: 7.85, offset: Offset(0, 2.025)),
    BoxShadow(color: Color(0x05000000), blurRadius: 2.93, offset: Offset(0, 0.8)),
    BoxShadow(color: Color(0x03000000), blurRadius: 1.04, offset: Offset(0, 0.175)),
  ];

  /// 5-layer deep shadow for modals (max opacity 0.05)
  static const List<BoxShadow> deep = [
    BoxShadow(color: Color(0x03000000), blurRadius: 3,  offset: Offset(0, 1)),
    BoxShadow(color: Color(0x05000000), blurRadius: 7,  offset: Offset(0, 3)),
    BoxShadow(color: Color(0x05000000), blurRadius: 15, offset: Offset(0, 7)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 28, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 52, offset: Offset(0, 23)),
  ];
}

// ─── Radii ───────────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();

  static const double micro       = 4;    // buttons, inputs
  static const double subtle      = 5;    // links, list items
  static const double standard    = 8;    // small cards, inline
  static const double comfortable = 12;   // standard cards
  static const double large       = 16;   // hero cards
  static const double pill        = 9999; // badges, pills
}

// ─── Typography ──────────────────────────────────────────────────────────────

class AppText {
  AppText._();

  static const String _family = 'Inter';
  static const String fontFamily = _family;

  static TextStyle display({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 64, fontWeight: FontWeight.w700,
        height: 1.00, letterSpacing: -2.125,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle displaySecondary({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 54, fontWeight: FontWeight.w700,
        height: 1.04, letterSpacing: -1.875,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle sectionHeading({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 48, fontWeight: FontWeight.w700,
        height: 1.00, letterSpacing: -1.5,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle subHeadingLarge({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 40, fontWeight: FontWeight.w700,
        height: 1.50,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle subHeading({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 26, fontWeight: FontWeight.w700,
        height: 1.23, letterSpacing: -0.625,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle cardTitle({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 22, fontWeight: FontWeight.w700,
        height: 1.27, letterSpacing: -0.25,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle bodyLarge({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 20, fontWeight: FontWeight.w600,
        height: 1.40, letterSpacing: -0.125,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle body({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w400,
        height: 1.50,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle bodyMedium({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w500,
        height: 1.50,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle bodySemibold({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w600,
        height: 1.50,
        color: dark ? AppColors.white : AppColors.black,
      );

  static TextStyle navButton({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 15, fontWeight: FontWeight.w600,
        height: 1.33,
        color: dark ? AppColors.white : AppColors.black,
      );

  /// 14px medium — section labels, field headings.
  static TextStyle caption({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w500,
        height: 1.43,
        color: AppColors.mutedText(dark: dark),
      );

  /// 14px regular — helper text, subtitles.
  static TextStyle captionLight({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w400,
        height: 1.43,
        color: AppColors.mutedText(dark: dark),
      );

  /// 12px badge label — color must be set by the caller.
  static TextStyle badge() => const TextStyle(
        fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w600,
        height: 1.33, letterSpacing: 0.125,
      );

  /// 12px micro text — timestamps, meta, hints.
  static TextStyle microLabel({bool dark = false}) => TextStyle(
        fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w400,
        height: 1.33, letterSpacing: 0.125,
        color: AppColors.mutedText(dark: dark),
      );
}

// ─── Spacing ─────────────────────────────────────────────────────────────────

class Sp {
  Sp._();
  static const double s2  = 2;
  static const double s4  = 4;
  static const double s6  = 6;
  static const double s8  = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;
}

// ─── Decoration helpers ───────────────────────────────────────────────────────

BoxDecoration surfaceCard({bool dark = false}) => BoxDecoration(
      color: dark ? AppColors.darkCard : AppColors.white,
      border: Border.all(color: AppColors.border(dark: dark)),
      borderRadius: BorderRadius.circular(AppRadius.comfortable),
      boxShadow: AppShadows.card,
    );

BoxDecoration surfaceHeroCard({bool dark = false}) => BoxDecoration(
      color: dark ? AppColors.darkCard : AppColors.white,
      border: Border.all(color: AppColors.border(dark: dark)),
      borderRadius: BorderRadius.circular(AppRadius.large),
      boxShadow: AppShadows.card,
    );

// ─── ThemeMode resolver ───────────────────────────────────────────────────────

ThemeMode resolveThemeMode(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

// ─── ThemeData builder ────────────────────────────────────────────────────────

ThemeData buildAppTheme({required bool dark}) {
  final bg          = dark ? AppColors.darkSurface : AppColors.warmWhite;
  final cardBg      = dark ? AppColors.darkCard    : AppColors.white;
  final borderColor = AppColors.border(dark: dark);
  final mutedColor  = AppColors.mutedText(dark: dark);

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: dark
        ? const ColorScheme.dark(
            primary:   AppColors.blue,
            onPrimary: AppColors.white,
            secondary: AppColors.teal,
            surface:   AppColors.darkCard,
            onSurface: AppColors.white,
            outline:   AppColors.darkBorder,
            error:     AppColors.orange,
          )
        : const ColorScheme.light(
            primary:   AppColors.blue,
            onPrimary: AppColors.white,
            secondary: AppColors.teal,
            surface:   AppColors.white,
            onSurface: AppColors.black,
            outline:   AppColors.borderLight,
            error:     AppColors.orange,
          ),

    cardTheme: CardThemeData(
      color: cardBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadius.comfortable),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF2A2825) : AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        borderSide: const BorderSide(color: AppColors.borderInput),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        borderSide: const BorderSide(color: AppColors.blueFocus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        borderSide: const BorderSide(color: AppColors.orange),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
        borderSide: const BorderSide(color: AppColors.orange, width: 2),
      ),
      labelStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 14,
        fontWeight: FontWeight.w500, color: mutedColor,
      ),
      hintStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 14,
        fontWeight: FontWeight.w400,
        color: dark ? AppColors.darkMuted : AppColors.gray300,
      ),
      helperStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 12,
        fontWeight: FontWeight.w400, color: mutedColor,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppColors.gray300;
          if (states.contains(WidgetState.pressed))  return AppColors.blueActive;
          return AppColors.blue;
        }),
        foregroundColor: WidgetStateProperty.all(AppColors.white),
        textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15, fontWeight: FontWeight.w600, height: 1.33,
        )),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.micro),
        )),
        elevation: WidgetStateProperty.all(0),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return AppColors.pressedBg;
          if (states.contains(WidgetState.hovered)) return AppColors.hoverBg;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.all(
          dark ? AppColors.white : AppColors.black,
        ),
        side: WidgetStateProperty.all(BorderSide(color: borderColor)),
        textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15, fontWeight: FontWeight.w600,
        )),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.micro),
        )),
        elevation: WidgetStateProperty.all(0),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(AppColors.blue),
        textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 14, fontWeight: FontWeight.w500,
        )),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.micro),
        )),
        overlayColor: WidgetStateProperty.all(
          AppColors.blue.withValues(alpha: 0.08),
        ),
        elevation: WidgetStateProperty.all(0),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: borderColor, thickness: 1, space: 1,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AppColors.darkCard : AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 16,
        fontWeight: FontWeight.w600,
        color: dark ? AppColors.white : AppColors.black,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: dark ? const Color(0xFF2A2825) : AppColors.warmWhite,
      labelStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 12,
        fontWeight: FontWeight.w600, letterSpacing: 0.125,
        color: dark ? AppColors.white : AppColors.black,
      ),
      side: BorderSide(color: borderColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: dark ? AppColors.darkCard : AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadius.comfortable),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: dark ? AppColors.darkCard : AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      textStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 14,
        fontWeight: FontWeight.w400,
        color: dark ? AppColors.white : AppColors.black,
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? AppColors.darkCard : AppColors.white,
      selectedIconTheme:
          const IconThemeData(color: AppColors.blue, size: 20),
      unselectedIconTheme:
          IconThemeData(color: mutedColor, size: 20),
      selectedLabelTextStyle: const TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.blue, letterSpacing: 0.125,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 12,
        fontWeight: FontWeight.w500,
        color: mutedColor, letterSpacing: 0.125,
      ),
      indicatorColor: AppColors.blue.withValues(alpha: 0.10),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.subtle),
      ),
      elevation: 0,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? AppColors.warmDark : AppColors.black,
      contentTextStyle: const TextStyle(
        fontFamily: AppText.fontFamily, fontSize: 14,
        fontWeight: FontWeight.w400, color: AppColors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.micro),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    textTheme: TextTheme(
      displayLarge:   AppText.display(dark: dark),
      displayMedium:  AppText.displaySecondary(dark: dark),
      displaySmall:   AppText.subHeadingLarge(dark: dark),
      headlineLarge:  AppText.sectionHeading(dark: dark),
      headlineMedium: AppText.subHeading(dark: dark),
      headlineSmall:  AppText.cardTitle(dark: dark),
      titleLarge:     AppText.cardTitle(dark: dark),
      titleMedium:    AppText.bodySemibold(dark: dark),
      titleSmall:     AppText.bodyMedium(dark: dark),
      bodyLarge:      AppText.bodyLarge(dark: dark),
      bodyMedium:     AppText.body(dark: dark),
      bodySmall:      AppText.captionLight(dark: dark),
      labelLarge:     AppText.navButton(dark: dark),
      labelMedium:    AppText.caption(dark: dark),
      labelSmall:     AppText.badge(),
    ),
  );
}
