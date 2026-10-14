import '../../models/alert_event.dart';
import '../../models/alert_rule.dart';
import '../../models/app_settings.dart';

class NotificationTemplateService {
  /// Single source of the notification text. Each field falls back
  /// rule template → global increase/decrease template → global generic.
  (String, String) resolve(AppSettings settings, AlertRule? rule, AlertEvent alert) {
    String pick(String? a, String? b, String fallback) =>
        a?.isNotEmpty == true ? a! : (b?.isNotEmpty == true ? b! : fallback);

    final increase = alert.diff > 0;
    final decrease = alert.diff < 0;
    final title = pick(
      rule?.titleTemplate,
      increase
          ? settings.notificationIncreaseTitleTemplate
          : decrease
              ? settings.notificationDecreaseTitleTemplate
              : null,
      settings.notificationTitleTemplate,
    );
    final body = pick(
      rule?.bodyTemplate,
      increase
          ? settings.notificationIncreaseBodyTemplate
          : decrease
              ? settings.notificationDecreaseBodyTemplate
              : null,
      settings.notificationBodyTemplate,
    );
    return (render(title, alert), render(body, alert));
  }

  String render(String template, AlertEvent alert) {
    final diff = alert.diff;
    final newCount = diff > 0 ? diff : 0;
    final replacements = <String, String>{
      '{queryName}': alert.queryName,
      '{previousCount}': '${alert.previousCount}',
      '{currentCount}': '${alert.currentCount}',
      '{diff}': _formatDiff(diff),
      '{newCount}': '$newCount',
      '{time}': _formatDate(alert.createdAt),
      '{url}': alert.directUrl,
    };

    var text = template;
    replacements.forEach((key, value) {
      text = text.replaceAll(key, value);
    });
    return text;
  }

  String _formatDiff(int diff) {
    final prefix = diff > 0 ? '+' : '';
    return '$prefix$diff';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final sec = local.second.toString().padLeft(2, '0');
    return '$d-$m-$y $h:$min:$sec';
  }
}
