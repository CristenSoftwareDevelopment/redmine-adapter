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
    board/                — board/list of a pinned query, issue detail dialog
    teams/                — teams + time report (admin only)
    widgets/              — per-page cards and the query form
    ui_utils.dart         — fmtDateTime/fmtDate, openRedmineLink, LabelPill, UserAvatar

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

Proxy accepts only `POST /redmine-proxy/fetch` with JSON body `{ url, apiKey, method?, body? }`. `method` is `GET` (default) or `PUT`; `body` is forwarded as JSON. Forwards request to Redmine with `X-Redmine-API-Key` header. Any other path returns 404. Port defaults to `4311`; override with env `REDMINE_PROXY_PORT`.

## Schema changes

New columns/tables are added idempotently in `onOpen` (`_ensureColumn`, `CREATE TABLE IF NOT EXISTS`) and also in the `CREATE TABLE` for fresh databases. Legacy `queries.alert_on` + per-query templates are read once into `alert_rules` (JSON) by `MonitoredQuery.fromDbMap`.

---

## Notification rules and templates

Each query has a list of `AlertRule`s (`any`, `increase`, `decrease`, `eq`, `lte`, `gte`), evaluated only when the count changes; the first match fires. `lte`/`gte` fire only when crossing the threshold. Text is resolved by `NotificationTemplateService.resolve` (rule template → global increase/decrease → generic) and stored on the alert, so the OS notification and the in-app list always match.

Placeholders for title/message: `{queryName}`, `{previousCount}`, `{currentCount}`, `{diff}`, `{newCount}`, `{time}`, `{url}`.

---

## Tests

One test file: `test/widget_test.dart` — templates/resolve, `AlertRule` semantics and legacy migration, URL param handling, time-entry aggregation, plus a widget test of the query form. In widget tests all HTTP returns 400, which the form uses to exercise its manual-URL fallback. Run with `flutter test`.

## Formatting

Files are formatted with `dart format -l 100`, but not every file is — format only the files you change.

---

## Linting

`analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` — no custom rules. Run `flutter analyze` before committing.

---

## Desktop extras

On Windows/macOS/Linux, app initializes `window_manager` (min size 600×500) and `tray_manager` (system tray icon + context menu). No-ops on web/mobile — guarded by `_isDesktop` check in `main.dart`.
