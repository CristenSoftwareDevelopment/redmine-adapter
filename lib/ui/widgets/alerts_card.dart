import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alert_event.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';

/// "Alertas recentes" panel. Each row shows the stored title/body, so the
/// text matches the OS notification exactly.
class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: const Text('Alertas recentes'),
            trailing: TextButton(
              onPressed: state.alerts.isEmpty ? null : state.clearAlerts,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger(dark: dark)),
              child: const Text('Limpar'),
            ),
          ),
          if (state.alerts.isEmpty)
            const EmptyState(icon: Icons.notifications_none, text: 'Sem alertas ainda.')
          else
            for (final alert in state.alerts) _AlertRow(alert: alert),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final AlertEvent alert;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final (title, body) = state.alertText(alert);
    final diff = alert.diff;

    return ListRow(
      leading: IconBox(icon: Icons.notifications_none, highlighted: !alert.isRead),
      title: Text(title),
      meta: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(body),
            Tag('${diff > 0 ? '+' : ''}$diff', tone: diff > 0 ? TagTone.green : TagTone.amber),
          ],
        ),
        Text('${fmtDateTime(alert.createdAt)} · ${alert.isRead ? 'Lido' : 'Não lido'}'),
      ],
      actions: [
        IconBtn(
          compact: true,
          icon: Icons.open_in_new,
          tooltip: 'Abrir no Redmine',
          onPressed: () => openRedmineLink(context, alert.directUrl),
        ),
        if (!alert.isRead)
          IconBtn(
            compact: true,
            icon: Icons.check,
            tooltip: 'Marcar como lido',
            onPressed: () => state.markAlertRead(alert.id!),
          ),
        IconBtn(
          compact: true,
          icon: Icons.delete_outline,
          tooltip: 'Excluir',
          onPressed: () => state.deleteAlert(alert.id!),
        ),
      ],
    );
  }
}
