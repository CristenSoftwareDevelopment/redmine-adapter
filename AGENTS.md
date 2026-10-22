# AGENTS.md

## What this repo is

Flutter app (`redmine_monitor_flutter`) monitors Redmine saved queries, fires in-app alerts on count change. Has tiny Node.js CORS proxy (`src/web_proxy.js`) for web builds.

---

## Setup — first time

Repo **not** bootstrapped with `flutter create`, platform scaffold files generated separately. Exist. Do not run `flutter create .` again — overwrites platform configs.

```bash
flutter pub get
```

**Flutter version is pinned**: the release workflow (`.github/workflows/release.yml`) uses
`flutter-version: 3.41.6`, the version that generated `pubspec.lock`. A floating `stable` broke the
release once (pdfrx_engine 0.4.5 fails on newer Dart; its fix needs a newer Flutter). To upgrade,
bump the local Flutter, `flutter pub upgrade`, and the workflow version together.

---

## Dev commands

| Purpose | Command |
|---|---|
| Run on Chrome (fixed port) | `flutter run -d chrome --web-port 64451` |
| Run CORS proxy (required for web) | `node src/web_proxy.js` (or `npm start`) |
| Run on desktop | `flutter run -d windows` / `-d macos` / `-d linux` |
| Run tests | `flutter test` |
| Lint | `flutter analyze` |
| Regenerate launcher icons | `dart run flutter_launcher_icons` |
| Release (bump pubspec, push main + tag `v*`) | `scripts/release.sh 0.2.0` |

**Web + Redmine**: start proxy in separate terminal before Chrome. Without it, all HTTP calls to Redmine blocked by CORS.

**Custom proxy URL**:
```bash
flutter run -d chrome --web-port 64451 --dart-define=REDMINE_PROXY_URL=http://localhost:4311
```

**Banco por ambiente**:
```bash
flutter run -d windows --dart-define=REDMINE_DB_ENV=dev
flutter run -d windows --release --dart-define=REDMINE_DB_ENV=prod
```
Sem `REDMINE_DB_ENV`, o app usa `prod` em `release` e `dev` em `debug/profile`.

---

## Architecture

```
lib/
  main.dart               — bootstrap: DB factory, AlertNotifier, window/tray (desktop only)
  state/app_state.dart    — single ChangeNotifier; holds all UI state
  services/
    database_service.dart      — SQLite singleton; tables: settings, queries, alerts, monitor_logs, teams,
                                 overtime
    redmine_api_service.dart   — HTTP to Redmine via one `_send` (proxy on web, direct elsewhere);
                                 getJson / putJson / getAllPages
    monitor_service.dart       — polling scheduler, picks the first matching AlertRule
    notifications/             — AlertNotifier (local_notifier) + NotificationTemplateService
  models/                 — pure data classes (AlertRule, AlertEvent, MonitoredQuery, Team, TimeEntry, …)
  ui/
    home_screen.dart      — root scaffold: collapsible sidebar (pages + pinned boards), each
                            opened as a closable tab (WorkspaceTabs on top: folder style, arrows
                            when they overflow); every tab has its own Navigator, so
                            showAppDialog (nearest navigator) covers only its tab and stays open
                            while another tab is in front
    board/                — board/list of a pinned query (columns in queries.board_statuses; mode,
                            filters and grouping/lanes in queries.board_prefs), issue detail dialog
                            (Markdown via flutter_markdown_plus) and "Enviar trâmite" dialog
    teams/                — teams (members from /projects/:id/memberships.json) + time report;
                            "Meu tempo" (logged-in user from /my/account.json) is the first option
    widgets/              — per-page content (alerts, queries + form, logs, settings,
                            handoff rules and custom fields panels)
    components.dart       — layout kit: PageHeader, Panel, FiltersPanel, StatCard, ListRow,
                            Tag, AppTabs, LineTabs, SegmentButtons, DateSelect, AppDialog…
                            (see DESIGN.md)
    ui_utils.dart         — fmtDateTime/fmtDate, searchKey, openRedmineLink, UserAvatar,
                            IssueNumber (#id that copies the bare number on click)

src/web_proxy.js          — Node CORS proxy; single endpoint POST /redmine-proxy/fetch
```

**State flow**: `MonitorService` polls Redmine → calls `onAlert` / `onQueryUpdate` callbacks → `AppState` reacts → `notifyListeners()` → UI rebuilds.

---

## Platform-specific SQLite init (critical)

`main.dart` must set `databaseFactory` before any DB call:
- **Web** → `databaseFactoryFfiWeb`
- **Windows / Linux** → `sqfliteFfiInit()` + `databaseFactoryFfi`
- **Android / iOS / macOS** → default sqflite (no override needed)

Do not remove or reorder init — app silently fails to open DB.

---

## Web data isolation

SQLite on web uses browser `IndexedDB`, scoped by `origin (host:port)`. Changing `--web-port` loses all saved data. Always use `--web-port 64451` for dev to keep data between runs.

---

## Proxy contract

Proxy accepts only `POST /redmine-proxy/fetch` with JSON body `{ url, apiKey, method?, body?, bodyBase64? }`. `method` is `GET` (default), `PUT` or `POST`; `body` is forwarded as JSON, `bodyBase64` as `application/octet-stream` bytes (uploads; request limit 50 MB). The response body is relayed as raw bytes (attachments). Forwards request to Redmine with `X-Redmine-API-Key` header. Any other path returns 404. Port defaults to `4311`; override with env `REDMINE_PROXY_PORT`.

## Schema changes

New columns/tables are added idempotently in `onOpen` (`_ensureColumn`, `CREATE TABLE IF NOT EXISTS`) and also in the `CREATE TABLE` for fresh databases. Legacy `queries.alert_on` + per-query templates are read once into `alert_rules` (JSON) by `MonitoredQuery.fromDbMap`.

---

## Notification rules and templates

Each query has a list of `AlertRule`s (`any`, `increase`, `decrease`, `eq`, `lte`, `gte`), evaluated only when the count changes; the first match fires. `lte`/`gte` fire only when crossing the threshold. Text is resolved by `NotificationTemplateService.resolve` (rule template → global increase/decrease → generic) and stored on the alert, so the OS notification and the in-app list always match.

Placeholders for title/message: `{queryName}`, `{previousCount}`, `{currentCount}`, `{diff}`, `{newCount}`, `{time}`, `{url}`.

---

## Handoff ("Enviar trâmite") rules

`logTime` toggles the hours section in both dialogs (`timeActivityId` is just its default
activity). A rule with `sameIssue` is a trâmite on the opened issue itself (`lib/ui/board/tramite_dialog.dart`):
status, assignee, a comment typed on the spot and hours.
Hours are prefilled from a base picked in "Contar desde" (`timeBases` in
`lib/ui/board/time_entry_fields.dart`: journals, the issue's own time entries and its creation),
preselecting the newest **status change or time entry** — a journal that only changes other fields
doesn't restart the count. The time is split by `settings.business_hours` (`BusinessHours.split`:
a list of `BusinessPeriod` — weekdays + start/end, so days can differ; overlaps count once —
edited in Configurações › Expediente with `TimeSelect`) into **Horas** and **Hora extra**; the gap
between two periods of a day (lunch) is a break and counts as neither. Redmine gets the
sum and the extra goes to the local `overtime` table (step `overtime`, after `time`). Tempo gasto ›
Horas extras shows it per month; each month is banco or cobrado (`settings.overtime_paid`), the
balance sums the banco months (`bankBalance`). **Lançar hora extra** there adds one by hand (day, issue ID,
hours, description; local only); Tarefa is a `SearchSelect` of the issues the user logged hours on
that month (`/time_entries.json?user_id=me`) with `typedId` (a typed number outside the list can be
picked). Overtime and both settings are in the backup. Both
dialogs share `TimeEntryFields` and the step runner in `lib/ui/board/send_steps.dart` (done steps never
re-run, so a retry can't duplicate a comment).

`settings.handoff_rules` (JSON list of `HandoffRule`) adds actions to the issue dialog: comment on
another issue mentioning notes of the current one, preloading the rule's status/assignee. Target
candidates come from `nearbyIssues` (breadth-first over parent, subtasks and relations, stopping at
the first level with the rule's target tracker), or a typed #id. Project lists/members use
`RedmineApiService.listProjects`/`listProjectMembers` (no admin key). Template placeholders: `{{tipoAtividadeComentario}}` (source
tracker, lowercase), `{{noteSelecionado}}` (`#id#note-N`, N = 1-based journal position),
`{{tarefa}}`, `{{titulo}}`. Optional closing steps per rule (code review): log hours
(`POST /time_entries.json`, `timeActivityId`) and `statusSteps` — free tracker → status pairs (e.g.
Desenvolvimento → Em teste, Negócio → Resolvida); the dialog lists the linked issues of each tracker,
pre-checking the opened issue, those with a picked note, or else the closest one (`defaultChecked`). The dialog runs them in order and never re-runs a
done step, so retrying can't duplicate the QA comment. Status changes go through
`RedmineApiService.setIssueStatus` (PUT + re-read, since Redmine answers 204 even when the workflow
drops the change). Notes can be picked from the issue, its subtasks and the siblings the
rule covers; with 2+ notes `multiTemplate` is used and each line with `{{noteSelecionado}}` repeats
per note (sorted by issue, then note). Rules and `settings.sidebar_width` are saved with
`AppState.savePreferences` (no monitor restart).

---

## "Ágil" board

Built-in board in the sidebar, no saved query: `settings.agile_board` (`AgileBoard`: project, mine,
open only, columns, `BoardPrefs`) becomes an in-memory `MonitoredQuery` with id `agileQueryId` (-1),
never monitored; `AppState.setBoardStatuses`/`setBoardPrefs` route that id to settings.
Ágil and the pinned boards are one list in the sidebar: hold and drag
(`ReorderableDelayedDragStartListener`) to reorder; `settings.board_order` keeps the ids
(`AppSettings.sortBoards`, unknown ones after in name order; not in the backup, ids change on import).

---

## Attachment preview

`lib/ui/board/attachment_preview.dart`: the Anexos tab and inline images in descriptions/notes are
shown in the app. Files come from `RedmineApiService.getBytes` (API key only for the configured
Redmine host, small in-memory cache). The viewer gets the issue's attachment list and moves with ← → (buttons or keys); `previewKind` picks image / text / markdown / PDF (`pdfrx`) /
video (`video_player`, played from a temp file made by `RedmineApiService.downloadToTemp`: AVPlayer
failed streaming from Redmine; macOS/iOS/Android only) / none (browser).
`pdfrx` needs Windows **Developer Mode** to build (symlinks).

---

## Editing an issue

The issue dialog (prototype layout: heading with project/title/tags, `LineTabs` with counts,
history as a timeline filtered by Tudo/Comentários/Alterações with old → new values by name, time as
`StatCard`s + table, attachments as list or thumbnails, side panel in sections) loads the field
choices once as `IssueOptions` (`lib/ui/board/issue_fields.dart`: statuses, priorities, the
project's trackers + categories via `include=trackers,issue_categories`, members, versions; a
failed list just falls back to `#id`). **Editar** turns every field into its typed editor (title,
project, tracker, status, priority, assignee, version, category, parent, dates with `DateSelect`,
estimate via `parseHours`, % done, custom fields via `customFieldEditor`) and the description (its
tab); values live in one `_edit` map by Redmine key (`due_date`, `cf_12`…) and **Salvar** sends one
update with only the keys that differ from `_original` (status via `setIssueStatus`). Another
project reloads the choices and clears version/category/assignee missing there; another tracker
shows the saved custom fields whose `trackerIds` include it. Notes and hours stay in "Novo
trâmite". "Novo trâmite" (Histórico tab) opens the trâmite dialog with an empty
`sameIssue` rule (`newTramiteRule`, hours optional: the field starts empty). "Lançar horas" (Tempo
gasto tab, `showLogTimeDialog`) posts one time entry with a day. Relações also lists the siblings
(other subtasks of the parent). Subtarefas and Relações render `LinkedIssueList` (one shared header; relation,
task, assignee, version, status columns sized to their widest content; stacked with short labels
when narrow); subtasks are re-read with the related issues, since `include=children` has no status. Both trâmite dialogs also pick a version (`listVersions`: open ones, shared
included; never stored in the rule, sprints change). **Alterar em massa** (button next to Editar,
`lib/ui/board/bulk_edit_dialog.dart`) sets status, assignee and/or version on the checked issues of
an `IssueTree` (`lib/ui/board/issue_tree.dart`: the issue, parent, related and the subtasks of all
of them, so siblings too; up to 3 levels, one `parent_id=a,b,c` request per level; checking an issue
checks its subtasks) through the step runner. A handoff rule with `bulk` shows the same tree in its
send dialog (around the opened issue, or around the target for sends to another issue): checked
issues get the same comment, status, assignee, version and attachments; hours stay on the main one.
`showIssueDetail(onChanged:)` lets the board reload after changes;
the board then writes its count to the sidebar (`AppState.syncQueryCount`, no alert).

Comments and the description use `NoteEditor` (`lib/ui/board/note_editor.dart`), like Redmine's
notes box: **Editar** / **Pré-visualizar** tabs (preview = `RedmineMarkdown`, the same renderer as
the issue dialog, `lib/ui/board/redmine_markdown.dart`; pending files show from memory), a
formatting bar (`wrapSelection`, `prefixLines`, `codeBlock`), "Anexar arquivos"
(`file_selector`) or paste (`pasteboard`: copied files, else text, else an image, which is also
inlined as `![](clipboard-….png)` like Redmine web). Files go up with `RedmineApiService.upload`
(`POST /uploads.json`) inside the send step, then as `uploads` in the issue update.

---

## Custom fields

The type and choices of each issue custom field live in `settings.custom_fields` (JSON list of
`CustomFieldDef`, same shape as Redmine's admin-only `/custom_fields.json`). Configurações ›
Campos (`lib/ui/widgets/custom_fields_panel.dart`) → **Buscar no Redmine**: with an admin key the
definitions replace the list; on 401/403 `scanCustomFields` reads the 300 most recent issues and
`CustomFieldDef.infer` guesses each new field (0/1 → bool, dates, numbers, few repeated values →
list of them), which the user reviews. A field with no saved type is edited as text (dates detected
by value). `customFieldText` shows values (Sim/Não, list labels, user/version names).

## Automation buttons

Each Claude Code action and each handoff rule is its own button in a wrapping strip above the
issue dialog's tabs, left column only (no grouping menu; the header keeps only Atualizar — reloads the
issue, time and board after changes made elsewhere —, Editar, Alterar em massa and Abrir no Redmine), with an icon picked in its editor (`lib/ui/icon_picker.dart`). The same actions
(plus open/edit, Alterar situação, Alterar em massa, Novo trâmite, Abrir no Redmine) are in the ⋮ menu
of board cards and list rows (`IssueActionsMenu` in `lib/ui/board/issue_actions.dart`, which also
holds `runClaudeAction`, `fetchFullIssue` and `confirmChanges`). Automations that change status,
assignee or version (Claude status, trâmite and handoff dialogs) list the changes in
`confirmChanges` first; dragging, the status menus and Editar → Salvar don't ask. Icons are saved by key
from the const `actionIcons` map, never as code points, so release builds keep icon tree-shaking.

Both kinds show only on issues matching their filters (`showsOn(tracker, status)`: Claude
`trackerIds`/`statusIds`, rule `sourceTrackerIds`/`statusIds`; empty = all; `appliesTo` stays
tracker-only for the handoff dialog's note sources). The order is one for both kinds:
`AppSettings.orderedActions` sorts by each one's `order` (set by dragging in Automações › Ordem dos
botões, `lib/ui/widgets/action_order_panel.dart`), the never ordered ones last (Claude first, list
order); `issueActions(settings, issue)` applies the filters for the dialog strip and the ⋮ menu.
Editing an action keeps its `order` (`withOrder`, a JSON round trip).

---

## Claude Code actions

`settings.claude_actions` (JSON list of `ClaudeAction`: name, absolute project folder, prompt
template with `{{numeroAtividade}}`/`{{titulo}}`, optional status on open) adds a "Claude Code"
button to the issue dialog.
The folder comes from the native picker (`file_selector`; macOS needs the
`com.apple.security.files.user-selected.read-only` entitlement). It opens the documented deep link `claude-cli://open?cwd=…&q=…` via `url_launcher` (works inside the
macOS sandbox): a terminal with Claude Code in that folder and the prompt typed, not sent.
`openInApp` (experimental) opens `claude://code/new?q=…` instead: the Claude Desktop new-session
page with the prompt typed. Not documented without SSH parameters; no local-folder parameter, and a
leading `/` arrives as plain text. The prompt is also copied; the terminal link is the fallback.

---

## Tests

One test file: `test/widget_test.dart` — templates/resolve, `AlertRule` semantics and legacy migration, URL param handling, time-entry aggregation, plus a widget test of the query form. In widget tests all HTTP returns 400, which the form uses to exercise its manual-URL fallback. Run with `flutter test`.

## Visual identity

Searchable choices use `SearchSelect` (`components.dart`): a 40px field that opens a list with its own
empty search box. Don't use Flutter's `DropdownMenu` with a typed filter (the chosen label stays in
the field and typing appends to it). Keep side-by-side controls at `controlHeight` (40px); single-line text inputs use `LineField` (padding alone doesn't make the border 40px). Text
selection uses `AppColors.selection` (solid, readable in dark mode). Markdown code styles must set
`backgroundColor: Colors.transparent` explicitly: flutter_markdown_plus merges them into its default,
whose per-glyph background paints over the selection (covered by a widget test).
Text selection is browser-like: one `SelectionArea` per column (header, tab content, attributes —
Flutter selects by geometry, so one area over side-by-side columns mixes them), with
`LineBreakSelection` inside the scroll view so copied blocks keep their line breaks; markdown uses
`selectable: false` (its own mode makes every block a separate selection). Colors come only from theme-aware tokens (`AppColors.accent(dark: dark)` …) in
`lib/services/theme_service.dart`; screens compose `lib/ui/components.dart`. Both
light and dark themes exist. Material texts are Portuguese (`flutter_localizations`,
locale pt_BR). Guide: [DESIGN.md](DESIGN.md).

## Formatting

Files are formatted with `dart format -l 100`, but not every file is — format only the files you change.

---

## Linting

`analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` — no custom rules. Run `flutter analyze` before committing.

---

## Desktop extras

On Windows/macOS/Linux, app initializes `window_manager` (min size 600×500) and `tray_manager` (system tray icon + context menu). No-ops on web/mobile — guarded by `_isDesktop` check in `main.dart`.
