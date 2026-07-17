# Memória — compiler-craftsman (Itá / ita-next)

Índice. Detalhe nos arquivos-tema; aqui só ponteiros de uma linha.

## Semântica / Tipos (Dragon Book cap 6)
- [Spec 011 — dispatch + membros de extension/impl](dispatch_members.md) — tabela do ALVO (6.3.6); dispatch não mata o 1-walk (overload sim); `for` não precisa de `Iterator`; corte 011/012/013.
- [F5 — prefixo ∀, `≤` e igualdade de assinatura](f5_quantifiers_subtyping.md) — W3: o que provei certo, os 5 danos, e o meu "R1→R0 é diagnóstico" FALSIFICADO (é semântico).
- [Label de param + opt-out `_`](labels_params.md) — meu "o livro não cobre" CORRIGIDO (6.9+Fig 6.18); SE-0111 sai do Dragon; opt-out = 4 camadas, só 1 é gramática; trailing closure é o carve-out.
- [Walks sobre `sources` — o desenho do H1](walks_sources.md) — 6.5.2 fatora a ARESTA; invariante do `_conform` mata 6 filtros; `TypeInfo` e não `TypeTable` (a tabela escolheria em silêncio); tabela de mutação D1-D5.
- [Bounds + associated types](bounds_associated_types.md) — Dragon 6.5 é HM irrestrito (lacuna PROVADA); F<: e não type classes; §B-7 falso por Γ≠Σ; o §C-9 encomenda o que o §B-7 adia; `distinct by decl` colapsa instanciações.

## Fluxo / Análises (F6 — JLS, Maranget)
- [Spec 014 — F6 flow-check](f6_flow_check.md) — parecer W1 + BLUEPRINT do flow-walk (2026-07-17): `itac flow` novo; ⊤=neutro do ∩; anticascata=1 bit à javac; breakDAs (JLS 16.2.10); closure mais estrita que C# (anotado); resolution fora do CheckResult (L1); self-em-param-default é furo roteado (L3).

## Parsing / Sintaxe (Dragon Book cap 4–5, CI cap 6)
- [Spec 006 — where-expr + operadores tipados](parsing_where_typed_ops.md) — WhereExpr nível 0; op:string→enum fechado; símbolo no printer; divergência `~`; códigos where-*.
- [Inventário dump Tag→enum→símbolo](dump_preservation_inventory.md) — tabela que garante S-expr byte-idêntico após migração de operadores.
