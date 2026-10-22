import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_settings.dart';
import '../../models/custom_field.dart';
import '../../models/team.dart';
import '../../services/redmine_api_service.dart';
import '../components.dart';
import '../ui_utils.dart';

// Field choices and typed editors of the issue dialog.

/// Names and choices of an issue's fields: the global lists plus the project's.
/// A list that fails to load stays empty (names fall back to `#id`); [error]
/// keeps the first failure for the edit mode notice.
class IssueOptions {
  const IssueOptions({
    this.statuses = const [],
    this.priorities = const [],
    this.trackers = const [],
    this.categories = const [],
    this.members = const [],
    this.versions = const [],
    this.versionNames = const {},
    this.error,
  });

  final List<(int, String)> statuses;
  final List<(int, String)> priorities;
  final List<(int, String)> trackers;
  final List<(int, String)> categories;
  final List<(int, String)> members;

  /// Open versions (the ones Redmine accepts); [versionNames] has the closed ones too.
  final List<(int, String)> versions;
  final Map<int, String> versionNames;
  final String? error;

  static Future<IssueOptions> load(AppSettings settings, int projectId) async {
    final api = RedmineApiService();
    String? error;
    Future<Object?> safe(Future<Object?> request) => request.catchError((Object e) {
          error ??= '$e'.replaceFirst('Exception: ', '');
          return null;
        });
    final [statuses, priorities, project, members, versions] = await Future.wait([
      safe(api.getJson(settings, '/issue_statuses.json')),
      safe(api.getJson(settings, '/enumerations/issue_priorities.json')),
      safe(api.getJson(settings, '/projects/$projectId.json?include=trackers,issue_categories')),
      safe(api.listProjectMembers(settings, projectId)),
      safe(api.getJson(settings, '/projects/$projectId/versions.json')),
    ]);
    List<(int, String)> named(Object? json, String key) => [
          for (final i in ((json as Map?)?[key] as List? ?? const []).whereType<Map>())
            (i['id'] as int, '${i['name']}'),
        ];
    final allVersions = ((versions as Map?)?['versions'] as List? ?? const []).whereType<Map>();
    return IssueOptions(
      statuses: named(statuses, 'issue_statuses'),
      priorities: named(priorities, 'issue_priorities'),
      trackers: named((project as Map?)?['project'], 'trackers'),
      categories: named(project?['project'], 'issue_categories'),
      members: [for (final m in members as List<TeamMember>? ?? const []) (m.id, m.name)],
      versions: [
        for (final v in allVersions)
          if (v['status'] == 'open') (v['id'] as int, '${v['name']}'),
      ],
      versionNames: {for (final v in allVersions) v['id'] as int: '${v['name']}'},
      error: error,
    );
  }
}

/// Saved definition of an issue's custom [field] (`{id, name, value}`), or a
/// fallback when it isn't configured: dates by their value, multiple values as
/// a list of the current ones, anything else as text.
CustomFieldDef customFieldDef(List<CustomFieldDef> saved, Map field) {
  final id = field['id'] as int;
  final value = field['value'];
  final multiple = field['multiple'] == true || value is List;
  return saved.where((d) => d.id == id).firstOrNull ??
      CustomFieldDef(
        id: id,
        name: '${field['name']}',
        format: multiple
            ? 'list'
            : _isDate('${value ?? ''}')
                ? 'date'
                : 'string',
        multiple: multiple,
        options: [for (final v in value is List ? value : const []) ('$v', '$v')],
      );
}

bool _isDate(String v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v);

/// A custom field value as text: Sim/Não, dates, list labels, user and version
/// names. Empty values give ''.
String customFieldText(CustomFieldDef? def, Object? value, IssueOptions options) {
  String one(String v) => switch (def?.format) {
        'bool' => v == '1'
            ? 'Sim'
            : v == '0'
                ? 'Não'
                : v,
        'date' => fmtDate(v),
        'enumeration' => def!.options.where((o) => o.$1 == v).firstOrNull?.$2 ?? v,
        'user' => options.members.where((o) => '${o.$1}' == v).firstOrNull?.$2 ?? '#$v',
        'version' => options.versionNames[int.tryParse(v)] ?? '#$v',
        _ when def == null && _isDate(v) => fmtDate(v),
        _ => v,
      };
  return [
    for (final v in value is List ? value : [value])
      if (v != null && '$v'.isNotEmpty) one('$v'),
  ].join(', ');
}

/// Editor of a custom field by its [def] format. [value] is a String, or a
/// List<String> when the field is multiple; [options] gives users and versions.
Widget customFieldEditor({
  required CustomFieldDef def,
  required Object? value,
  required ValueChanged<Object> onChanged,
  required IssueOptions options,
}) {
  final text = value is List ? value.join(', ') : '${value ?? ''}';
  final key = ValueKey('cf_${def.id}');
  switch (def.format) {
    case 'date':
      return DateSelect(key: key, value: text, onChanged: onChanged);
    case 'bool':
      return SegmentButtons<String>(
        key: key,
        segments: const [('', '—', null), ('1', 'Sim', null), ('0', 'Não', null)],
        selected: text,
        onChanged: onChanged,
      );
    case 'list' || 'enumeration' || 'user' || 'version':
      final picked = value is List ? [for (final v in value) '$v'] : [if (text.isNotEmpty) text];
      // The current values stay choosable even when missing from the list.
      final choices = [
        ...switch (def.format) {
          'user' => [for (final (id, name) in options.members) ('$id', name)],
          'version' => [for (final (id, name) in options.versions) ('$id', name)],
          _ => def.options,
        },
      ];
      for (final v in picked) {
        if (!choices.any((c) => c.$1 == v)) {
          choices.add((v, customFieldText(def, v, options)));
        }
      }
      if (def.multiple) {
        // ponytail: one chip per value; a searchable multi-select if lists get long.
        return Wrap(
          key: key,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (v, label) in choices)
              FilterChip(
                label: Text(label),
                selected: picked.contains(v),
                onSelected: (on) => onChanged(on ? [...picked, v] : [...picked]
                  ..remove(v)),
              ),
          ],
        );
      }
      return SearchSelect(
        key: key,
        value: text.isEmpty ? null : choices.indexWhere((c) => c.$1 == text),
        options: [for (final (i, (_, label)) in choices.indexed) (i, label)],
        none: '—',
        onChanged: (i) => onChanged(i == null ? '' : choices[i].$1),
      );
    case 'string' || 'link' || 'int' || 'float' || 'text':
      final number = def.format == 'int' || def.format == 'float';
      if (def.format == 'text') {
        return TextFormField(
          key: key,
          initialValue: text,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(12)),
          onChanged: onChanged,
        );
      }
      return LineField(
        key: key,
        initialValue: text,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        inputFormatters: [
          if (def.format == 'int') FilteringTextInputFormatter.allow(RegExp(r'[-0-9]')),
          if (def.format == 'float') FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        onChanged: onChanged,
      );
    default: // e.g. attachment: not editable here
      return Text(text.isEmpty ? '-' : text, key: key);
  }
}

/// Single-line text editor of the issue dialog (estimate, parent…).
Widget fieldText({
  required Key key,
  required String value,
  required ValueChanged<String> onChanged,
  String? hint,
}) =>
    LineField(key: key, initialValue: value, hint: hint, onChanged: onChanged);
