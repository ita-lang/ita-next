# Memória — ita-visionary (guardião da identidade do Itá)

## Doutrinas de identidade
- [Doutrina "a AST representa, não valida"](doctrine-ast-representa.md) — lente governante das specs de sintaxe; engolir token sem representar fere P4.
- [`extension Alvo` + declaração legível](doctrine-extension-declaracao-legivel.md) — alvo NU, T implícito do alvo; built-in precisa de DECLARAÇÃO, não de mecanismo; declaração ≠ implementação.
- ["Cite o artefato, ou assina"](doctrine-citacao-ou-nome.md) — anti-ruling-fabricado: a DATA não é fonte; autoridade custa citação, opinião é grátis; é Art. IV, não P4.

## Diretrizes de visão
- [Systems programming das bordas / FFI mínimo](systems-low-ffi-vision.md) — ADR-0012 §C-9: quadrante Erlang; bitwise = API funcional `Bits.*` (não operadores); `~` morto-no-parser.

## Reviews de identidade (precedentes)
- [Review spec 005 (init/traits/guard-let-cond)](spec-005-identity-review.md) — veredito itaiano; bloqueador `pub init` engolido; tensão guard-`&&`.
- [Review spec 006 (where-expr + op:string→enum)](spec-006-identity-review.md) — itaiano; `~` órfão RESOLVIDO (dono desceu a morto-no-parser, ADR-0012 §C-9).
- [Ruling pré-spec 011 (extension/impl na F5)](spec-011-identity-review.md) — 011 = extension/impl entram na F5; built-in-com-decl é M5; `impl Trait for T` é INERTE (bug vs 009 §4); 4 rulings de dono.
- [W0 consolidação da F5 (label/bounds/diamante)](f5-consolidacao-identity-review.md) — "ruling do label" é FABRICADO; bounds são decorativos e o ADR-0012 §B-7 pende deles; diamante = erro da DECL.
- [Crivo das 5 decisões abertas](crivo-5-decisoes-identity-review.md) — 3 fabricações novas (a confissão fabricou; a auditoria fabricou); ADR-0014 é UM artefato p/ 3 decisões; a ordem 5→4→3→1→2.
- [Gate do refactor da aresta dos walks](walks-refactor-identity-review.md) — vai, com 3 cercas; são CINCO walks e o índice doutrinal mente; divergência inobservável = ponto cego do refactor.
- [Review W3 do flow-walk F6](phase6-flow-w3-review.md) — APROVA C/ EMENDAS; "blueprint fantasma" = citação sem endereço versionado (estende citação-ou-nome); write-only capture sustentada.
- [W0 da LT-F6a (destravar list/rest-pattern)](spec-014-ltf6a-identity-review.md) — ✅×2; a reserva 012 é sobre `_member`, NÃO destructuring de type-arg; precedente Result/Option; comentário `:542` = fabricação-por-classe (não fura ruling do dono).
- [W0 da LT-F6b Fatia 2 (Range como intervalo/testemunha concreta)](spec-014-ltf6b-fatia2-identity-review.md) — liberado-c/-ressalva; 3 flancos: detail stale nomeia `range`, witness overflow no maxInt64, empty-range em código genérico; negativos não parseiam ⟹ witness sempre ≥0.
- [W0 da LT-F6b Fatia 3 (produto/List/String)](spec-014-ltf6b-fatia3-identity-review.md) — liberado-c/-ressalva; substância itaiana, mas 🔴 ATRIBUIÇÃO: código carimba "ruling do dono 2026-07-19" (ban Str-interp + campo-ω) sem artefato; tasks.md:41 do ban segue `[ ]`; detail unsupported stale nomeia list/produto.
