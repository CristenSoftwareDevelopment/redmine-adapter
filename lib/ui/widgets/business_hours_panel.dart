import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/business_hours.dart';
import '../../models/time_entry.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';

/// Configurações › Expediente: working periods, each on its own weekdays
/// (add with +, remove with the bin). The hours counted for a trâmite inside
/// them are "Horas", the rest "Hora extra". Saved on change.
class BusinessHoursPanel extends StatelessWidget {
  const BusinessHoursPanel({super.key});

  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final state = context.watch<AppState>();
    final hours = state.settings.businessHours;
    final periods = hours.periods;

    Future<void> save(List<BusinessPeriod> next) =>
        state.savePreferences(state.settings.copyWith(businessHours: BusinessHours(periods: next)));
    void replace(int i, BusinessPeriod p) => save([...periods]..[i] = p);

    final week = [for (var d = 1; d <= 7; d++) hours.minutesOn(d)];
    final total = week.fold(0, (a, b) => a + b);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHead(
            title: const Text('Expediente'),
            subtitle: 'Períodos de trabalho por dia da semana. As horas calculadas nos trâmites '
                'dentro deles vão em "Horas"; o intervalo entre dois períodos do mesmo dia '
                '(almoço) não conta; o resto vai em "Hora extra". Salva na hora.',
            trailing: FilledButton.icon(
              // A new period starts on the days of the last one.
              onPressed: () => save([
                ...periods,
                BusinessPeriod(days: periods.lastOrNull?.days ?? const {1, 2, 3, 4, 5}),
              ]),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Adicionar período'),
            ),
          ),
          if (periods.isEmpty)
            const EmptyState(
              icon: Icons.schedule,
              text: 'Sem períodos: todo o tempo calculado conta como hora extra.',
            ),
          for (final (i, p) in periods.indexed)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final (d, name) in _days.indexed)
                            FilterChip(
                              label: Text(name),
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              selected: p.days.contains(d + 1),
                              onSelected: (on) => replace(
                                  i,
                                  p.copyWith(
                                      days:
                                          on ? {...p.days, d + 1} : ({...p.days}..remove(d + 1)))),
                            ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('das', style: AppText.caption(dark: dark)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: TimeSelect(
                                value: p.start, onChanged: (v) => replace(i, p.copyWith(start: v))),
                          ),
                          const SizedBox(width: 8),
                          Text('às', style: AppText.caption(dark: dark)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: TimeSelect(
                                value: p.end, onChanged: (v) => replace(i, p.copyWith(end: v))),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Excluir período',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => save([...periods]..removeAt(i)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (!p.valid)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        p.days.isEmpty
                            ? 'Escolha ao menos um dia: este período não conta.'
                            : 'O fim precisa ser depois do início: este período não conta.',
                        style: AppText.microLabel(dark: dark)
                            .copyWith(color: AppColors.danger(dark: dark)),
                      ),
                    ),
                ],
              ),
            ),
          // What the periods add up to, so different days are easy to check.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            decoration: BoxDecoration(
              color: AppColors.well(dark: dark),
              border: Border(top: BorderSide(color: AppColors.border(dark: dark))),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final (d, name) in _days.indexed)
                  Text(
                    '$name ${week[d] == 0 ? '—' : '${fmtHours(week[d] / 60)} h'}',
                    style: AppText.microLabel(dark: dark),
                  ),
                Text('Semana: ${fmtHours(total / 60)} h',
                    style: AppText.microLabel(dark: dark).copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
