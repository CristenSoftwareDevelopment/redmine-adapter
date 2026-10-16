# Redmine Monitor (Flutter)

Aplicativo Flutter para monitorar consultas salvas do Redmine e disparar alertas quando a contagem muda.

Plataformas alvo principais: **Windows e macOS**.
Web e mobile sao suportes secundarios.

## O que o app faz

- Configura URL do Redmine e API key.
- Escolhe a consulta salva do Redmine numa lista com busca (ou cola uma URL manual).
- Monitora consultas com polling e varias regras de notificacao por consulta
  (qualquer mudanca, aumentou, diminuiu, `= N`, `<= N`, `>= N`), cada uma com sua mensagem.
- Exibe alertas in-app e notificacoes locais com o mesmo texto.
- Marca com badge "Falhou" a consulta cuja ultima verificacao deu erro.
- Fixa consultas no menu como board (estilo Jira) ou lista; arrastar o card muda o status
  no Redmine. As colunas (status) visiveis sao escolhidas por board e ficam salvas.
- Abre a tarefa num modal com a descricao e o historico renderizados em Markdown.
- Tempo gasto (times): os membros vem dos projetos do Redmine (nao precisa ser admin); horas por
  pessoa e dia, detalhadas por tarefa ou por tipo de atividade. So aparecem as horas que o seu
  papel pode ver (permissao "Ver tempo gasto").
- Persiste dados em SQLite (`settings`, `queries`, `alerts`, `monitor_logs`, `teams`).
- Permite backup/restauracao de configuracao, consultas e times.
- Suporta tema claro, escuro e sistema.

## Importante antes de tudo

Este repositorio **nao** deve executar `flutter create .`.
Os arquivos de plataforma ja existem e esse comando pode sobrescrever configuracoes.

## Instalar no macOS

Instala ou atualiza a partir da ultima release, sem o macOS pedir autorizacao a cada versao:

```bash
curl -fsSL https://raw.githubusercontent.com/CristenSoftwareDevelopment/redmine-adapter/main/scripts/install-macos.sh | bash
```

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
create-dmg \
  --volname "Redmine Monitor" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Redmine Monitor.app" 200 190 \
  --hide-extension "Redmine Monitor.app" \
  --app-drop-link 600 185 \
  "Redmine Monitor.dmg" \
  "build/macos/Build/Products/Release/Redmine Monitor.app"
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
- `lib/services/notifications/notification_template_service.dart`: escolha e render de templates.
- `lib/ui/board/`: board/lista das consultas fixadas e modal da tarefa.
- `lib/ui/teams/`: times e relatorio de horas.
- `src/web_proxy.js`: proxy CORS para o Web (`POST /redmine-proxy/fetch`, GET e PUT).

## Templates de notificacao

Placeholders suportados em titulo e mensagem:

- `{queryName}`
- `{previousCount}`
- `{currentCount}`
- `{diff}`
- `{newCount}`
- `{time}`
- `{url}`

Ordem de escolha: mensagem da regra -> template global de aumento/diminuicao -> template generico.
O texto renderizado fica gravado no alerta.

## Observacoes

- O monitoramento acontece enquanto o app esta aberto.
- Textos do Redmine sao renderizados como Markdown (`flutter_markdown_plus`). Instancias
  configuradas com Textile aparecem quase como texto puro.
- No Web, dados ficam no `IndexedDB` e sao separados por origem (`host:porta`).
- Para manter os dados no desenvolvimento Web, use sempre `--web-port 64451`.
