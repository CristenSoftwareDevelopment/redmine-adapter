# Redmine Monitor — guia visual

Identidade aprovada a partir do protótipo HTML (outubro/2026): superfícies em
azul-ardósia, destaque verde-água, painéis com borda fina e sem sombra.
Tokens em `lib/services/theme_service.dart`; componentes em `lib/ui/components.dart`.

## Cores (sempre via `AppColors.<token>(dark: dark)`)

| Token | Escuro | Claro | Uso |
|---|---|---|---|
| `page` / `sidebar` | `#101419` / `#141920` | `#F3F5F8` / `#F8FAFC` | fundo da página e do menu |
| `panel` / `field` | `#191F27` / `#202833` | `#FFFFFF` / `#FFFFFF` | painéis, cards; campos e botões |
| `sunken` / `well` / `footer` | `#161C23` / `#11171E` / `#202A32` | `#EEF1F5` / `#E9EDF2` / `#EEF1F5` | cabeçalho de tabela; trilho de abas e código; linha de totais |
| `border` / `borderStrong` | `#2B3440` / `#526477` | `#DFE4EA` / `#B8C2CE` | divisórias; hover de borda |
| `text` / `mutedText` | `#EDF2F7` / `#96A3B3` | `#111820` / `#5B6878` | texto principal; secundário |
| `accent` / `onAccent` | `#46D4BD` / `#092B26` | `#0B7A6A` / `#FFFFFF` | ação primária, links, selecionado |
| `accentSoft` / `chip` / `tabActive` | `#213630` / `#223B35` / `#2D403B` | `#E3F4F0` / `#DDF1EC` / `#D5EDE7` | item de menu ativo; chips de filtro; aba ativa |
| `danger` | `#FFAAA6` | `#B4232C` | ações destrutivas, erros |

O destaque claro é mais escuro de propósito: `#46D4BD` não tem contraste em fundo branco.

**Tags suaves** (`Tag`, `AppColors.tone`): neutra, verde, âmbar, vermelha, roxa, azul e
destaque. Status, níveis de log e diferenças ± usam tons fixos por significado.
Tipos de tarefa e status do Redmine usam `Tag.hashed(nome)`: o tom sai do nome,
então nada fica preso aos valores de um ambiente específico.

## Tipografia (`AppText`)

Corpo 14 · títulos de painel 17/700 · título de página 28/700 (−0.7) · KPI 29/700 ·
rótulos 12 · subtítulos 13 · rótulos de seção do menu 10/600 com espaçamento 1.5.

## Forma e espaço

- Controles (campos, botões, selects): raio 8, altura 40.
- Painéis: raio 12, borda de 1px, sem sombra, 20px entre painéis.
- Diálogos: raio 14, borda `dialogBorder`, cabeçalho e rodapé fixos, fundo desfocado; abrem
  dentro da aba (cobrem só ela) com 85% da sua largura (confirmações sim/não: 460).
- Abas do workspace: `WorkspaceTabs`, estilo pasta no topo da área principal — trilho `well`,
  inativas `sunken` com borda, ativa na cor da página (sem linha embaixo, emenda no conteúdo) com
  faixa `accent` de 3px no topo; × ou clique do meio fecha; setas ‹ › (e a roda do mouse) quando
  não cabem, e a aba ativa sempre rola para a vista.
- Página: padding 28/34 (24 abaixo de 1100px), sem largura máxima.
- Menu lateral: 240px, recolhe para 75px (só ícones) abaixo de 1100px.

## Componentes

`PageHeader` (título + subtítulo + ações) · `Panel` + `PanelHead` · `FiltersPanel`
(controles, ações à direita, linha "Mais filtros", resumo com chips e "Limpar filtros") ·
`SearchField` · `SelectBox` · `StatCard` em `StatGrid` (4 colunas, 2 abaixo de 700px) ·
`ListRow` com `IconBox` e ações `IconBtn` · `Tag` · `AppTabs` (alternâncias como
Board/Lista) · `LineTabs` (abas sublinhadas com contador, seções do diálogo da tarefa) ·
`WorkspaceTabs` (abas do workspace) ·
`SegmentButtons` (escolha única com destaque, como períodos) · `DateSelect` (data com calendário) ·
`EmptyState` · `SectionTitle` · `Notice` · `AppDialog` com `showAppDialog`.

## Regras

- Uma ação primária por tela (botão preenchido); o resto é contornado, ícone ou link.
- Destaque só para ação, seleção e valores-chave (totais), nunca como decoração.
- Cores sempre por token: valores hex ficam apenas no `theme_service`.
