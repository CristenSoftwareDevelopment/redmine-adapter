import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/query_health.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';

class MonitoringHealthCard extends StatelessWidget {
  const MonitoringHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final health = state.queryHealth;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: surfaceCard(dark: dark),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saúde da monitoração',
            style: AppText.cardTitle(dark: dark),
          ),
          const SizedBox(height: Sp.s12),
          if (health.isEmpty)
            Text('Sem consultas cadastradas.', style: AppText.captionLight(dark: dark))
          else
            ...health.map((item) => _HealthTile(item: item)),
        ],
      ),
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.item});

  final QueryHealth item;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _statusColor(item.lastStatus);
    final borderColor = dark ? AppColors.darkBorder : AppColors.whisperBorder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.s8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2825) : AppColors.warmWhite,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppRadius.standard),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Icon(Icons.circle, color: color, size: 8),
                      ),
                      const SizedBox(width: Sp.s8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.queryName,
                              style: AppText.bodyMedium(dark: dark).copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Status: ', style: AppText.caption(dark: dark)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    item.lastStatus.toUpperCase(),
                                    style: AppText.badge().copyWith(color: color),
                                  ),
                                ),
                                Text(' \u2022 Ativa: ${item.enabled ? 'sim' : 'não'}', style: AppText.caption(dark: dark)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Última execução: ${_fmtDate(item.lastCheckedAt)} \u2022 Último total: ${item.lastCount ?? '-'}',
                              style: AppText.microLabel(dark: dark),
                            ),
                            if (item.lastMessage != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.microLabel(dark: dark),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'error':
        return AppColors.orange;
      case 'warn':
        return const Color(0xFFDD9900);
      case 'alert':
        return const Color(0xFF7B5EA7);
      case 'success':
        return AppColors.green;
      default:
        return AppColors.notionBlue;
    }
  }

  String _fmtDate(DateTime? date) {
    if (date == null) {
      return '-';
    }
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
