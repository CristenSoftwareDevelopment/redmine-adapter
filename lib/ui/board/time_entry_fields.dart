import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/redmine_issue.dart';
import '../../models/time_entry.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../../state/app_state.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'send_steps.dart';

/// One typed hours field: '' is fine (nothing), otherwise it must parse.
bool _badHours(TextEditingController? c) =>
    c != null && c.text.trim().isNotEmpty && parseHours(c.text) == null;

/// Hours typed but invalid, or valid hours without an activity: can't log.
bool timeEntryBlocked(TextEditingController hours, int? activityId,
    [TextEditingController? extra]) {
  if (_badHours(hours) || _badHours(extra)) return true;
  return totalHours(hours, extra) != null && activityId == null;
}

/// Business + extra hours sent to Redmine; null when both are empty.
double? totalHours(TextEditingController hours, [TextEditingController? extra]) {
  final a = parseHours(hours.text), b = extra == null ? null : parseHours(extra.text);
  return a == null && b == null ? null : (a ?? 0) + (b ?? 0);
}

/// A moment the hours can count from: a journal, a time entry or the creation.
typedef TimeBase = ({DateTime at, String label});

/// Starting points for the hours of [issue] (loaded with journals), newest
/// first, and the index of the default: the newest status change or time
/// entry ([timeEntries], raw `/time_entries.json` items), else the newest of all.
/// A journal that only changes other fields doesn't restart the count.
(List<TimeBase>, int) timeBases(RedmineIssue issue, List<Map> timeEntries) {
  final all = <(TimeBase, bool)>[];
  String who(Map item) => '${(item['user'] as Map?)?['name'] ?? '?'}';
  for (final j in (issue.json['journals'] as List? ?? const []).whereType<Map>()) {
    final at = DateTime.tryParse('${j['created_on']}')?.toLocal();
    if (at == null) continue;
    final details = (j['details'] as List? ?? const []).whereType<Map>();
    final status = details.any((d) => d['property'] == 'attr' && d['name'] == 'status_id');
    final kind = status
        ? 'Situação alterada'
        : details.isEmpty
            ? 'Comentário'
            : 'Alterações';
    all.add(((at: at, label: '${fmtDateTime(at)} · ${who(j)} · $kind'), status));
  }
  for (final e in timeEntries) {
    final at = DateTime.tryParse('${e['created_on']}')?.toLocal();
    if (at == null) continue;
    final hours = fmtHours((e['hours'] as num? ?? 0).toDouble());
    all.add(((at: at, label: '${fmtDateTime(at)} · ${who(e)} · Horas lançadas ($hours h)'), true));
  }
  final created = DateTime.tryParse('${issue.json['created_on']}')?.toLocal();
  if (created != null) {
    all.add(((at: created, label: '${fmtDateTime(created)} · Criação da tarefa'), false));
  }
  all.sort((a, b) => b.$1.at.compareTo(a.$1.at));
  final preferred = all.indexWhere((c) => c.$2);
  return ([for (final c in all) c.$1], preferred < 0 ? 0 : preferred);
}

/// [timeBases] with the issue's own time entries fetched (subtasks left out);
/// a failed fetch just leaves the journals.
Future<(List<TimeBase>, int)> loadTimeBases(AppSettings settings, RedmineIssue issue) async {
  final entries = await RedmineApiService()
      .getJson(settings, '/time_entries.json?issue_id=${issue.id}&limit=100')
      .then((data) => (data['time_entries'] as List? ?? const []).whereType<Map>().toList())
      .catchError((Object _) => <Map>[]);
  return timeBases(issue, [
    for (final e in entries)
      if ((e['issue'] as Map?)?['id'] == issue.id) e,
  ]);
}

/// Fills [hours] (business) and [extra] with the time from [since] to now,
/// split by the configured business hours.
void fillHoursFrom(BuildContext context, DateTime since, TextEditingController hours,
    TextEditingController extra) {
  final split = context.read<AppState>().settings.businessHours.split(since, DateTime.now());
  hours.text = fmtHm(split.business);
  extra.text = fmtHm(split.extra);
}

/// Keeps the extra hours of a send in the local overtime bank, after the
/// `time` step logged them on Redmine (never before, never twice).
/// [context] is read only when the step runs (the step list is built in `build`).
SendStep overtimeStep(BuildContext context, Map<String, StepResult> results, double extra,
        int? issueId, String note) =>
    (
      'overtime',
      '${fmtHours(extra)} h extras no banco de horas',
      () async {
        if (results['time']?.done != true) throw Exception('as horas não foram lançadas');
        await context.read<AppState>().addOvertime(
            OvertimeEntry(day: ymd(DateTime.now()), hours: extra, issueId: issueId, note: note));
        return '';
      },
    );

/// Hours (business) + extra + activity + comment of a time entry logged on
/// send. Redmine gets the sum; the extra also goes to the overtime bank.
/// With [bases], "Contar desde" picks where the count starts. Empty hours =
/// nothing is logged. [issuePicker] (optional) goes between the hours row and the comment.
class TimeEntryFields extends StatelessWidget {
  const TimeEntryFields({
    super.key,
    required this.hours,
    required this.extra,
    required this.comment,
    required this.activities,
    required this.activityId,
    required this.onActivity,
    required this.onChanged,
    this.bases,
    this.base,
    this.onBase,
    this.issuePicker,
  });

  final TextEditingController hours;
  final TextEditingController extra;
  final TextEditingController comment;

  /// Null while loading.
  final List<(int, String)>? activities;
  final int? activityId;
  final ValueChanged<int?> onActivity;

  /// Hours edited (the parent re-checks its send button).
  final VoidCallback onChanged;

  /// Starting points of the count ([timeBases]); null = no picker.
  final List<TimeBase>? bases;
  final int? base;
  final ValueChanged<int>? onBase;
  final Widget? issuePicker;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final invalid = _badHours(hours) || _badHours(extra);
    final total = totalHours(hours, extra);
    final noActivity = !invalid && total != null && activityId == null;
    Widget hoursField(String label, TextEditingController c) => SizedBox(
          width: 120,
          child: LabeledField(
            label: label,
            child: LineField(controller: c, hint: '1:30 ou 1,5', onChanged: (_) => onChanged()),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bases case final bases? when bases.isNotEmpty) ...[
          LabeledField(
            label: 'Contar desde',
            child: SearchSelect(
              value: base,
              options: [for (final (i, b) in bases.indexed) (i, b.label)],
              onChanged: (i) {
                if (i == null) return;
                fillHoursFrom(context, bases[i].at, hours, extra);
                onBase?.call(i);
                onChanged();
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Labels above and 40px controls, so they all sit on the same line.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hoursField('Horas', hours),
            const SizedBox(width: 12),
            hoursField('Hora extra', extra),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Atividade',
                child: activities == null
                    ? const LinearProgressIndicator(minHeight: 2)
                    : SearchSelect(
                        value: activityId,
                        options: activities!,
                        hint: 'Atividade…',
                        onChanged: onActivity,
                      ),
              ),
            ),
          ],
        ),
        if (invalid || noActivity)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              invalid ? 'Horas inválidas: use 1,5 ou 1:30.' : 'Escolha a atividade do lançamento.',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            ),
          ),
        if (issuePicker != null) ...[const SizedBox(height: 12), issuePicker!],
        const SizedBox(height: 12),
        TextField(
          controller: comment,
          decoration: const InputDecoration(hintText: 'Comentário do lançamento (opcional)'),
        ),
        const SizedBox(height: 4),
        Text(
          total == null
              ? 'Vazio = não lança.'
              : 'Total no Redmine: ${fmtHours(total)} h'
                  '${parseHours(extra.text) == null ? '' : '; a hora extra também vai para o banco de horas'}.',
          style: AppText.microLabel(dark: dark),
        ),
      ],
    );
  }
}

/// Logs hours on [issue] (aba "Tempo gasto"): hours, activity, day and comment.
/// True when the entry was created.
Future<bool> showLogTimeDialog(BuildContext context, RedmineIssue issue) async =>
    await showAppDialog<bool>(context, (_) => _LogTimeDialog(issue: issue)) ?? false;

class _LogTimeDialog extends StatefulWidget {
  const _LogTimeDialog({required this.issue});

  final RedmineIssue issue;

  @override
  State<_LogTimeDialog> createState() => _LogTimeDialogState();
}

class _LogTimeDialogState extends State<_LogTimeDialog> {
  final _api = RedmineApiService();
  final _hours = TextEditingController();
  final _extra = TextEditingController();
  final _comment = TextEditingController();
  String _day = ymd(DateTime.now());
  int? _activityId;
  List<(int, String)>? _activities;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api
        .listNamed(context.read<AppState>().settings, '/enumerations/time_entry_activities.json',
            'time_entry_activities')
        .catchError((Object _) => const <(int, String)>[])
        .then((list) {
      if (mounted) setState(() => _activities = list);
    });
  }

  @override
  void dispose() {
    _hours.dispose();
    _extra.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final state = context.read<AppState>();
    final extra = parseHours(_extra.text);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.postJson(state.settings, '/time_entries.json', {
        'time_entry': {
          'issue_id': widget.issue.id,
          'hours': totalHours(_hours, _extra),
          'activity_id': _activityId,
          'spent_on': _day,
          if (_comment.text.trim().isNotEmpty) 'comments': _comment.text.trim(),
        },
      });
      if (extra != null) {
        await state.addOvertime(OvertimeEntry(
            day: _day, hours: extra, issueId: widget.issue.id, note: _comment.text.trim()));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '$error'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready =
        totalHours(_hours, _extra) != null && !timeEntryBlocked(_hours, _activityId, _extra);
    return AppDialog(
      title: Row(children: [const Text('Lançar horas · '), IssueNumber(widget.issue.id)]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.issue.subject, style: AppText.bodySemibold(dark: dark)),
          const SizedBox(height: 18),
          TimeEntryFields(
            hours: _hours,
            extra: _extra,
            comment: _comment,
            activities: _activities,
            activityId: _activityId,
            onActivity: (v) => setState(() => _activityId = v),
            onChanged: () => setState(() {}),
            issuePicker: LabeledField(
              label: 'Data',
              child: DateSelect(value: _day, onChanged: (v) => setState(() => _day = v)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              'Falha ao lançar: $_error',
              style: AppText.microLabel(dark: dark).copyWith(color: AppColors.danger(dark: dark)),
            ),
          ],
        ],
      ),
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: ready && !_sending ? _send : null,
          icon: _sending
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.schedule, size: 16),
          label: const Text('Lançar'),
        ),
      ],
    );
  }
}
