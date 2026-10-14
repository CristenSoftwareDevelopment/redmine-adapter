import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alert_rule.dart';
import '../../models/monitored_query.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';

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
  late final List<_RuleDraft> _rules;
  bool _enabled = true;
  bool _pinned = false;
  bool _showAdvanced = false;

  // Source of the query: a saved Redmine query (picker) or a pasted URL.
  late bool _manualUrl;
  List<SavedQuery>? _saved;
  String? _savedError;
  SavedQuery? _selected;
  String? _pickerError;
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
    _rules = (item?.alertRules ?? const [AlertRule()]).map(_RuleDraft.new).toList();
    _enabled = item?.enabled ?? true;
    _pinned = item?.pinned ?? false;
    _scheduleWeekdays = List<int>.from(item?.scheduleWeekdays ?? defaultScheduleWeekdays);
    _scheduleStartHour = item?.scheduleStartHour ?? defaultScheduleStartHour;
    _scheduleEndHour = item?.scheduleEndHour ?? defaultScheduleEndHour;
    _manualUrl = item != null && SavedQuery.idFromEndpoint(item.endpoint) == null;
    _loadSavedQueries();
  }

  @override
  void dispose() {
    _name.dispose();
    _queryUrl.dispose();
    _countPath.dispose();
    _pollSeconds.dispose();
    for (final rule in _rules) {
      rule.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = SizedBox(height: 17);

    return AppDialog(
      title: Text(widget.initial == null ? 'Nova consulta' : 'Editar consulta'),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 17),
          label: const Text('Salvar'),
        ),
      ],
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppTabs<bool>(
                tabs: const [
                  (false, 'Consulta salva', Icons.push_pin_outlined),
                  (true, 'URL manual', Icons.link),
                ],
                selected: _manualUrl,
                onChanged: (v) => setState(() => _manualUrl = v),
              ),
            ),
            const SizedBox(height: 20),
            if (!_manualUrl) _buildSavedPicker(dark),
            if (_savedError != null) ...[
              Text(
                'Não foi possível carregar as consultas salvas: $_savedError',
                style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
              ),
              const SizedBox(height: 8),
            ],
            if (_manualUrl)
              LabeledField(
                label: 'URL da consulta no Redmine',
                child: TextFormField(
                  controller: _queryUrl,
                  decoration: const InputDecoration(
                    hintText: 'https://seu-redmine.com/projects/x/issues?query_id=123',
                    helperText:
                        'Inclua os filtros ou o query_id da lista de tarefas. O app gera o endpoint /issues.json.',
                    helperMaxLines: 2,
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
              ),
            gap,
            LabeledField(
              label: 'Nome da consulta',
              child: TextFormField(
                controller: _name,
                validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
              ),
            ),
            const SizedBox(height: 8),
            _SwitchLine(
              label: 'Consulta ativa',
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            _SwitchLine(
              label: 'Fixar no menu como board',
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
            ),
            const Divider(height: 46),
            _ScheduleSection(
              weekdays: _scheduleWeekdays,
              startHour: _scheduleStartHour,
              endHour: _scheduleEndHour,
              dark: dark,
              onWeekdaysChanged: (days) => setState(() => _scheduleWeekdays = days),
              onStartHourChanged: (h) => setState(() => _scheduleStartHour = h),
              onEndHourChanged: (h) => setState(() => _scheduleEndHour = h),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 18),
                label: const Text('Opções avançadas'),
              ),
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              LabeledField(
                label: 'Intervalo de verificação (segundos)',
                child: TextFormField(
                  controller: _pollSeconds,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '$defaultPollSeconds',
                    helperText: 'Mínimo de $minPollSeconds segundos.',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null) return 'Obrigatório';
                    if (parsed < minPollSeconds) return 'Mínimo $minPollSeconds segundos';
                    return null;
                  },
                ),
              ),
              gap,
              LabeledField(
                label: 'Caminho da contagem no JSON',
                child: TextFormField(
                  controller: _countPath,
                  decoration: const InputDecoration(hintText: 'total_count'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                ),
              ),
            ],
            const Divider(height: 46),
            _buildRules(dark),
          ],
        ),
      ),
    );
  }

  Widget _buildRules(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(icon: Icons.notifications_none, text: 'Regras de notificação'),
        Text(
          'Avaliadas quando a contagem muda. A primeira regra atendida dispara a notificação — arraste para reordenar.',
          style: AppText.microLabel(dark: dark),
        ),
        const SizedBox(height: 12),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (from, to) => setState(() {
            if (to > from) to--;
            _rules.insert(to, _rules.removeAt(from));
          }),
          children: [
            for (var i = 0; i < _rules.length; i++) _buildRuleTile(i, dark),
          ],
        ),
        if (_rules.isEmpty)
          Text(
            'Sem regras: esta consulta nunca vai notificar.',
            style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => setState(() => _rules.add(_RuleDraft(const AlertRule()))),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar regra'),
        ),
        if (_rules.any((r) => r.expanded))
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
    );
  }

  Widget _buildRuleTile(int index, bool dark) {
    final rule = _rules[index];
    final hasCustomText = rule.title.text.trim().isNotEmpty || rule.body.text.trim().isNotEmpty;
    return Container(
      key: ObjectKey(rule),
      margin: const EdgeInsets.only(bottom: Sp.s8),
      padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s8, Sp.s4, Sp.s8),
      decoration: BoxDecoration(
        color: AppColors.field(dark: dark),
        border: Border.all(color: AppColors.border(dark: dark)),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.all(Sp.s4),
                    child: Icon(Icons.drag_indicator, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: rule.op,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final e in alertRuleOps.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => rule.op = v ?? ruleAny),
                ),
              ),
              if (AlertRule(op: rule.op).needsValue) ...[
                const SizedBox(width: Sp.s8),
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    controller: rule.value,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true, hintText: 'N'),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return n == null || n < 0 ? 'Nº' : null;
                    },
                  ),
                ),
              ],
              IconButton(
                tooltip: 'Mensagem desta regra',
                onPressed: () => setState(() => rule.expanded = !rule.expanded),
                icon: Icon(
                  rule.expanded ? Icons.expand_less : Icons.edit_note,
                  size: 20,
                  color: hasCustomText
                      ? AppColors.accent(dark: dark)
                      : AppColors.mutedText(dark: dark),
                ),
              ),
              IconButton(
                tooltip: 'Remover regra',
                onPressed: () => setState(() {
                  final removed = _rules.removeAt(index);
                  // Fields still reference the controllers until this frame ends.
                  WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                }),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          if (rule.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.s32, Sp.s8, Sp.s8, 0),
              child: Column(
                children: [
                  TextFormField(
                    controller: rule.title,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      hintText: 'Vazio = template global',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: Sp.s8),
                  TextFormField(
                    controller: rule.body,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Corpo',
                      hintText: 'Vazio = template global',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadSavedQueries() async {
    try {
      final saved = await RedmineApiService().listSavedQueries(context.read<AppState>().settings);
      if (!mounted) return;
      final currentId = SavedQuery.idFromEndpoint(widget.initial?.endpoint);
      setState(() {
        _saved = saved;
        _selected = saved.where((q) => q.id == currentId).firstOrNull;
        // Editing a query_id the user can no longer see: keep the raw URL.
        if (currentId != null && _selected == null) _manualUrl = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savedError = '$error'.replaceFirst('Exception: ', '');
        _manualUrl = true;
      });
    }
  }

  Widget _buildSavedPicker(bool dark) {
    final saved = _saved;
    if (saved == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Sp.s8),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Sp.s8),
            Text('Carregando consultas do Redmine…', style: AppText.caption(dark: dark)),
          ],
        ),
      );
    }
    return DropdownMenu<SavedQuery>(
      initialSelection: _selected,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 320,
      label: const Text('Consulta salva no Redmine'),
      hintText: 'Digite para buscar…',
      errorText: _pickerError,
      leadingIcon: const Icon(Icons.search, size: 18),
      dropdownMenuEntries: [
        for (final q in saved)
          DropdownMenuEntry(
            value: q,
            label: q.label,
            trailingIcon: q.isPublic
                ? null
                : const Tooltip(
                    message: 'Consulta privada',
                    child: Icon(Icons.lock_outline, size: 14),
                  ),
          ),
      ],
      onSelected: (q) => setState(() {
        _selected = q;
        _pickerError = null;
        if (q != null && _name.text.trim().isEmpty) _name.text = q.name;
      }),
    );
  }

  void _submit() {
    final missingPick = !_manualUrl && _selected == null;
    setState(() => _pickerError = missingPick ? 'Selecione uma consulta' : null);
    if (!_formKey.currentState!.validate() || missingPick) return;

    final _ResolvedUrls? resolved;
    if (_manualUrl) {
      resolved = _resolveUrls(_queryUrl.text.trim());
    } else {
      final initial = widget.initial;
      // Same saved query as before: keep the stored URL (may carry extra params).
      final unchanged =
          initial != null && SavedQuery.idFromEndpoint(initial.endpoint) == _selected!.id;
      resolved = unchanged
          ? _ResolvedUrls(endpoint: initial.endpoint, directUrl: initial.directUrl)
          : _ResolvedUrls(endpoint: _selected!.endpoint, directUrl: _selected!.directUrl);
    }
    if (resolved == null) return;

    final result = MonitoredQuery(
      id: widget.initial?.id,
      name: _name.text.trim(),
      endpoint: resolved.endpoint,
      directUrl: resolved.directUrl,
      countPath: _countPath.text.trim(),
      pollSeconds: int.parse(_pollSeconds.text.trim()),
      enabled: _enabled,
      pinned: _pinned,
      alertRules: _rules.map((r) => r.toRule()).toList(),
      lastCount: widget.initial?.lastCount,
      lastCheckedAt: widget.initial?.lastCheckedAt,
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

/// Editable state of one [AlertRule] in the form.
class _RuleDraft {
  _RuleDraft(AlertRule rule)
      : op = rule.op,
        value = TextEditingController(text: rule.value?.toString() ?? ''),
        title = TextEditingController(text: rule.titleTemplate ?? ''),
        body = TextEditingController(text: rule.bodyTemplate ?? ''),
        expanded = rule.titleTemplate != null || rule.bodyTemplate != null;

  String op;
  final TextEditingController value;
  final TextEditingController title;
  final TextEditingController body;
  bool expanded;

  AlertRule toRule() {
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return AlertRule(
      op: op,
      value: AlertRule(op: op).needsValue ? int.tryParse(value.text.trim()) : null,
      titleTemplate: text(title),
      bodyTemplate: text(body),
    );
  }

  void dispose() {
    value.dispose();
    title.dispose();
    body.dispose();
  }
}

class _ResolvedUrls {
  _ResolvedUrls({required this.endpoint, required this.directUrl});

  final String endpoint;
  final String directUrl;
}

/// "Label ............ [switch]" line.
class _SwitchLine extends StatelessWidget {
  const _SwitchLine({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.body(dark: dark))),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
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

  Widget _hour(String label, int value, ValueChanged<int?> onChanged) => LabeledField(
        label: label,
        child: DropdownButtonFormField<int>(
          initialValue: value,
          isDense: true,
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _warning(String text, {bool danger = true}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: AppText.microLabel(dark: dark).copyWith(
            color: danger ? AppColors.danger(dark: dark) : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(icon: Icons.calendar_today_outlined, text: 'Agendamento'),
        LabeledField(
          label: 'Dias da semana',
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (var i = 0; i < 7; i++)
                _DayButton(
                  label: _labels[i],
                  selected: weekdays.contains(i + 1),
                  onTap: () {
                    final day = i + 1;
                    final next = List<int>.from(weekdays);
                    next.contains(day) ? next.remove(day) : (next..add(day)).sort();
                    onWeekdaysChanged(next);
                  },
                ),
            ],
          ),
        ),
        if (weekdays.isEmpty)
          _warning('Atenção: nenhum dia selecionado — consulta nunca será executada.'),
        const SizedBox(height: 17),
        Row(
          children: [
            Expanded(
              child: _hour(
                  'Início', startHour, (v) => onStartHourChanged(v ?? defaultScheduleStartHour)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _hour('Fim', endHour, (v) => onEndHourChanged(v ?? defaultScheduleEndHour)),
            ),
          ],
        ),
        if (startHour == endHour)
          _warning('Atenção: início e fim iguais — consulta nunca será executada.'),
        if (startHour > endHour)
          _warning(
            'Janela noturna: monitora das ${startHour.toString().padLeft(2, '0')}h '
            'até ${endHour.toString().padLeft(2, '0')}h do dia seguinte.',
            danger: false,
          ),
      ],
    );
  }
}

/// Day-of-week toggle: bordered, filled with the accent when selected.
class _DayButton extends StatelessWidget {
  const _DayButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.accent(dark: dark);
    return Material(
      color: selected ? accent : AppColors.field(dark: dark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.standard),
        side: BorderSide(color: selected ? accent : AppColors.border(dark: dark)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: AppText.caption(dark: dark).copyWith(
              fontSize: 11,
              color: selected ? AppColors.onAccent(dark: dark) : AppColors.text(dark: dark),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
