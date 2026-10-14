import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import '../services/theme_service.dart';
import 'board/board_view.dart';
import 'onboarding_screen.dart';
import 'teams/teams_view.dart';
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

class _HomeScreenState extends State<HomeScreen> with WindowListener, TrayListener {
  String _lastAlertKey = '';
  _Page _page = _Page.monitoring;

  /// Pinned query shown as a board over the regular pages, if any.
  int? _boardQueryId;

  /// User choice; null = automatic (collapsed on narrow windows).
  bool? _collapsed;

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
        _showAlertSnackIfNeeded(context, appState);

        if (appState.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.initError != null) {
          return _ErrorScreen(error: appState.initError!, onRetry: appState.retryInit);
        }

        final collapsed = _collapsed ?? MediaQuery.sizeOf(context).width < 900;
        final unreadAlerts = appState.alerts.where((a) => !a.isRead).length;
        final failedQueries = appState.queries.where((q) => q.lastError != null).length;
        final pinned = appState.queries.where((q) => q.pinned && q.id != null).toList();
        final board = pinned.where((q) => q.id == _boardQueryId).firstOrNull;
        if (board == null) _boardQueryId = null; // board was unpinned or deleted
        final sidebarBg = dark ? AppColors.darkCard : AppColors.pureWhite;
        final contentBg = dark ? AppColors.darkSurface : AppColors.warmWhite;
        final borderColor = dark ? AppColors.darkBorder : AppColors.whisperBorder;
        final hasConfiguredAccount = appState.settings.baseUrl.trim().isNotEmpty &&
            appState.settings.apiKey.trim().isNotEmpty;
        final accountLabel = (appState.settings.accountName?.trim().isNotEmpty ?? false)
            ? appState.settings.accountName!.trim()
            : 'Conta conectada';

        return Scaffold(
          backgroundColor: contentBg,
          body: Row(
            children: [
              // ── Sidebar ──────────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: collapsed ? 64 : 232,
                color: sidebarBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark + collapse toggle (adapts while the width animates)
                    SizedBox(
                      height: 56,
                      child: LayoutBuilder(
                        builder: (context, constraints) => constraints.maxWidth < 160
                            ? Center(
                                child: IconButton(
                                  tooltip: 'Expandir menu',
                                  onPressed: () => setState(() => _collapsed = false),
                                  icon: const Icon(Icons.menu, size: 20),
                                ),
                              )
                            : Row(
                                children: [
                                  const SizedBox(width: 21),
                                  Image.asset('assets/icon.png', width: 22, height: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Redmine Monitor',
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.fade,
                                      style: AppText.bodySemibold(dark: dark),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Recolher menu',
                                    onPressed: () => setState(() => _collapsed = true),
                                    icon: const Icon(Icons.menu_open, size: 20),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                      ),
                    ),
                    Container(height: 1, color: borderColor),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          _SectionLabel('Geral', dark: dark),
                          _navItem(
                            _Page.monitoring,
                            Icons.podcasts_outlined,
                            Icons.podcasts,
                            'Monitoração',
                            dark,
                            badge: unreadAlerts,
                          ),
                          _navItem(
                            _Page.queries,
                            Icons.query_stats_outlined,
                            Icons.query_stats,
                            'Consultas',
                            dark,
                            badge: failedQueries,
                            badgeColor: AppColors.orange,
                          ),
                          _navItem(
                            _Page.teams,
                            Icons.groups_outlined,
                            Icons.groups,
                            'Times e horas',
                            dark,
                          ),
                          if (pinned.isNotEmpty) _SectionLabel('Boards', dark: dark),
                          for (final q in pinned)
                            _NavItem(
                              icon: Icons.view_kanban_outlined,
                              label: q.name,
                              selected: board?.id == q.id,
                              dark: dark,
                              badge: q.lastError != null ? '!' : q.lastCount?.toString(),
                              badgeColor:
                                  q.lastError != null ? AppColors.orange : AppColors.warmGray500,
                              onTap: () => setState(() => _boardQueryId = q.id),
                            ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: borderColor),
                    const SizedBox(height: 6),
                    _navItem(_Page.settings, Icons.tune_outlined, Icons.tune, 'Configuração', dark),
                    _navItem(
                      _Page.logs,
                      Icons.receipt_long_outlined,
                      Icons.receipt_long,
                      'Logs',
                      dark,
                    ),
                    const SizedBox(height: 6),
                  ],
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
                        children: [
                          // Expanded (not Flexible + Spacer) keeps the account at the far right.
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    board == null ? _pageTitle : 'Boards  ›  ${board.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.bodySemibold(dark: dark),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (!appState.isProductionDatabase)
                                  _EnvironmentBadge(
                                    environment: appState.databaseEnvironment,
                                    isProduction: appState.isProductionDatabase,
                                    dark: dark,
                                  ),
                              ],
                            ),
                          ),
                          if (hasConfiguredAccount) ...[
                            Icon(Icons.account_circle_outlined,
                                size: 16, color: dark ? AppColors.darkMuted : AppColors.warmDark),
                            const SizedBox(width: 6),
                            Text(
                              accountLabel,
                              style: AppText.caption(dark: dark).copyWith(
                                color: dark ? AppColors.darkMuted : AppColors.warmDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: () => _confirmSignOut(context),
                              icon: const Icon(Icons.logout, size: 16),
                              label: const Text('Sair'),
                              style: TextButton.styleFrom(
                                foregroundColor: dark ? AppColors.darkMuted : AppColors.warmDark,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(height: 1, color: borderColor),

                    // Content
                    Expanded(
                      child: Stack(
                        children: [
                          // Offstage keeps the pages' state while a board is open.
                          Offstage(
                            offstage: board != null,
                            child: IndexedStack(
                              index: _page.index,
                              children: const [
                                _MonitoringTab(),
                                _QueriesTab(),
                                TeamsView(),
                                _SettingsTab(),
                                _LogsTab(),
                              ],
                            ),
                          ),
                          if (board != null) BoardView(key: ValueKey(board.id), query: board),
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

  String get _pageTitle => switch (_page) {
        _Page.monitoring => 'Monitoração',
        _Page.queries => 'Consultas',
        _Page.teams => 'Times e horas',
        _Page.settings => 'Configuração',
        _Page.logs => 'Logs',
      };

  Widget _navItem(
    _Page page,
    IconData icon,
    IconData activeIcon,
    String label,
    bool dark, {
    int badge = 0,
    Color badgeColor = AppColors.notionBlue,
  }) {
    final selected = _page == page && _boardQueryId == null;
    return _NavItem(
      icon: selected ? activeIcon : icon,
      label: label,
      selected: selected,
      dark: dark,
      badge: badge > 0 ? '$badge' : null,
      badgeColor: badgeColor,
      onTap: () => setState(() {
        _page = page;
        _boardQueryId = null;
      }),
    );
  }

  void _showAlertSnackIfNeeded(BuildContext context, AppState appState) {
    final alert = appState.lastAlert;
    if (alert == null) return;
    final key = '${alert.queryId}-${alert.createdAt.toIso8601String()}';
    if (key == _lastAlertKey) return;
    _lastAlertKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final (title, body) = appState.alertText(alert);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title\n$body')),
      );
    });
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair da conta'),
        content: const Text(
          'A URL e a API key atuais serão removidas deste ambiente. As consultas salvas serão mantidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (shouldSignOut != true || !context.mounted) return;
    await context.read<AppState>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }
}

class _EnvironmentBadge extends StatelessWidget {
  const _EnvironmentBadge({
    required this.environment,
    required this.isProduction,
    required this.dark,
  });

  final String environment;
  final bool isProduction;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isProduction
        ? (dark ? const Color(0x1FD2CFC9) : const Color(0xFFF0EEEB))
        : (dark ? const Color(0x332A9D99) : const Color(0x1F2A9D99));
    final borderColor = isProduction
        ? (dark ? AppColors.darkBorder : AppColors.whisperBorder)
        : AppColors.teal.withValues(alpha: dark ? 0.45 : 0.3);
    final textColor = isProduction
        ? (dark ? AppColors.darkMuted : AppColors.warmDark)
        : (dark ? const Color(0xFF7CE5D9) : AppColors.teal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        environment.toUpperCase(),
        style: AppText.badge().copyWith(color: textColor),
      ),
    );
  }
}

// ─── Nav item ────────────────────────────────────────────────────────────────

/// Pages that live in the main [IndexedStack]; order = stack index.
enum _Page { monitoring, queries, teams, settings, logs }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.dark});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 120
          ? const SizedBox(height: 12)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
              child: Text(
                text.toUpperCase(),
                maxLines: 1,
                style: AppText.microLabel(dark: dark).copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
    );
  }
}

/// Sidebar entry. Shows only the icon (label in a tooltip) when the sidebar
/// is too narrow, so it adapts while the width animates.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.badge,
    this.badgeColor = AppColors.notionBlue,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final String? badge;
  final Color badgeColor;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.selected;
    final inactiveColor = widget.dark ? AppColors.darkMuted : AppColors.warmDark;
    final hoverColor = widget.dark ? AppColors.pureWhite : AppColors.notionBlack;
    final color = isActive
        ? AppColors.notionBlue
        : _hovered
            ? hoverColor
            : inactiveColor;
    final bgColor = isActive
        ? AppColors.notionBlue.withValues(alpha: 0.08)
        : _hovered
            ? AppColors.hoverBg
            : Colors.transparent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 120;
        final badge = widget.badge == null
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: widget.badgeColor,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  widget.badge!,
                  textAlign: TextAlign.center,
                  style: AppText.badge().copyWith(color: AppColors.pureWhite, fontSize: 10),
                ),
              );
        final icon = Icon(widget.icon, size: 18, color: color);

        return Tooltip(
          message: compact ? widget.label : '',
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.subtle),
                ),
                child: compact
                    ? Badge(
                        isLabelVisible: badge != null,
                        backgroundColor: widget.badgeColor,
                        smallSize: 8,
                        child: icon,
                      )
                    : Row(
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.navButton(dark: widget.dark).copyWith(
                                color: color,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (badge != null) badge,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
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
                const Icon(Icons.warning_amber_outlined, size: 40, color: AppColors.orange),
                const SizedBox(height: Sp.s16),
                Text('Falha ao inicializar', style: AppText.cardTitle(dark: dark)),
                const SizedBox(height: Sp.s8),
                Text(error, textAlign: TextAlign.center, style: AppText.captionLight(dark: dark)),
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
                      appState.monitoring ? 'Monitoração ativa' : 'Monitoração pausada',
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
              _MetricPill(label: 'Logs', value: '${appState.monitorLogs.length}'),
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
      padding: const EdgeInsets.symmetric(horizontal: Sp.s8, vertical: Sp.s4),
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
              style: AppText.badge().copyWith(color: AppColors.badgeBlueText),
            ),
          ],
        ),
      ),
    );
  }
}
