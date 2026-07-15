# Design notes — Épico 002 (reescrita) · foco na Fase 0

> ⚠️ OBSOLETO (ADR-0011, 2026-07-10): este design-notes era da "Fase 0 mini-tradutor", DESCARTADA. A abordagem virou horizontal (7 fases); o scaffold entra na Fase 1 (ver specs/003-lexer-scaffold/). Mantido como histórico.

> Phase 0 do `/speckit-plan`. Fixa as decisões de design da **Fase 0** (scaffold + mini-tradutor) para o
> `/speckit-specify` da Fase 0 herdar sem re-litigar. Decisões maiores de linguagem já vivem nos ADRs.

## Decisão D0.1 — Subconjunto exato do mini-tradutor (Cap 2)

- **Decision:** a Fase 0 implementa **apenas** expressões aritméticas + `print`:
  - **Literais:** `Int` (decimal) e `Float`. **Operadores:** `+ - * /` (binários) e `-` unário. **Grupos:** `( )`.
  - **Precedência:** `* /` > `+ -`; `-` unário no topo (espelha a escada do `GRAMMAR.md`, mas mínima).
  - **Saída:** `print(expr)` — um `main` que avalia e imprime.
- **Rationale:** o Cap 2 do Dragon Book usa o "tradutor simples" para provar o **pipeline end-to-end** com o
  mínimo de superfície. Menos é mais: valida lexer→parser→codegen→`.dill`→VM sem arrastar semântica/tipos
  (que são Fase 4). `[Cap 2]`.
- **Alternatives considered:** incluir `let`/variáveis ou `if` — **rejeitado**: puxaria escopo/tabela de
  símbolos (Cap 6) para dentro da Fase 0; adiado à fase própria.
- **Fronteira dura:** nenhuma construção além da acima entra na Fase 0 (Risco "escopo incha" do plan §6).

## Decisão D0.2 — Divisão `Int`/`Float` no mini-tradutor

- **Decision:** seguir a semântica já canônica do `ita/`: `/` entre `Int` é divisão inteira; entre `Float` é
  Float (o bug do `ita/` M0 já foi resolvido lá). No mini-tradutor, inferir Float se **algum** operando é
  Float. **Confirmar o comportamento exato via MCP `ita`** no oracle antes de fixar o golden.
- **Rationale:** o oracle (`ita/`) define a verdade; o `ita-next` reproduz. `[Cap 6.5.2]` (coerção numérica).

## Decisão D0.3 — Estrutura de pacotes Dart do `ita-next`

- **Decision:** um único pacote Dart `ita_next_compiler` em `ita-next/compiler/`, com `lib/` organizado por
  fase (`frontend/{lexer,parser,sdd,semantic}`, `codegen/`, `driver/`). Imports internos via
  `package:ita_next_compiler/...` (evitar os imports relativos `../lib/...` que a auditoria apontou como
  smell no `itac.dart` do `ita/`). Dep externa: só `package:kernel` (vendor, ADR-0003).
- **Rationale:** barrel + package-imports desde o dia 1; `codegen/` já nasce como diretório (não uma classe
  monolítica — invariante da spec §A).

## Decisão D0.4 — Versionamento do `ita-next`

- **Decision:** `git init` **próprio** no `ita-next/` ao final da Fase 0 (quando o mini-tradutor rodar), sem
  herdar o histórico do `ita/`. Commit inicial = o scaffold funcional. Repositório na org `ita-lang` e o
  **cutover** (`ita-next` → `ita`) ficam para ADRs futuros (spec §10).
- **Rationale:** o dono pediu "cópia nova, git novo (ou sem git até estabilizar)" — `git init` no fim da
  Fase 0 é o "até estabilizar".

## Abordagem por fase (confirmação vs Dragon Book)

- **Lexer (Cap 3):** definições regulares; a Fase 0 faz o mínimo, a Fase 1 completa. A gramática léxica é
  herdada do `GRAMMAR.md` §1 do `ita/`.
- **Parser (Cap 4):** recursive-descent + Pratt (como o `ita/`); a Fase 0 só a escada aritmética.
- **Codegen (Cap 8):** montar `k.Component` via `package:kernel` (a mesma API que o `ita/` usa); a Fase 0
  emite um `main` com `print`. Alvo sempre Kernel → VM (ADR-0001).
- **Runtime (Cap 7):** herdado da Dart VM; o `ita-next` **não** tem `runtime/` (ADR-0007).
