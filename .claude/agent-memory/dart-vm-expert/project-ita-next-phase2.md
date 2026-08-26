---
name: project-ita-next-phase2
description: Estado do ita-next — reescrita do compilador Itá; Fase 2 (AST) concluída, modelada p/ forward-compat de Kernel; codegen é futuro.
metadata:
  type: project
---

# ita-next — reescrita do compilador Itá

**Fato:** `ita-next/` é a reescrita do compilador (o oracle antigo é `ita/`). A **Fase 2
(Sintaxe → AST)** foi concluída. A AST **não emite Kernel/`.dill` ainda** — codegen é fase
futura (~Fase 7). A modelagem foi feita para carregar o que o codegen→Kernel exigirá (M1–M7
em `specs/004-parser-ast/design-notes.md`).

**Why:** decisão do dono (ADR-0001: Dart VM é backend permanente; ADR-0010/P11: zero codegen
em build-time — `ast.dart` é escrito à mão a partir de `compiler/docs/spec/ast.asdl`).

**How to apply:** em review de forward-compat, a régua é "a Fase 2 perde info que só o parser
vê?" (M1 span, M3 interpolação, M4 Int/Float, M6 ordem-fonte de args). §8 desta fase = SEM
dependência de VM (análise sintática pura); o papel do backend é forward-looking. Ver
[[kernel-nodes]], [[parity-js]], [[span-interpolation-debt]].

Arquivos-chave: `compiler/lib/frontend/parser/{ast.dart,parser.dart}`,
`compiler/lib/frontend/lexer/{lexer.dart,token.dart}`, `compiler/docs/spec/ast.asdl`.
