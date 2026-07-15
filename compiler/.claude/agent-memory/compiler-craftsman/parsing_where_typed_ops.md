---
name: parsing-where-typed-ops
description: Spec 006 — where-expr (nível 0 da cascata) + migração de operadores op:string → enum fechado. Fonte, algoritmo, divergência e códigos de erro.
metadata:
  type: project
---

# Spec 006 — `where`-expr + operadores tipados (preparação Fase 3)

**Fase (Dragon Book):** Sintaxe, cap 4.2–4.3 (análise descendente) + cap 5.1 (modelagem SDD).
**Como (Crafting Interpreters):** cap 6.2 — cascata de precedência (uma função por nível), NÃO Pratt table-driven (D0). CI 5.2.1 — `sealed` = switch exaustivo de graça.

## Decisões cravadas
- **`WhereExpr(expr value, stmt* bindings)` no nível 0** (mais frouxo). `_expression() => _where()`; `_where()` = `_assignment()` + `( "where" "{" (letStmt ";"?)+ "}" )?`. LL(1), sem recursão à esquerda. Só `let`/`var` no bloco. Um `where` por expr (não-assoc). Desugaring/escopo/pureza = Fase 3 (ADR-0011).
- **Operadores op:string → enum fechado** (`BinaryOp`/`UnaryOp`/`AssignOp`) em `ast.dart` + sums no ASDL. **Alternativa rejeitada:** manter `op:string` (perde exaustividade — esquecer `??` compilava mudo). **Conversão `Tag`→enum centralizada** em `_binaryOpFor`/`_assignOpFor` (parser); unários usam variante direta. **Símbolo (tag do dump) vive no PRINTER** (`_binarySym`/`_unarySym`/`_assignSym`, switch sem default), NÃO na AST — "nenhum símbolo cru sobrevive na árvore".

## Invariante do dump (crítica)
Migração é **invisível ao S-expr**: ~30 goldens 001–005 byte-idênticos. Round-trip Tag→enum→símbolo reproduz o string exato. Ver [[dump-preservation-inventory]].

## Divergência spec vs. código (registrada)
Spec 006 §5 lista `unaryOp = Neg | Not` — **omitiu `~`**. Mas `grammar.ebnf` §10 e o parser produzem `~` como unário (`Unary('~')`). Adicionei **`UnaryOp.bitNot → "~"`** para preservar o dump. Nenhum golden `.ast` exercita `~` hoje (só fixture léxico), mas o path do parser existe.

## Códigos parse-error novos (não há taxonomia central; vivem no parser)
- `where-binding-not-let` — statement não-`let`/`var` no bloco (span do token ofensor).
- `where-non-associative` — 2º `where` seguido (mirror de `range-non-associative`).
- `where-empty` — bloco sem bindings (o `+` da produção; span da expr toda).

## Armadilha de fixture (CA3)
No `.tu` inválido de CA3, evitar corpo que comece com **keyword de boundary** (`emit`, `return`, …): a recuperação N2 re-sincroniza nela e o `}` órfão vira 2º erro (`expected-expression`). Usar expressão comum (`y + 1`) → resync consome tudo → erro único.
