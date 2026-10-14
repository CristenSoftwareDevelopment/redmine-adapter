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
