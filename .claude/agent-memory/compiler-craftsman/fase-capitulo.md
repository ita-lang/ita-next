---
name: fase-capitulo
description: Mapa fase-do-compilador → capítulo Dragon Book / Crafting Interpreters para o Itá (ita-next)
metadata:
  type: project
---

# Mapa fase → capítulo (Itá, reescrita horizontal Dragon Book)

Régua constitucional (Art. III): implementamos DB cap 2–6 → Kernel. Fronteira do
compiler-craftsman = até emissão de código intermediário (Cap 6 → Dart Kernel). VM (Cap 7+) é do `dart-vm-expert`.

| Fase | Dragon Book | Crafting Interpreters | Spec |
| :-- | :-- | :-- | :-- |
| Léxico (scanner) | DB cap 2–3 (maximal munch, DFA) | CI cap 4 (scanner à mão) | Fase 1 (concluída) |
| Sintaxe → AST | DB cap 4 (análise sintática, error productions 4.1.4) | CI cap 5 (representar código), cap 6 (parsing expr) | Fase 2 / spec 004 |
| Binding / resolução de nomes | DB cap 6 (tabela de símbolos) | CI cap 11 (resolving/binding) | (futura) |
| Type-check | DB cap 6 (checagem de tipos) | — | (futura, Fase 5) |
| Codegen → Kernel | DB cap 6 (código intermediário) | — | (futura) |

**Convenção de citação nas specs:** CI = Crafting Interpreters (Nystrom); DB = Dragon Book.

**Nota de disparo (W1):** agentes custom em `ita-next/.claude/agents/` só entram no registro de
`subagent_type` quando cwd = `ita-next/`; sob `ita-lang/` rodam encarnados via `general-purpose`.
