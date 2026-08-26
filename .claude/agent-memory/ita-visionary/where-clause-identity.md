---
name: where-clause-identity
description: A cláusula `where { bindings }` pós-fixa é feature de identidade do Itá; sem nó na AST do ita-next; semântica exata é decisão de dono aberta e alvo de desugaring na Fase 3.
metadata:
  type: project
---

# Identidade da cláusula `where { }`

**Fato:** `EXPR where { let a = …; let b = … }` — a expressão-valor vem ANTES, os
bindings depois (leitura top-down). Está no oracle (`GRAMMAR.md` §4.1, nível 0), em
exemplos shipados (`ita/examples/functional.tu`, `conformance/valid/expr_where.tu`) e
foi reafirmado no ruling RD-1 como "a forma de bindings-antes-do-valor".

**Why:** é ergonomia de assinatura do Itá (P3, tudo-é-expressão + ler de cima p/ baixo).
ADR-0011 lista `where` explicitamente como alvo de DESUGARING (Fase 3). Logo a AST bruta
(Fase 2) PRECISA representá-lo p/ a Fase 3 baixá-lo — hoje NÃO há nó (`expression ::=
assignment (* nível 0 where DEFER *)`; sem `WhereExpr` no `ast.asdl`).

**How to apply:** recomendar `WhereExpr(expr value, stmt* bindings)` + produção nível 0.

## Semântica — RESOLVIDA na spec 006 §3.6 (não mais "aberta")
Spec `006-where-typed-ops` §3.6 + §7-nota #1 cravou: **LETREC** — "ordem de avaliação =
dependência, NÃO textual"; sort topológico é responsabilidade da **Fase 3** (não é campo do
nó); bindings visíveis só na `value` (e entre si); **pureza** dos bindings (Fase 3 rejeita
efeito observável). O `where_multi.desugar` confirma: forward-ref (`total` referenciando `a`/`b`
declarados depois) reordenado por dependência.
**Veredito de identidade (Fase 3, 2026-07-12):** a reordenação topológica HONRA o top-down
reading e NÃO é magia — está VISÍVEL no `desugar --dump` (aninhamento de `match`/let-in com os
NOMES do usuário, sem gensym) E os bindings são PUROS (reordenar puro é referencialmente
transparente → zero efeito observável de ordem). A pureza é o que sustenta o "sem mágica" (P4):
se houvesse efeito, reordenar seria magia. NB: `desugar.dart` DEFERE a rejeição-de-pureza p/
Fase 6 (comentário em `_where`), enquanto a spec 006 diz "Fase 3 rejeita" — discrepância de
LOCAL da checagem (decisão do `compiler-craftsman`), não de identidade: basta existir antes de
virar observável (codegen). Ver [[fase2-structural-gaps]], [[phase3-iteration-protocol-ruling]].

## Pureza — REFINADA pelo ruling 1+3 do dono (spec 014 §12-5, 2026-07-16)
O veredicto acima ("se houvesse efeito, reordenar seria magia") foi REFINADO, não derrubado:
pureza TOTAL exigiria análise interprocedural (fora de alcance, declarada). O dono cravou
**1+3**: os 5 primitivos sintáticos de efeito são banidos no binding (`impure-where-binding`);
chamada que efetua roda na **ordem publicada** (topo + empate textual, 006 §3.6). A defesa de
P4 muda de "efeito inobservável" para "efeito com ordem publicada e determinística" — sem
mágica = nada escondido, NÃO = sem efeito. Sistema de efeitos = débito de roadmap (inclinação
do dono). Detalhe: `print` é Call ⟹ cai no resíduo, não no ban — a checagem é sintática e o
hint deve ser honesto sobre isso. Ver [[phase6-flow-identity-rulings]].
