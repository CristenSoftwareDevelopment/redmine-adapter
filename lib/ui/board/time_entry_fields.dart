import 'package:flutter/material.dart';

import '../../models/time_entry.dart';
import '../../services/theme_service.dart';
import '../components.dart';
import '../ui_utils.dart';

/// Hours typed but invalid, or valid hours without an activity: can't log.
bool timeEntryBlocked(TextEditingController hours, int? activityId) {
  final text = hours.text.trim();
  if (text.isEmpty) return false;
  return parseHours(text) == null || activityId == null;
}

/// Hours + activity + comment of a time entry logged on send, with the hint
/// of when the counting started. Empty hours = nothing is logged.
/// [issuePicker] (optional) goes between the hours row and the comment.
class TimeEntryFields extends StatelessWidget {
  const TimeEntryFields({
    super.key,
    required this.hours,
    required this.comment,
    required this.activities,
    required this.activityId,
    required this.onActivity,
    required this.onChanged,
    this.since,
    this.issuePicker,
  });

  final TextEditingController hours;
  final TextEditingController comment;

  /// Null while loading.
  final List<(int, String)>? activities;
  final int? activityId;
  final ValueChanged<int?> onActivity;

  /// Hours edited (the parent re-checks its send button).
  final VoidCallback onChanged;

  /// Last update of the issue: the prefilled hours count from it.
  final DateTime? since;
  final Widget? issuePicker;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = hours.text.trim();
    final invalid = text.isNotEmpty && parseHours(text) == null;
    final noActivity = !invalid && text.isNotEmpty && activityId == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Labels above and 40px controls, so both sit on the same line.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: LabeledField(
                label: 'Horas',
                child: TextField(
                  controller: hours,
                  decoration: const InputDecoration(
                    hintText: '1:30 ou 1,5',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    constraints: BoxConstraints.tightFor(height: controlHeight),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ),
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
          [
            if (since != null) 'Desde o último trâmite (${fmtDateTime(since)}). Edite se precisar;',
            'vazio = não lança.',
          ].join(' '),
          style: AppText.microLabel(dark: dark),
        ),
      ],
    );
  }
}
