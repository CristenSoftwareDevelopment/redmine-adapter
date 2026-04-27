import 'package:flutter/material.dart';

/// Linear-inspired design system constants.
/// Based on DESIGN.md specification.
class LinearDesign {
  LinearDesign._();

  // ============== COLORS ==============

  /// Marketing Black - deepest background
  static const marketingBlack = Color(0xFF08090a);

  /// Panel Dark - sidebar/panel backgrounds
  static const panelDark = Color(0xFF0f1011);

  /// Level 3 Surface - elevated surfaces, cards
  static const level3Surface = Color(0xFF191a1b);

  /// Secondary Surface - lightest dark surface, hover states
  static const secondarySurface = Color(0xFF28282c);

  // Text Colors
  static const primaryText = Color(0xFFf7f8f8); // Near-white
  static const secondaryText = Color(0xFFd0d6e0); // Silver-gray
  static const tertiaryText = Color(0xFF8a8f98); // Muted gray
  static const quaternaryText = Color(0xFF62666d); // Subtle gray

  // Brand & Accent
  static const brandIndigo = Color(0xFF5e6ad2);
  static const accentViolet = Color(0xFF7170ff);
  static const accentHover = Color(0xFF828fff);
  static const securityLavender = Color(0xFF7a7fad);

  // Status Colors
  static const successGreen = Color(0xFF27a644);
  static const emerald = Color(0xFF10b981);
  static const errorRed = Color(0xFFdc2626);
  static const warningOrange = Color(0xFFf59e0b);

  // Border Colors
  static const borderPrimary = Color(0xFF23252a);
  static const borderSecondary = Color(0xFF34343a);
  static const borderTertiary = Color(0xFF3e3e44);
  static const borderSubtle = Color(0x0dffffff); // rgba(255,255,255,0.05)
  static const borderStandard = Color(0x14ffffff); // rgba(255,255,255,0.08)

  // Light Mode
  static const lightBackground = Color(0xFFf7f8f8);
  static const lightSurface = Color(0xFFf3f4f5);
  static const lightBorder = Color(0xFFd0d6e0);

  // Overlay
  static const overlayPrimary = Color(0xD9000000); // rgba(0,0,0,0.85)

  // ============== OPACITY VALUES ==============

  /// Button backgrounds: near-zero opacity
  static const btnGhostBg = Color(0x05ffffff); // rgba(255,255,255,0.02)
  static const btnSubtleBg = Color(0x0affffff); // rgba(255,255,255,0.04)
  static const btnHoverBg = Color(0x0dffffff); // rgba(255,255,255,0.05)

  /// Card backgrounds
  static const cardGhostBg = Color(0x05ffffff);
  static const cardHoverBg = Color(0x0affffff);
  static const cardStandardBg = Color(0x0dffffff);

  /// Light mode card
  static const lightCardBg = Color(0xffffffff);

  // ============== BORDER RADIUS ==============

  static const radiusMicro = 2.0;
  static const radiusStandard = 4.0;
  static const radiusComfortable = 6.0;
  static const radiusCard = 8.0;
  static const radiusPanel = 12.0;
  static const radiusLarge = 22.0;
  static const radiusPill = 9999.0;

  // ============== SPACING ==============

  static const space1 = 1.0;
  static const space2 = 2.0;
  static const space4 = 4.0;
  static const space6 = 6.0;
  static const space7 = 7.0;
  static const space8 = 8.0;
  static const space10 = 10.0;
  static const space11 = 11.0;
  static const space12 = 12.0;
  static const space14 = 14.0;
  static const space16 = 16.0;
  static const space18 = 18.0;
  static const space19 = 19.0;
  static const space20 = 20.0;
  static const space22 = 22.0;
  static const space24 = 24.0;
  static const space28 = 28.0;
  static const space32 = 32.0;

  // ============== FONT WEIGHTS ==============

  static const fontLight = FontWeight.w300;
  static const fontRegular = FontWeight.w400;
  static const fontMedium = FontWeight.w500; // Linear's signature weight (was w510, but using w500 for Flutter)
  static const fontSemibold = FontWeight.w600;

  // ============== SHADOWS ==============

  /// Subtle shadow for toolbar buttons
  static List<BoxShadow> get subtleShadow => const [
        BoxShadow(
          color: Color(0x08000000),
          offset: Offset(0, 1.2),
          blurRadius: 0,
        ),
      ];

  /// Ring shadow for emphasis
  static List<BoxShadow> get ringShadow => const [
        BoxShadow(
          color: Color(0x33000000),
          offset: Offset(0, 0),
          blurRadius: 0,
        ),
      ];

  /// Elevated shadow for floating elements
  static List<BoxShadow> get elevatedShadow => const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 2),
          blurRadius: 4,
        ),
      ];

  /// Dialog shadow
  static List<BoxShadow> get dialogShadow => const [
        BoxShadow(
          color: Color(0x00000000),
          offset: Offset(0, 8),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Color(0x03ffffff),
          offset: Offset(0, 5),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Color(0x0affffff),
          offset: Offset(0, 3),
          blurRadius: 2,
        ),
        BoxShadow(
          color: Color(0x12ffffff),
          offset: Offset(0, 1),
          blurRadius: 1,
        ),
        BoxShadow(
          color: Color(0x14ffffff),
          offset: Offset(0, 0),
          blurRadius: 1,
        ),
      ];

  // ============== HELPER METHODS ==============

  /// Get color scheme for dark mode
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: brandIndigo,
        onPrimary: primaryText,
        secondary: accentViolet,
        onSecondary: primaryText,
        surface: level3Surface,
        onSurface: primaryText,
        error: errorRed,
        onError: primaryText,
        outline: borderSecondary,
      );

  /// Get color scheme for light mode
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: brandIndigo,
        onPrimary: lightBackground,
        secondary: accentViolet,
        onSecondary: lightBackground,
        surface: lightSurface,
        onSurface: marketingBlack,
        error: errorRed,
        onError: lightBackground,
        outline: lightBorder,
      );
}

/// Extension for easy access to Linear design tokens
extension LinearDesignExtension on BuildContext {
  ColorScheme get linearColorScheme =>
      Theme.of(this).brightness == Brightness.dark
          ? LinearDesign.darkColorScheme
          : LinearDesign.lightColorScheme;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

/// Custom decoration helpers for Linear-style components
class LinearDecorations {
  LinearDecorations._();

  static BoxDecoration card({bool isDark = true}) => BoxDecoration(
        color: isDark
            ? LinearDesign.cardGhostBg
            : LinearDesign.lightCardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LinearDesign.radiusCard),
        border: Border.all(
          color: LinearDesign.borderStandard,
          width: 1,
        ),
      );

  static BoxDecoration cardHover({bool isDark = true}) => BoxDecoration(
        color: isDark
            ? LinearDesign.cardHoverBg
            : LinearDesign.lightCardBg,
        borderRadius: BorderRadius.circular(LinearDesign.radiusCard),
        border: Border.all(
          color: LinearDesign.borderStandard,
          width: 1,
        ),
      );

  static BoxDecoration ghostButton({bool isDark = true}) => BoxDecoration(
        color: LinearDesign.btnGhostBg,
        borderRadius: BorderRadius.circular(LinearDesign.radiusComfortable),
        border: Border.all(
          color: LinearDesign.borderPrimary,
          width: 1,
        ),
      );

  static BoxDecoration primaryButton() => BoxDecoration(
        color: LinearDesign.brandIndigo,
        borderRadius: BorderRadius.circular(LinearDesign.radiusComfortable),
      );

  static BoxDecoration pill({bool isDark = true}) => BoxDecoration(
        color: isDark ? Colors.transparent : Colors.transparent,
        borderRadius: BorderRadius.circular(LinearDesign.radiusPill),
        border: Border.all(
          color: isDark ? LinearDesign.borderPrimary : LinearDesign.lightBorder,
          width: 1,
        ),
      );
}

/// Text styles following Linear's typography system
class LinearTextStyles {
  LinearTextStyles._();

  static TextStyle display({
    double fontSize = 48,
    FontWeight fontWeight = LinearDesign.fontMedium,
    Color color = LinearDesign.primaryText,
    double letterSpacing = -1.056,
  }) =>
      TextStyle(
        fontFamily: 'Inter Variable',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.0,
      );

  static TextStyle heading({
    double fontSize = 20,
    FontWeight fontWeight = LinearDesign.fontSemibold,
    Color color = LinearDesign.primaryText,
    double letterSpacing = -0.24,
  }) =>
      TextStyle(
        fontFamily: 'Inter Variable',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.33,
      );

  static TextStyle body({
    double fontSize = 16,
    FontWeight fontWeight = LinearDesign.fontRegular,
    Color color = LinearDesign.secondaryText,
  }) =>
      TextStyle(
        fontFamily: 'Inter Variable',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.5,
      );

  static TextStyle label({
    double fontSize = 12,
    FontWeight fontWeight = LinearDesign.fontMedium,
    Color color = LinearDesign.quaternaryText,
  }) =>
      TextStyle(
        fontFamily: 'Inter Variable',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.4,
      );
}

/// Status colors helper
class StatusColors {
  StatusColors._();

  static Color fromLevel(String level, {bool isDark = true}) {
    switch (level) {
      case 'error':
        return LinearDesign.errorRed;
      case 'warn':
      case 'warning':
        return LinearDesign.warningOrange;
      case 'alert':
      case 'success':
        return isDark ? LinearDesign.emerald : LinearDesign.successGreen;
      case 'info':
        return LinearDesign.accentViolet;
      default:
        return isDark ? LinearDesign.tertiaryText : LinearDesign.borderSecondary;
    }
  }
}