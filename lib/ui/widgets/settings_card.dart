import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../state/app_state.dart';

class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key});

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _defaultPollController;
  late final TextEditingController _alertCooldownController;
  late final TextEditingController _notificationTitleTemplateController;
  late final TextEditingController _notificationBodyTemplateController;
  late final TextEditingController _increaseTitleController;
  late final TextEditingController _increaseBodyController;
  late final TextEditingController _decreaseTitleController;
  late final TextEditingController _decreaseBodyController;
  String _themeMode = defaultThemeMode;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _defaultPollController = TextEditingController();
    _alertCooldownController = TextEditingController();
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
    _defaultPollController.text = '${settings.defaultPollSeconds}';
    _alertCooldownController.text = '${settings.alertCooldownSeconds}';
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
    _defaultPollController.dispose();
    _alertCooldownController.dispose();
    _notificationTitleTemplateController.dispose();
    _notificationBodyTemplateController.dispose();
    _increaseTitleController.dispose();
    _increaseBodyController.dispose();
    _decreaseTitleController.dispose();
    _decreaseBodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Configuracao', style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 20),

              // ── Conexão ──────────────────────────────────────────────────
              const _SectionHeader(icon: Icons.cloud_outlined, label: 'Conexao com Redmine'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL do Redmine',
                  hintText: 'https://seu-redmine.com',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe a URL do Redmine';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe a API key';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _defaultPollController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo padrao (segundos)',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed < 10) return 'Minimo 10 segundos';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _alertCooldownController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cooldown de alerta (segundos)',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Use 0 ou maior';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Aparência ─────────────────────────────────────────────────
              const _SectionHeader(icon: Icons.palette_outlined, label: 'Aparencia'),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'light',
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'dark',
                    label: Text('Escuro'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'system',
                    label: Text('Sistema'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: {_themeMode},
                onSelectionChanged: (next) => setState(() => _themeMode = next.first),
              ),
              const SizedBox(height: 20),

              // ── Notificações ──────────────────────────────────────────────
              const _SectionHeader(
                  icon: Icons.notifications_outlined, label: 'Notificacoes'),
              const SizedBox(height: 12),
              Text(
                'Template generico (usado quando nao ha template especifico)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notificationTitleTemplateController,
                decoration: const InputDecoration(
                  labelText: 'Titulo padrao',
                  hintText: defaultNotificationTitleTemplate,
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Obrigatorio' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notificationBodyTemplateController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Corpo padrao',
                  hintText: defaultNotificationBodyTemplate,
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Obrigatorio' : null,
              ),
              const SizedBox(height: 12),
              _TestNotificationButton(
                label: 'Testar template generico',
                getTitleTemplate: () => _notificationTitleTemplateController.text.trim(),
                getBodyTemplate: () => _notificationBodyTemplateController.text.trim(),
                getFallbackTitle: null,
                getFallbackBody: null,
              ),
              const SizedBox(height: 12),
              Text(
                'Template para aumento de contagem (opcional)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _increaseTitleController,
                decoration: const InputDecoration(
                  labelText: 'Titulo — somente aumento',
                  hintText: 'Deixe vazio para usar o template padrao',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _increaseBodyController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Corpo — somente aumento',
                  hintText: 'Deixe vazio para usar o template padrao',
                ),
              ),
              const SizedBox(height: 12),
              _TestNotificationButton(
                label: 'Testar template de aumento',
                getTitleTemplate: () => _increaseTitleController.text.trim(),
                getBodyTemplate: () => _increaseBodyController.text.trim(),
                getFallbackTitle: () => _notificationTitleTemplateController.text.trim(),
                getFallbackBody: () => _notificationBodyTemplateController.text.trim(),
              ),
              const SizedBox(height: 12),
              Text(
                'Template para diminuicao de contagem (opcional)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _decreaseTitleController,
                decoration: const InputDecoration(
                  labelText: 'Titulo — somente diminuicao',
                  hintText: 'Deixe vazio para usar o template padrao',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _decreaseBodyController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Corpo — somente diminuicao',
                  hintText: 'Deixe vazio para usar o template padrao',
                ),
              ),
              const SizedBox(height: 12),
              _TestNotificationButton(
                label: 'Testar template de diminuicao',
                getTitleTemplate: () => _decreaseTitleController.text.trim(),
                getBodyTemplate: () => _decreaseBodyController.text.trim(),
                getFallbackTitle: () => _notificationTitleTemplateController.text.trim(),
                getFallbackBody: () => _notificationBodyTemplateController.text.trim(),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 20),

              // ── Backup ────────────────────────────────────────────────────
              const _SectionHeader(icon: Icons.backup_outlined, label: 'Backup'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await context.read<AppState>().copyBackupToClipboard();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Backup copiado para a area de transferencia.')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copiar backup'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _showImportBackupDialog(context),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Restaurar backup'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Salvar ────────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;

                    final state = context.read<AppState>();
                    final settings = AppSettings(
                      baseUrl: _baseUrlController.text.trim(),
                      apiKey: _apiKeyController.text.trim(),
                      defaultPollSeconds:
                          int.parse(_defaultPollController.text.trim()),
                      alertCooldownSeconds:
                          int.parse(_alertCooldownController.text.trim()),
                      notificationTitleTemplate:
                          _notificationTitleTemplateController.text.trim(),
                      notificationBodyTemplate:
                          _notificationBodyTemplateController.text.trim(),
                      themeMode: _themeMode,
                      notificationIncreaseTitleTemplate:
                          _increaseTitleController.text.trim().isEmpty
                              ? null
                              : _increaseTitleController.text.trim(),
                      notificationIncreaseBodyTemplate:
                          _increaseBodyController.text.trim().isEmpty
                              ? null
                              : _increaseBodyController.text.trim(),
                      notificationDecreaseTitleTemplate:
                          _decreaseTitleController.text.trim().isEmpty
                              ? null
                              : _decreaseTitleController.text.trim(),
                      notificationDecreaseBodyTemplate:
                          _decreaseBodyController.text.trim().isEmpty
                              ? null
                              : _decreaseBodyController.text.trim(),
                    );

                    await state.saveSettings(settings);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Configuracao salva.')),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar configuracao'),
                ),
              ),
            ],
          ),
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
    return FilledButton.tonalIcon(
      onPressed: () {
        final title = getTitleTemplate().isNotEmpty
            ? getTitleTemplate()
            : (getFallbackTitle?.call() ?? defaultNotificationTitleTemplate);
        final body = getBodyTemplate().isNotEmpty
            ? getBodyTemplate()
            : (getFallbackBody?.call() ?? defaultNotificationBodyTemplate);
        context.read<AppState>().sendTestNotificationWithTemplates(
              titleTemplate: title,
              bodyTemplate: body,
            );
      },
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(label),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
