import 'package:flutter/material.dart';

import '../../models/monitored_query.dart';
import '../../services/theme_service.dart';

class QueryFormDialog extends StatefulWidget {
  const QueryFormDialog({
    super.key,
    this.initial,
  });

  final MonitoredQuery? initial;

  @override
  State<QueryFormDialog> createState() => _QueryFormDialogState();
}

class _QueryFormDialogState extends State<QueryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _queryUrl;
  late final TextEditingController _countPath;
  late final TextEditingController _pollSeconds;
  late final TextEditingController _customTitle;
  late final TextEditingController _customBody;
  bool _enabled = true;
  String _alertOn = alertOnAny;
  bool _showAdvanced = false;
  bool _showCustomTemplate = false;
  late List<int> _scheduleWeekdays;
  late int _scheduleStartHour;
  late int _scheduleEndHour;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _name = TextEditingController(text: item?.name ?? '');
    _queryUrl = TextEditingController(
      text: item?.directUrl.isNotEmpty == true ? item!.directUrl : (item?.endpoint ?? ''),
    );
    _countPath = TextEditingController(text: item?.countPath ?? 'total_count');
    _pollSeconds = TextEditingController(
      text: '${item?.pollSeconds ?? defaultPollSeconds}',
    );
    _customTitle = TextEditingController(text: item?.notificationTitleTemplate ?? '');
    _customBody = TextEditingController(text: item?.notificationBodyTemplate ?? '');
    _enabled = item?.enabled ?? true;
    _alertOn = item?.alertOn ?? alertOnAny;
    _scheduleWeekdays = List<int>.from(item?.scheduleWeekdays ?? defaultScheduleWeekdays);
    _scheduleStartHour = item?.scheduleStartHour ?? defaultScheduleStartHour;
    _scheduleEndHour = item?.scheduleEndHour ?? defaultScheduleEndHour;
    _showCustomTemplate =
        (item?.notificationTitleTemplate?.isNotEmpty ?? false) ||
            (item?.notificationBodyTemplate?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _name.dispose();
    _queryUrl.dispose();
    _countPath.dispose();
    _pollSeconds.dispose();
    _customTitle.dispose();
    _customBody.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Sp.s24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: surfaceCard(dark: dark),
        padding: const EdgeInsets.all(Sp.s24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.initial == null ? 'Nova consulta' : 'Editar consulta',
                    style: AppText.bodyLarge(dark: dark),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.warmGray500,
                    splashRadius: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: Sp.s16),
              Divider(
                color: dark ? AppColors.darkBorder : AppColors.whisperBorder,
                height: 1,
              ),
              const SizedBox(height: Sp.s16),

              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Nome'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                      ),
                      const SizedBox(height: Sp.s12),
                      TextFormField(
                        controller: _queryUrl,
                        decoration: const InputDecoration(
                          labelText: 'URL da consulta no Redmine',
                          hintText: 'https://seu-redmine.com/projects/x/issues?query_id=123',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Obrigatório';
                          final parsed = _parseUserUrl(value.trim());
                          if (parsed == null) {
                            return 'Informe uma URL válida (com /issues e query_id)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: Sp.s4),
                      Text(
                        'Cole a URL da página da consulta salva. O app gera o endpoint /issues.json automaticamente.',
                        style: AppText.microLabel(dark: dark),
                      ),
                      const SizedBox(height: Sp.s16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.notionBlue,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                          icon: Icon(
                            _showAdvanced ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          label: Text(
                            _showAdvanced ? 'Ocultar opções avançadas' : 'Mostrar opções avançadas',
                          ),
                        ),
                      ),
                      if (_showAdvanced) ...[
                        const SizedBox(height: Sp.s8),
                        TextFormField(
                          controller: _countPath,
                          decoration: const InputDecoration(
                            labelText: 'Caminho da contagem no JSON',
                            hintText: 'total_count',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: Sp.s12),
                      ],
                      if (!_showAdvanced) const SizedBox(height: Sp.s8),
                      TextFormField(
                        controller: _pollSeconds,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Intervalo de monitoramento (segundos)',
                          hintText: '$defaultPollSeconds',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null) return 'Obrigatório';
                          if (parsed < minPollSeconds) return 'Mínimo $minPollSeconds segundos';
                          return null;
                        },
                      ),
                      const SizedBox(height: Sp.s12),
                      DropdownButtonFormField<String>(
                        initialValue: _alertOn,
                        decoration: const InputDecoration(labelText: 'Notificar quando'),
                        items: const [
                          DropdownMenuItem(value: alertOnAny, child: Text('Qualquer mudança')),
                          DropdownMenuItem(value: alertOnIncrease, child: Text('Somente aumento')),
                          DropdownMenuItem(value: alertOnDecrease, child: Text('Somente diminuição')),
                        ],
                        onChanged: (value) => setState(() => _alertOn = value ?? alertOnAny),
                      ),
                      const SizedBox(height: Sp.s16),

                      // Consulta ativa custom switch
                      InkWell(
                        onTap: () => setState(() => _enabled = !_enabled),
                        borderRadius: BorderRadius.circular(AppRadius.subtle),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Sp.s8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Consulta ativa', style: AppText.body(dark: dark)),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 36,
                                height: 20,
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: _enabled ? AppColors.notionBlue : AppColors.warmGray300,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                alignment: _enabled ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: AppColors.pureWhite,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Divider(
                        color: dark ? AppColors.darkBorder : AppColors.whisperBorder,
                        height: Sp.s24,
                      ),

                      // ── Agendamento ─────────────────────────────────────
                      _ScheduleSection(
                        weekdays: _scheduleWeekdays,
                        startHour: _scheduleStartHour,
                        endHour: _scheduleEndHour,
                        dark: dark,
                        onWeekdaysChanged: (days) =>
                            setState(() => _scheduleWeekdays = days),
                        onStartHourChanged: (h) =>
                            setState(() => _scheduleStartHour = h),
                        onEndHourChanged: (h) =>
                            setState(() => _scheduleEndHour = h),
                      ),

                      Divider(
                        color: dark ? AppColors.darkBorder : AppColors.whisperBorder,
                        height: Sp.s24,
                      ),

                      // Template personalizado por consulta
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.notionBlue,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () =>
                              setState(() => _showCustomTemplate = !_showCustomTemplate),
                          icon: Icon(
                            _showCustomTemplate ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          label: const Text('Template de notificação personalizado (opcional)'),
                        ),
                      ),

                      if (_showCustomTemplate) ...[
                        const SizedBox(height: Sp.s4),
                        Text(
                          'Sobrescreve os templates globais apenas para está consulta.',
                          style: AppText.captionLight(dark: dark),
                        ),
                        const SizedBox(height: Sp.s12),
                        TextFormField(
                          controller: _customTitle,
                          decoration: const InputDecoration(
                            labelText: 'Titulo personalizado',
                            hintText: 'Deixe vazio para usar o template global',
                          ),
                        ),
                        const SizedBox(height: Sp.s12),
                        TextFormField(
                          controller: _customBody,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Corpo personalizado',
                            hintText: 'Deixe vazio para usar o template global',
                          ),
                        ),
                        const SizedBox(height: Sp.s12),
                        const Wrap(
                          spacing: 6,
                          runSpacing: 6,
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Sp.s24),

              // Actions
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: AppColors.warmGray500),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.notionBlue),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final resolved = _resolveUrls(_queryUrl.text.trim());
    if (resolved == null) return;

    final customTitleRaw = _customTitle.text.trim();
    final customBodyRaw = _customBody.text.trim();

    final result = MonitoredQuery(
      id: widget.initial?.id,
      name: _name.text.trim(),
      endpoint: resolved.endpoint,
      directUrl: resolved.directUrl,
      countPath: _countPath.text.trim(),
      pollSeconds: int.parse(_pollSeconds.text.trim()),
      enabled: _enabled,
      alertOn: _alertOn,
      lastCount: widget.initial?.lastCount,
      lastCheckedAt: widget.initial?.lastCheckedAt,
      notificationTitleTemplate: customTitleRaw.isEmpty ? null : customTitleRaw,
      notificationBodyTemplate: customBodyRaw.isEmpty ? null : customBodyRaw,
      scheduleWeekdays: _scheduleWeekdays,
      scheduleStartHour: _scheduleStartHour,
      scheduleEndHour: _scheduleEndHour,
    );

    Navigator.of(context).pop(result);
  }

  Uri? _parseUserUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) return uri;
    if (!value.startsWith('/')) return null;
    return Uri.parse('https://placeholder.local$value');
  }

  _ResolvedUrls? _resolveUrls(String value) {
    final parsed = _parseUserUrl(value);
    if (parsed == null) return null;

    // Always store paths only — base URL comes from global settings at runtime.
    final directPath = _toPathAndQuery(parsed);
    final apiPath = _toJsonPath(parsed.path);
    final endpointPath = _toPathAndQuery(parsed.replace(path: apiPath));

    return _ResolvedUrls(endpoint: endpointPath, directUrl: directPath);
  }

  String _toJsonPath(String path) {
    if (path.endsWith('.json')) return path;
    if (path.endsWith('/')) return '${path.substring(0, path.length - 1)}.json';
    return '$path.json';
  }

  String _toPathAndQuery(Uri uri) {
    final query = uri.query;
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }
}

class _ResolvedUrls {
  _ResolvedUrls({required this.endpoint, required this.directUrl});

  final String endpoint;
  final String directUrl;
}

// ─── Schedule section ─────────────────────────────────────────────────────────

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.weekdays,
    required this.startHour,
    required this.endHour,
    required this.dark,
    required this.onWeekdaysChanged,
    required this.onStartHourChanged,
    required this.onEndHourChanged,
  });

  final List<int> weekdays;
  final int startHour;
  final int endHour;
  final bool dark;
  final ValueChanged<List<int>> onWeekdaysChanged;
  final ValueChanged<int> onStartHourChanged;
  final ValueChanged<int> onEndHourChanged;

  static const _labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_outlined, size: 15, color: AppColors.blue),
            const SizedBox(width: 6),
            Text(
              'AGENDAMENTO',
              style: AppText.caption(dark: dark).copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.s12),

        // Day-of-week chips
        Text('Dias da semana', style: AppText.caption(dark: dark)),
        const SizedBox(height: Sp.s8),
        Wrap(
          spacing: 6,
          children: List.generate(7, (i) {
            final day = i + 1;
            final selected = weekdays.contains(day);
            return _DayChip(
              label: _labels[i],
              selected: selected,
              dark: dark,
              onTap: () {
                final next = List<int>.from(weekdays);
                if (selected) {
                  next.remove(day);
                } else {
                  next.add(day);
                  next.sort();
                }
                onWeekdaysChanged(next);
              },
            );
          }),
        ),

        if (weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Atenção: nenhum dia selecionado — consulta nunca será executada.',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.orange),
            ),
          ),

        const SizedBox(height: Sp.s12),

        // Hour range
        Text('Horário', style: AppText.caption(dark: dark)),
        const SizedBox(height: Sp.s8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: startHour,
                decoration: const InputDecoration(
                  labelText: 'Início',
                  isDense: true,
                ),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h,
                  child: Text('${h.toString().padLeft(2, '0')}:00'),
                )),
                onChanged: (v) => onStartHourChanged(v ?? defaultScheduleStartHour),
              ),
            ),
            const SizedBox(width: Sp.s12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: endHour,
                decoration: const InputDecoration(
                  labelText: 'Fim',
                  isDense: true,
                ),
                items: List.generate(24, (h) => DropdownMenuItem(
                  value: h,
                  child: Text('${h.toString().padLeft(2, '0')}:00'),
                )),
                onChanged: (v) => onEndHourChanged(v ?? defaultScheduleEndHour),
              ),
            ),
          ],
        ),

        if (startHour == endHour)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Atenção: início e fim iguais — consulta nunca será executada.',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.orange),
            ),
          ),
        if (startHour > endHour)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Janela noturna: monitora das ${startHour.toString().padLeft(2, '0')}h '
              'até ${endHour.toString().padLeft(2, '0')}h do dia seguinte.',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.warmGray500),
            ),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.blue
        : (dark ? AppColors.darkCard : AppColors.warmWhite);
    final fg = selected
        ? AppColors.white
        : (dark ? AppColors.darkMuted : AppColors.warmDark);
    final border = selected
        ? AppColors.blue
        : (dark ? AppColors.darkBorder : AppColors.borderLight);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.subtle),
          border: Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}
