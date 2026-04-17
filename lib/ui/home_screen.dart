import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/alert_event.dart';
import '../state/app_state.dart';
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

  // Intercept window close → hide instead of quit
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  // Tray double-click → show window
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
    return Consumer<AppState>(
      builder: (context, appState, _) {
        _showAlertSnackIfNeeded(context, appState.lastAlert);

        if (appState.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.initError != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Redmine Monitor')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Falha ao inicializar o aplicativo.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appState.initError!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: appState.retryInit,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(title: const Text('Redmine Monitor')),
            body: const TabBarView(
              children: [
                _MonitoringTab(),
                _QueriesTab(),
                _SettingsTab(),
                _LogsTab(),
              ],
            ),
            bottomNavigationBar: const _TabsBar(),
          ),
        );
      },
    );
  }

  void _showAlertSnackIfNeeded(BuildContext context, AlertEvent? alert) {
    if (alert == null) {
      return;
    }
    final key = '${alert.queryId}-${alert.createdAt.toIso8601String()}';
    if (key == _lastAlertKey) {
      return;
    }

    _lastAlertKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final diffPrefix = alert.diff > 0 ? '+' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${alert.queryName}: ${alert.previousCount} -> ${alert.currentCount} ($diffPrefix${alert.diff})',
          ),
        ),
      );
    });
  }
}

class _MonitoringTab extends StatelessWidget {
  const _MonitoringTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        _HeroHeader(),
        SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        QueriesCard(),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        SettingsCard(),
      ],
    );
  }
}

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        MonitoringHealthCard(),
        SizedBox(height: 12),
        LogsCard(),
      ],
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      child: SafeArea(
        top: false,
        child: TabBar(
          tabs: const [
            Tab(icon: Icon(Icons.podcasts_outlined), text: 'Monitoracao'),
            Tab(icon: Icon(Icons.query_stats_outlined), text: 'Consultas'),
            Tab(icon: Icon(Icons.tune), text: 'Configuracao'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Logs'),
          ],
          indicatorWeight: 3,
          labelStyle: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final activeQueries = appState.queries.where((q) => q.enabled).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appState.monitoring ? 'Monitoracao ativa' : 'Monitoracao pausada',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Switch(
                value: appState.monitoring,
                onChanged: (_) => appState.toggleMonitoring(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Consultas ativas', value: '$activeQueries'),
              _MetricChip(label: 'Alertas', value: '${appState.alerts.length}'),
              _MetricChip(label: 'Eventos de log', value: '${appState.monitorLogs.length}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }
}
