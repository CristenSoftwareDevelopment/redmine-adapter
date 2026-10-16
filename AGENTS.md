# AGENTS.md

## What this repo is

Flutter app (`redmine_monitor_flutter`) monitors Redmine saved queries, fires in-app alerts on count change. Has tiny Node.js CORS proxy (`src/web_proxy.js`) for web builds.

---

## Setup — first time

Repo **not** bootstrapped with `flutter create`, platform scaffold files generated separately. Exist. Do not run `flutter create .` again — overwrites platform configs.

```bash
flutter pub get
```

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
    database_service.dart      — SQLite singleton; tables: settings, queries, alerts, monitor_logs, teams
    redmine_api_service.dart   — HTTP to Redmine via one `_send` (proxy on web, direct elsewhere);
                                 getJson / putJson / getAllPages
    monitor_service.dart       — polling scheduler, picks the first matching AlertRule
    notifications/             — AlertNotifier (local_notifier) + NotificationTemplateService
  models/                 — pure data classes (AlertRule, AlertEvent, MonitoredQuery, Team, TimeEntry, …)
  ui/
    home_screen.dart      — root scaffold: collapsible sidebar (pages + pinned boards)
    board/                — board/list of a pinned query (columns in queries.board_statuses; mode,
                            filters and grouping/lanes in queries.board_prefs), issue detail dialog
                            (Markdown via flutter_markdown_plus) and "Enviar trâmite" dialog
    teams/                — teams (members from /projects/:id/memberships.json) + time report;
                            "Meu tempo" (logged-in user from /my/account.json) is the first option
    widgets/              — per-page content (alerts, queries + form, logs, settings,
                            handoff rules panel)
    components.dart       — layout kit: PageHeader, Panel, FiltersPanel, StatCard, ListRow,
                            Tag, AppTabs, SegmentButtons, AppDialog… (see DESIGN.md)
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

Proxy accepts only `POST /redmine-proxy/fetch` with JSON body `{ url, apiKey, method?, body? }`. `method` is `GET` (default), `PUT` or `POST`; `body` is forwarded as JSON. The response body is relayed as raw bytes (attachments). Forwards request to Redmine with `X-Redmine-API-Key` header. Any other path returns 404. Port defaults to `4311`; override with env `REDMINE_PROXY_PORT`.

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
status, assignee, a comment typed on the spot and hours (prefilled since the last update). Both
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

---

## Attachment preview

`lib/ui/board/attachment_preview.dart`: the Anexos tab and inline images in descriptions/notes are
shown in the app. Files come from `RedmineApiService.getBytes` (API key only for the configured
Redmine host, small in-memory cache). The viewer gets the issue's attachment list and moves with ← → (buttons or keys); `previewKind` picks image / text / markdown / PDF (`pdfrx`) /
video (`video_player`, streamed with the key header; macOS/iOS/Android only) / none (browser).
`pdfrx` needs Windows **Developer Mode** to build (symlinks).

---

## Automation buttons

Each Claude Code action and each handoff rule is its own button in the issue dialog header (no
grouping menu), with an icon picked in its editor (`lib/ui/icon_picker.dart`). Icons are saved by key
from the const `actionIcons` map, never as code points, so release builds keep icon tree-shaking.

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
the field and typing appends to it). Keep side-by-side controls at `controlHeight` (40px). Text
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
