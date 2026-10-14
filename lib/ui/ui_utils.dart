import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/redmine_api_service.dart';
import '../state/app_state.dart';

/// `dd-MM-yyyy HH:mm:ss` in local time, or `-` when null.
String fmtDateTime(DateTime? date) {
  if (date == null) return '-';
  final l = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}-${two(l.month)}-${l.year.toString().padLeft(4, '0')} '
      '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

/// Opens a Redmine path (or absolute URL) in the external browser.
Future<void> openRedmineLink(BuildContext context, String link) async {
  final baseUrl = context.read<AppState>().settings.baseUrl;
  final uri = Uri.tryParse(RedmineApiService.absoluteUrl(baseUrl, link));
  if (uri == null || !uri.hasScheme) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o link.')),
    );
  }
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Lowercase without accents, for search: `searchKey('André') == 'andre'`.
String searchKey(String text) => text.toLowerCase().split('').map((c) => _accents[c] ?? c).join();

/// Redmine date (`YYYY-MM-DD`) as `dd-MM-yyyy`, or `-`.
String fmtDate(String? ymd) {
  final d = DateTime.tryParse(ymd ?? '');
  if (d == null) return '-';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)}-${d.year}';
}

// Dark enough for white text in both themes.
const _labelPalette = [
  Color(0xFFB7791F),
  Color(0xFF0E7490),
  Color(0xFFC2410C),
  Color(0xFF6D28D9),
  Color(0xFF15803D),
  Color(0xFF1D4ED8),
  Color(0xFFBE123C),
];

/// Stable color for a text (tracker, user…), so the same name keeps its color.
Color labelColor(String text) =>
    _labelPalette[text.codeUnits.fold(0, (a, b) => a + b) % _labelPalette.length];

/// "André Cristen" → "AC".
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// Circle with the person's initials; full name in the tooltip.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 24});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(name);
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: labelColor(name),
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
