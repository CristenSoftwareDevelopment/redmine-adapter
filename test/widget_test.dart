import 'package:flutter_test/flutter_test.dart';

import 'package:redmine_monitor_flutter/models/alert_event.dart';
import 'package:redmine_monitor_flutter/services/notifications/notification_template_service.dart';
import 'package:redmine_monitor_flutter/services/redmine_api_service.dart';

void main() {
  test('Notification template renders placeholders', () {
    final service = NotificationTemplateService();
    final alert = AlertEvent(
      queryId: 1,
      queryName: 'Backlog',
      previousCount: 5,
      currentCount: 8,
      directUrl: 'https://redmine.example/issues?query_id=1',
      createdAt: DateTime.parse('2026-01-02T03:04:05Z'),
    );

    final text = service.render(
      'Consulta {queryName}: {previousCount}->{currentCount} ({diff}) {url}',
      alert,
    );

    expect(text.contains('Backlog'), true);
    expect(text.contains('5->8'), true);
    expect(text.contains('(+3)'), true);
    expect(text.contains('https://redmine.example/issues?query_id=1'), true);
  });

  test('withParams keeps repeated filter keys', () {
    final uri = RedmineApiService.withParams(
      Uri.parse('/issues.json?f[]=status_id&f[]=assigned_to_id&op[status_id]=o'),
      {'limit': '1'},
    );
    expect(uri.queryParametersAll['f[]'], ['status_id', 'assigned_to_id']);
    expect(uri.queryParameters['limit'], '1');
  });
}
