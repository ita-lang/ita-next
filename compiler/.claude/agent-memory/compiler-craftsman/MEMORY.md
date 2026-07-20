# Memória — compiler-craftsman (Itá / ita-next)

Índice. Detalhe nos arquivos-tema; aqui só ponteiros de uma linha.

## Semântica / Tipos (Dragon Book cap 6)
- [Spec 011 — dispatch + membros de extension/impl](dispatch_members.md) — tabela do ALVO (6.3.6); dispatch não mata o 1-walk (overload sim); `for` não precisa de `Iterator`; corte 011/012/013.
- [F5 — prefixo ∀, `≤` e igualdade de assinatura](f5_quantifiers_subtyping.md) — W3: o que provei certo, os 5 danos, e o meu "R1→R0 é diagnóstico" FALSIFICADO (é semântico).
- [Label de param + opt-out `_`](labels_params.md) — meu "o livro não cobre" CORRIGIDO (6.9+Fig 6.18); SE-0111 sai do Dragon; opt-out = 4 camadas, só 1 é gramática; trailing closure é o carve-out.
- [Walks sobre `sources` — o desenho do H1](walks_sources.md) — 6.5.2 fatora a ARESTA; invariante do `_conform` mata 6 filtros; `TypeInfo` e não `TypeTable` (a tabela escolheria em silêncio); tabela de mutação D1-D5.
- [Bounds + associated types](bounds_associated_types.md) — Dragon 6.5 é HM irrestrito (lacuna PROVADA); F<: e não type classes; §B-7 falso por Γ≠Σ; o §C-9 encomenda o que o §B-7 adia; `distinct by decl` colapsa instanciações.

## Fluxo / Análises (F6 — JLS, Maranget)
- [Spec 014 — F6 flow-check](f6_flow_check.md) — W1 + blueprint flow-walk (lote 1, EM MAIN) + blueprint match analysis (lote 2, 2026-07-17): Sig materializa a tabela §4; **2 dedos na F5 são pré-condição** (list-pattern bloqueia CA9; pattern-type-mismatch); FlowError ganha detail/isWarning; match-not-exhaustive/unreachable-match-arm.
- [LT-F6a — tipar list/rest-pattern + pattern-type-mismatch](list_pattern_typing.md) — W1: RATIFICO `t.args[0]` (6.5.1 array ≠ 6.3.6 membro=M5); precedente `_bindEnumPattern`; nil não sintetiza; Literal/Range é F5 (I5/I2); backstop throw; 2 dedos A→B; 3 rulings-dono.
- [LT-F6b Fatia 2 — interval-splitting de Range](interval_splitting.md) — W1: exaustividade NÃO splita o domínio (cobertura monótona ⟹ gap `maxHi+1` basta; Itá diverge do rustc pq Int é ℤ ilimitado); split só na redundância; `_RangeSig`/`_HInt(_Iv)`/`_WInt`/BigInt; regressão só em `flow_test.dart:584`.
- [LT-F6b Fatia 3 — produto + List + String](product_list_exhaustiveness.md) — W1: produto=1 ctor RIDA o motor selado (`_StructSig`, Maranget §3.1); List é SEALED-like pq o rabo é alcançável (`_ListSig`+split, NÃO Range-like); NÃO existe RecordType (Struct=Record=1 máquina); String-redundância via `_atomKey` valor-real cercado; 6 rulings-dono; 3a→3b→3c.

## Parsing / Sintaxe (Dragon Book cap 4–5, CI cap 6)
- [Spec 006 — where-expr + operadores tipados](parsing_where_typed_ops.md) — WhereExpr nível 0; op:string→enum fechado; símbolo no printer; divergência `~`; códigos where-*.
- [Inventário dump Tag→enum→símbolo](dump_preservation_inventory.md) — tabela que garante S-expr byte-idêntico após migração de operadores.
