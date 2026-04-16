import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/alert_event.dart';
import '../../services/notifications/notification_template_service.dart';
import '../../state/app_state.dart';

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: state.alerts.isEmpty ? null : state.clearAlerts,
                  child: const Text('Limpar tudo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state.alerts.isEmpty)
              const Text('Sem alertas ainda.')
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final diff = alert.diff;
    final isIncrease = diff > 0;
    final isDecrease = diff < 0;

    final templateService = NotificationTemplateService();
    final title = templateService.render(settings.notificationTitleTemplate, alert);
    final body = templateService.render(settings.notificationBodyTemplate, alert);

    final diffColor = isIncrease
        ? Colors.green
        : isDecrease
            ? Colors.red
            : scheme.outline;

    final diffPrefix = diff > 0 ? '+' : '';

    return Opacity(
      opacity: alert.isRead ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: alert.isRead
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : scheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: alert.isRead
              ? null
              : Border.all(
                  color: scheme.primary.withValues(alpha: 0.25),
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
                color: alert.isRead ? scheme.outline : scheme.primary,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: alert.isRead ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$diffPrefix$diff',
                          style: theme.textTheme.labelSmall?.copyWith(color: diffColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmtDate(alert.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Abrir no Redmine',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => _openLink(context, alert.directUrl),
                ),
                if (!alert.isRead)
                  IconButton(
                    tooltip: 'Marcar como lida',
                    icon: const Icon(Icons.mark_email_read_outlined, size: 20),
                    onPressed: () => state.markAlertRead(alert.id!),
                  ),
                IconButton(
                  tooltip: 'Excluir',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => state.deleteAlert(alert.id!),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel abrir o link.')),
      );
    }
  }

  String _fmtDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
