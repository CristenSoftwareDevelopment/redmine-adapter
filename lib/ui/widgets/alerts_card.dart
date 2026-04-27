import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/alert_event.dart';
import '../../services/notifications/notification_template_service.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: surfaceCard(dark: dark),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Alertas recentes',
                    style: AppText.cardTitle(dark: dark),
                  ),
                ),
                TextButton(
                  onPressed: state.alerts.isEmpty ? null : state.clearAlerts,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.notionBlue,
                  ),
                  child: const Text('Limpar tudo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state.alerts.isEmpty)
              Text(
                'Sem alertas ainda.',
                style: AppText.captionLight(dark: dark),
              )
            else
              ...state.alerts.map(
                (alert) => _AlertTile(
                  alert: alert,
                  settings: state.settings,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.settings});

  final AlertEvent alert;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final diff = alert.diff;
    final isIncrease = diff > 0;
    final isDecrease = diff < 0;

    final templateService = NotificationTemplateService();
    final title = templateService.render(settings.notificationTitleTemplate, alert);
    final body = templateService.render(settings.notificationBodyTemplate, alert);

    final diffColor = isIncrease
        ? AppColors.green
        : isDecrease
            ? AppColors.orange
            : AppColors.warmGray500;

    final diffPrefix = diff > 0 ? '+' : '';

    return Opacity(
      opacity: alert.isRead ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.s8),
        padding: const EdgeInsets.fromLTRB(Sp.s12, 10, Sp.s8, 10),
        decoration: BoxDecoration(
          color: alert.isRead
              ? (dark ? const Color(0xFF2A2825) : AppColors.warmWhite)
              : AppColors.notionBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.standard),
          border: Border.all(
            color: alert.isRead
                ? (dark ? AppColors.darkBorder : AppColors.whisperBorder)
                : AppColors.notionBlue.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Icon(
                alert.isRead
                    ? Icons.notifications_outlined
                    : Icons.notifications_active_outlined,
                color: alert.isRead ? AppColors.warmGray500 : AppColors.notionBlue,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.bodyMedium(dark: dark).copyWith(
                      fontWeight: alert.isRead ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: AppText.captionLight(dark: dark)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '$diffPrefix$diff',
                          style: AppText.badge().copyWith(color: diffColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmtDate(alert.createdAt),
                        style: AppText.microLabel(dark: dark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIcon(
                  tooltip: 'Abrir no Redmine',
                  icon: Icons.open_in_new,
                  onTap: () => _openLink(context, alert.directUrl),
                ),
                if (!alert.isRead) ...[
                  const SizedBox(height: 4),
                  _ActionIcon(
                    tooltip: 'Marcar como lida',
                    icon: Icons.mark_email_read_outlined,
                    onTap: () => state.markAlertRead(alert.id!),
                  ),
                ],
                const SizedBox(height: 4),
                _ActionIcon(
                  tooltip: 'Excluir',
                  icon: Icons.delete_outline,
                  onTap: () => state.deleteAlert(alert.id!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String link) async {
    final baseUrl = context.read<AppState>().settings.baseUrl;
    final fullLink = _buildFullUrl(baseUrl, link);
    final uri = Uri.tryParse(fullLink);
    if (uri == null || !uri.hasScheme) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }

  String _buildFullUrl(String baseUrl, String link) {
    if (link.startsWith('http://') || link.startsWith('https://')) return link;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final path = link.startsWith('/') ? link : '/$link';
    return '$base$path';
  }

  String _fmtDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.micro),
        hoverColor: AppColors.hoverBg,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.warmGray500,
          ),
        ),
      ),
    );
  }
}
