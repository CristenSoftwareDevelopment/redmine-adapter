import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import '../services/theme_service.dart';
import 'components.dart';
import 'ui_utils.dart';
import 'board/board_view.dart';
import 'onboarding_screen.dart';
import 'teams/teams_view.dart';
import 'widgets/alerts_card.dart';
import 'widgets/logs_card.dart';
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (appState.initError != null) {
          return _ErrorScreen(error: appState.initError!, onRetry: appState.retryInit);
        }

        final width = MediaQuery.sizeOf(context).width;
        final collapsed = _collapsed ?? width < 1100;
        final narrow = width < 1100;
        final unreadAlerts = appState.alerts.where((a) => !a.isRead).length;
        final failedQueries = appState.queries.where((q) => q.lastError != null).length;
        final pinned = appState.queries.where((q) => q.pinned && q.id != null).toList();
        final board = pinned.where((q) => q.id == _boardQueryId).firstOrNull;
        if (board == null) _boardQueryId = null; // board was unpinned or deleted
        final hasAccount = appState.settings.baseUrl.trim().isNotEmpty &&
            appState.settings.apiKey.trim().isNotEmpty;
        final accountName = (appState.settings.accountName?.trim().isNotEmpty ?? false)
            ? appState.settings.accountName!.trim()
            : 'Conta conectada';
        final hPad = narrow ? 24.0 : 34.0;

        return Scaffold(
          backgroundColor: AppColors.page(dark: dark),
          body: Row(
            children: [
              // ── Sidebar ──────────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: collapsed ? 75 : 240,
                decoration: BoxDecoration(
                  color: AppColors.sidebar(dark: dark),
                  border: Border(right: BorderSide(color: AppColors.border(dark: dark))),
                ),
                padding: const EdgeInsets.fromLTRB(10, 24, 10, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Brand(
                      dark: dark,
                      onToggle: () => setState(() => _collapsed = !collapsed),
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: ListView(
                        children: [
                          _SectionLabel('Geral', dark: dark),
                          _navItem(_Page.monitoring, Icons.podcasts, 'Monitoração', dark,
                              count: unreadAlerts),
                          _navItem(_Page.queries, Icons.search, 'Consultas', dark,
                              count: failedQueries, countTone: TagTone.red),
                          _navItem(_Page.teams, Icons.groups_outlined, 'Times e horas', dark),
                          if (pinned.isNotEmpty) _SectionLabel('Boards', dark: dark),
                          for (final q in pinned)
                            _NavItem(
                              icon: Icons.view_kanban_outlined,
                              label: q.name,
                              selected: board?.id == q.id,
                              dark: dark,
                              count: q.lastError != null ? '!' : q.lastCount?.toString(),
                              countTone: q.lastError != null ? TagTone.red : null,
                              onTap: () => setState(() => _boardQueryId = q.id),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 14),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
                      ),
                      child: Column(
                        children: [
                          _navItem(_Page.settings, Icons.tune, 'Configuração', dark),
                          _navItem(_Page.logs, Icons.receipt_long_outlined, 'Logs', dark),
                          if (hasAccount)
                            _NavItem(
                              icon: Icons.logout,
                              label: 'Sair',
                              selected: false,
                              dark: dark,
                              onTap: () => _confirmSignOut(context),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main area ────────────────────────────────────────────
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1750),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 30),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  board == null
                                      ? 'Workspace / $_pageTitle'
                                      : 'Workspace / Boards / ${board.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.microLabel(dark: dark),
                                ),
                              ),
                              if (!appState.isProductionDatabase) ...[
                                _DevTag(appState.databaseEnvironment, dark: dark),
                                const SizedBox(width: 9),
                              ],
                              if (hasAccount) ...[
                                _AccountAvatar(accountName, dark: dark),
                                const SizedBox(width: 9),
                                Text(accountName, style: AppText.microLabel(dark: dark)),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              // Offstage keeps the pages' state while a board is open.
                              Offstage(
                                offstage: board != null,
                                child: IndexedStack(
                                  index: _page.index,
                                  children: [
                                    _Page.monitoring,
                                    _Page.queries,
                                    _Page.teams,
                                    _Page.settings,
                                    _Page.logs,
                                  ].map((p) => _PageBody(page: p, hPad: hPad)).toList(),
                                ),
                              ),
                              if (board != null)
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: hPad),
                                  child: BoardView(key: ValueKey(board.id), query: board),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
    String label,
    bool dark, {
    int count = 0,
    TagTone? countTone,
  }) {
    return _NavItem(
      icon: icon,
      label: label,
      selected: _page == page && _boardQueryId == null,
      dark: dark,
      count: count > 0 ? '$count' : null,
      countTone: countTone,
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
    final shouldSignOut = await showAppDialog<bool>(
      context,
      (dialogContext) => AppDialog(
        width: 460,
        title: const Text('Sair da conta'),
        body: Text(
          'A URL e a API key atuais serão removidas deste ambiente. As consultas salvas serão mantidas.',
          style: AppText.captionLight(dark: Theme.of(dialogContext).brightness == Brightness.dark),
        ),
        footer: [
          OutlinedButton(
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

/// Pages that live in the main [IndexedStack]; order = stack index.
enum _Page { monitoring, queries, teams, settings, logs }

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.hPad});

  final _Page page;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(hPad, 0, hPad, 28);
    return switch (page) {
      _Page.monitoring => ListView(padding: padding, children: const [_MonitoringPage()]),
      _Page.queries => ListView(padding: padding, children: const [QueriesCard()]),
      _Page.teams => ListView(padding: padding, children: const [TeamsView()]),
      _Page.settings => ListView(padding: padding, children: const [SettingsCard()]),
      _Page.logs => ListView(padding: padding, children: const [LogsCard()]),
    };
  }
}

// ─── Sidebar pieces ──────────────────────────────────────────────────────────

class _Brand extends StatelessWidget {
  const _Brand({required this.dark, required this.onToggle});

  final bool dark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final mark = Tooltip(
      message: 'Expandir/recolher menu',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: AppColors.accentSoft(dark: dark),
            border: Border.all(color: AppColors.accent(dark: dark).withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(AppRadius.standard),
          ),
          child: Icon(Icons.grid_view_rounded, size: 16, color: AppColors.accent(dark: dark)),
        ),
      ),
    );
    // Adapts while the width animates.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 150
          ? Center(child: mark)
          : Row(
              children: [
                const SizedBox(width: 8),
                mark,
                const SizedBox(width: 10),
                Expanded(
                  // Shrinks instead of clipping when the system font is wider.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Redmine Monitor',
                      maxLines: 1,
                      style: AppText.cardTitle(dark: dark).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Recolher menu',
                  onPressed: onToggle,
                  icon: const Icon(Icons.menu_open, size: 18),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.dark});
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 150
          ? const SizedBox(height: 18)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              child: Text(text.toUpperCase(), maxLines: 1, style: AppText.sectionLabel(dark: dark)),
            ),
    );
  }
}

/// Sidebar entry. Shows only the icon (label in a tooltip) when the sidebar
/// is too narrow, so it adapts while the width animates.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.count,
    this.countTone,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final String? count;

  /// Defaults to the neutral counter (accent when selected).
  final TagTone? countTone;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent(dark: dark) : AppColors.mutedText(dark: dark);
    final (countBg, countFg) = AppColors.tone(
      countTone ?? (selected ? TagTone.accent : TagTone.neutral),
      dark: dark,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 150;
        final iconWidget = Icon(icon, size: 17, color: color);
        return Tooltip(
          message: compact ? label : '',
          waitDuration: const Duration(milliseconds: 300),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: selected ? AppColors.accentSoft(dark: dark) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.standard),
              child: InkWell(
                onTap: onTap,
                hoverColor: AppColors.hover(dark: dark),
                borderRadius: BorderRadius.circular(AppRadius.standard),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: compact
                      ? Center(
                          child: Badge(
                            isLabelVisible: count != null,
                            backgroundColor: countFg,
                            smallSize: 7,
                            child: iconWidget,
                          ),
                        )
                      : Row(
                          children: [
                            iconWidget,
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.navButton(dark: dark).copyWith(
                                  color: color,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (count != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: countBg,
                                  borderRadius: BorderRadius.circular(AppRadius.subtle),
                                ),
                                child: Text(
                                  count!,
                                  style: AppText.badge().copyWith(color: countFg, fontSize: 10),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Top bar pieces ──────────────────────────────────────────────────────────

class _DevTag extends StatelessWidget {
  const _DevTag(this.environment, {required this.dark});
  final String environment;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.accent(dark: dark).withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.subtle),
      ),
      child: Text(
        environment.toUpperCase(),
        style: AppText.badge().copyWith(fontSize: 10, color: AppColors.accent(dark: dark)),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar(this.name, {required this.dark});
  final String name;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 12.5,
      backgroundColor: dark ? const Color(0xFF354B5D) : const Color(0xFFD5E0EA),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: dark ? const Color(0xFFCADBE8) : const Color(0xFF2B3A4A),
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
                Icon(Icons.warning_amber_outlined, size: 40, color: AppColors.danger(dark: dark)),
                const SizedBox(height: Sp.s16),
                Text('Falha ao inicializar', style: AppText.cardTitle(dark: dark)),
                const SizedBox(height: Sp.s8),
                Text(error, textAlign: TextAlign.center, style: AppText.captionLight(dark: dark)),
                const SizedBox(height: Sp.s24),
                FilledButton(onPressed: onRetry, child: const Text('Tentar novamente')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Monitoração ──────────────────────────────────────────────────────────────

class _MonitoringPage extends StatelessWidget {
  const _MonitoringPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unread = state.alerts.where((a) => !a.isRead).length;
    final failures = state.monitorLogs.where((l) => l.level == 'error').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Monitoração',
          subtitle: 'Acompanhe mudanças e mantenha o controle das consultas.',
        ),
        StatGrid(
          children: [
            StatCard(
              label: 'Consultas ativas',
              value: '${state.queries.where((q) => q.enabled).length}',
              note: 'Respeitam seus próprios agendamentos',
              icon: Icons.search,
            ),
            StatCard(
              label: 'Alertas não lidos',
              value: '$unread',
              note: 'Mudanças que precisam de atenção',
              icon: Icons.notifications_none,
            ),
            StatCard(
              label: 'Falhas no histórico',
              value: '$failures',
              note: 'Consulte os logs para investigar',
              icon: Icons.monitor_heart_outlined,
            ),
            StatCard(
              label: 'Monitoração',
              value: state.monitoring ? 'Ativa' : 'Pausada',
              note: state.monitoring
                  ? 'Verificações automáticas habilitadas'
                  : 'Verificações automáticas suspensas',
              icon: Icons.podcasts,
            ),
          ],
        ),
        Panel(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              IconBox(icon: Icons.podcasts, highlighted: state.monitoring),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.monitoring ? 'Monitoração ativa' : 'Monitoração pausada',
                      style: AppText.cardTitle(dark: dark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Intervalos, dias e horários definidos em cada consulta.',
                      style: AppText.captionLight(dark: dark),
                    ),
                  ],
                ),
              ),
              Switch(value: state.monitoring, onChanged: (_) => state.toggleMonitoring()),
            ],
          ),
        ),
        const AlertsCard(),
      ],
    );
  }
}
