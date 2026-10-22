import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claude_action.dart';
import '../../models/handoff_rule.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../icon_picker.dart';

/// Settings panel with every issue action (trâmites and Claude Code) in one
/// list: dragging sets the order of the buttons in the issue dialog and ⋮ menu.
class ActionOrderPanel extends StatelessWidget {
  const ActionOrderPanel({super.key});

  /// Each action gets its new position as `order`; the lists themselves keep
  /// their order, so the editors above don't move.
  Future<void> _reorder(AppState state, List<Object> actions, int from, int to) {
    final moved = [...actions];
    moved.insert(to > from ? to - 1 : to, moved.removeAt(from));
    final settings = state.settings;
    return state.savePreferences(settings.copyWith(
      claudeActions: [for (final a in settings.claudeActions) a.withOrder(moved.indexOf(a))],
      handoffRules: [for (final r in settings.handoffRules) r.withOrder(moved.indexOf(r))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final actions = settings.orderedActions;
    if (actions.length < 2) return const SizedBox.shrink();
    Widget row(Key key, IconData icon, String name, String kind) => ListRow(
          key: key,
          leading: IconBox(icon: icon),
          title: Text(name),
          meta: [Text(kind)],
          trailing: const SizedBox(width: 24), // room for the drag handle
        );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHead(
            title: Text('Ordem dos botões'),
            subtitle: 'Arraste para definir a ordem das ações na tarefa e no menu ⋮. '
                'Salva na hora.',
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (from, to) => _reorder(state, actions, from, to),
            children: [
              for (final action in actions)
                switch (action) {
                  ClaudeAction a => row(ValueKey('claude-${settings.claudeActions.indexOf(a)}'),
                      actionIcon(a.icon, Icons.terminal), a.name, 'Claude Code'),
                  HandoffRule r => row(ValueKey('rule-${settings.handoffRules.indexOf(r)}'),
                      actionIcon(r.icon, Icons.send_outlined), r.name, 'Trâmite'),
                  _ => SizedBox.shrink(key: ObjectKey(action)),
                },
            ],
          ),
        ],
      ),
    );
  }
}
