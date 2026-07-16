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
    database_service.dart      — SQLite singleton; tables: settings, queries, alerts, logs
    redmine_api_service.dart   — HTTP to Redmine (via proxy on web, direct on desktop/mobile)
    monitor_service.dart       — polling scheduler + delta detection
    notifications/             — AlertNotifier (local_notifier) + NotificationTemplateService
  models/                 — pure data classes (AlertEvent, AppSettings, MonitoredQuery, …)
  ui/
    home_screen.dart      — root scaffold with bottom nav
    widgets/              — per-tab widgets

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

Proxy accepts only `POST /redmine-proxy/fetch` with JSON body `{ url, apiKey }`. Forwards request to Redmine with `X-Redmine-API-Key` header. Any other path returns 404. Port defaults to `4311`; override with env `REDMINE_PROXY_PORT`.

---

## Notification templates

Placeholders for title/message: `{queryName}`, `{previousCount}`, `{currentCount}`, `{diff}`, `{time}`, `{url}`. Rendering logic in `NotificationTemplateService` — only unit-tested class.

---

## Tests

One test file: `test/widget_test.dart` — tests `NotificationTemplateService.render()`. No widget tests, no integration tests. Run with `flutter test`.

---

## Linting

`analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` — no custom rules. Run `flutter analyze` before committing.

---

## Desktop extras

On Windows/macOS/Linux, app initializes `window_manager` (min size 600×500) and `tray_manager` (system tray icon + context menu). No-ops on web/mobile — guarded by `_isDesktop` check in `main.dart`.
