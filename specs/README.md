# Índice das specs — `ita-next`

> **Mapa fase ↔ spec do front-end.** Número de spec é **ordem de criação**, não de fase (ADR-README).
> Duas colunas de estado deliberadamente separadas: **`status`** é o rótulo do fluxo SDD no cabeçalho da
> spec (`draft` → `clarified`); **`impl`** é o estado REAL de implementação (código + `tasks.md` + goldens
> + `make test`). Quando as duas divergem, é dívida de *bookkeeping* — não de código.
>
> *Índice criado na auditoria de 2026-07-17 (fecha o débito de visibilidade: a numeração pulava 012 sem
> mapa que explicasse). Estado medido: `make test` 790 verde, `analyze` limpo.*
>
> *Atualização de 2026-07-22 (bookkeeping de índice): as linhas **012**, **014** e **013** avançaram desde a
> auditoria — a 012 (o chão dos built-ins) e a F6 (014, exaustividade) **fecharam**, e a F7 (013) entrou em
> execução com os gates §0.6 **caídos**. O número `790` acima é da auditoria; o `make test` mais recente
> registrado é **862 verde** (spec 012 LT-012a, commit `da85bc1`) — a 014 Fatia 3 media 849 em 2026-07-19.
> Esta atualização mexe só no índice — não re-rodou a suíte nem os checkboxes internos dos `tasks.md`.*

## Grupo A — o que o Itá implementa (Dragon Book caps 2–6)

| Fase | Spec | Título | `status` | `impl` |
|:-:|:-:|:--|:--|:--|
| **F1** Léxico | [003](003-lexer-scaffold/) | Léxico completo + scaffold | `clarified` | ✅ implementada (30/30) |
| **F2** Sintaxe→AST | [004](004-parser-ast/) | Sintaxe completa → AST | `draft` | ✅ implementada (60/60) |
| **F2** Sintaxe→AST | [005](005-decl-surface/) | Superfície declarativa | `draft` | ✅ implementada (2026-07-17) |
| **F3** Desugar | [006](006-where-typed-ops/) | `where`-expr + operadores tipados (prep) | `draft` | ✅ implementada (2026-07-17) |
| **F3** Desugar | [007](007-desugaring/) | Desugaring / lowering | `draft` | ✅ implementada¹ (2026-07-17) |
| **F4** Binding | [008](008-binding/) | Binding / resolução de nomes | `draft` | ✅ implementada² (2026-07-17) |
| **F5** Semântica | [009](009-semantic-types/) | Semântica / Tipos | `clarified` | ✅ implementada (rulings/§12) |
| **F5** Semântica | [010](010-contextual-typing/) | Tipagem contextual | `clarified` | ✅ implementada (rulings/§12) |
| **F5** Semântica | [011](011-member-resolution/) | Resolução de membro | `clarified` | ✅ implementada (rulings/§12) |
| **F5**→M5 | [012](012-builtin-members/) | **Membros de built-in** — o chão (`.length`, `xs[i]`, `+`) | `clarified` | 🟡 **chão da F5 ✅** (LT-012a mergeada, PR #2 `da85bc1`); codegen (LT-012b) pendente⁵ |
| **F6** Flow | [014](014-flow-check/) | Flow-check (fluxo + exaustividade `match`) | `clarified` | ✅ **implementada** — flow-walk + exaustividade Maranget (Fatias 1-3); resíduo menor³ |
| **F7** Codegen | [013](013-codegen-kernel/) | Codegen → Dart Kernel (`.dill`) | `clarified` | 🟡 **em execução** — gates §0.6 caídos (F6 ✅ · SDK pinado ✅ `72d31da`); design LT-F7a assentado; emissão não escrita (`codegen/` só `.gitkeep`)⁴ |

## Specs transversais / cross-target

| Spec | Título | `status` | `impl` |
|:-:|:--|:--|:--|
| [001](001-int-bitwise-semantics/) | Semântica de largura de `Int` + bitwise cross-target | `clarified` | 🔵 planejada (0/18) — ligada ao alvo JS/M4 |
| [002](002-rewrite-compiler-dragon-book/) | **ÉPICO** — reescrita do compilador (guarda-chuva) | `clarified` | — épico, sem tasks próprias |

---

### 📂 Nota sobre a spec 012 (reserva destravada — o chão saiu em 2026-07-20)

A numeração salta de **011 → 013** por ordem de criação (a 013 nasceu antes da 012). O nº **012 era uma
reserva normativa do dono** para **membros de built-in** (`.length`, indexação `xs[i]`, `+`/`.map`/`.slice`
de `List`, `Map.keys()`), registrada em:

- [`spec 013 §Numeração`](013-codegen-kernel/spec.md) — *"esta spec é a 013 porque a 012 está RESERVADA
  pela spec 011 §1.3 … Número de spec é ordem de criação, não de fase."*
- [`spec 011 §1.3`](011-member-resolution/spec.md) — o **corte do `compiler-craftsman`**: os membros de
  **tipo do usuário** (011) e os de **built-in** (012) são **produtores independentes** da tabela de tipos;
  a F5 recusava built-in com `builtin-member-unsupported` (§4.7).

**Destravada em 2026-07-20:** a pasta [`specs/012-builtin-members/`](012-builtin-members/) já existe e o
**CHÃO** (`.length`/`[]`/`+`) foi recortado do resto (`.map`/`.slice`/`Map.keys()`, que seguem p/ **M5** na
des-Dartificação → built-ins migram para `.tu`):

- **LT-012a — F5 (o chão TIPADO):** ✅ **implementada e mergeada** (PR #2, `da85bc1`; W3 🟢). A F5 deixa de
  recusar `.length`/`[]`/`+` de built-in e passa a tipá-los.
- **LT-012b — F7 (codegen do chão):** 🔴 **pendente** — dependia do Gate 2 (pin do SDK, **já caído** em
  `72d31da`) e agora do esqueleto de emissão da F7 (LT-F7a, spec 013). Co-verifica a 013 (CA8: `match` de List
  passa a emitir `.dill`).

⚠️ **Bookkeeping interno:** os checkboxes de [`012/tasks.md`](012-builtin-members/tasks.md) (T001–T030) ainda
não foram marcados apesar do merge da LT-012a — dívida a fechar (revalidar via `make test`/MCP `ita` antes de
marcar, Art. IV-1: nunca assumir a saída).

---

¹ **007** tem 1 divergência declarada: `guard let` foi **retido como nó core** (RD-1), não desaçucarado
como a T004 previa. Pendente de ruling do dono — ver [`007/tasks.md` T004](007-desugaring/tasks.md).
² **008** tem 1 débito de contrato aberto: `resolution` trafega por parâmetro solto até a F7 — roteado em
[`013/tasks.md` AF4](013-codegen-kernel/tasks.md).
³ **014**: a exaustividade de `match` (Maranget U/S/D + testemunha) — o **gate DURO da F7** — **foi
implementada** (LT-F6a co-requisito na F5 ✅ 2026-07-17; LT-F6b Fatias 1-3 ✅ de `71961ab` a `f911beb`, último
medido **849 verde** em 2026-07-19). Resíduo menor aberto: redundância-de-`List` (3b-ii) + rulings menores —
ver [`014/tasks.md`](014-flow-check/tasks.md). O achado 🔴1 da auditoria está **resolvido**.
⁴ **013**: os gates de §0.6 **caíram** — F6 implementada (spec 014, nota ³) e SDK pinado+vendorado (`72d31da`,
2026-07-20: Dart 3.12.2 + `vm_platform.dill` fmt 130 + `pkg/kernel`+`_fe_analyzer_shared` em `third_party/`).
Falta a **emissão em si** (`compiler/lib/codegen/` só tem `.gitkeep`): a LT-F7a (passes de saneamento
+ driver `build`/`run` via `CommandRunner`) está destravada p/ W3·implement. Achados 🔴2 / 🟠3 / 🟡4 / 🟠5 da
auditoria: os de gate resolvidos, a implementação pendente. Pipeline em
[`013/tasks.md`](013-codegen-kernel/tasks.md).
⁵ **012**: o chão da F5 (LT-012a) está mergeado (PR #2, `da85bc1`); o codegen (LT-012b) é gated no esqueleto
da F7 (013) — ver a nota da spec 012 acima. Débito de bookkeeping: `012/tasks.md` ainda com checkboxes vazios.
