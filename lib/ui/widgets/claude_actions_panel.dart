import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claude_action.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../icon_picker.dart';

/// Settings panel with the "Claude Code" actions shown in the issue dialog.
/// Saved right away, independent of the "Salvar configuração" button.
class ClaudeActionsPanel extends StatelessWidget {
  const ClaudeActionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<AppState>().settings.claudeActions;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: const Text('Claude Code'),
            subtitle: 'Comandos abertos no Claude Code, na pasta do projeto, a partir da tarefa '
                '(ex. /pano-cr refs #{{numeroAtividade}}). Salvos na hora.',
            trailing: OutlinedButton.icon(
              onPressed: () => _edit(context, actions, null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Nova ação'),
            ),
          ),
          if (actions.isEmpty)
            const EmptyState(icon: Icons.terminal, text: 'Nenhuma ação ainda.')
          else
            for (var i = 0; i < actions.length; i++)
              ListRow(
                leading: IconBox(icon: actionIcon(actions[i].icon, Icons.terminal)),
                title: Text(actions[i].name),
                meta: [
                  Text(actions[i].template, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      actions[i].openInApp ? 'App (experimental)' : 'Terminal',
                      if (actions[i].cwd.isNotEmpty) actions[i].cwd,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                onTap: () => _edit(context, actions, i),
                actions: [
                  IconBtn(
                    icon: Icons.delete_outline,
                    tooltip: 'Excluir ação',
                    compact: true,
                    onPressed: () => _save(context, [...actions]..removeAt(i)),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, List<ClaudeAction> actions, int? index) async {
    final action = await showAppDialog<ClaudeAction>(
      context,
      (_) => _ClaudeActionDialog(initial: index == null ? null : actions[index]),
    );
    if (action == null || !context.mounted) return;
    // An edited action keeps its place among the buttons.
    await _save(
      context,
      index == null
          ? [...actions, action]
          : ([...actions]..[index] = action.withOrder(actions[index].order)),
    );
  }

  Future<void> _save(BuildContext context, List<ClaudeAction> actions) {
    final state = context.read<AppState>();
    return state.savePreferences(state.settings.copyWith(claudeActions: actions));
  }
}

/// Pops the edited [ClaudeAction].
class _ClaudeActionDialog extends StatefulWidget {
  const _ClaudeActionDialog({this.initial});

  final ClaudeAction? initial;

  @override
  State<_ClaudeActionDialog> createState() => _ClaudeActionDialogState();
}

class _ClaudeActionDialogState extends State<_ClaudeActionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? 'Code review');
  late String? _icon = widget.initial?.icon;
  late bool _openInApp = widget.initial?.openInApp ?? false;
  late final _cwd = TextEditingController(text: widget.initial?.cwd ?? '');
  late final _template = TextEditingController(
    text: widget.initial?.template ?? '/pano-cr refs #{{numeroAtividade}}',
  );
  late int? _statusId = widget.initial?.statusId;
  late final Set<int> _showTrackers = {...?widget.initial?.trackerIds};
  late final Set<int> _showStatuses = {...?widget.initial?.statusIds};
  List<(int, String)>? _trackers;
  List<(int, String)>? _statuses;
  String? _statusesError;

  @override
  void initState() {
    super.initState();
    final api = RedmineApiService();
    final settings = context.read<AppState>().settings;
    Future.wait([
      api.listNamed(settings, '/trackers.json', 'trackers'),
      api.listNamed(settings, '/issue_statuses.json', 'issue_statuses'),
    ]).then((lists) {
      if (!mounted) return;
      setState(() {
        _trackers = lists[0];
        _statuses = lists[1];
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _statusesError = '$e'.replaceFirst('Exception: ', ''));
    });
  }

  /// Chips of a "show only on" filter; none checked = every one.
  Widget _filter(String label, List<(int, String)> options, Set<int> picked) => LabeledField(
        label: label,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (id, name) in options)
              FilterChip(
                label: Text(name),
                selected: picked.contains(id),
                onSelected: (on) => setState(() => on ? picked.add(id) : picked.remove(id)),
              ),
          ],
        ),
      );

  @override
  void dispose() {
    _name.dispose();
    _cwd.dispose();
    _template.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(
      initialDirectory: _cwd.text.trim().isEmpty ? null : _cwd.text.trim(),
      confirmButtonText: 'Escolher',
    );
    if (path != null && mounted) setState(() => _cwd.text = path);
  }

  String? _required(String? v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 17);
    return AppDialog(
      title: Text(widget.initial == null ? 'Nova ação do Claude Code' : 'Editar ação'),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Nome do botão',
              child: TextFormField(controller: _name, validator: _required),
            ),
            gap,
            LabeledField(
              label: 'Ícone do botão',
              child: IconPickerField(
                value: _icon,
                fallback: Icons.terminal,
                onChanged: (v) => setState(() => _icon = v),
              ),
            ),
            gap,
            LabeledField(
              label: 'Abrir em',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentButtons<bool>(
                    segments: const [
                      (false, 'Terminal', Icons.terminal),
                      (true, 'App (experimental)', Icons.desktop_windows_outlined),
                    ],
                    selected: _openInApp,
                    onChanged: (v) => setState(() => _openInApp = v),
                  ),
                  if (_openInApp)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Abre a nova sessão do Claude Desktop com o texto preenchido; escolha a '
                        'pasta lá e envie. O texto vai como mensagem (o /comando pode não rodar '
                        'como skill) e também é copiado. A pasta abaixo é usada se o app não abrir.',
                        style: AppText.microLabel(
                            dark: Theme.of(context).brightness == Brightness.dark),
                      ),
                    ),
                ],
              ),
            ),
            gap,
            LabeledField(
              label: _openInApp ? 'Pasta do projeto (reserva no terminal)' : 'Pasta do projeto',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // Only the native picker fills it, so the path is always absolute.
                    child: TextFormField(
                      controller: _cwd,
                      readOnly: true,
                      onTap: _pickFolder,
                      decoration: const InputDecoration(hintText: 'Nenhuma pasta escolhida'),
                      // Only the terminal needs it; the app picks the folder itself.
                      validator: (v) =>
                          !_openInApp && (v ?? '').trim().isEmpty ? 'Escolha uma pasta' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 17),
                    label: const Text('Escolher pasta…'),
                  ),
                ],
              ),
            ),
            gap,
            LabeledField(
              label: 'Comando',
              child: TextFormField(
                controller: _template,
                minLines: 1,
                maxLines: 4,
                validator: _required,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in claudePlaceholders.entries)
                  Tooltip(message: p.value, child: Tag(p.key)),
              ],
            ),
            if (_trackers != null && _statuses != null) ...[
              gap,
              _filter('Mostrar nas tarefas do tipo (nenhum marcado = todos)', _trackers!,
                  _showTrackers),
              gap,
              _filter('Mostrar nas tarefas na situação (nenhuma marcada = todas)', _statuses!,
                  _showStatuses),
            ],
            gap,
            LabeledField(
              label: 'Situação da tarefa ao abrir (ex. Em andamento)',
              child: _statusesError != null
                  ? Text(
                      'Não foi possível carregar tipos e situações: $_statusesError',
                      style:
                          AppText.microLabel(dark: Theme.of(context).brightness == Brightness.dark),
                    )
                  : _statuses == null
                      ? const LinearProgressIndicator(minHeight: 2)
                      : SelectBox<int?>(
                          value: _statusId,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Não alterar')),
                            for (final (id, name) in _statuses!)
                              DropdownMenuItem(value: id, child: Text(name)),
                            if (_statusId != null && !_statuses!.any((s) => s.$1 == _statusId))
                              DropdownMenuItem(value: _statusId, child: Text('#$_statusId')),
                          ],
                          onChanged: (v) => setState(() => _statusId = v),
                        ),
            ),
          ],
        ),
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              ClaudeAction(
                name: _name.text.trim(),
                icon: _icon,
                openInApp: _openInApp,
                cwd: _cwd.text.trim(),
                template: _template.text.trim(),
                statusId: _statusId,
                trackerIds: _showTrackers.toList(),
                statusIds: _showStatuses.toList(),
              ),
            );
          },
          child: const Text('Salvar ação'),
        ),
      ],
    );
  }
}
