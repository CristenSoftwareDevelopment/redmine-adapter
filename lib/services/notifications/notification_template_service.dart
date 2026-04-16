import '../../models/alert_event.dart';

class NotificationTemplateService {
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
    return '$y-$m-$d $h:$min';
  }
}
