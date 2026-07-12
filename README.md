# ita-next — Reescrita do compilador Itá (Dragon Book)

Reescrita do compilador **do zero**, fase a fase pela sequência do *Compiladores — Princípios,
Técnicas e Ferramentas* (Dragon Book), com o **`../ita/` como oracle** de validação (cada fase nova
deve reproduzir os goldens/paridade que o `ita/` já passa).

**Decisão:** [`ita-rewrite-ita-next-dragon-book`] (memória) · 2026-07-10.

## Fonte de verdade (ler antes de codar)

- **Constituição:** [`../.specify/memory/constitution.md`](../.specify/memory/constitution.md) — a lei.
- **ADRs:** [`../.specify/memory/adr/`](../.specify/memory/adr/) — decisões datadas. Em especial:
  - **ADR-0001** Dart VM é o backend **permanente** (LLVM abandonado). O alvo é sempre Kernel → Dart VM.
  - **ADR-0002** `.tu` · **ADR-0004** semântica side-table · **ADR-0005** alvo JS (`itac build --target=js`)
  - **ADR-0006** `itac` AOT · **ADR-0007** Grupo A (implementar caps 2–6) / Grupo B (VM herda 7–12)
- **Visão:** [`../ita/MANIFESTO.md`](../ita/MANIFESTO.md) · **Marcos:** `../references/livro-compiladores/ROADMAP.md`
- **Épico da reescrita:** `../specs/` (via `/speckit`).

## Estado

- ✅ **Fase 1 — Léxico** (`lib/frontend/lexer/`): scanner à mão, maximal munch, erros não-abortantes.
- ✅ **Fase 2 — Sintaxe → AST** (`lib/frontend/parser/`): descendente-recursivo + cascata de 13 níveis
  (§4.2), `ast.asdl`/`ast.dart` (nós `sealed`, span byte-preciso), `itac parse --dump` (S-expr
  determinística) e recuperação de erro N2 (top-level **e** intra-bloco). **Corpus de conformância:
  23 CAs (spec 004) + débitos de review verdes.** Cluster de débitos deferidos fechado em 2026-07-11
  (D1 recuperação intra-bloco · D2 span em `param`/`mapEntry` · D3 `operator` associatividade ·
  D5 `let/var` sem init) — ver `compiler/docs/reports/2026-07-10_review-fase2-parser.md`.
- ⏳ **Fase 3+** — semântica (binding, type-check), IR, codegen → Kernel. Entram **sob demanda** pelo
  `/speckit`, fase a fase.

`itac tokenize <f.tu>` (Fase 1) · `itac parse <f.tu> --dump [--spans]` (Fase 2). `make test` roda a
conformância (léxica `.tokens`/`.errors` + sintática `.ast`/`// EXPECT:`) num único gate `dart test`.
