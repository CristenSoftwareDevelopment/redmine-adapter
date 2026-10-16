import 'package:flutter/material.dart';

import '../services/theme_service.dart';
import 'components.dart';
import 'ui_utils.dart';

/// Icons offered for automation buttons, saved by key. A fixed const map (not
/// code points built at runtime) keeps Flutter's icon tree-shaking working in
/// release builds.
// ponytail: curated Material subset; add entries here when one is missing.
const actionIcons = <String, (IconData, String)>{
  'terminal': (Icons.terminal, 'terminal'),
  'code': (Icons.code, 'código'),
  'rate_review': (Icons.rate_review_outlined, 'code review revisão'),
  'fact_check': (Icons.fact_check_outlined, 'conferir checklist'),
  'checklist': (Icons.checklist, 'lista checklist'),
  'task_alt': (Icons.task_alt, 'concluir ok'),
  'verified': (Icons.verified_outlined, 'verificado qualidade qa'),
  'bug_report': (Icons.bug_report_outlined, 'bug erro'),
  'science': (Icons.science_outlined, 'teste qa'),
  'send': (Icons.send_outlined, 'enviar trâmite'),
  'forward': (Icons.forward_to_inbox_outlined, 'encaminhar'),
  'reply': (Icons.reply, 'responder'),
  'chat': (Icons.chat_bubble_outline, 'comentário conversa'),
  'edit_note': (Icons.edit_note, 'nota texto trâmite'),
  'article': (Icons.article_outlined, 'documento texto'),
  'description': (Icons.description_outlined, 'descrição arquivo'),
  'smart_toy': (Icons.smart_toy_outlined, 'robô ia claude'),
  'auto_awesome': (Icons.auto_awesome_outlined, 'ia mágica'),
  'psychology': (Icons.psychology_outlined, 'análise ia'),
  'lightbulb': (Icons.lightbulb_outline, 'ideia'),
  'bolt': (Icons.bolt, 'raio automação'),
  'rocket': (Icons.rocket_launch_outlined, 'deploy lançar'),
  'play': (Icons.play_arrow_outlined, 'iniciar executar'),
  'build': (Icons.build_outlined, 'ferramenta build'),
  'merge': (Icons.merge_type, 'merge'),
  'branch': (Icons.call_split, 'branch'),
  'commit': (Icons.commit, 'commit'),
  'search': (Icons.search, 'buscar'),
  'link': (Icons.link, 'link'),
  'folder': (Icons.folder_open_outlined, 'pasta'),
  'storage': (Icons.storage, 'banco dados'),
  'cloud': (Icons.cloud_outlined, 'nuvem'),
  'security': (Icons.security, 'segurança'),
  'speed': (Icons.speed, 'performance'),
  'timer': (Icons.timer_outlined, 'tempo horas'),
  'schedule': (Icons.schedule, 'agenda horário'),
  'flag': (Icons.flag_outlined, 'marcar bandeira'),
  'star': (Icons.star_outline, 'estrela favorito'),
  'thumb_up': (Icons.thumb_up_outlined, 'aprovar'),
  'person': (Icons.person_outline, 'pessoa'),
  'groups': (Icons.groups_outlined, 'time equipe'),
  'notifications': (Icons.notifications_none, 'notificação'),
};

/// Icon for a saved key, or [fallback] when unset/unknown.
IconData actionIcon(String? key, IconData fallback) => actionIcons[key]?.$1 ?? fallback;

/// Field showing the chosen icon; opens a searchable grid to pick another.
class IconPickerField extends StatelessWidget {
  const IconPickerField({
    super.key,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String? value;
  final IconData fallback;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () async {
          final picked = await showAppDialog<String>(
            context,
            (_) => _IconPickerDialog(selected: value),
          );
          // '' = "Padrão" chosen in the dialog.
          if (picked != null) onChanged(picked.isEmpty ? null : picked);
        },
        icon: Icon(actionIcon(value, fallback), size: 18),
        label: Text(value == null ? 'Ícone padrão · trocar' : 'Trocar ícone'),
      ),
    );
  }
}

class _IconPickerDialog extends StatefulWidget {
  const _IconPickerDialog({this.selected});

  final String? selected;

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final q = searchKey(_search.trim());
    final shown = [
      for (final e in actionIcons.entries)
        if (q.isEmpty || searchKey('${e.key} ${e.value.$2}').contains(q)) e,
    ];
    return AppDialog(
      title: const Text('Escolher ícone'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchField(
            width: double.infinity,
            hint: 'Buscar ícone (ex. teste, código, enviar)…',
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in shown)
                Tooltip(
                  message: e.value.$2,
                  child: Material(
                    color: e.key == widget.selected
                        ? AppColors.accentSoft(dark: dark)
                        : AppColors.field(dark: dark),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.standard),
                      side: BorderSide(
                        color: e.key == widget.selected
                            ? AppColors.accent(dark: dark)
                            : AppColors.border(dark: dark),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(e.key),
                      borderRadius: BorderRadius.circular(AppRadius.standard),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(e.value.$1, size: 22, color: AppColors.text(dark: dark)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (shown.isEmpty)
            Text('Nenhum ícone encontrado.', style: AppText.captionLight(dark: dark)),
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Usar o padrão'),
        ),
      ],
    );
  }
}
