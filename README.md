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

`scaffold vazio` — a infra (SDK pinado, vendor `pkg/kernel`, toolchain) e o código entram **sob demanda**,
conduzidos pelo `/speckit` fase a fase. Layout-alvo segmentado pela sequência do livro:
`frontend/{lexer,parser,desugar,binding,semantic,analysis}` → `codegen` (→ Kernel) → `driver` (itac).
