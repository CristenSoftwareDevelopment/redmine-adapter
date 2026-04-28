// Re-export shim — kept for backwards compatibility during migration.
// All symbols now live in lib/services/theme_service.dart.
// Prefer importing theme_service.dart directly in new code.
export '../../services/theme_service.dart';

// Legacy aliases so old code referencing NotionColors / NotionText /
// NotionRadius / NotionShadows / notionCard / notionHeroCard / buildNotionTheme
// keeps compiling without changes.
import 'package:flutter/material.dart';
import '../../services/theme_service.dart';

// ignore_for_file: non_constant_identifier_names

typedef NotionColors  = AppColors;
typedef NotionText    = AppText;
typedef NotionRadius  = AppRadius;
typedef NotionShadows = AppShadows;

BoxDecoration notionCard({bool dark = false})     => surfaceCard(dark: dark);
BoxDecoration notionHeroCard({bool dark = false}) => surfaceHeroCard(dark: dark);
ThemeData buildNotionTheme({required bool dark})  => buildAppTheme(dark: dark);
