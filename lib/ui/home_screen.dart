import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/alert_event.dart';
import '../state/app_state.dart';
import '../services/theme_service.dart';
import 'widgets/alerts_card.dart';
import 'widgets/logs_card.dart';
import 'widgets/monitoring_health_card.dart';
import 'widgets/queries_card.dart';
import 'widgets/settings_card.dart';

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WindowListener, TrayListener {
  String _lastAlertKey = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppState>(
      builder: (context, appState, _) {
        _showAlertSnackIfNeeded(context, appState.lastAlert);

        if (appState.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.initError != null) {
          return _ErrorScreen(error: appState.initError!, onRetry: appState.retryInit);
        }

        final sidebarBg = dark ? AppColors.darkCard : AppColors.pureWhite;
        final contentBg = dark ? AppColors.darkSurface : AppColors.warmWhite;
        final borderColor = dark ? AppColors.darkBorder : AppColors.whisperBorder;

        return Scaffold(
          backgroundColor: contentBg,
          body: Row(
            children: [
              // ── Sidebar ──────────────────────────────────────────────
              SizedBox(
                width: 200,
                child: Container(
                  color: sidebarBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand mark
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Image.asset('assets/icon.png', width: 22, height: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Redmine',
                              style: AppText.bodySemibold(dark: dark),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 1, color: borderColor),
                      const SizedBox(height: 8),
                      // Nav items
                      _NavItem(
                        icon: Icons.podcasts_outlined,
                        activeIcon: Icons.podcasts,
                        label: 'Monitoração',
                        selected: _selectedIndex == 0,
                        dark: dark,
                        onTap: () => setState(() => _selectedIndex = 0),
                      ),
                      _NavItem(
                        icon: Icons.query_stats_outlined,
                        activeIcon: Icons.query_stats,
                        label: 'Consultas',
                        selected: _selectedIndex == 1,
                        dark: dark,
                        onTap: () => setState(() => _selectedIndex = 1),
                      ),
                      _NavItem(
                        icon: Icons.tune_outlined,
                        activeIcon: Icons.tune,
                        label: 'Configuração',
                        selected: _selectedIndex == 2,
                        dark: dark,
                        onTap: () => setState(() => _selectedIndex = 2),
                      ),
                      _NavItem(
                        icon: Icons.receipt_long_outlined,
                        activeIcon: Icons.receipt_long,
                        label: 'Logs',
                        selected: _selectedIndex == 3,
                        dark: dark,
                        onTap: () => setState(() => _selectedIndex = 3),
                      ),
                    ],
                  ),
                ),
              ),

              // Divider
              Container(width: 1, color: borderColor),

              // ── Main área ────────────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    // Top header bar
                    Container(
                      height: 56,
                      color: sidebarBg,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (appState.settings.accountName != null &&
                              appState.settings.accountName!.isNotEmpty) ...[
                            Icon(Icons.account_circle_outlined,
                                size: 16,
                                color: dark ? AppColors.darkMuted : AppColors.warmDark),
                            const SizedBox(width: 6),
                            Text(
                              appState.settings.accountName!,
                              style: AppText.caption(dark: dark).copyWith(
                                color: dark ? AppColors.darkMuted : AppColors.warmDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(height: 1, color: borderColor),

                    // Content
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: const [
                          _MonitoringTab(),
                          _QueriesTab(),
                          _SettingsTab(),
                          _LogsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAlertSnackIfNeeded(BuildContext context, AlertEvent? alert) {
    if (alert == null) return;
    final key = '${alert.queryId}-${alert.createdAt.toIso8601String()}';
    if (key == _lastAlertKey) return;
    _lastAlertKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final diffPrefix = alert.diff > 0 ? '+' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${alert.queryName}: ${alert.previousCount} → ${alert.currentCount} ($diffPrefix${alert.diff})',
          ),
        ),
      );
    });
  }
}

// ─── Nav item ────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.selected;
    final inactiveColor = widget.dark ? AppColors.darkMuted : AppColors.warmDark;
    final iconColor = isActive
        ? AppColors.notionBlue
        : _hovered
            ? (widget.dark ? AppColors.pureWhite : AppColors.notionBlack)
            : inactiveColor;
    final textColor = isActive
        ? AppColors.notionBlue
        : _hovered
            ? (widget.dark ? AppColors.pureWhite : AppColors.notionBlack)
            : inactiveColor;
    final bgColor = isActive
        ? AppColors.notionBlue.withValues(alpha: 0.08)
        : _hovered
            ? AppColors.hoverBg
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.subtle),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? widget.activeIcon : widget.icon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: AppText.navButton(dark: widget.dark).copyWith(
                  color: textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Error screen ─────────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(Sp.s32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_outlined,
                    size: 40, color: AppColors.orange),
                const SizedBox(height: Sp.s16),
                Text('Falha ao inicializar',
                    style: AppText.cardTitle(dark: dark)),
                const SizedBox(height: Sp.s8),
                Text(error,
                    textAlign: TextAlign.center,
                    style: AppText.captionLight(dark: dark)),
                const SizedBox(height: Sp.s24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tab contents ─────────────────────────────────────────────────────────────

class _MonitoringTab extends StatelessWidget {
  const _MonitoringTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.s24),
      children: const [
        _HeroHeader(),
        SizedBox(height: Sp.s16),
        AlertsCard(),
      ],
    );
  }
}

class _QueriesTab extends StatelessWidget {
  const _QueriesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.s24),
      children: const [QueriesCard()],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.s24),
      children: const [SettingsCard()],
    );
  }
}

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.s24),
      children: const [
        MonitoringHealthCard(),
        SizedBox(height: Sp.s16),
        LogsCard(),
      ],
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeQueries = appState.queries.where((q) => q.enabled).length;

    return Container(
      padding: const EdgeInsets.all(Sp.s24),
      decoration: surfaceHeroCard(dark: dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appState.monitoring
                          ? 'Monitoração ativa'
                          : 'Monitoração pausada',
                      style: AppText.cardTitle(dark: dark),
                    ),
                    const SizedBox(height: Sp.s4),
                    Text(
                      appState.monitoring
                          ? 'Verificando consultas periodicamente.'
                          : 'Clique para retomar o monitoramento.',
                      style: AppText.captionLight(dark: dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.s16),
              _NotionSwitch(
                value: appState.monitoring,
                onChanged: (_) => appState.toggleMonitoring(),
              ),
            ],
          ),
          const SizedBox(height: Sp.s16),
          Wrap(
            spacing: Sp.s8,
            runSpacing: Sp.s8,
            children: [
              _MetricPill(label: 'Consultas ativas', value: '$activeQueries'),
              _MetricPill(label: 'Alertas', value: '${appState.alerts.length}'),
              _MetricPill(
                  label: 'Logs',
                  value: '${appState.monitorLogs.length}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotionSwitch extends StatelessWidget {
  const _NotionSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          color: value ? AppColors.notionBlue : AppColors.warmGray300,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding: const EdgeInsets.all(3),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.s8, vertical: Sp.s4),
      decoration: BoxDecoration(
        color: AppColors.badgeBlueBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: RichText(
        text: TextSpan(
          style: AppText.badge().copyWith(
            color: AppColors.warmGray500,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: AppText.badge()
                  .copyWith(color: AppColors.badgeBlueText),
            ),
          ],
        ),
      ),
    );
  }
}
