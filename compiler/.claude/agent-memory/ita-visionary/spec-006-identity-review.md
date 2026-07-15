---
name: spec-006-identity-review
description: Review de identidade da spec 006 (where-expr + migração op:string→enum) — veredito itaiano, decisão de dono sobre `~` (bitNot)
metadata:
  type: project
---

Spec 006 preparou a Fase 3: nó `WhereExpr(value, bindings)` (nível 0 da cascata,
o mais frouxo) + migração de `Binary`/`Unary`/`Assign` de `op:string` → enum
fechado (`binaryOp`/`unaryOp`/`assignOp`).

**Veredito (review 2026-07-11): itaiano, pode fechar. Nenhum bloqueador.**

- **`where` honra P3:** `V where { let … }` é value-first / leitura top-down (o *quê*
  antes do *como*), herança Elixir/Haskell. É `WhereExpr extends Expr` (expressão, não
  statement — spec §10 rejeita a forma-statement por P3). É a substituição SANCIONADA
  do bare-block-como-expr rejeitado (RD-1/Q1); não cria 2ª via de yield (`=>` segue o
  único token "rende valor"). Non-assoc + level-0 = "decora o valor final uma vez".
- **Migração op→enum é P4-positiva (o oposto de mágica):** `op:string` era o único furo
  na AST-sealed; `switch` sobre string engolia `??` esquecido e compilava em silêncio.
  Enum fechado restaura exaustividade (CI 5.2.1) — esquecer caso agora é erro de compilação.
  Dump byte-idêntico (mapa enum→símbolo no printer). Comentário do enum crava "ordem NÃO
  tem semântica" (evita precedência-escondida-na-ordem). Coerente com [[doctrine-ast-representa]].
- **Códigos de erro coerentes:** `where-empty` (do `+` da produção) = well-formedness
  sintática, mesma classe de `TupleExpr ≥2` (M7), NÃO viola a doutrina. `where-non-associative`
  espelha `range-non-associative`. Spans precisos (aponta o token ofensor).

**Decisão de dono — `~` (BitNot): RESOLVIDA (ADR-0012 §C-9, palavra-final 2026-07-11). Meu lean
foi confirmado.** O dono decidiu bitwise = API funcional `Bits.*` (NÃO operadores) e desceu `~` a
**morto-no-parser** (junto de `& | ^ <<`): removido de `_unary`, do `UnaryOp` (agora só `neg|not`)
e da gramática §10; `~` segue tokenizado (§5 mortos). Isto CONFIRMA+ESTENDE spec 001 Q2 (Q2 mantinha
`~`), sem supersede. Fecha o `~` órfão que eu apontara. Histórico: enquanto o parser produzia `~`,
representá-lo como `UnaryOp.bitNot` era o movimento certo (engolir feriria P4 — [[doctrine-ast-representa]]);
o `compiler-craftsman` acertou. A visão systems/FFI-mínimo que motivou a decisão está em
[[systems-low-ffi-vision]] (manipulação de binários vai por binary pattern-matching, não operadores).

**Sugestões não-bloqueantes:** (1) nome `where-binding-not-let` engana — o parser aceita
`let` E `var` (L810); `var`-mutável destoa da alma pura/declarativa do `where`, mas
representar-e-deferir-a-Fase-3 é fiel à doutrina; renomear ou documentar. (2) spec §10 diz
"só `let`" vs §3.1 "let/var" — apertar a redação.
