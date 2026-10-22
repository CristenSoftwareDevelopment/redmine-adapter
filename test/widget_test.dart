import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:redmine_monitor_flutter/models/alert_event.dart';
import 'package:redmine_monitor_flutter/models/alert_rule.dart';
import 'package:redmine_monitor_flutter/models/app_settings.dart';
import 'package:redmine_monitor_flutter/models/business_hours.dart';
import 'package:redmine_monitor_flutter/models/claude_action.dart';
import 'package:redmine_monitor_flutter/models/custom_field.dart';
import 'package:redmine_monitor_flutter/models/handoff_rule.dart';
import 'package:redmine_monitor_flutter/models/monitored_query.dart';
import 'package:redmine_monitor_flutter/models/redmine_issue.dart';
import 'package:redmine_monitor_flutter/models/time_entry.dart';
import 'package:redmine_monitor_flutter/services/notifications/notification_template_service.dart';
import 'package:redmine_monitor_flutter/services/database_service.dart';
import 'package:redmine_monitor_flutter/services/redmine_api_service.dart';
import 'package:redmine_monitor_flutter/state/app_state.dart';
import 'package:redmine_monitor_flutter/ui/board/attachment_preview.dart';
import 'package:redmine_monitor_flutter/ui/board/board_view.dart';
import 'package:redmine_monitor_flutter/ui/board/handoff_dialog.dart';
import 'package:redmine_monitor_flutter/ui/board/issue_actions.dart';
import 'package:redmine_monitor_flutter/ui/board/issue_detail_dialog.dart';
import 'package:redmine_monitor_flutter/ui/board/issue_fields.dart';
import 'package:redmine_monitor_flutter/ui/board/note_editor.dart';
import 'package:redmine_monitor_flutter/ui/board/time_entry_fields.dart';
import 'package:redmine_monitor_flutter/ui/board/tramite_dialog.dart';
import 'package:redmine_monitor_flutter/ui/board/bulk_edit_dialog.dart';
import 'package:redmine_monitor_flutter/services/theme_service.dart';
import 'package:redmine_monitor_flutter/ui/components.dart';
import 'package:redmine_monitor_flutter/ui/home_screen.dart';
import 'package:redmine_monitor_flutter/ui/icon_picker.dart';
import 'package:redmine_monitor_flutter/ui/ui_utils.dart';
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

    test('fromJson tolerates a numeric string value', () {
      expect(AlertRule.fromJson({'op': 'eq', 'value': '3'}).value, 3);
      expect(AlertRule.fromJson({'op': 'eq', 'value': 'x'}).value, null);
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
    // Labels sit above the inputs (LabeledField), so find the field under each label.
    Finder field(String label) => find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(LabeledField)),
          matching: find.byType(TextFormField),
        );
    await tester.enterText(field('URL da consulta no Redmine'), '/issues?assigned_to_id=me');
    await tester.enterText(field('Nome da consulta'), 'Fila do dev');

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
    expect(saved?.alertRules.map((r) => r.label), ['Qualquer mudança', '= 1']);
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

  test('board columns keep Redmine order and never drop automatic ones', () {
    const order = [1, 2, 3, 4];
    // Automatic: statuses seen this session, in Redmine order.
    expect(boardColumnIds(statusOrder: order, saved: null, seen: {3, 1}), [1, 3]);
    // Saved choice wins, even for empty statuses; unknown ids with issues go last.
    expect(boardColumnIds(statusOrder: order, saved: [4, 2], seen: {1}), [2, 4]);
    expect(boardColumnIds(statusOrder: order, saved: null, seen: {9, 2}), [2, 9]);
  });

  test('search ignores case and accents', () {
    expect(searchKey('André Ação'), 'andre acao');
    expect(searchKey('André Cristen').contains(searchKey('andre')), true);
  });

  test('withinDays keeps only entries whose spent_on is inside the range', () {
    TimeEntry on(int day) => TimeEntry.fromJson({
          'user': {'id': 1, 'name': 'U'},
          'spent_on': '2026-10-${day.toString().padLeft(2, '0')}',
          'hours': 1,
        });
    final kept = withinDays(
        [on(12), on(13), on(14), on(15)], DateTime(2026, 10, 13), DateTime(2026, 10, 14));
    expect(kept.map((e) => e.day.day), [13, 14]);
  });

  test('handoff note renders one note or repeats the line for several', () {
    const rule =
        HandoffRule(name: 'QA', template: '$defaultHandoffTemplate ({{tarefa}} {{titulo}})');
    String render(List<(int, int)> notes) => renderHandoffNote(
          rule,
          trackerName: 'Desenvolvimento',
          issueId: 484448,
          subject: 'Tela X',
          notes: notes,
        );
    expect(
      render([(484530, 9)]),
      '* Tramite de desenvolvimento: #484530#note-9 (#484448 Tela X)',
    );
    // Picked out of order: sorted by issue, then note.
    expect(
      render([(485091, 4), (484448, 8)]),
      '* Tramites de desenvolvimento:\n  - #484448#note-8\n  - #485091#note-4',
    );
  });

  test('handoff rules round-trip and apply to their trackers', () {
    const rule = HandoffRule(name: 'QA', sourceTrackerIds: [2], statusId: 4, assigneeId: 7);
    final back = HandoffRule.listFromJson(HandoffRule.listToJson([rule])).single;
    expect((back.name, back.statusId, back.assigneeId), ('QA', 4, 7));
    expect(back.sourceTrackerIds, [2]);
    expect(back.template, defaultHandoffTemplate);
    expect(back.multiTemplate, defaultHandoffMultiTemplate);
    // Rules saved before multiTemplate existed get the default.
    expect(HandoffRule.fromJson({'name': 'old'}).multiTemplate, defaultHandoffMultiTemplate);
    expect(back.appliesTo(2), true);
    expect(back.appliesTo(3), false);
    expect(const HandoffRule(name: 'any').appliesTo(3), true);
    expect(HandoffRule.listFromJson(null), isEmpty);
  });

  test('actions show by tracker and status, in the order picked', () {
    const paused = HandoffRule(name: 'Retomar', statusIds: [5]);
    expect(paused.showsOn(1, 5), true);
    expect(paused.showsOn(1, 2), false);
    const review =
        ClaudeAction(name: 'CR', cwd: '/x', template: 't', trackerIds: [2], statusIds: [3]);
    expect(review.showsOn(2, 3), true);
    expect(review.showsOn(1, 3), false);
    expect(review.showsOn(2, 4), false);
    // Saved before the filters and the order: shows everywhere, never ordered.
    final old = ClaudeAction.fromJson({'name': 'old', 'cwd': '', 'template': ''});
    expect(old.showsOn(9, 9), true);
    expect(old.order, isNull);
    expect(HandoffRule.fromJson({'name': 'old'}).statusIds, isEmpty);
    // withOrder goes through the JSON: nothing else is lost.
    const qa = HandoffRule(name: 'QA', statusIds: [5], statusSteps: [(trackerId: 1, statusId: 2)]);
    final ordered = qa.withOrder(3);
    expect(ordered.order, 3);
    expect(ordered.statusIds, [5]);
    expect(ordered.statusSteps, [(trackerId: 1, statusId: 2)]);

    String names(AppSettings s) => [
          for (final a in s.orderedActions)
            switch (a) {
              ClaudeAction a => a.name,
              HandoffRule r => r.name,
              _ => '?',
            },
        ].join(',');
    const c1 = ClaudeAction(name: 'c1', cwd: '', template: '');
    const c2 = ClaudeAction(name: 'c2', cwd: '', template: '');
    const r1 = HandoffRule(name: 'r1'), r2 = HandoffRule(name: 'r2');
    final settings =
        AppSettings(baseUrl: '', apiKey: '', claudeActions: [c1, c2], handoffRules: [r1, r2]);
    expect(names(settings), 'c1,c2,r1,r2'); // never ordered: as before
    expect(
      names(settings.copyWith(
        claudeActions: [c1.withOrder(2), c2], // c2 never ordered (e.g. new): last
        handoffRules: [r1.withOrder(1), r2.withOrder(0)],
      )),
      'r2,r1,c1,c2',
    );
  });

  test('sidebar boards follow the dragged order, the others after', () {
    MonitoredQuery board(int id) =>
        MonitoredQuery(id: id, name: '#$id', endpoint: '/issues.json', directUrl: '/issues');
    final boards = [board(agileQueryId), board(1), board(2), board(3)];
    String ids(List<int> order) => AppSettings(baseUrl: '', apiKey: '', boardOrder: order)
        .sortBoards(boards)
        .map((b) => b.id)
        .join(',');
    expect(ids(const []), '-1,1,2,3');
    expect(ids(const [3, agileQueryId]), '3,-1,1,2');
  });

  test('board groups sort naturally with the missing value last', () {
    expect(compareNatural('3.79', '3.80') < 0, true);
    expect(compareNatural('3.80', '3.100') < 0, true);
    expect(compareNatural('Sprint 9', 'sprint 10') < 0, true);
    RedmineIssue issue(int id, [String? version, int? versionId]) => RedmineIssue({
          'id': id,
          if (version != null) 'fixed_version': {'id': versionId, 'name': version},
        });
    final groups = groupIssues(
      [issue(1, '3.80', 12), issue(2), issue(3, '3.79', 11), issue(4, '3.80', 12)],
      'fixed_version',
      'Sem versão',
    );
    expect(groups.map((g) => g.name), ['3.79', '3.80', 'Sem versão']);
    expect(groups.map((g) => g.issues.map((i) => i.id).toList()), [
      [3],
      [1, 4],
      [2],
    ]);
  });

  test('board filters: OR within a field, AND across fields, missing = 0', () {
    final issue = RedmineIssue({
      'id': 1,
      'tracker': {'id': 2, 'name': 'Bug'},
      'fixed_version': {'id': 11, 'name': '3.79'},
    });
    expect(matchesBoardFilters(issue, const {}), true);
    expect(
        matchesBoardFilters(issue, const {
          'fixed_version': [11, 12]
        }),
        true);
    expect(
        matchesBoardFilters(issue, const {
          'fixed_version': [12]
        }),
        false);
    expect(
        matchesBoardFilters(issue, const {
          'tracker': [2],
          'fixed_version': [12]
        }),
        false);
    expect(
        matchesBoardFilters(issue, const {
          'assigned_to': [0]
        }),
        true);
  });

  test('board prefs round-trip and default when missing', () {
    const prefs = BoardPrefs(
      listMode: true,
      groupBy: 'fixed_version',
      filters: {
        'tracker': [2, 3]
      },
    );
    final back = BoardPrefs.fromJson(
      jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
    );
    expect((back.listMode, back.groupBy), (true, 'fixed_version'));
    expect(back.filters, {
      'tracker': [2, 3],
    });
    final query = MonitoredQuery.fromDbMap({
      'id': 1,
      'name': 'Q',
      'endpoint': '/issues.json',
      'direct_url': '/issues',
    });
    expect((query.boardPrefs.listMode, query.boardPrefs.groupBy), (false, null));
    expect(query.boardPrefs.filters, isEmpty);
  });

  group('nearbyIssues', () {
    // Real case: dev #485058 → parent #485064 → (blocks) QA #485060, (relates) business #317401.
    Map<String, dynamic> issue(int id, int tracker,
            {int? parent, List<int> children = const [], List<(int, int)> relations = const []}) =>
        {
          'id': id,
          'tracker': {'id': tracker, 'name': '$tracker'},
          if (parent != null) 'parent': {'id': parent},
          'children': [
            for (final c in children) {'id': c}
          ],
          'relations': [
            for (final (from, to) in relations) {'issue_id': from, 'issue_to_id': to}
          ],
        };
    const dev = 42, qa = 43, business = 41;
    final issues = {
      485058: issue(485058, dev, parent: 485064),
      485064: issue(485064, dev,
          children: [485058, 485059], relations: [(317401, 485064), (485064, 485060)]),
      485059: issue(485059, dev, parent: 485064),
      317401: issue(317401, business, relations: [(317401, 485060), (317401, 485064)]),
      485060: issue(485060, qa, relations: [(317401, 485060), (485064, 485060)]),
    };

    test('finds the QA two levels up and stops there', () async {
      final fetched = <int>[];
      final found = await nearbyIssues(RedmineIssue(issues[485058]!), (id) async {
        fetched.add(id);
        return issues[id] == null ? null : RedmineIssue(issues[id]!);
      }, trackerIds: {qa});
      expect(found.where((n) => n.issue.refId('tracker') == qa).map((n) => (n.issue.id, n.depth)),
          [(485060, 2)]);
      // Level 1 = the parent; level 2 = its subtasks and relations. No level 3.
      expect(fetched.toSet(), {485064, 485059, 317401, 485060});
    });

    test('keeps going until QA and business are both found', () async {
      final found = await nearbyIssues(
        RedmineIssue(issues[485058]!),
        (id) async => RedmineIssue(issues[id]!),
        trackerIds: {qa, business},
      );
      int depthOf(int tracker) =>
          found.firstWhere((n) => n.issue.refId('tracker') == tracker).depth;
      expect((depthOf(qa), depthOf(business)), (2, 2));
    });

    test('skips unreadable issues and respects maxDepth', () async {
      final found = await nearbyIssues(
        RedmineIssue(issues[485058]!),
        (id) async => id == 485064 ? null : RedmineIssue(issues[id]!),
        trackerIds: {qa},
      );
      expect(found, isEmpty); // the parent failed, so nothing beyond it is reachable

      final shallow = await nearbyIssues(
        RedmineIssue(issues[485058]!),
        (id) async => RedmineIssue(issues[id]!),
        trackerIds: {999},
        maxDepth: 1,
      );
      expect(shallow.map((n) => n.issue.id), [485064]);
    });
  });

  test('Claude action builds the claude-cli deep link', () {
    final prompt = renderClaudePrompt(
      '/pano-cr refs #{{numeroAtividade}}',
      issueId: 484530,
      subject: 'Tela X',
    );
    expect(prompt, '/pano-cr refs #484530');
    expect(
      claudeDeepLink('/Users/x/proj', prompt).toString(),
      'claude-cli://open?cwd=%2FUsers%2Fx%2Fproj&q=%2Fpano-cr%20refs%20%23484530',
    );
    const action = ClaudeAction(name: 'CR', cwd: '/p', template: '/x {{titulo}}');
    final back = ClaudeAction.listFromJson(ClaudeAction.listToJson([action])).single;
    expect((back.name, back.cwd, back.template), ('CR', '/p', '/x {{titulo}}'));
    expect(ClaudeAction.listFromJson(null), isEmpty);
  });

  test('board columns stretch to fill, never below 270', () {
    expect(boardColumnWidth(7 * 400, 7), 400 - 14); // fits: fills exactly
    expect(boardColumnWidth(1000, 7), 270); // doesn't fit: scrolls
    expect(boardColumnWidth(3000, 2), 480); // few columns: capped
  });

  test('parseHours accepts decimal comma/dot and h:mm', () {
    expect(parseHours('1,5'), 1.5);
    expect(parseHours('1.5'), 1.5);
    expect(parseHours('1:30'), 1.5);
    expect(parseHours(' 0:45 '), 0.75);
    expect(parseHours(''), null);
    expect(parseHours('abc'), null);
    expect(parseHours('0'), null);
  });

  test('closing steps round-trip and old JSON has none', () {
    const rule = HandoffRule(
      name: 'QA',
      timeActivityId: 14,
      statusSteps: [(trackerId: 42, statusId: 110), (trackerId: 41, statusId: 3)],
    );
    final back = HandoffRule.fromJson(
      jsonDecode(jsonEncode(rule.toJson())) as Map<String, dynamic>,
    );
    expect(back.timeActivityId, 14);
    expect(back.statusSteps.map((s) => (s.trackerId, s.statusId)), [(42, 110), (41, 3)]);
    final old = HandoffRule.fromJson({'name': 'old'});
    expect(old.timeActivityId, null);
    expect(old.statusSteps, isEmpty);
    const action = ClaudeAction(name: 'CR', cwd: '/p', template: '/x', statusId: 2);
    expect(ClaudeAction.fromJson(action.toJson() as Map<String, dynamic>).statusId, 2);
    expect(ClaudeAction.fromJson({'name': 'old'}).statusId, null);
  });

  test('status steps pre-check the opened issue, noted ones, else the closest', () {
    // Dev step: opened #10 (depth 0), sibling #11 with a picked note, parent #9.
    expect(
      defaultChecked([(id: 10, depth: 0), (id: 9, depth: 1), (id: 11, depth: 2)], 10, {11}),
      {10, 11},
    );
    // Business step: none of them; the closest one wins.
    expect(defaultChecked([(id: 30, depth: 3), (id: 20, depth: 2)], 10, {11}), {20});
    expect(defaultChecked([], 10, {}), isEmpty);
  });

  test('Ágil board builds its endpoint from the scope', () {
    expect(
      const AgileBoard().endpoint,
      '/issues.json?status_id=open&assigned_to_id=me&sort=updated_on:desc',
    );
    const scoped = AgileBoard(projectId: 7, mine: false, openOnly: false);
    expect(scoped.endpoint, '/projects/7/issues.json?status_id=*&sort=updated_on:desc');
    expect(scoped.directUrl, '/projects/7/issues?status_id=*&sort=updated_on:desc');
    expect(scoped.toQuery().id, agileQueryId);
    final back = AgileBoard.fromJson(
      jsonDecode(jsonEncode(
        scoped.copyWith(boardStatusIds: [1, 2], prefs: const BoardPrefs(listMode: true)).toJson(),
      )) as Map<String, dynamic>,
    );
    expect(
        (back.projectId, back.mine, back.openOnly, back.prefs.listMode), (7, false, false, true));
    expect(back.boardStatusIds, [1, 2]);
  });

  test('relation labels read from each side', () {
    const blocks = {'relation_type': 'blocks', 'issue_id': 1, 'issue_to_id': 2};
    expect(relationLabel(blocks, 1), 'Bloqueia');
    expect(relationLabel(blocks, 2), 'Bloqueada por');
    expect(relationLabel({'relation_type': 'relates', 'issue_id': 1}, 2), 'Relacionada a');
    expect(relationLabel({'relation_type': 'precedes', 'issue_id': 1}, 2), 'Segue');
  });

  test('button icons are saved by key and fall back to the default', () {
    const action = ClaudeAction(name: 'CR', cwd: '/p', template: '/x', icon: 'rate_review');
    expect(ClaudeAction.fromJson(action.toJson() as Map<String, dynamic>).icon, 'rate_review');
    const rule = HandoffRule(name: 'QA', icon: 'verified');
    expect(HandoffRule.fromJson(rule.toJson() as Map<String, dynamic>).icon, 'verified');
    expect(HandoffRule.fromJson({'name': 'old'}).icon, null);
    expect(actionIcon('rate_review', Icons.terminal), Icons.rate_review_outlined);
    expect(actionIcon(null, Icons.terminal), Icons.terminal);
    expect(actionIcon('gone', Icons.send_outlined), Icons.send_outlined);
  });

  test('same-issue rules round-trip; old rules send to another issue', () {
    const rule = HandoffRule(name: 'Mandar pro Rafael', sameIssue: true, template: '');
    final back = HandoffRule.fromJson(rule.toJson() as Map<String, dynamic>);
    expect((back.sameIssue, back.template), (true, ''));
    expect(HandoffRule.fromJson({'name': 'old'}).sameIssue, false);
  });

  test('previewKind by content type, then by extension', () {
    expect(previewKind('print.png', 'image/png'), AttachmentKind.image);
    expect(previewKind('print.PNG', 'application/octet-stream'), AttachmentKind.image);
    expect(previewKind('erro.log', 'application/octet-stream'), AttachmentKind.text);
    expect(previewKind('dados.json', 'application/json'), AttachmentKind.text);
    expect(previewKind('Leia.md', 'text/plain'), AttachmentKind.markdown);
    expect(previewKind('spec.pdf', 'application/pdf'), AttachmentKind.pdf);
    expect(previewKind('tela.mov', 'video/quicktime'), AttachmentKind.video);
    const xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    expect(previewKind('planilha.xlsx', xlsx), AttachmentKind.none);
    expect(previewKind('logo.svg', 'image/svg+xml'), AttachmentKind.text); // shown as source
    expect(fmtFileSize(1536), '1,5 KB');
    expect(fmtFileSize(512), '512 B');
    expect(fmtFileSize(2048), '2 KB');
  });

  test('getBytes sends the API key only to the configured Redmine', () async {
    final seen = <String, String?>{};
    await http.runWithClient(() async {
      final settings = AppSettings(baseUrl: 'https://redmine.test', apiKey: 'secret');
      final api = RedmineApiService();
      final file = await api.getBytes(settings, '/attachments/download/1/a.png');
      expect(file.bytes, [1, 2, 3]);
      expect(() => api.getBytes(settings, 'https://evil.test/x.png'), throwsArgumentError);
    },
        () => MockClient((r) async {
              seen[r.url.host] = r.headers['X-Redmine-API-Key'];
              return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/png'});
            }));
    expect(seen, {'redmine.test': 'secret'});
  });

  test('Claude Desktop link (experimental) and the openInApp flag', () {
    expect(
      claudeDesktopLink('/pano-cr refs #484530').toString(),
      'claude://code/new?q=%2Fpano-cr%20refs%20%23484530',
    );
    const action = ClaudeAction(name: 'CR', cwd: '', template: '/x', openInApp: true);
    expect(ClaudeAction.fromJson(action.toJson() as Map<String, dynamic>).openInApp, true);
    expect(ClaudeAction.fromJson({'name': 'old'}).openInApp, false);
  });

  testWidgets('SearchSelect: empty search on open, filters, Enter picks, none is null',
      (tester) async {
    int? value = 7;
    final picked = <int?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => SearchSelect(
            value: value,
            none: 'Manter o atual (Fulano)',
            options: const [(7, 'Fulano'), (8, 'Rafael Schork'), (9, 'André Cristen')],
            onChanged: (v) => set(() {
              value = v;
              picked.add(v);
            }),
          ),
        ),
      ),
    ));
    expect(find.text('Fulano'), findsOneWidget); // current choice on the field

    await tester.tap(find.text('Fulano'));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Buscar…');
    expect(tester.widget<TextField>(search).controller!.text, isEmpty); // not the label
    await tester.enterText(search, 'andre'); // no accent
    await tester.pumpAndSettle();
    expect(find.text('André Cristen'), findsOneWidget);
    expect(find.text('Rafael Schork'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
    await tester.pumpAndSettle();
    expect(picked, [9]);

    await tester.tap(find.text('André Cristen'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Buscar…')).controller!.text,
        isEmpty); // fresh search on every opening
    await tester.tap(find.text('Manter o atual (Fulano)'));
    await tester.pumpAndSettle();
    expect(picked, [9, null]);
    expect(find.text('Manter o atual (Fulano)'), findsOneWidget);
  });

  testWidgets('SearchSelect with typedId picks a number outside the options', (tester) async {
    int? value;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => SearchSelect(
            value: value,
            typedId: true,
            hint: 'Tarefa…',
            options: const [(287239, '#287239 · Comprovante')],
            onChanged: (v) => set(() => value = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Tarefa…'));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Buscar…');
    await tester.enterText(search, '287239'); // already an option: no extra entry
    await tester.pumpAndSettle();
    expect(find.textContaining('usar este ID'), findsNothing);
    await tester.enterText(search, '#4001');
    await tester.pumpAndSettle();
    expect(find.text('#4001 · usar este ID'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
    await tester.pumpAndSettle();
    expect(value, 4001);
    expect(find.text('#4001'), findsOneWidget); // shown on the field
  });

  test('logTime round-trips and keeps the old behaviour for saved rules', () {
    const rule = HandoffRule(name: 'QA', logTime: true, timeActivityId: 14);
    expect(HandoffRule.fromJson(rule.toJson() as Map<String, dynamic>).logTime, true);
    expect(
        HandoffRule.fromJson({'name': 'x', 'logTime': false, 'timeActivityId': 14}).logTime, false);
    // Saved before the toggle: same-issue always logged; others only with an activity.
    expect(HandoffRule.fromJson({'name': 'a', 'sameIssue': true}).logTime, true);
    expect(HandoffRule.fromJson({'name': 'b', 'timeActivityId': 14}).logTime, true);
    expect(HandoffRule.fromJson({'name': 'c'}).logTime, false);
  });

  for (final dark in [false, true]) {
    testWidgets('selected text stays visible in markdown code (dark: $dark)', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      final issue = {
        'id': 10,
        'subject': 'Prazo',
        'description':
            'Texto\n\n```\nFoi alterado o prazo do pedido 2606246035\n```\n\nUse `código`.',
        'status': {'id': 1, 'name': 'Nova'},
        'journals': [],
      };
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => AppState(databaseService: DatabaseService.instance)
            ..settings = AppSettings(baseUrl: 'https://r.test', apiKey: 'k'),
          child: MaterialApp(
            theme: buildAppTheme(dark: dark),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showIssueDetail(context, RedmineIssue(issue)),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }, () => MockClient((r) async => http.Response(jsonEncode({'issue': issue}), 200)));

      // A per-glyph background is painted over the selection highlight.
      final painted = <String>[];
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          final bg = span.style?.backgroundColor;
          if (bg != null && bg.a > 0) painted.add('${span.text}');
          span.children?.forEach(visit);
        }
      }

      for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
        visit(w.text);
      }
      expect(find.textContaining('2606246035', findRichText: true), findsWidgets);
      expect(painted, isEmpty);
      // Page-like selection (SelectionArea per column), not a selectable box per block.
      expect(find.byType(SelectionArea), findsWidgets);
      expect(find.byType(SelectableText), findsNothing);
    });
  }

  // Browser-like copy on macOS (regression: per-block selection, glued blocks).

  testWidgets('macOS: drag across code block and paragraph, Cmd+C copies both', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final issue = {
      'id': 10,
      'subject': 'Prazo',
      'description':
          'Antes.\n\n```\nFoi alterado o prazo da Nota Fiscal\nsegunda linha do bloco\n```\n\nValidamos os dois pedidos repassados.\n\n- item um\n- item dois',
      'status': {'id': 1, 'name': 'Nova'},
      'journals': [],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppState(databaseService: DatabaseService.instance)
          ..settings = AppSettings(baseUrl: 'https://r.test', apiKey: 'k'),
        child: MaterialApp(
          theme: buildAppTheme(dark: true),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showIssueDetail(context, RedmineIssue(issue)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }, () => MockClient((r) async => http.Response(jsonEncode({'issue': issue}), 200)));

    final block = find.textContaining('Foi alterado', findRichText: true).first;
    final para = find.textContaining('item dois', findRichText: true).first;
    final start = tester.getTopLeft(block) + const Offset(2, 4);
    final end = tester.getBottomRight(para) - const Offset(2, 4);
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
    expect(copied, isNotNull);
    expect(copied, contains('Nota Fiscal'));
    expect(copied, contains('segunda linha do bloco'));
    expect(copied, startsWith('Foi alterado'));
    expect(copied, contains('do bloco\nValidamos os dois pedidos'));
    expect(copied, contains('repassados.\n• item um\n• item dois'));
  });

  testWidgets('macOS: attributes copy label and value on separate lines', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final issue = {
      'id': 10,
      'subject': 'Prazo',
      'description': 'x',
      'status': {'id': 1, 'name': 'Nova'},
      'priority': {'id': 1, 'name': 'Normal'},
      'journals': [],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppState(databaseService: DatabaseService.instance)
          ..settings = AppSettings(baseUrl: 'https://r.test', apiKey: 'k'),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showIssueDetail(context, RedmineIssue(issue)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }, () => MockClient((r) async => http.Response(jsonEncode({'issue': issue}), 200)));
    final status = find.text('Status').last;
    final value = find.text('Normal').last;
    final g = await tester.startGesture(tester.getTopLeft(status) + const Offset(1, 2),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveTo(tester.getBottomRight(value) - const Offset(1, 2));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(copied, 'Status\nNova\nPrioridade\nNormal');
  });

  /// App with an "open" button running [open] (inside a Scaffold, for snackbars).
  Widget appWith(void Function(BuildContext context) open, {AppSettings? settings}) =>
      ChangeNotifierProvider(
        create: (_) => AppState(databaseService: DatabaseService.instance)
          ..settings = settings ?? AppSettings(baseUrl: 'https://r.test', apiKey: 'k'),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  TextButton(onPressed: () => open(context), child: const Text('open')),
            ),
          ),
        ),
      );

  testWidgets('description keeps Redmine line breaks; edit saves only what changed',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = {
      'id': 10,
      'subject': 'Portal',
      'description': '**Descrição:**\r\nAlgumas telas',
      'project': {'id': 1, 'name': 'P'},
      'status': {'id': 1, 'name': 'Nova'},
      'journals': [],
    };
    final puts = <String, Object?>{};
    await http.runWithClient(() async {
      await tester.pumpWidget(appWith((c) => showIssueDetail(c, RedmineIssue(issue))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Redmine renders every newline as a line break (CommonMark hardbreaks).
      expect(find.textContaining('Descrição:\nAlgumas telas', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      final editor = find.widgetWithText(TextField, '**Descrição:**\nAlgumas telas');
      expect(editor, findsOneWidget); // raw text, line endings as typed
      await tester.enterText(editor, 'Nova descrição');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              if (r.method == 'PUT') {
                puts[r.url.path] = jsonDecode(r.body);
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode(r.url.path == '/issue_statuses.json'
                    ? {
                        'issue_statuses': [
                          {'id': 1, 'name': 'Nova'},
                        ],
                      }
                    : {'issue': issue}),
                200,
              );
            }));
    expect(puts, {
      '/issues/10.json': {
        'issue': {'description': 'Nova descrição'},
      },
    });
    expect(find.text('Salvar'), findsNothing); // back to view mode
  });

  testWidgets('issue dialog shows only the actions of its status', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = {
      'id': 10,
      'subject': 'Pausada',
      'status': {'id': 5, 'name': 'Em pausa'},
      'tracker': {'id': 1, 'name': 'Bug'},
      'journals': [],
    };
    final settings = AppSettings(
      baseUrl: 'https://r.test',
      apiKey: 'k',
      handoffRules: const [
        HandoffRule(name: 'Pausar', sameIssue: true, statusIds: [2]),
        HandoffRule(name: 'Retomar', sameIssue: true, statusIds: [5]),
      ],
    );
    await http.runWithClient(() async {
      await tester
          .pumpWidget(appWith((c) => showIssueDetail(c, RedmineIssue(issue)), settings: settings));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }, () => MockClient((r) async => http.Response(jsonEncode({'issue': issue}), 200)));
    expect(find.text('Retomar'), findsOneWidget);
    expect(find.text('Pausar'), findsNothing);
  });

  test('CustomFieldDef: admin JSON, guessed types, scan and display', () {
    final level = CustomFieldDef.fromJson({
      'id': 7,
      'name': 'Nível',
      'field_format': 'enumeration',
      'possible_values': [
        {'value': '3', 'label': 'Alta'},
      ],
      'trackers': [
        {'id': 1, 'name': 'Bug'},
      ],
      'default_value': '',
    });
    expect(level.options, [('3', 'Alta')]);
    expect(level.trackerIds, [1]);
    expect(level.defaultValue, isNull);
    expect(CustomFieldDef.fromJson(level.toJson()).options, level.options); // saved = same JSON

    String guess(List<Object?> values) =>
        CustomFieldDef.infer(id: 1, name: 'x', values: values).format;
    expect(guess(['0', '1', '', null]), 'bool');
    expect(guess(['2026-06-03']), 'date');
    expect(guess(['12', '-3']), 'int');
    expect(guess(['1,5', '2']), 'float');
    expect(guess(['a\nb']), 'text');
    expect(guess(['Vendas', 'Vendas', 'Portal', 'Portal']), 'list');
    expect(guess(['Ana', 'Bia', 'Caio']), 'string');

    final scanned = scanCustomFields([
      {
        'tracker': {'id': 3},
        'custom_fields': [
          {'id': 5, 'name': 'Revisar', 'value': '0'},
        ],
      },
      {
        'tracker': {'id': 2},
        'custom_fields': [
          {'id': 5, 'name': 'Revisar', 'value': '1'},
        ],
      },
    ]);
    expect(scanned.single.format, 'bool');
    expect(scanned.single.trackerIds, [2, 3]);

    const options = IssueOptions(members: [(4, 'Rafael')]);
    const flag = CustomFieldDef(id: 1, name: 'b', format: 'bool');
    expect(customFieldText(flag, '1', options), 'Sim');
    expect(customFieldText(flag, '0', options), 'Não');
    expect(customFieldText(level, '3', options), 'Alta');
    expect(customFieldText(const CustomFieldDef(id: 2, name: 'u', format: 'user'), '4', options),
        'Rafael');
    expect(customFieldText(null, '2026-06-03', options), '03-06-2026'); // no type saved
    expect(customFieldText(null, ['a', 'b'], options), 'a, b');
  });

  testWidgets('Editar: typed fields send only what changed; history names the changes',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = {
      'id': 10,
      'subject': 'Portal',
      'description': 'x',
      'project': {'id': 1, 'name': 'P'},
      'tracker': {'id': 3, 'name': 'Negócio'},
      'status': {'id': 2, 'name': 'Em andamento'},
      'custom_fields': [
        {'id': 5, 'name': 'Revisar Código-Fonte', 'value': '0'},
        {'id': 6, 'name': 'Módulo', 'value': 'Vendas'},
      ],
      'journals': [
        {
          'user': {'name': 'Ana'},
          'created_on': '2026-10-16T10:00:00Z',
          'notes': '',
          'details': [
            {'property': 'attr', 'name': 'status_id', 'old_value': '1', 'new_value': '2'},
            {'property': 'cf', 'name': '5', 'old_value': '1', 'new_value': '0'},
          ],
        },
      ],
    };
    final settings = AppSettings(
      baseUrl: 'https://r.test',
      apiKey: 'k',
      customFields: const [CustomFieldDef(id: 5, name: 'Revisar Código-Fonte', format: 'bool')],
    );
    final puts = <String, Object?>{};
    await http.runWithClient(() async {
      await tester
          .pumpWidget(appWith((c) => showIssueDetail(c, RedmineIssue(issue)), settings: settings));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Não'), findsOneWidget); // bool shown as Sim/Não, not "0"

      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Status:  Nova  →  Em andamento', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Revisar Código-Fonte:  Sim  →  Não', findRichText: true),
          findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Portal'), 'Portal novo');
      await tester.enterText(find.byKey(const ValueKey('estimated_hours')), '1:30');
      await tester.ensureVisible(find.text('Sim')); // bottom of the side panel
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              if (r.method == 'PUT') {
                puts[r.url.path] = jsonDecode(r.body);
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode(switch (r.url.path) {
                  '/issue_statuses.json' => {
                      'issue_statuses': [
                        {'id': 1, 'name': 'Nova'},
                        {'id': 2, 'name': 'Em andamento'},
                      ],
                    },
                  '/issues/10.json' => {'issue': issue},
                  _ => <String, Object>{},
                }),
                200,
              );
            }));
    expect(puts, {
      '/issues/10.json': {
        'issue': {
          'subject': 'Portal novo',
          'estimated_hours': 1.5,
          'custom_fields': [
            {'id': 5, 'value': '1'},
          ],
        },
      },
    });
  });

  testWidgets('Alterar em massa lists subtasks of related issues; changes checked ones only',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = RedmineIssue({
      'id': 10,
      'subject': 'História',
      'project': {'id': 1, 'name': 'P'},
      'relations': [
        {'issue_id': 10, 'issue_to_id': 12, 'relation_type': 'relates'},
      ],
    });
    final puts = <String, Object?>{};
    var moved = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(appWith((c) async => moved = await showBulkEditDialog(c, issue)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Velha'), findsNothing); // closed versions are not offered
      await tester.tap(find.text('Manter').at(2)); // Situação, Responsável, Versão
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sprint 1').first); // the menu entry, before the row tags
      await tester.pumpAndSettle();
      // #10 and its subtask #11 are checked, but #11 is already there.
      expect(find.text('Aplicar em 1'), findsOneWidget);
      // Checking the related #12 takes its subtask #13 along.
      await tester.tap(find.text('QA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar em 3'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              if (r.method == 'PUT') {
                puts[r.url.path] = jsonDecode(r.body);
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode(switch (r.url.path) {
                  '/projects/1/versions.json' => {
                      'versions': [
                        {'id': 5, 'name': 'Sprint 1', 'status': 'open'},
                        {'id': 6, 'name': 'Velha', 'status': 'closed'},
                      ],
                    },
                  '/issue_statuses.json' => {
                      'issue_statuses': [
                        {'id': 1, 'name': 'Nova'},
                      ],
                    },
                  // Roots by issue_id, then subtasks level by level by parent_id.
                  _ => {
                      'issues': switch (r.url.queryParameters['parent_id']) {
                        null when r.url.queryParameters['issue_id'] != null => [
                            {'id': 10, 'subject': 'História'},
                            {'id': 12, 'subject': 'QA'},
                          ],
                        '10,12' => [
                            {
                              'id': 11,
                              'subject': 'Dev',
                              'parent': {'id': 10},
                              'fixed_version': {'id': 5, 'name': 'Sprint 1'},
                            },
                            {
                              'id': 13,
                              'subject': 'Teste',
                              'parent': {'id': 12},
                            },
                          ],
                        _ => <Object>[],
                      },
                    },
                }),
                200,
              );
            }));
    const version = {
      'issue': {'fixed_version_id': 5},
    };
    expect(
        puts, {'/issues/10.json': version, '/issues/12.json': version, '/issues/13.json': version});
    expect(moved, true);
  });

  test('bulk round-trips and old rules have it off', () {
    const rule = HandoffRule(name: 'Enviar ao dev', sameIssue: true, bulk: true);
    expect(HandoffRule.fromJson(rule.toJson() as Map<String, dynamic>).bulk, true);
    expect(HandoffRule.fromJson({'name': 'x'}).bulk, false);
  });

  testWidgets('bulk trâmite repeats comment and status on the checked linked issues',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = RedmineIssue({
      'id': 10,
      'subject': 'Portal',
      'project': {'id': 1, 'name': 'P'},
      'status': {'id': 1, 'name': 'Nova'},
      'journals': [],
      'relations': [
        {'issue_id': 10, 'issue_to_id': 12, 'relation_type': 'relates'},
      ],
    });
    const rule = HandoffRule(
      name: 'Enviar ao dev',
      sameIssue: true,
      statusId: 2,
      template: 'Para dev',
      bulk: true,
    );
    final puts = <String, Object?>{};
    await http.runWithClient(() async {
      await tester.pumpWidget(appWith((c) => showTramiteDialog(c, issue, rule)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QA')); // the related #12
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('•  Situação: Nova → Em aprovação'), findsOneWidget);
      expect(find.text('•  #12 situação: Nova → Em aprovação'), findsOneWidget);
      expect(find.text('•  Comentário também em #12'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              if (r.method == 'PUT') {
                puts[r.url.path] = jsonDecode(r.body);
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode(switch (r.url.path) {
                  '/issue_statuses.json' => {
                      'issue_statuses': [
                        {'id': 1, 'name': 'Nova'},
                        {'id': 2, 'name': 'Em aprovação'},
                      ],
                    },
                  '/issues.json' when r.url.queryParameters['issue_id'] != null => {
                      'issues': [
                        {
                          'id': 10,
                          'subject': 'Portal',
                          'status': {'id': 1, 'name': 'Nova'},
                        },
                        {
                          'id': 12,
                          'subject': 'QA',
                          'status': {'id': 1, 'name': 'Nova'},
                        },
                      ],
                    },
                  // setIssueStatus reads the issue again.
                  '/issues/10.json' || '/issues/12.json' => {
                      'issue': {
                        'status': {'id': 2, 'name': 'Em aprovação'},
                      },
                    },
                  _ => <String, Object>{},
                }),
                200,
              );
            }));
    const update = {
      'issue': {'notes': 'Para dev', 'status_id': 2},
    };
    expect(puts, {'/issues/10.json': update, '/issues/12.json': update});
  });

  testWidgets('⋮ menu: Alterar situação moves; a Claude action that moves asks first',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = RedmineIssue({
      'id': 10,
      'subject': 'Portal',
      'status': {'id': 1, 'name': 'Nova'},
    });
    final moves = <int>[];
    final requests = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AppState(databaseService: DatabaseService.instance)
          ..settings = AppSettings(
            baseUrl: 'https://r.test',
            apiKey: 'k',
            claudeActions: const [
              ClaudeAction(name: 'Revisar', cwd: '/tmp', template: 'x', statusId: 2),
            ],
          ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: IssueActionsMenu(
                issue: issue,
                onChanged: () {},
                statuses: const [(1, 'Nova'), (2, 'Em andamento')],
                onMove: moves.add,
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alterar situação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Em andamento'));
      await tester.pumpAndSettle();
      expect(moves, [2]);

      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      expect(find.text('•  Situação: Nova → Em andamento'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              requests.add('${r.method} ${r.url.path}');
              return http.Response(
                jsonEncode({
                  'issue_statuses': [
                    {'id': 1, 'name': 'Nova'},
                    {'id': 2, 'name': 'Em andamento'},
                  ],
                }),
                200,
              );
            }));
    expect(requests, ['GET /issue_statuses.json']); // Cancelar: nothing opened or changed
  });

  testWidgets('trâmite that changes the status asks before sending', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final issue = RedmineIssue({
      'id': 10,
      'subject': 'Portal',
      'project': {'id': 1, 'name': 'P'},
      'status': {'id': 1, 'name': 'Nova'},
      'journals': [],
    });
    const rule = HandoffRule(name: 'Testar', sameIssue: true, statusId: 2, template: '');
    final puts = <String>[];
    var sent = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(appWith((c) async => sent = await showTramiteDialog(c, issue, rule)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('•  Situação: Nova → Em teste'), findsOneWidget);
      expect(puts, isEmpty); // nothing before confirming
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
    },
        () => MockClient((r) async {
              if (r.method == 'PUT') {
                puts.add(r.url.path);
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode(switch (r.url.path) {
                  '/issue_statuses.json' => {
                      'issue_statuses': [
                        {'id': 1, 'name': 'Nova'},
                        {'id': 2, 'name': 'Em teste'},
                      ],
                    },
                  '/issues/10.json' => {
                      'issue': {
                        'id': 10,
                        'status': {'id': 2, 'name': 'Em teste'},
                      },
                    },
                  _ => <String, Object>{},
                }),
                200,
              );
            }));
    expect(puts, ['/issues/10.json']);
    expect(sent, true);
  });

  test('formatting bar: wrap the selection, prefix lines, code block on its own line', () {
    TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
        );
    final bold = wrapSelection(v('um dois', 3, 7), '**');
    expect(bold.text, 'um **dois**');
    expect(bold.selection.textInside(bold.text), 'dois'); // stays selected
    final empty = wrapSelection(v('ab', 1), '`');
    expect(empty.text, 'a``b');
    expect(empty.selection, const TextSelection.collapsed(offset: 2)); // cursor between
    expect(prefixLines(v('um\ndois\ntrês', 4), '# ').text, 'um\n# dois\ntrês'); // cursor's line
    expect(prefixLines(v('um\ndois\ntrês', 1, 5), '* ').text, '* um\n* dois\ntrês');
    expect(codeBlock(v('texto', 5)).text, 'texto\n```\n\n```');
    expect(codeBlock(v('', 0)).text, '```\n\n```');
  });

  testWidgets('NoteEditor preview renders the markdown', (tester) async {
    final controller = TextEditingController(text: '# Teste\n**forte**');
    final files = <PendingFile>[]; // changed in place by the editor
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteEditor(controller: controller, files: files, onChanged: () {}),
      ),
    ));
    expect(find.widgetWithText(TextField, '# Teste\n**forte**'), findsOneWidget);
    await tester.tap(find.text('Pré-visualizar'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    final texts = [
      for (final w in tester.widgetList<RichText>(find.byType(RichText))) w.text.toPlainText(),
    ];
    expect(texts, containsAll(['Teste', 'forte'])); // no "#" or "**" left
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('LineField border is controlHeight tall and keeps one line', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(dark: true),
      home: Scaffold(body: LineField(controller: controller, hint: 'Horas')),
    ));
    expect(tester.getSize(find.byType(InputDecorator)).height, controlHeight);
    await tester.enterText(find.byType(TextField), '1:30\n');
    expect(controller.text, '1:30');
  });

  test('hours count from the last status change or time entry, not a field-only change', () {
    final issue = RedmineIssue({
      'id': 1,
      'created_on': '2026-10-01T08:00:00Z',
      'journals': [
        {
          'created_on': '2026-10-05T09:00:00Z',
          'user': {'name': 'Ana'},
          'details': [
            {'property': 'attr', 'name': 'status_id', 'old_value': '1', 'new_value': '2'},
          ],
        },
        {
          'created_on': '2026-10-05T15:00:00Z',
          'user': {'name': 'Ana'},
          'details': [
            {'property': 'cf', 'name': '12', 'old_value': '0', 'new_value': '1'},
          ],
        },
      ],
    });
    var (bases, base) = timeBases(issue, const []);
    expect(bases.length, 3); // 2 journals + creation, newest first
    expect(bases[base].at, DateTime.parse('2026-10-05T09:00:00Z').toLocal());
    expect(bases[base].label, contains('Situação alterada'));

    (bases, base) = timeBases(issue, [
      {
        'created_on': '2026-10-05T12:00:00Z',
        'hours': 1.5,
        'user': {'name': 'Bia'}
      },
    ]);
    expect(bases[base].at, DateTime.parse('2026-10-05T12:00:00Z').toLocal());
    expect(bases[base].label, contains('Horas lançadas (1,5 h)'));
  });

  test('business hours split counted time into business and overtime', () {
    const hours = BusinessHours(); // seg–sex 08–12 / 13–18
    // Monday 2026-10-19.
    var split = hours.split(DateTime(2026, 10, 19, 9), DateTime(2026, 10, 19, 11));
    expect((split.business, split.extra), (const Duration(hours: 2), Duration.zero));
    // Across lunch and past 18:00: lunch is a break, only 18–20 is overtime.
    split = hours.split(DateTime(2026, 10, 19, 11), DateTime(2026, 10, 19, 20));
    expect((split.business, split.extra), (const Duration(hours: 6), const Duration(hours: 2)));
    // Started before lunch, sent after it.
    split = hours.split(DateTime(2026, 10, 19, 11, 48), DateTime(2026, 10, 19, 13, 42));
    expect((split.business, split.extra), (const Duration(minutes: 54), Duration.zero));
    // Overnight: 17:00 Mon → 09:00 Tue.
    split = hours.split(DateTime(2026, 10, 19, 17), DateTime(2026, 10, 20, 9));
    expect((split.business, split.extra), (const Duration(hours: 2), const Duration(hours: 14)));
    // Saturday is all overtime.
    split = hours.split(DateTime(2026, 10, 24, 9), DateTime(2026, 10, 24, 12));
    expect((split.business, split.extra), (Duration.zero, const Duration(hours: 3)));

    // The real time, to the minute: no rounding, no minimum.
    expect(fmtHm(const Duration(seconds: 59)), '');
    expect(fmtHm(const Duration(minutes: 1)), '0:01');
    expect(fmtHm(const Duration(minutes: 7, seconds: 40)), '0:07');
    expect(fmtHm(const Duration(hours: 26, minutes: 38)), '26:38');
    expect(parseHours(fmtHm(const Duration(hours: 1, minutes: 38))), closeTo(1.6333, 0.001));

    // Days can differ; overlapping periods count once; invalid ones are ignored.
    const custom = BusinessHours(periods: [
      BusinessPeriod(days: {1, 2, 3, 4}, start: 8 * 60, end: 18 * 60),
      BusinessPeriod(days: {5}, start: 8 * 60, end: 12 * 60),
      BusinessPeriod(days: {1}, start: 17 * 60, end: 19 * 60),
      BusinessPeriod(days: {6}, start: 12 * 60, end: 8 * 60),
    ]);
    expect([for (var d = 1; d <= 7; d++) custom.minutesOn(d) ~/ 60], [11, 10, 10, 10, 4, 0, 0]);
    // Friday 2026-10-23, 11:00 → 14:00: one business hour.
    split = custom.split(DateTime(2026, 10, 23, 11), DateTime(2026, 10, 23, 14));
    expect((split.business, split.extra), (const Duration(hours: 1), const Duration(hours: 2)));

    final restored = BusinessHours.fromJson(custom.toJson());
    expect([for (final p in restored.periods) (p.days.length, p.start, p.end)],
        [(4, 480, 1080), (1, 480, 720), (1, 1020, 1140), (1, 720, 480)]);
    // First format: one weekday set for every period.
    final legacy = BusinessHours.fromJson({
      'weekdays': [1, 3],
      'periods': [
        [480, 720]
      ],
    });
    expect(legacy.periods.single.days, {1, 3});
    expect(legacy.periods.single.start, 480);
  });

  test('bank balance leaves out the paid months', () {
    const entries = [
      OvertimeEntry(day: '2026-08-10', hours: 2),
      OvertimeEntry(day: '2026-09-03', hours: 3),
      OvertimeEntry(day: '2026-10-01', hours: 1.5),
    ];
    expect(bankBalance(entries, {}), 6.5);
    expect(bankBalance(entries, {'2026-09'}), 3.5);
  });

  testWidgets('a dialog stays in its tab while the sidebar opens another one', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(databaseService: DatabaseService.instance)
        ..loading = false
        ..settings = AppSettings(baseUrl: 'https://r.test', apiKey: 'k'),
      child: const MaterialApp(home: HomeScreen()),
    ));
    final tabBar = find.byType(WorkspaceTabs<Object>);
    Finder inTabs(Finder f) => find.descendant(of: tabBar, matching: f);

    showAppDialog<void>(
      tester.element(find.byType(StatGrid)),
      (_) => const AppDialog(title: Text('Janela'), body: Text('dentro da aba')),
    );
    await tester.pumpAndSettle();
    expect(find.text('dentro da aba'), findsOneWidget);

    // The backdrop covers only the tab: the sidebar still opens Logs.
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(inTabs(find.text('Logs')), findsOneWidget);
    expect(find.text('dentro da aba'), findsNothing);

    await tester.tap(inTabs(find.text('Monitoração')));
    await tester.pumpAndSettle();
    expect(find.text('dentro da aba'), findsOneWidget);

    await tester.tap(inTabs(find.byIcon(Icons.close)).last);
    await tester.pumpAndSettle();
    expect(inTabs(find.text('Logs')), findsNothing);
    expect(find.text('dentro da aba'), findsOneWidget);
  });

  testWidgets('WorkspaceTabs: arrows when they overflow; the selected tab is scrolled into view',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: WorkspaceTabs<int>(
              tabs: [for (var i = 0; i < 20; i++) (i, 'Aba $i', null)],
              selected: 19,
              onChanged: (_) {},
              onClose: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Inside the scrolling area, between the arrows.
    bool shown(String text) {
      final view = tester.getRect(find.byType(SingleChildScrollView));
      final rect = tester.getRect(find.text(text));
      return rect.left >= view.left && rect.right <= view.right;
    }

    IconButton arrow(IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));
    expect(shown('Aba 19'), isTrue);
    expect(arrow(Icons.chevron_right).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(shown('Aba 19'), isFalse);
    expect(arrow(Icons.chevron_right).onPressed, isNotNull);
  });

  testWidgets('LinkedIssueList: header columns wide, stacked when narrow; prefix shown once',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <int>[];
    final issue = RedmineIssue({
      'id': 7,
      'subject': '[Qualidade] Unificar listas',
      'tracker': {'id': 1, 'name': 'Qualidade'},
      'status': {'id': 1, 'name': 'Nova'},
      'assigned_to': {'id': 1, 'name': 'André Cristen'},
      'fixed_version': {'id': 1, 'name': 'backlog'},
    });
    Future<void> pump(double width) => tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: LinkedIssueList(
                rows: [
                  ('Relacionada a', issue),
                  ('Copiada de', RedmineIssue({'id': 8})),
                ],
                onOpen: (i) => opened.add(i.id),
              ),
            ),
          ),
        ));

    await pump(1100);
    expect(find.text('RESPONSÁVEL'), findsOneWidget);
    expect(find.text('Unificar listas'), findsOneWidget);
    expect(issue.subject, '[Qualidade] Unificar listas');
    expect(find.text('—'), findsNWidgets(3)); // #8: no assignee, version or status

    await pump(360); // throws on overflow
    expect(find.text('RESPONSÁVEL'), findsNothing);
    expect(find.text('Resp.'), findsNWidgets(2));

    await tester.tap(find.text('Unificar listas'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, [7, 8]);
  });
}
