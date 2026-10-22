import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/redmine_issue.dart';
import '../../services/redmine_api_service.dart';
import '../../services/theme_service.dart';
import '../components.dart';
import '../ui_utils.dart';
import 'issue_detail_dialog.dart';

/// An issue with its parent, related issues and the subtasks of all of them
/// (the parent's are the issue's siblings), to act on several at once.
class IssueTree {
  IssueTree._(this.rows, this._children);

  /// Top-level issues (the issue, parent, related), each followed by its
  /// subtasks; [role] says how it links to the issue.
  final List<({RedmineIssue issue, int depth, String role})> rows;
  final Map<int, List<RedmineIssue>> _children;

  /// [id] and all its subtasks.
  Iterable<int> subtree(int id) sync* {
    yield id;
    for (final c in _children[id] ?? const <RedmineIssue>[]) {
      yield* subtree(c.id);
    }
  }

  /// [issue] must come with `relations`. Top-level issues in one call, then
  /// subtasks level by level, one request per level (`parent_id` takes a list).
  // ponytail: 3 levels deep; raise it if trees go further.
  static Future<IssueTree> load(AppSettings settings, RedmineIssue issue) async {
    final api = RedmineApiService();
    final roles = {issue.id: 'Esta tarefa'};
    if (issue.refId('parent') case final parent?) roles.putIfAbsent(parent, () => 'Tarefa pai');
    for (final r in (issue.json['relations'] as List? ?? const []).cast<Map>()) {
      final other = (r['issue_id'] == issue.id ? r['issue_to_id'] : r['issue_id']) as int;
      roles.putIfAbsent(other, () => relationLabel(r, issue.id));
    }
    // The ones the user can't see are skipped.
    final found = await api.getAllPages(
      settings,
      '/issues.json?issue_id=${roles.keys.join(',')}&status_id=*',
      'issues',
    );
    final byId = {for (final j in found) j['id'] as int: RedmineIssue(j)};
    final roots = [
      for (final id in roles.keys)
        if (byId[id] case final i?) i,
    ];

    // Already listed issues (the issue under its parent) don't repeat.
    final seen = {...byId.keys};
    final children = <int, List<RedmineIssue>>{};
    var parents = [for (final i in roots) i.id];
    for (var level = 0; level < 3 && parents.isNotEmpty; level++) {
      final batch = await api.getAllPages(
        settings,
        '/issues.json?parent_id=${parents.join(',')}&status_id=*',
        'issues',
      );
      parents = [];
      for (final j in batch) {
        final child = RedmineIssue(j);
        final parent = child.refId('parent');
        if (parent == null || !seen.add(child.id)) continue;
        children.putIfAbsent(parent, () => []).add(child);
        parents.add(child.id);
      }
    }

    final rows = <({RedmineIssue issue, int depth, String role})>[];
    void add(RedmineIssue i, int depth) {
      rows.add((issue: i, depth: depth, role: roles[i.id] ?? 'Subtarefa'));
      for (final c in children[i.id] ?? const <RedmineIssue>[]) {
        add(c, depth + 1);
      }
    }

    for (final r in roots) {
      add(r, 0);
    }
    return IssueTree._(rows, children);
  }
}

/// Rows of an [IssueTree] with a checkbox, indented under their parent, with
/// the current status, assignee and version. (Un)checking an issue takes its
/// subtasks along; [locked] ones stay checked. [checked] changes in place.
class IssueTreeList extends StatelessWidget {
  const IssueTreeList({
    super.key,
    required this.tree,
    required this.checked,
    required this.onChanged,
    this.locked = const {},
  });

  final IssueTree tree;
  final Set<int> checked;
  final VoidCallback onChanged;
  final Set<int> locked;

  void _toggle(int id) {
    final on = !checked.contains(id);
    for (final i in tree.subtree(id)) {
      if (locked.contains(i)) continue;
      on ? checked.add(i) : checked.remove(i);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (:issue, :depth, :role) in tree.rows)
          InkWell(
            onTap: locked.contains(issue.id) ? null : () => _toggle(issue.id),
            borderRadius: BorderRadius.circular(AppRadius.standard),
            child: Row(
              children: [
                SizedBox(width: depth * 24.0),
                Checkbox(
                  value: checked.contains(issue.id),
                  onChanged: locked.contains(issue.id) ? null : (_) => _toggle(issue.id),
                ),
                SizedBox(width: 110, child: Text(role, style: AppText.microLabel(dark: dark))),
                if (issue.trackerName.isNotEmpty) ...[
                  Tag.hashed(issue.trackerName),
                  const SizedBox(width: 8),
                ],
                IssueNumber(
                  issue.id,
                  style:
                      AppText.microLabel(dark: dark).copyWith(color: AppColors.accent(dark: dark)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issue.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(dark: dark),
                  ),
                ),
                // Fixed columns, so status, assignee and version line up.
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: issue.json['status'] == null ? null : Tag(issue.statusName),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: Text(
                    issue.assigneeName ?? 'Ninguém',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(dark: dark),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tag(issue.nameOf('fixed_version') ?? 'Sem versão'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
