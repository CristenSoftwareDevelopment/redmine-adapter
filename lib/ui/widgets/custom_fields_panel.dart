import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/custom_field.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';

/// Settings panel with the type and choices of each issue custom field, used
/// to show and edit them in the issue dialog. Saved right away.
class CustomFieldsPanel extends StatefulWidget {
  const CustomFieldsPanel({super.key});

  @override
  State<CustomFieldsPanel> createState() => _CustomFieldsPanelState();
}

class _CustomFieldsPanelState extends State<CustomFieldsPanel> {
  bool _busy = false;

  /// Admin key: Redmine's own definitions replace the list. Otherwise (403)
  /// recent issues are scanned and only fields not saved yet are added.
  Future<void> _import() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final api = RedmineApiService();
    setState(() => _busy = true);
    try {
      List<CustomFieldDef> next;
      String message;
      try {
        final json = await api.getJson(state.settings, '/custom_fields.json');
        next = [
          for (final f in (json['custom_fields'] as List? ?? const []).whereType<Map>())
            if (f['customized_type'] == 'issue') CustomFieldDef.fromJson(f),
        ];
        message = '${next.length} campos importados do Redmine.';
      } on Exception catch (error) {
        if (!RegExp(r'HTTP 40[13]').hasMatch('$error')) rethrow;
        final issues = await api.getAllPages(
          state.settings,
          '/issues.json?status_id=*&sort=updated_on:desc',
          'issues',
          cap: 300,
        );
        final known = {for (final f in state.settings.customFields) f.id};
        final added = [
          for (final f in scanCustomFields(issues))
            if (!known.contains(f.id)) f,
        ];
        next = [...state.settings.customFields, ...added];
        message = 'Sem chave admin: ${added.length} campos novos sugeridos a partir de '
            '${issues.length} tarefas. Revise os tipos.';
      }
      await state.savePreferences(state.settings.copyWith(customFields: next));
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text('Falha ao buscar campos: ${'$error'.replaceFirst('Exception: ', '')}'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(List<CustomFieldDef> fields) {
    final state = context.read<AppState>();
    return state.savePreferences(state.settings.copyWith(customFields: fields));
  }

  Future<void> _edit(List<CustomFieldDef> fields, int index) async {
    final edited = await showAppDialog<CustomFieldDef>(
      context,
      (_) => _CustomFieldDialog(initial: fields[index]),
    );
    if (edited != null && mounted) await _save([...fields]..[index] = edited);
  }

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<AppState>().settings.customFields;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: const Text('Campos personalizados'),
            subtitle: 'Tipo e valores de cada campo, usados para mostrar e editar tarefas. '
                'Com chave admin vêm do Redmine; sem ela são sugeridos pelas tarefas recentes '
                'e você revisa. Salvos na hora.',
            trailing: OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined, size: 17),
              label: const Text('Buscar no Redmine'),
            ),
          ),
          if (fields.isEmpty)
            const EmptyState(icon: Icons.tune, text: 'Nenhum campo ainda: use Buscar no Redmine.')
          else
            for (var i = 0; i < fields.length; i++)
              ListRow(
                leading: const IconBox(icon: Icons.tune),
                title: Text(fields[i].name),
                meta: [
                  Text([
                    fieldFormats[fields[i].format] ?? '${fields[i].format} (não editável)',
                    if (fields[i].multiple) 'múltiplo',
                    if (fields[i].hasOptions) '${fields[i].options.length} valores',
                  ].join(' · ')),
                ],
                onTap: () => _edit(fields, i),
                actions: [
                  IconBtn(
                    icon: Icons.delete_outline,
                    tooltip: 'Excluir campo',
                    compact: true,
                    onPressed: () => _save([...fields]..removeAt(i)),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Pops the edited [CustomFieldDef]: type, multiple and the list values.
class _CustomFieldDialog extends StatefulWidget {
  const _CustomFieldDialog({required this.initial});

  final CustomFieldDef initial;

  @override
  State<_CustomFieldDialog> createState() => _CustomFieldDialogState();
}

class _CustomFieldDialogState extends State<_CustomFieldDialog> {
  late String _format = widget.initial.format;
  late bool _multiple = widget.initial.multiple;
  late final _values = TextEditingController(
    text: [
      for (final (value, label) in widget.initial.options)
        widget.initial.format == 'enumeration' ? '$value=$label' : value,
    ].join('\n'),
  );

  /// Formats offered; an unknown one (e.g. attachment) stays as it came.
  late final _formats = [
    ...fieldFormats.keys,
    if (!fieldFormats.containsKey(widget.initial.format)) widget.initial.format,
  ];

  bool get _canBeMultiple => const {'list', 'enumeration', 'user', 'version'}.contains(_format);

  @override
  void dispose() {
    _values.dispose();
    super.dispose();
  }

  /// One value per line; `id=Rótulo` for key/value lists.
  List<(String, String)> get _options => [
        for (final line in _values.text.split('\n').map((l) => l.trim()))
          if (line.isNotEmpty)
            if (_format == 'enumeration' && line.contains('='))
              (
                line.substring(0, line.indexOf('=')).trim(),
                line.substring(line.indexOf('=') + 1).trim(),
              )
            else
              (line, line),
      ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasOptions = _format == 'list' || _format == 'enumeration';
    return AppDialog(
      width: 560,
      title: Text(widget.initial.name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Tipo',
            child: SearchSelect(
              value: _formats.indexOf(_format),
              options: [
                for (final (i, f) in _formats.indexed) (i, fieldFormats[f] ?? '$f (não editável)'),
              ],
              onChanged: (i) => setState(() => _format = _formats[i ?? 0]),
            ),
          ),
          if (_canBeMultiple)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _multiple,
              onChanged: (v) => setState(() => _multiple = v ?? false),
              title: const Text('Aceita vários valores'),
            ),
          if (hasOptions) ...[
            const SizedBox(height: 12),
            LabeledField(
              label: _format == 'enumeration'
                  ? 'Valores, um por linha (id=Rótulo)'
                  : 'Valores, um por linha',
              child: TextField(controller: _values, minLines: 4, maxLines: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'O Redmine só aceita valores da lista: inclua os que faltarem.',
              style: AppText.microLabel(dark: dark),
            ),
          ],
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(widget.initial.copyWith(
            format: _format,
            multiple: _multiple && _canBeMultiple,
            options: hasOptions ? _options : const [],
          )),
          child: const Text('Salvar campo'),
        ),
      ],
    );
  }
}
