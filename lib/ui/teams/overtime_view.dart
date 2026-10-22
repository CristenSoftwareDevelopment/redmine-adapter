import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';

const _monthNames = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez'
];

/// `2026-10` → `out/2026`.
String _monthLabel(String month) =>
    '${_monthNames[int.parse(month.substring(5)) - 1]}/${month.substring(0, 4)}';

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Tempo gasto › Horas extras: the local overtime bank. Each month is kept in
/// the bank or marked as paid out (cobrado); the balance sums the bank months.
class OvertimeView extends StatefulWidget {
  const OvertimeView({super.key});

  @override
  State<OvertimeView> createState() => _OvertimeViewState();
}

class _OvertimeViewState extends State<OvertimeView> {
  String _month = _ym(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final state = context.watch<AppState>();
    final entries = state.overtime;
    final paid = state.settings.overtimePaid;
    final byMonth = <String, double>{};
    for (final e in entries) {
      byMonth.update(e.month, (v) => v + e.hours, ifAbsent: () => e.hours);
    }
    final now = DateTime.now();
    final current = _ym(now);
    final last12 = [for (var i = 11; i >= 0; i--) _ym(DateTime(now.year, now.month - i))];
    final months = {...byMonth.keys, current}.toList()..sort();

    // Running bank balance per month (oldest first).
    final running = <String, double>{};
    var acc = 0.0;
    for (final m in months) {
      if (!paid.contains(m)) acc += byMonth[m] ?? 0;
      running[m] = acc;
    }
    final paidThisYear = byMonth.entries
        .where((e) => paid.contains(e.key) && e.key.startsWith('${now.year}-'))
        .fold(0.0, (sum, e) => sum + e.value);
    final selected = entries.where((e) => e.month == _month).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Este mês',
              value: '${fmtHours(byMonth[current] ?? 0)} h',
              note: paid.contains(current) ? 'Marcado para cobrar' : 'No banco de horas',
              icon: Icons.more_time,
            ),
            StatCard(
              label: 'Saldo em banco',
              value: '${fmtHours(bankBalance(entries, paid))} h',
              note: 'Soma dos meses não cobrados',
              icon: Icons.savings_outlined,
            ),
            StatCard(
              label: 'Cobradas em ${now.year}',
              value: '${fmtHours(paidThisYear)} h',
              note: 'Meses marcados para cobrar',
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelHead(
                title: const Text('Horas extras por mês'),
                subtitle: 'Últimos 12 meses. Clique numa barra para ver os lançamentos.',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _legend(AppColors.accent(dark: dark), 'Banco', dark),
                  const SizedBox(width: 14),
                  _legend(AppColors.borderStrong(dark: dark), 'Cobrado', dark),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _MonthBars(
                  months: last12,
                  hours: byMonth,
                  paid: paid,
                  selected: _month,
                  onSelect: (m) => setState(() => _month = m),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelHead(
                title: Text('Meses'),
                subtitle: 'Escolha se as horas do mês ficam no banco ou serão cobradas.',
              ),
              for (final m in months.reversed)
                ListRow(
                  onTap: () => setState(() => _month = m),
                  accentBorder: m == _month ? AppColors.accent(dark: dark) : null,
                  title: Text(_monthLabel(m)),
                  meta: [
                    Text('${fmtHours(byMonth[m] ?? 0)} h extras'),
                    Text('saldo ao fim do mês: ${fmtHours(running[m] ?? 0)} h'),
                  ],
                  trailing: SegmentButtons<bool>(
                    segments: const [
                      (false, 'Banco', Icons.savings_outlined),
                      (true, 'Cobrar', Icons.payments_outlined),
                    ],
                    selected: paid.contains(m),
                    onChanged: (v) => state.setMonthPaid(m, v),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelHead(
                title: Text('Lançamentos de ${_monthLabel(_month)}'),
                subtitle: 'Gravados ao enviar trâmites, lançar horas com "Hora extra" ou à mão.',
                trailing: FilledButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final day = _month == _ym(now) ? ymd(now) : '$_month-01';
                    final month = await showAppDialog<String>(
                        context, (_) => _OvertimeDialog(initialDay: day));
                    if (month != null && mounted) setState(() => _month = month);
                  },
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Lançar hora extra'),
                ),
              ),
              if (selected.isEmpty)
                const EmptyState(icon: Icons.more_time, text: 'Nenhuma hora extra neste mês.')
              else
                for (final e in selected)
                  ListRow(
                    title: Text(e.note.isEmpty ? 'Hora extra' : e.note),
                    meta: [
                      Text(fmtDate(e.day).replaceAll('-', '/')),
                      if (e.issueId != null) IssueNumber(e.issueId!),
                    ],
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${fmtHours(e.hours)} h', style: AppText.bodySemibold(dark: dark)),
                      IconButton(
                        tooltip: 'Excluir',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: e.id == null ? null : () => state.deleteOvertime(e.id!),
                      ),
                    ]),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color color, String text, bool dark) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(text, style: AppText.microLabel(dark: dark)),
        ],
      );
}

/// One bar per month (single axis from zero), banco in accent and cobrado in
/// neutral gray; the value is labeled only on the selected month and the
/// tallest one, the rest on hover.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.months,
    required this.hours,
    required this.paid,
    required this.selected,
    required this.onSelect,
  });

  final List<String> months;
  final Map<String, double> hours;
  final Set<String> paid;
  final String selected;
  final ValueChanged<String> onSelect;

  static const _plot = 140.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final values = [for (final m in months) hours[m] ?? 0];
    final max = values.fold(0.0, (a, b) => a > b ? a : b);
    final tallest = max == 0 ? null : months[values.indexOf(max)];
    return Column(
      children: [
        SizedBox(
          height: _plot + 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, m) in months.indexed)
                Expanded(
                  child: Tooltip(
                    message: '${_monthLabel(m)}: ${fmtHours(values[i])} h · '
                        '${paid.contains(m) ? 'cobrado' : 'banco'}',
                    child: InkWell(
                      onTap: () => onSelect(m),
                      // The whole column is the hit target, not just the bar.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (values[i] > 0 && (m == selected || m == tallest))
                              Text('${fmtHours(values[i])} h',
                                  style: AppText.microLabel(dark: dark)),
                            const SizedBox(height: 2),
                            Container(
                              height: max == 0 ? 0 : (values[i] / max * _plot).clamp(2, _plot),
                              constraints: const BoxConstraints(maxWidth: 28),
                              decoration: BoxDecoration(
                                color: paid.contains(m)
                                    ? AppColors.borderStrong(dark: dark)
                                    : AppColors.accent(dark: dark),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(AppRadius.micro)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.border(dark: dark)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Text(
                  _monthNames[int.parse(m.substring(5)) - 1],
                  textAlign: TextAlign.center,
                  style: AppText.microLabel(dark: dark).copyWith(
                    fontWeight: m == selected ? FontWeight.w700 : null,
                    color: m == selected ? AppColors.text(dark: dark) : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Manual overtime (forgot "Hora extra" on the trâmite, or work done earlier
/// this month): day, issue, hours and a description, kept only in the local
/// bank. The issue is searched among those the user logged hours on in that
/// month, or typed by ID. Pops the month (`yyyy-MM`) of the saved entry.
class _OvertimeDialog extends StatefulWidget {
  const _OvertimeDialog({required this.initialDay});

  final String initialDay;

  @override
  State<_OvertimeDialog> createState() => _OvertimeDialogState();
}

class _OvertimeDialogState extends State<_OvertimeDialog> {
  late String _day = widget.initialDay;
  int? _issueId;
  final _hours = TextEditingController();
  final _note = TextEditingController();

  /// (issue id, subject) of the month of [_day], newest first; null while loading.
  List<(int, String)>? _recent;
  String? _recentMonth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Issues with time entries of the logged-in user in the month of [_day].
  Future<void> _loadRecent() async {
    final month = _day.substring(0, 7);
    if (month == _recentMonth) return;
    setState(() {
      _recentMonth = month;
      _recent = null;
    });
    final first = DateTime.parse('$month-01');
    final last = DateTime(first.year, first.month + 1, 0);
    final settings = context.read<AppState>().settings;
    final api = RedmineApiService();
    var recent = <(int, String)>[];
    try {
      final entries = await api.getAllPages(settings,
          '/time_entries.json?user_id=me&from=${ymd(first)}&to=${ymd(last)}', 'time_entries');
      final lastDay = <int, String>{};
      for (final e in entries) {
        final id = (e['issue'] as Map?)?['id'] as int?;
        final day = e['spent_on'] as String? ?? '';
        if (id != null && day.compareTo(lastDay[id] ?? '') > 0) lastDay[id] = day;
      }
      if (lastDay.isNotEmpty) {
        final issues = await api.getAllPages(
            settings, '/issues.json?issue_id=${lastDay.keys.join(',')}&status_id=*', 'issues');
        final subjects = {for (final i in issues) i['id'] as int: i['subject'] as String? ?? ''};
        final ids = lastDay.keys.toList()..sort((a, b) => lastDay[b]!.compareTo(lastDay[a]!));
        recent = [for (final id in ids) (id, subjects[id] ?? '')];
      }
    } catch (_) {
      // No list: the ID can still be typed in the search.
    }
    if (mounted && month == _recentMonth) setState(() => _recent = recent);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AppState>().addOvertime(OvertimeEntry(
          day: _day,
          hours: parseHours(_hours.text)!,
          issueId: _issueId,
          note: _note.text.trim(),
        ));
    if (mounted) Navigator.of(context).pop(_day.substring(0, 7));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hours = parseHours(_hours.text);
    final badHours = _hours.text.trim().isNotEmpty && hours == null;
    final recent = _recent;
    return AppDialog(
      title: const Text('Lançar hora extra'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fica só no banco de horas local: nada é enviado ao Redmine.',
            style: AppText.captionLight(dark: dark),
          ),
          const SizedBox(height: 18),
          // Labels above and 40px controls, so they all sit on the same line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: LabeledField(
                  label: 'Data',
                  child: DateSelect(
                    value: _day,
                    onChanged: (v) {
                      if (v.isEmpty) return;
                      setState(() => _day = v);
                      _loadRecent();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Tarefa',
                  child: recent == null
                      ? const LinearProgressIndicator(minHeight: 2)
                      : SearchSelect(
                          value: _issueId,
                          typedId: true,
                          hint: 'Buscar tarefa ou digitar o ID…',
                          options: [for (final (id, subject) in recent) (id, '#$id · $subject')],
                          onChanged: (id) => setState(() {
                            _issueId = id;
                            final subject = recent.where((r) => r.$1 == id).firstOrNull?.$2;
                            if (_note.text.trim().isEmpty && subject != null) _note.text = subject;
                          }),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: LabeledField(
                  label: 'Horas',
                  child: LineField(
                    controller: _hours,
                    hint: '1:30 ou 1,5',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          if (badHours)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Horas inválidas: use 1,5 ou 1:30.',
                style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
              ),
            ),
          const SizedBox(height: 18),
          LabeledField(
            label: 'Descrição',
            child: TextField(
              controller: _note,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'O que foi feito'),
            ),
          ),
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: hours != null && !_saving ? _save : null,
          icon: const Icon(Icons.more_time, size: 16),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}
