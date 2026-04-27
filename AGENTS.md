# AGENTS.md

## What this repo is

Flutter app (`redmine_monitor_flutter`) that monitors Redmine saved queries and fires in-app alerts when counts change. Also contains a tiny Node.js CORS proxy (`src/web_proxy.js`) required for web builds.

---

## Setup — first time

This repo was **not** bootstrapped with `flutter create`, so platform scaffold files were generated separately. They exist already. Do not run `flutter create .` again — it would overwrite platform configs.

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

**Web + Redmine**: always start the proxy in a separate terminal before running in Chrome. Without it, all HTTP calls to Redmine are blocked by CORS.

**Custom proxy URL**:
```bash
flutter run -d chrome --web-port 64451 --dart-define=REDMINE_PROXY_URL=http://localhost:4311
```

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

Do not remove or reorder this initialization — the app silently fails to open the DB otherwise.

---

## Web data isolation

SQLite on web uses browser `IndexedDB`, scoped by `origin (host:port)`. Changing `--web-port` loses all saved data. Always use `--web-port 64451` for dev to keep data between runs.

---

## Proxy contract

The proxy accepts only `POST /redmine-proxy/fetch` with JSON body `{ url, apiKey }`. It forwards the request to Redmine with the `X-Redmine-API-Key` header. Any other path returns 404. Port defaults to `4311`; override with env `REDMINE_PROXY_PORT`.

---

## Notification templates

Placeholders for title/message: `{queryName}`, `{previousCount}`, `{currentCount}`, `{diff}`, `{time}`, `{url}`. Rendering logic is in `NotificationTemplateService` — the only unit-tested class.

---

## Tests

One test file: `test/widget_test.dart` — tests `NotificationTemplateService.render()`. No widget tests, no integration tests. Run with `flutter test`.

---

## Linting

`analysis_options.yaml` includes only `package:flutter_lints/flutter.yaml` — no custom rules. Run `flutter analyze` before committing.

---

## Desktop extras

On Windows/macOS/Linux, the app initializes `window_manager` (minimum size 600×500) and `tray_manager` (system tray icon + context menu). These are no-ops on web/mobile — guarded by `_isDesktop` check in `main.dart`.
