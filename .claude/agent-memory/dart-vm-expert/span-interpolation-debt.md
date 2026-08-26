---
name: span-interpolation-debt
description: Forward-compat gap — offsets de sub-expressões de interpolação são relativos ao sub-fonte; o lexer descarta o offset absoluto do ${…}.
metadata:
  type: project
---

# Débito de span: sub-expressões de interpolação (M1 vs M3)

Sub-expressões de `${…}` são reparseadas de uma SUBSTRING crua
(`parser.dart` `_parseSubExpression` → `Lexer(src)` + `Parser(..., sourceLength: src.length)`).
Todo offset interno fica relativo a `[0, len(src))`, NÃO ao arquivo.

**Why:** o lexer (`lexer.dart` `_string`, no ramo `${`) guarda só `['expr', expr.toString()]`
— DESCARTA o offset absoluto do conteúdo (que ele conhece no momento, logo após consumir `${`).
Como as literais são DECODIFICADAS (escapes colapsados), o parser NÃO consegue reconstruir
os offsets absolutos a partir da lista de partes de forma confiável.

**How to apply:** é forward-compat gap real (a info se perde na Fase 1, irrecuperável no
codegen→Kernel sem re-lexar). Quebra M1 (`fileOffset`→ stack traces DWARF em AOT / source-maps
em JS) para TODA expressão interpolada, e já hoje mis-atribui spans de ERRO de sub-parse
(`errors.addAll(sub.errors)`). Conserto correto = LEXER guarda o offset absoluto do `${…}`
(ex.: `['expr', src, baseOffset]`); parser rebaseia os offsets do sub-parse somando `baseOffset`.
Fallback só-parser (re-scan de `t.lexeme`) é frágil. Prioridade: cedo, porque toca a Fase 1.
