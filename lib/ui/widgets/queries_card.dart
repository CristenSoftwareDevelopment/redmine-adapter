import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/monitored_query.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';
import 'query_form_dialog.dart';

class QueriesCard extends StatefulWidget {
  const QueriesCard({super.key});

  @override
  State<QueriesCard> createState() => _QueriesCardState();
}

class _QueriesCardState extends State<QueriesCard> {
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() => _filter = _filterController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final filtered = state.queries
        .where((q) => q.name.toLowerCase().contains(_filter))
        .toList();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: surfaceCard(dark: dark),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Consultas monitoradas',
                  style: AppText.cardTitle(dark: dark),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Nova'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.notionBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filterController,
            decoration: InputDecoration(
              hintText: 'Filtrar por nome...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _filter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _filterController.clear(),
                    )
                  : null,
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          if (state.queries.isEmpty)
            Text('Nenhuma consulta cadastrada ainda.', style: AppText.body(dark: dark))
          else if (filtered.isEmpty)
            Text('Nenhuma consulta encontrada para o filtro.', style: AppText.body(dark: dark))
          else
            ...filtered.map((query) => _QueryTile(query: query)),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, [MonitoredQuery? query]) async {
    final state = context.read<AppState>();
    final result = await showDialog<MonitoredQuery>(
      context: context,
      builder: (_) => QueryFormDialog(initial: query),
    );

    if (result == null) return;

    if (result.id == null) {
      await state.addQuery(result);
    } else {
      await state.updateQuery(result);
    }
  }
}

class _QueryTile extends StatelessWidget {
  const _QueryTile({required this.query});

  final MonitoredQuery query;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: Sp.s8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2825) : AppColors.warmWhite,
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.whisperBorder,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        query.name,
                        style: AppText.bodySemibold(dark: dark),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusBadge(enabled: query.enabled),
                    const SizedBox(width: 4),
                    _AlertOnBadge(alertOn: query.alertOn),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 13, color: AppColors.warmGray500),
                    const SizedBox(width: 4),
                    Text(
                      'Última verificação: ${_fmtDate(query.lastCheckedAt)}',
                      style: AppText.microLabel(dark: dark),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.tag, size: 13, color: AppColors.warmGray500),
                    const SizedBox(width: 4),
                    Text(
                      'Contagem atual: ${query.lastCount ?? '-'}',
                      style: AppText.microLabel(dark: dark),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.timer_outlined, size: 13, color: AppColors.warmGray500),
                    const SizedBox(width: 4),
                    Text(
                      'A cada ${query.pollSeconds}s',
                      style: AppText.microLabel(dark: dark),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Ações compactas
          Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Abrir consulta no Redmine',
                  child: InkWell(
                    onTap: () => _openLink(context, query.directUrl),
                    borderRadius: BorderRadius.circular(AppRadius.micro),
                    child: const Padding(
                      padding: EdgeInsets.all(6.0),
                      child: Icon(Icons.open_in_new, size: 18, color: AppColors.warmGray500),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Theme(
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: AppColors.warmGray500, size: 18),
                  ),
                  child: PopupMenuButton<_QueryAction>(
                    tooltip: 'Mais ações',
                    icon: const Icon(Icons.more_vert, size: 18, color: AppColors.warmGray500),
                    onSelected: (action) => _handleAction(context, state, action),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _QueryAction.runNow,
                        enabled: query.id != null,
                        child: const ListTile(
                          leading: Icon(Icons.play_circle_outline),
                          title: Text('Executar agora'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: _QueryAction.toggle,
                        child: ListTile(
                          leading: Icon(query.enabled
                              ? Icons.pause_circle_outline
                              : Icons.play_arrow_outlined),
                          title: Text(query.enabled ? 'Pausar' : 'Ativar'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _QueryAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _QueryAction.duplicate,
                        child: ListTile(
                          leading: Icon(Icons.copy_outlined),
                          title: Text('Duplicar'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _QueryAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Excluir'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, AppState state, _QueryAction action) async {
    switch (action) {
      case _QueryAction.runNow:
        if (query.id != null) await state.runQueryNow(query.id!);
      case _QueryAction.toggle:
        await state.toggleQueryEnabled(query);
      case _QueryAction.duplicate:
        await state.duplicateQuery(query);
      case _QueryAction.edit:
        if (!context.mounted) return;
        final result = await showDialog<MonitoredQuery>(
          context: context,
          builder: (_) => QueryFormDialog(initial: query),
        );
        if (result != null) await state.updateQuery(result);
      case _QueryAction.delete:
        if (query.id != null) await state.deleteQuery(query.id!);
    }
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

  String _fmtDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

enum _QueryAction { runNow, toggle, edit, duplicate, delete }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.green.withValues(alpha: 0.12)
            : AppColors.warmGray300.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        enabled ? 'Ativa' : 'Pausada',
        style: AppText.badge().copyWith(
          color: enabled ? AppColors.green : AppColors.warmGray500,
        ),
      ),
    );
  }
}

class _AlertOnBadge extends StatelessWidget {
  const _AlertOnBadge({required this.alertOn});
  final String alertOn;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (alertOn) {
      'increase' => ('↑ Aumento', AppColors.green),
      'decrease' => ('↓ Diminuição', AppColors.orange),
      _ => ('↕ Qualquer', AppColors.notionBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: AppText.badge().copyWith(color: color)),
    );
  }
}
