# Índice das specs — `ita-next`

> **Mapa fase ↔ spec do front-end.** Número de spec é **ordem de criação**, não de fase (ADR-README).
> Duas colunas de estado deliberadamente separadas: **`status`** é o rótulo do fluxo SDD no cabeçalho da
> spec (`draft` → `clarified`); **`impl`** é o estado REAL de implementação (código + `tasks.md` + goldens
> + `make test`). Quando as duas divergem, é dívida de *bookkeeping* — não de código.
>
> *Índice criado na auditoria de 2026-07-17 (fecha o débito de visibilidade: a numeração pulava 012 sem
> mapa que explicasse). Estado medido: `make test` 790 verde, `analyze` limpo.*

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
| **F5**→M5 | **012** *(reservada)* | **Membros de built-in** (`.length`, `xs[i]`, `.map`) | — | 🔒 **RESERVADA** — ver nota abaixo |
| **F6** Flow | [014](014-flow-check/) | Flow-check (fluxo + exaustividade `match`) | `clarified` | 🟡 **parcial** — flow-walk ✅, exaustividade pendente³ |
| **F7** Codegen | [013](013-codegen-kernel/) | Codegen → Dart Kernel (`.dill`) | `clarified` | 🔵 **não iniciada** — `codegen/` vazio; gates em §0.6⁴ |

## Specs transversais / cross-target

| Spec | Título | `status` | `impl` |
|:-:|:--|:--|:--|
| [001](001-int-bitwise-semantics/) | Semântica de largura de `Int` + bitwise cross-target | `clarified` | 🔵 planejada (0/18) — ligada ao alvo JS/M4 |
| [002](002-rewrite-compiler-dragon-book/) | **ÉPICO** — reescrita do compilador (guarda-chuva) | `clarified` | — épico, sem tasks próprias |

---

### 🔒 Nota sobre a spec 012 (reservada, não pulada)

A numeração salta de **011 → 013 de propósito.** O nº **012 está RESERVADO** para **membros de built-in**
(`.length`, indexação `xs[i]`, `+`/`.map`/`.slice` de `List`, `Map.keys()`) — uma **reserva normativa do
dono**, registrada em:

- [`spec 013 §Numeração`](013-codegen-kernel/spec.md) — *"esta spec é a 013 porque a 012 está RESERVADA
  pela spec 011 §1.3 … Número de spec é ordem de criação, não de fase."*
- [`spec 011 §1.3`](011-member-resolution/spec.md) — o **corte do `compiler-craftsman`**: os membros de
  **tipo do usuário** (011) e os de **built-in** (012) são **produtores independentes** da tabela de tipos;
  a F5 hoje recusa built-in com `builtin-member-unsupported` (§4.7). Destino: **M5** (des-Dartificação →
  built-ins migram para `.tu`).

Não há arquivo `specs/012-*/` — a reserva é intencional e destrava no M5.

---

¹ **007** tem 1 divergência declarada: `guard let` foi **retido como nó core** (RD-1), não desaçucarado
como a T004 previa. Pendente de ruling do dono — ver [`007/tasks.md` T004](007-desugaring/tasks.md).
² **008** tem 1 débito de contrato aberto: `resolution` trafega por parâmetro solto até a F7 — roteado em
[`013/tasks.md` AF4](013-codegen-kernel/tasks.md).
³ **014**: a exaustividade de `match` (Maranget) é o **gate DURO da F7** e ainda não existe no código —
pipeline em [`014/tasks.md`](014-flow-check/tasks.md), achado 🔴1 da auditoria.
⁴ **013**: gates de §0.6 pendentes (spec da F6 + pin do SDK). Pipeline em
[`013/tasks.md`](013-codegen-kernel/tasks.md), achados 🔴2 / 🟠3 / 🟡4 / 🟠5 da auditoria.
