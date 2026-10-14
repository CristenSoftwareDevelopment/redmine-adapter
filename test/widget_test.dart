import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:redmine_monitor_flutter/models/alert_event.dart';
import 'package:redmine_monitor_flutter/models/alert_rule.dart';
import 'package:redmine_monitor_flutter/models/app_settings.dart';
import 'package:redmine_monitor_flutter/models/monitored_query.dart';
import 'package:redmine_monitor_flutter/models/time_entry.dart';
import 'package:redmine_monitor_flutter/services/notifications/notification_template_service.dart';
import 'package:redmine_monitor_flutter/services/database_service.dart';
import 'package:redmine_monitor_flutter/services/redmine_api_service.dart';
import 'package:redmine_monitor_flutter/state/app_state.dart';
import 'package:redmine_monitor_flutter/ui/widgets/query_form_dialog.dart';

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

  group('AlertRule', () {
    test('eq fires when count lands on the value', () {
      const rule = AlertRule(op: ruleEq, value: 1);
      expect(rule.matches(2, 1), true);
      expect(rule.matches(0, 1), true);
      expect(rule.matches(2, 3), false);
    });

    test('lte/gte fire only when crossing the threshold', () {
      const lte = AlertRule(op: ruleLte, value: 1);
      expect(lte.matches(3, 1), true);
      expect(lte.matches(1, 0), false);
      expect(lte.matches(0, 2), false);
      const gte = AlertRule(op: ruleGte, value: 5);
      expect(gte.matches(4, 6), true);
      expect(gte.matches(6, 7), false);
    });

    test('direction rules and missing value', () {
      expect(const AlertRule(op: ruleIncrease).matches(1, 2), true);
      expect(const AlertRule(op: ruleIncrease).matches(2, 1), false);
      expect(const AlertRule(op: ruleDecrease).matches(2, 1), true);
      expect(const AlertRule().matches(2, 1), true);
      expect(const AlertRule(op: ruleEq).matches(2, 1), false);
    });

    test('first matching rule wins', () {
      const rules = [
        AlertRule(op: ruleEq, value: 1, titleTemplate: 'um'),
        AlertRule(op: ruleDecrease, titleTemplate: 'caiu'),
      ];
      expect(AlertRule.firstMatch(rules, 2, 1)?.titleTemplate, 'um');
      expect(AlertRule.firstMatch(rules, 3, 2)?.titleTemplate, 'caiu');
      expect(AlertRule.firstMatch(rules, 1, 2), null);
    });

    test('legacy row becomes a single rule', () {
      final query = MonitoredQuery.fromDbMap({
        'id': 1,
        'name': 'Fila',
        'endpoint': '/issues.json',
        'direct_url': '/issues',
        'alert_on': 'increase',
        'notification_title_template': 'T {queryName}',
        'notification_body_template': '',
      });
      expect(query.alertRules.length, 1);
      expect(query.alertRules.single.op, ruleIncrease);
      expect(query.alertRules.single.titleTemplate, 'T {queryName}');
      expect(query.alertRules.single.bodyTemplate, null);

      final roundTrip = MonitoredQuery.fromDbMap({...query.toDbMap(), 'id': 1});
      expect(roundTrip.alertRules.single.op, ruleIncrease);
    });
  });

  test('resolve: rule template > increase/decrease template > generic', () {
    final service = NotificationTemplateService();
    final settings = AppSettings(
      baseUrl: '',
      apiKey: '',
      notificationTitleTemplate: 'G {queryName}',
      notificationBodyTemplate: 'GB',
      notificationIncreaseTitleTemplate: 'UP {currentCount}',
    );
    AlertEvent alert(int prev, int curr) => AlertEvent(
          queryId: 1,
          queryName: 'Fila',
          previousCount: prev,
          currentCount: curr,
          directUrl: '/issues',
          createdAt: DateTime(2026),
        );

    expect(
      service.resolve(settings, const AlertRule(titleTemplate: 'R {currentCount}'), alert(2, 1)),
      ('R 1', 'GB'),
    );
    expect(service.resolve(settings, const AlertRule(), alert(1, 2)), ('UP 2', 'GB'));
    expect(service.resolve(settings, null, alert(2, 1)), ('G Fila', 'GB'));
  });

  testWidgets('query form falls back to manual URL and saves extra rules', (tester) async {
    MonitoredQuery? saved;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(databaseService: DatabaseService.instance),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showDialog<MonitoredQuery>(
                context: context,
                builder: (_) => const QueryFormDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No Redmine configured: the saved-query list fails and the form goes manual.
    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL da consulta no Redmine'),
      '/issues?assigned_to_id=me',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Fila do dev');

    await tester.ensureVisible(find.text('Adicionar regra'));
    await tester.tap(find.text('Adicionar regra'));
    await tester.pumpAndSettle();
    final newRule = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(newRule);
    await tester.pumpAndSettle();
    await tester.tap(newRule);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ficou igual a').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'N'), '1');

    await tester.ensureVisible(find.text('Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved?.name, 'Fila do dev');
    expect(saved?.endpoint, '/issues.json?assigned_to_id=me');
    expect(saved?.alertRules.map((r) => r.label), ['↕ Qualquer', '= 1']);
  });

  test('time entries sum by person/day and by activity', () {
    Map<String, dynamic> raw(int user, String day, num hours, String activity, int? issue) => {
          'user': {'id': user, 'name': 'U$user'},
          'spent_on': day,
          'hours': hours,
          'activity': {'id': 1, 'name': activity},
          if (issue != null) 'issue': {'id': issue},
        };
    final entries = [
      raw(1, '2026-10-13', 2.5, 'Desenvolvimento', 10),
      raw(1, '2026-10-13', 1, 'Reunião', null),
      raw(2, '2026-10-14', 4, 'Desenvolvimento', 10),
    ].map(TimeEntry.fromJson).toList();

    final byUserDay = sumHours(entries, (e) => (e.userId, e.day));
    expect(byUserDay[(1, DateTime(2026, 10, 13))], 3.5);
    expect(byUserDay[(2, DateTime(2026, 10, 14))], 4);
    expect(sumHours(entries, (e) => e.activity)['Desenvolvimento'], 6.5);
    expect(sumHours(entries, (e) => e.issueId)[null], 1);
    expect(fmtHours(3.5), '3,5');
    expect(fmtHours(4), '4');
  });
}
