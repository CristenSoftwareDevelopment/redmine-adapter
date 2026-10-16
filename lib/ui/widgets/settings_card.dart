import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';
import '../components.dart';
import 'claude_actions_panel.dart';
import 'handoff_rules_panel.dart';

/// Sub-tabs of the settings page, in display order.
enum _SettingsTab {
  connection('Conexão', Icons.link),
  notifications('Notificações', Icons.notifications_none),
  automations('Automações', Icons.bolt_outlined),
  appearance('Aparência', Icons.palette_outlined),
  backup('Backup', Icons.backup_outlined);

  const _SettingsTab(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Tabs whose fields are saved by "Salvar configuração".
  bool get usesSaveButton => this == connection || this == notifications || this == appearance;
}

// ─── SettingsCard ─────────────────────────────────────────────────────────────

class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key});

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _notificationTitleTemplateController;
  late final TextEditingController _notificationBodyTemplateController;
  late final TextEditingController _increaseTitleController;
  late final TextEditingController _increaseBodyController;
  late final TextEditingController _decreaseTitleController;
  late final TextEditingController _decreaseBodyController;
  String _themeMode = defaultThemeMode;
  _SettingsTab _tab = _SettingsTab.connection;
  bool _seeded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _notificationTitleTemplateController = TextEditingController();
    _notificationBodyTemplateController = TextEditingController();
    _increaseTitleController = TextEditingController();
    _increaseBodyController = TextEditingController();
    _decreaseTitleController = TextEditingController();
    _decreaseBodyController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final settings = context.read<AppState>().settings;
    _baseUrlController.text = settings.baseUrl;
    _apiKeyController.text = settings.apiKey;
    _notificationTitleTemplateController.text = settings.notificationTitleTemplate;
    _notificationBodyTemplateController.text = settings.notificationBodyTemplate;
    _increaseTitleController.text = settings.notificationIncreaseTitleTemplate ?? '';
    _increaseBodyController.text = settings.notificationIncreaseBodyTemplate ?? '';
    _decreaseTitleController.text = settings.notificationDecreaseTitleTemplate ?? '';
    _decreaseBodyController.text = settings.notificationDecreaseBodyTemplate ?? '';
    _themeMode = settings.themeMode;
    _seeded = true;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _notificationTitleTemplateController.dispose();
    _notificationBodyTemplateController.dispose();
    _increaseTitleController.dispose();
    _increaseBodyController.dispose();
    _decreaseTitleController.dispose();
    _decreaseBodyController.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save(BuildContext context) async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      // The invalid field may sit on another tab: bring it into view.
      final connection =
          _baseUrlController.text.trim().isEmpty || _apiKeyController.text.trim().isEmpty;
      setState(() => _tab = connection ? _SettingsTab.connection : _SettingsTab.notifications);
      return;
    }
    setState(() => _saving = true);
    final state = context.read<AppState>();
    // copyWith keeps what this form doesn't edit (handoff rules, sidebar width…).
    final settings = state.settings.copyWith(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      notificationTitleTemplate: _notificationTitleTemplateController.text.trim(),
      notificationBodyTemplate: _notificationBodyTemplateController.text.trim(),
      themeMode: _themeMode,
      notificationIncreaseTitleTemplate: _increaseTitleController.text.trim().isEmpty
          ? null
          : _increaseTitleController.text.trim(),
      notificationIncreaseBodyTemplate:
          _increaseBodyController.text.trim().isEmpty ? null : _increaseBodyController.text.trim(),
      notificationDecreaseTitleTemplate: _decreaseTitleController.text.trim().isEmpty
          ? null
          : _decreaseTitleController.text.trim(),
      notificationDecreaseBodyTemplate:
          _decreaseBodyController.text.trim().isEmpty ? null : _decreaseBodyController.text.trim(),
    );
    try {
      await state.saveSettings(settings);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração salva.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    bool required = false,
  }) =>
      LabeledField(
        label: label,
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
          validator: required ? (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null : null,
        ),
      );

  /// Sends a test notification; empty fields fall back like real alerts.
  Widget _testButton(
    String label,
    TextEditingController title,
    TextEditingController body, {
    bool fallback = true,
  }) =>
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () {
            String pick(TextEditingController c, TextEditingController generic, String def) =>
                c.text.trim().isNotEmpty
                    ? c.text.trim()
                    : (fallback && generic.text.trim().isNotEmpty ? generic.text.trim() : def);
            context.read<AppState>().sendTestNotificationWithTemplates(
                  titleTemplate: pick(
                    title,
                    _notificationTitleTemplateController,
                    defaultNotificationTitleTemplate,
                  ),
                  bodyTemplate: pick(
                    body,
                    _notificationBodyTemplateController,
                    defaultNotificationBodyTemplate,
                  ),
                );
          },
          icon: const Icon(Icons.notifications_active_outlined, size: 17),
          label: Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 17);
    // Every tab stays in the Form (offstage when hidden), so its fields keep
    // their values and are still validated on save.
    Widget section(_SettingsTab tab, Widget child) =>
        Visibility(visible: _tab == tab, maintainState: true, child: child);
    Widget hint(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text, style: AppText.captionLight(dark: dark)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Configuração',
          subtitle: 'Conexão, notificações e preferências do monitor.',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppTabs<_SettingsTab>(
              tabs: [for (final t in _SettingsTab.values) (t, t.label, t.icon)],
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section(
                _SettingsTab.connection,
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PanelHead(
                        title: Text('Conexão com Redmine'),
                        subtitle: 'Endereço e chave de API usados pela integração.',
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _field(
                              'Endereço do Redmine',
                              _baseUrlController,
                              hint: 'https://seu-redmine.com',
                              required: true,
                            ),
                            gap,
                            _field('Chave da API', _apiKeyController,
                                obscure: true, required: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              section(
                _SettingsTab.notifications,
                Panel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle(icon: Icons.notifications_none, text: 'Notificações'),
                      hint('Template genérico (usado quando não há template específico).'),
                      _field(
                        'Título padrão',
                        _notificationTitleTemplateController,
                        hint: defaultNotificationTitleTemplate,
                        required: true,
                      ),
                      gap,
                      _field(
                        'Corpo padrão',
                        _notificationBodyTemplateController,
                        hint: defaultNotificationBodyTemplate,
                        maxLines: 4,
                        required: true,
                      ),
                      const SizedBox(height: 12),
                      _testButton(
                        'Testar template genérico',
                        _notificationTitleTemplateController,
                        _notificationBodyTemplateController,
                        fallback: false,
                      ),
                      const Divider(height: 46),
                      hint('Template para aumento de contagem (opcional).'),
                      _field(
                        'Título — somente aumento',
                        _increaseTitleController,
                        hint: 'Vazio = template padrão',
                      ),
                      gap,
                      _field(
                        'Corpo — somente aumento',
                        _increaseBodyController,
                        hint: 'Vazio = template padrão',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      _testButton(
                        'Testar template de aumento',
                        _increaseTitleController,
                        _increaseBodyController,
                      ),
                      const Divider(height: 46),
                      hint('Template para diminuição de contagem (opcional).'),
                      _field(
                        'Título — somente diminuição',
                        _decreaseTitleController,
                        hint: 'Vazio = template padrão',
                      ),
                      gap,
                      _field(
                        'Corpo — somente diminuição',
                        _decreaseBodyController,
                        hint: 'Vazio = template padrão',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      _testButton(
                        'Testar template de diminuição',
                        _decreaseTitleController,
                        _decreaseBodyController,
                      ),
                      const SizedBox(height: 20),
                      const Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag('{queryName}'),
                          Tag('{previousCount}'),
                          Tag('{currentCount}'),
                          Tag('{diff}'),
                          Tag('{newCount}'),
                          Tag('{time}'),
                          Tag('{url}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Saved on their own; not part of "Salvar configuração".
              section(
                  _SettingsTab.automations,
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [HandoffRulesPanel(), ClaudeActionsPanel()])),
              section(
                _SettingsTab.appearance,
                Panel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(icon: Icons.palette_outlined, text: 'Aparência'),
                      LabeledField(
                        label: 'Tema do aplicativo',
                        child: SegmentButtons<String>(
                          segments: const [
                            ('light', 'Claro', Icons.light_mode_outlined),
                            ('dark', 'Escuro', Icons.dark_mode_outlined),
                            ('system', 'Sistema', Icons.brightness_auto_outlined),
                          ],
                          selected: _themeMode,
                          onChanged: (v) => setState(() => _themeMode = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              section(
                _SettingsTab.backup,
                Panel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(icon: Icons.backup_outlined, text: 'Backup'),
                      hint(
                          'Copie a configuração, as consultas e os times, ou restaure de um JSON.'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await context.read<AppState>().copyBackupToClipboard();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Backup copiado para a área de transferência.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_all_outlined, size: 17),
                            label: const Text('Copiar backup'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showImportBackupDialog(context),
                            icon: const Icon(Icons.upload_file_outlined, size: 17),
                            label: const Text('Restaurar backup'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_tab.usesSaveButton)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _save(context),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 17),
                    label: Text(_saving ? 'Salvando…' : 'Salvar configuração'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showImportBackupDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showAppDialog<void>(
      context,
      (dialogContext) => AppDialog(
        title: const Text('Restaurar backup'),
        body: TextField(
          controller: controller,
          maxLines: 12,
          decoration: const InputDecoration(hintText: 'Cole aqui o JSON do backup…'),
        ),
        footer: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppState>().importBackupJson(controller.text.trim());
                if (!context.mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup restaurado com sucesso.')),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Falha ao restaurar backup: $error')),
                );
              }
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}
