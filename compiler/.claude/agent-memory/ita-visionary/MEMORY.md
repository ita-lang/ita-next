# Memória — ita-visionary (guardião da identidade do Itá)

## Doutrinas de identidade
- [Doutrina "a AST representa, não valida"](doctrine-ast-representa.md) — lente governante das specs de sintaxe; engolir token sem representar fere P4.
- [`extension Alvo` + declaração legível](doctrine-extension-declaracao-legivel.md) — alvo NU, T implícito do alvo; built-in precisa de DECLARAÇÃO, não de mecanismo; declaração ≠ implementação.

## Diretrizes de visão
- [Systems programming das bordas / FFI mínimo](systems-low-ffi-vision.md) — ADR-0012 §C-9: quadrante Erlang; bitwise = API funcional `Bits.*` (não operadores); `~` morto-no-parser.

## Reviews de identidade (precedentes)
- [Review spec 005 (init/traits/guard-let-cond)](spec-005-identity-review.md) — veredito itaiano; bloqueador `pub init` engolido; tensão guard-`&&`.
- [Review spec 006 (where-expr + op:string→enum)](spec-006-identity-review.md) — itaiano; `~` órfão RESOLVIDO (dono desceu a morto-no-parser, ADR-0012 §C-9).
- [Ruling pré-spec 011 (extension/impl na F5)](spec-011-identity-review.md) — 011 = extension/impl entram na F5; built-in-com-decl é M5; `impl Trait for T` é INERTE (bug vs 009 §4); 4 rulings de dono.
- [W0 consolidação da F5 (label/bounds/diamante)](f5-consolidacao-identity-review.md) — "ruling do label" é FABRICADO; bounds são decorativos e o ADR-0012 §B-7 pende deles; diamante = erro da DECL.
