---
name: identity-yield-and-nao-fazer
description: O invariante "=> é o único token que rende valor" (RD-1) e o catálogo de construtos anti-itaianos que NÃO se deve adicionar à AST/gramática.
metadata:
  type: project
---

# Invariante do yield + catálogo não-fazer

**Fato firme (ruling RD-1, registrado no rodapé do `ast.asdl`):** `=>` é o ÚNICO
token que "rende este valor" em todo o Itá — fn-body, closure, match-arm, if-expr.
Não há segunda via de yield.

**Why:** consistência de "tudo é expressão" (P3) sem virar Rust. Expressões rendem
via `=>`; blocos `{}` são para efeitos/statements e NÃO rendem seu último valor.
`if`/`match` são expressão porque usam `=>` (arms) ou são totais (if-expr com `else`
obrigatório).

**How to apply:** ao revisar propostas de "bloco-como-expressão" (`BlockExpr`),
recusar — contradiz RD-1. O oracle `ita/` tem um `BlockExpr` ÓRFÃO (nunca emitido);
não ressuscitar.

## Catálogo não-fazer (anti-itaiano — proteger de over-engineering)
Cada item fere um princípio permanente ou o posicionamento (Art. II):
- `try`/`catch`/`throw`/`finally` — fere P7 (Result + `?` + `panic`). `Panic` mapeia
  p/ Kernel Throw internamente, mas NÃO há `throw` de usuário.
- `@annotations`/decorators — fere P6. O lexer já erra `@` (`lex-annotation-unsupported`).
- Coerção truthy/falsy, `null`/`undefined` distintos de `nil` — fere [[nullity]] (só `T?`
  admite `nil`; `""`/`0`/`[]`/`false` são valores reais).
- Ownership/lifetimes/borrow-checker — fere Art. II (Dart VM = GC). `mut`/`MutType` é
  PERMISSÃO de mutação, não borrow. Não modelar lifetimes. NB: a visão "systems programming
  das bordas" ([[systems-low-ffi-vision]], ADR-0012 C9) NÃO afrouxa esta regra — é quadrante
  Erlang (VM gerenciada), não Rust/Zig. Bitwise/bytes SIM; no-GC/unsafe/ownership NÃO.
- `const`/`unsafe`/`effect`/`signal`/`state` — keywords MORTAS (removidas, D1). São outra
  linguagem; não ressuscitar. `let` já é imutável (não precisa `const`).
- Cláusula `where T: A + B` de GENÉRICOS (Rust-style, separada) — redundante: `genericParam`
  já tem bounds inline (`T: A + B`). NÃO confundir com o `where { }` de VALOR (esse é itaiano,
  ver [[where-clause-identity]]).
- Turbofish `Foo<Int>()`, cast `as` genérico, variadics — P6 infere sem anotação; conversões
  são métodos explícitos. Não especular; owner decide se houver caso concreto.
