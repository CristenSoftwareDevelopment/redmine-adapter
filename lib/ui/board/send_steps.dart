import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// One step of a send: unique key, summary, and the call. `run` returns a
/// warning ('' = all fine) or throws when the step failed.
typedef SendStep = (String key, String label, Future<String> Function() run);

typedef StepResult = ({bool done, String label, String text});

/// Runs the [steps] not done yet in [results], in order, calling [onProgress]
/// after each one. Done steps never run again, so retrying can't repeat a
/// comment already posted. True when every step is done without warnings.
Future<bool> runSendSteps(
  List<SendStep> steps,
  Map<String, StepResult> results,
  VoidCallback onProgress,
) async {
  for (final (key, label, run) in steps) {
    if (results[key]?.done == true) continue;
    try {
      results[key] = (done: true, label: label, text: await run());
    } catch (error) {
      results[key] = (done: false, label: label, text: '$error'.replaceFirst('Exception: ', ''));
    }
    onProgress();
  }
  return steps.every((s) => results[s.$1]?.done == true && results[s.$1]!.text.isEmpty);
}

/// ✓ done, ⚠ done with a warning, ✗ failed (retried by "Tentar de novo").
class StepResultsList extends StatelessWidget {
  const StepResultsList(this.results, {super.key});

  final Map<String, StepResult> results;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.well(dark: dark),
        border: Border.all(color: AppColors.border(dark: dark)),
        borderRadius: BorderRadius.circular(AppRadius.standard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in results.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    !r.done
                        ? Icons.error_outline
                        : r.text.isEmpty
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                    size: 16,
                    color: !r.done
                        ? AppColors.danger(dark: dark)
                        : r.text.isEmpty
                            ? AppColors.accent(dark: dark)
                            : AppColors.tone(TagTone.amber, dark: dark).$2,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.text.isEmpty ? r.label : '${r.label}: ${r.text}',
                      style: AppText.caption(dark: dark),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
