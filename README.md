# Redmine Monitor (Flutter)

Aplicativo Flutter para monitorar consultas salvas do Redmine e disparar alertas quando a contagem muda.

Plataformas alvo principais: **Windows e macOS**.
Web e mobile sao suportes secundarios.

## O que o app faz

- Configura URL do Redmine, API key e intervalo padrao.
- Monitora consultas com polling e detecta delta de contagem.
- Exibe alertas in-app e notificacoes locais.
- Persiste dados em SQLite (`settings`, `queries`, `alerts`, `logs`).
- Permite backup/restauracao de configuracao e consultas.
- Suporta tema claro, escuro e sistema.

## Importante antes de tudo

Este repositorio **nao** deve executar `flutter create .`.
Os arquivos de plataforma ja existem e esse comando pode sobrescrever configuracoes.

## Requisitos

- Flutter SDK instalado
- Node.js (somente para Web, por causa do proxy CORS)

## Setup

```bash
flutter pub get
```

## Uso principal (desktop)

### Rodar no Windows

```bash
flutter run -d windows
```

### Rodar no macOS

```bash
flutter run -d macos
```

## Desenvolvimento

| Objetivo | Comando |
|---|---|
| Rodar no Windows | `flutter run -d windows` |
| Rodar no macOS | `flutter run -d macos` |
| Rodar no Chrome (porta fixa) | `flutter run -d chrome --web-port 64451` |
| Rodar proxy CORS (Web) | `node src/web_proxy.js` ou `npm start` |
| Rodar no Linux | `flutter run -d linux` |
| Testes | `flutter test` |
| Lint | `flutter analyze` |

### Web + Redmine (obrigatorio)

No Web, rode o proxy em um terminal separado antes do app:

```bash
node src/web_proxy.js
```

Sem o proxy, o navegador bloqueia as chamadas ao Redmine por CORS.

Para usar URL customizada do proxy:

```bash
flutter run -d chrome --web-port 64451 --dart-define=REDMINE_PROXY_URL=http://localhost:4311
```

## Build

### Windows

```bash
flutter build windows --release
```

### macOS

```bash
flutter build macos --release
```

### Web

```bash
flutter build web --release --dart-define=REDMINE_PROXY_URL=http://localhost:4311
```

### Linux

```bash
flutter build linux --release
```

### Android

```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS

```bash
flutter build ios --release
```

## Estrutura principal

- `lib/main.dart`: bootstrap do app, init de banco e recursos desktop.
- `lib/state/app_state.dart`: estado global com `ChangeNotifier`.
- `lib/services/database_service.dart`: SQLite singleton e schema.
- `lib/services/redmine_api_service.dart`: chamadas HTTP ao Redmine.
- `lib/services/monitor_service.dart`: scheduler de polling + deteccao de delta.
- `lib/services/notifications/notification_template_service.dart`: render de templates.
- `src/web_proxy.js`: proxy CORS para o Web (`POST /redmine-proxy/fetch`).

## Templates de notificacao

Placeholders suportados em titulo e mensagem:

- `{queryName}`
- `{previousCount}`
- `{currentCount}`
- `{diff}`
- `{time}`
- `{url}`

## Observacoes

- O monitoramento acontece enquanto o app esta aberto.
- No Web, dados ficam no `IndexedDB` e sao separados por origem (`host:porta`).
- Para manter os dados no desenvolvimento Web, use sempre `--web-port 64451`.
