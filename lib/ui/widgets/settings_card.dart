import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../state/app_state.dart';
import '../../services/theme_service.dart';

// ─── Tab definitions ──────────────────────────────────────────────────────────

enum _SettingsTab { connection, notifications, appearance, backup }

extension _SettingsTabX on _SettingsTab {
  String get label => switch (this) {
        _SettingsTab.connection    => 'Conexão',
        _SettingsTab.notifications => 'Notificações',
        _SettingsTab.appearance    => 'Aparencia',
        _SettingsTab.backup        => 'Backup',
      };

  IconData get icon => switch (this) {
        _SettingsTab.connection    => Icons.cloud_outlined,
        _SettingsTab.notifications => Icons.notifications_outlined,
        _SettingsTab.appearance    => Icons.palette_outlined,
        _SettingsTab.backup        => Icons.backup_outlined,
      };
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
  bool _seeded = false;
  bool _saving = false;
  _SettingsTab _activeTab = _SettingsTab.connection;

  // Public mutator — used by child StatelessWidget to avoid
  // calling the protected setState() from outside this State.
  void setThemeMode(String value) => setState(() => _themeMode = value);

  @override
  void initState() {
    super.initState();
    _baseUrlController                    = TextEditingController();
    _apiKeyController                     = TextEditingController();
    _notificationTitleTemplateController  = TextEditingController();
    _notificationBodyTemplateController   = TextEditingController();
    _increaseTitleController              = TextEditingController();
    _increaseBodyController               = TextEditingController();
    _decreaseTitleController              = TextEditingController();
    _decreaseBodyController               = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final settings = context.read<AppState>().settings;
    _baseUrlController.text                   = settings.baseUrl;
    _apiKeyController.text                    = settings.apiKey;
    _notificationTitleTemplateController.text = settings.notificationTitleTemplate;
    _notificationBodyTemplateController.text  = settings.notificationBodyTemplate;
    _increaseTitleController.text             = settings.notificationIncreaseTitleTemplate ?? '';
    _increaseBodyController.text              = settings.notificationIncreaseBodyTemplate ?? '';
    _decreaseTitleController.text             = settings.notificationDecreaseTitleTemplate ?? '';
    _decreaseBodyController.text              = settings.notificationDecreaseBodyTemplate ?? '';
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
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final state    = context.read<AppState>();
    final settings = AppSettings(
      baseUrl:              _baseUrlController.text.trim(),
      apiKey:               _apiKeyController.text.trim(),
      notificationTitleTemplate: _notificationTitleTemplateController.text.trim(),
      notificationBodyTemplate:  _notificationBodyTemplateController.text.trim(),
      themeMode: _themeMode,
      notificationIncreaseTitleTemplate:
          _increaseTitleController.text.trim().isEmpty ? null : _increaseTitleController.text.trim(),
      notificationIncreaseBodyTemplate:
          _increaseBodyController.text.trim().isEmpty ? null : _increaseBodyController.text.trim(),
      notificationDecreaseTitleTemplate:
          _decreaseTitleController.text.trim().isEmpty ? null : _decreaseTitleController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: surfaceCard(dark: dark),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Tab bar ──────────────────────────────────────────────────
            _TabBar(
              active: _activeTab,
              dark: dark,
              onSelect: (t) => setState(() => _activeTab = t),
            ),
            Container(height: 1, color: dark ? AppColors.darkBorder : AppColors.whisperBorder),

            // ── Tab body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(Sp.s24),
              child: switch (_activeTab) {
                _SettingsTab.connection    => _ConnectionTab(this),
                _SettingsTab.notifications => _NotificationsTab(this),
                _SettingsTab.appearance    => _AppearanceTab(this),
                _SettingsTab.backup        => _BackupTab(this),
              },
            ),

            // ── Save footer ───────────────────────────────────────────────
            if (_activeTab != _SettingsTab.backup) ...[
              Container(height: 1, color: dark ? AppColors.darkBorder : AppColors.whisperBorder),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.s24, vertical: Sp.s16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _save(context),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando...' : 'Salvar configuração'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showImportBackupDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Cole aqui o JSON do backup...',
            ),
          ),
        ),
        actions: [
          TextButton(
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

// ─── Custom tab bar ───────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.active, required this.dark, required this.onSelect});

  final _SettingsTab active;
  final bool dark;
  final ValueChanged<_SettingsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Sp.s16, vertical: Sp.s12),
      child: Row(
        children: _SettingsTab.values.map((tab) {
          final isActive = tab == active;
          return Padding(
            padding: const EdgeInsets.only(right: Sp.s4),
            child: _TabChip(
              label: tab.label,
              icon: tab.icon,
              isActive: isActive,
              dark: dark,
              onTap: () => onSelect(tab),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool dark;
  final VoidCallback onTap;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.blue
        : _hovered
            ? (widget.dark ? AppColors.darkBorder : AppColors.hoverBg)
            : Colors.transparent;
    final fg = widget.isActive
        ? AppColors.white
        : widget.dark
            ? AppColors.darkMuted
            : AppColors.warmDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.subtle),
            border: widget.isActive
                ? null
                : Border.all(
                    color: widget.dark ? AppColors.darkBorder : AppColors.borderLight,
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 13,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab bodies ───────────────────────────────────────────────────────────────

class _ConnectionTab extends StatelessWidget {
  const _ConnectionTab(this.s);
  final _SettingsCardState s;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: s._baseUrlController,
          decoration: const InputDecoration(
            labelText: 'URL do Redmine',
            hintText: 'https://seu-redmine.com',
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Informe a URL do Redmine' : null,
        ),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._apiKeyController,
          decoration: const InputDecoration(labelText: 'API Key'),
          obscureText: true,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Informe a API key' : null,
        ),
      ],
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab(this.s);
  final _SettingsCardState s;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Generic template
        Text('Template genérico (usado quando não ha template específico)',
            style: AppText.captionLight(dark: dark)),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._notificationTitleTemplateController,
          decoration: const InputDecoration(
            labelText: 'Titulo padrão',
            hintText: defaultNotificationTitleTemplate,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
        ),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._notificationBodyTemplateController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Corpo padrão',
            hintText: defaultNotificationBodyTemplate,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Obrigatório' : null,
        ),
        const SizedBox(height: Sp.s12),
        _TestNotificationButton(
          label: 'Testar template genérico',
          getTitleTemplate: () => s._notificationTitleTemplateController.text.trim(),
          getBodyTemplate:  () => s._notificationBodyTemplateController.text.trim(),
          getFallbackTitle: null,
          getFallbackBody:  null,
        ),
        const SizedBox(height: Sp.s24),

        // Increase template
        Text('Template para aumento de contagem (opcional)',
            style: AppText.captionLight(dark: dark)),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._increaseTitleController,
          decoration: const InputDecoration(
            labelText: 'Titulo — somente aumento',
            hintText: 'Deixe vazio para usar o template padrão',
          ),
        ),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._increaseBodyController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Corpo — somente aumento',
            hintText: 'Deixe vazio para usar o template padrão',
          ),
        ),
        const SizedBox(height: Sp.s12),
        _TestNotificationButton(
          label: 'Testar template de aumento',
          getTitleTemplate: () => s._increaseTitleController.text.trim(),
          getBodyTemplate:  () => s._increaseBodyController.text.trim(),
          getFallbackTitle: () => s._notificationTitleTemplateController.text.trim(),
          getFallbackBody:  () => s._notificationBodyTemplateController.text.trim(),
        ),
        const SizedBox(height: Sp.s24),

        // Decrease template
        Text('Template para diminuição de contagem (opcional)',
            style: AppText.captionLight(dark: dark)),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._decreaseTitleController,
          decoration: const InputDecoration(
            labelText: 'Titulo — somente diminuição',
            hintText: 'Deixe vazio para usar o template padrão',
          ),
        ),
        const SizedBox(height: Sp.s12),
        TextFormField(
          controller: s._decreaseBodyController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Corpo — somente diminuição',
            hintText: 'Deixe vazio para usar o template padrão',
          ),
        ),
        const SizedBox(height: Sp.s12),
        _TestNotificationButton(
          label: 'Testar template de diminuição',
          getTitleTemplate: () => s._decreaseTitleController.text.trim(),
          getBodyTemplate:  () => s._decreaseBodyController.text.trim(),
          getFallbackTitle: () => s._notificationTitleTemplateController.text.trim(),
          getFallbackBody:  () => s._notificationBodyTemplateController.text.trim(),
        ),
        const SizedBox(height: Sp.s16),

        // Placeholders reference
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('{queryName}')),
            Chip(label: Text('{previousCount}')),
            Chip(label: Text('{currentCount}')),
            Chip(label: Text('{diff}')),
            Chip(label: Text('{newCount}')),
            Chip(label: Text('{time}')),
            Chip(label: Text('{url}')),
          ],
        ),
      ],
    );
  }
}

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab(this.s);
  final _SettingsCardState s;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tema do aplicativo', style: AppText.body(dark: dark)),
        const SizedBox(height: Sp.s12),
        StatefulBuilder(
          builder: (context, setSub) => Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: dark ? AppColors.darkBorder : AppColors.inputBorder),
              borderRadius: BorderRadius.circular(AppRadius.micro),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ThemeTab(
                  label: 'Claro',
                  icon: Icons.light_mode_outlined,
                  isSelected: s._themeMode == 'light',
                  dark: dark,
                   onTap: () {
                     s.setThemeMode('light');
                     setSub(() {});
                   },
                ),
                _ThemeTab(
                  label: 'Escuro',
                  icon: Icons.dark_mode_outlined,
                  isSelected: s._themeMode == 'dark',
                  dark: dark,
                   onTap: () {
                     s.setThemeMode('dark');
                     setSub(() {});
                   },
                ),
                _ThemeTab(
                  label: 'Sistema',
                  icon: Icons.brightness_auto_outlined,
                  isSelected: s._themeMode == 'system',
                  dark: dark,
                   onTap: () {
                     s.setThemeMode('system');
                     setSub(() {});
                   },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackupTab extends StatelessWidget {
  const _BackupTab(this.s);
  final _SettingsCardState s;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Sp.s12,
      runSpacing: Sp.s12,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            await context.read<AppState>().copyBackupToClipboard();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Backup copiado para a área de transferência.')),
            );
          },
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copiar backup'),
        ),
        OutlinedButton.icon(
          onPressed: () => s._showImportBackupDialog(context),
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Restaurar backup'),
        ),
      ],
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _TestNotificationButton extends StatelessWidget {
  const _TestNotificationButton({
    required this.label,
    required this.getTitleTemplate,
    required this.getBodyTemplate,
    required this.getFallbackTitle,
    required this.getFallbackBody,
  });

  final String label;
  final String Function() getTitleTemplate;
  final String Function() getBodyTemplate;
  final String Function()? getFallbackTitle;
  final String Function()? getFallbackBody;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        final title = getTitleTemplate().isNotEmpty
            ? getTitleTemplate()
            : (getFallbackTitle?.call() ?? defaultNotificationTitleTemplate);
        final body = getBodyTemplate().isNotEmpty
            ? getBodyTemplate()
            : (getFallbackBody?.call() ?? defaultNotificationBodyTemplate);
        context.read<AppState>().sendTestNotificationWithTemplates(
              titleTemplate: title,
              bodyTemplate:  body,
            );
      },
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(label),
    );
  }
}

class _ThemeTab extends StatelessWidget {
  const _ThemeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.micro),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.notionBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.micro),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: isSelected ? AppColors.pureWhite : AppColors.warmGray500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppText.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? AppColors.pureWhite : AppColors.warmGray500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
