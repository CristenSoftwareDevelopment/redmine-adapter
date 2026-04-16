# Redmine Monitor em Flutter

Aplicativo Flutter com monitoramento de consultas do Redmine, persistencia em SQLite e alerta dentro do app com som.

## Recursos implementados

- Configuracao de URL do Redmine, API key e intervalo padrao
- Cadastro de consultas monitoradas (URL da consulta, `countPath`, intervalo e status ativa/pausada)
- Acoes rapidas por consulta: executar agora, pausar/ativar, duplicar, editar e excluir
- Persistencia local em SQLite (`settings`, `queries`, `alerts`)
- Monitoramento por polling dentro do app
- Alerta in-app (SnackBar + som do sistema) com cooldown configuravel
- Tema com suporte a `Claro`, `Escuro` e `Sistema`
- Lista de alertas com botao para abrir link direto da atividade
- Logs com busca e filtros por severidade
- Backup/restauracao de configuracao+consultas em JSON

## Estrutura principal

- `lib/services/database_service.dart`: schema SQLite + CRUD
- `lib/services/redmine_api_service.dart`: chamadas HTTP para Redmine
- `lib/services/monitor_service.dart`: scheduler e deteccao de delta
- `lib/state/app_state.dart`: estado global com `ChangeNotifier`
- `lib/ui/*`: telas de configuracao, consultas e alertas

## Como rodar

Como este repositorio nao foi inicializado com `flutter create`, primeiro gere os arquivos de plataforma:

```bash
flutter create .
```

Depois:

```bash
flutter pub get
flutter run
```

Para Web (Chrome), use porta fixa para manter dados salvos entre execucoes:

```bash
flutter run -d chrome --web-port 64451
```

Para monitorar Redmine no Web sem erro de CORS, rode tambem o proxy local em outro terminal:

```bash
npm run start:proxy
```

Opcional: para apontar para outra URL de proxy:

```bash
flutter run -d chrome --web-port 64451 --dart-define=REDMINE_PROXY_URL=http://localhost:4311
```

## Uso

1. Abra o app e preencha URL + API key + intervalo padrao.
2. Cadastre a consulta colando a URL da pagina da consulta salva no Redmine (o app gera o endpoint JSON).
3. O app inicia monitoracao automaticamente ao abrir.
4. Acompanhe execucoes na aba `Logs`.
5. Quando a contagem mudar, o app toca som, registra alerta e envia notificacao do sistema.
6. Em `Configuracao > Notificacoes`, personalize titulo/mensagem e use `Testar notificacao`.
7. Em `Configuracao`, use `Copiar backup` e `Restaurar backup` para migrar dados.
8. Em `Configuracao > Notificacoes`, escolha o tema do app (`Claro`, `Escuro` ou `Sistema`).

## Formato esperado da consulta

Exemplo:

- URL da consulta: `https://seu-redmine.com/projects/x/issues?query_id=12`
- O app converte para endpoint de API `.json` automaticamente
- Count Path padrao: `total_count`

## Templates de notificacao

Placeholders disponiveis para titulo e mensagem:

- `{queryName}`
- `{previousCount}`
- `{currentCount}`
- `{diff}`
- `{time}`
- `{url}`

## Menus principais

- `Monitoracao`: status geral, saude das consultas e alertas recentes
- `Consultas`: cadastro e acoes rapidas por consulta
- `Configuracao`: conexao, notificacoes, cooldown e backup
- `Logs`: trilha de execucao com busca e filtros

## Observacoes

- O monitoramento atual roda enquanto o app esta aberto.
- No Web, o SQLite fica no `IndexedDB` do navegador e e separado por origem (`host:porta`). Se a porta mudar, os dados anteriores nao aparecem.
- No Web, o app usa proxy local (`http://localhost:4311`) para evitar bloqueio de CORS do navegador ao chamar o Redmine.
- No Chrome, a notificacao de sistema depende de permissao do navegador (Allow notifications).
- Para monitoramento em background real (app fechado), o proximo passo e integrar servico de background por plataforma.
