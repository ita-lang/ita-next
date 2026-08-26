---
name: phase3-desugar-identity-rulings
description: Quatro rulings de identidade do desugaring (Fase 3, spec 007) — escopo do `?`, `??`/`?.` vs P4, `Try` core vs block-expr, higiene de gensym. Vereditos itaianos + o que ficou como decisão de dono.
metadata:
  type: project
---

# Rulings de identidade do Desugaring (Fase 3 / spec 007)

Emitidos 2026-07-12 a pedido do `compiler-craftsman` (levantamento técnico Fase 3). O
desugaring é o ponto mais sensível de P4 ("sem mágica"), porque reescreve o açúcar.

## MODELO DE NULABILIDADE — Swift, cravado pelo dono (2026-07-12)
**Fato firme:** O Itá TEM `Option<T>` BUILT-IN (Swift-style). `T?` = `Option<T>`, `nil` = `.none`,
`.some(x)` = presença. Ancorado: `codegen.dart:684` (`Option<T> { some(value:T), none }` + métodos
`unwrapOr`/`map`); stdlib usa `.some`/`.none`/`-> Option<V>` (`cache.tu`, `async.tu`); `guard let`/
`if let` desembrulham o `Option`. É o Maybe que faz os guards existirem. Reconcilia com a invariante
de nulidade ([[identity-yield-and-nao-fazer]] nullity): `nil`=`.none`=ausência intencional SÓ sob
`T?`/`Option`; `""`/`0`/`[]`/`false` seguem valores reais (String, Int…), NÃO Option — sem truthy/falsy.
> Correção histórica: meu 1º ruling (2026-07-12) afirmou "o Itá não tem Option, só T?/nil" — ERRADO.
> Revertido pelo dono no mesmo dia. Não repetir esse erro no code review da Fase 3.

## 1. Escopo do `?` (try) — SÓ `Result`. Cravado pelo dono.
`?` (try) propaga SÓ erro de `Result` (P7). Ausência/nulabilidade é história SEPARADA:
`guard let`/`if let`/`??`/`?.`/`!` sobre `Option` (dois mundos distintos, à la Swift).
**Why:** P7 (Art. I.7 + manifesto §66) = tríade `Result`+`?`+`panic` para ERRO. `Option` tem seu
próprio arsenal para AUSÊNCIA. Manter `?` monomórfico sobre `Result` preserva a separação
erro×ausência (decisão de design, não acaso). A variante "`?` early-return em `nil`" foi RECUSADA
pelo dono — ausência não usa `?`, usa o guard family.
**How to apply:** recusar `?` sobre `Option`; fica na Fase 3, type-agnostic.

## 2. `??`/`?.`/`!`/`if-let` → `match` NÃO fere P4 (com dump). Desugar sobre `.some`/`.none`.
Desaçucarar é itaiano SE o dump (`itac desugar --dump`) expõe a expansão.
**Why:** P4 mira código fazer MAIS do que diz (coerção, alocação implícita). Aqui o teste de
presença/ausência É o significado que o usuário escreveu — o glifo `?`/`!` anuncia "trato Option
aqui". Lowering torna inspecionável, não esconde; honra P4.
**How to apply:** desugar sobre `.some(x)`/`.none` (proposta ORIGINAL do compiler-craftsman, cravada
pelo dono): `a ?? b` → `match a { .some(x) => x, .none => b }`; `a?.b` → `match a { .some(x) => .some(x.b), .none => .none }`
(ajustar conforme semântica exata). NÃO usar `nil`-pattern cru — `nil` É `.none`, e o desugar canônico
é sobre os construtores do `Option`. (Minha "correção para nil-pattern" de 2026-07-12 fica REVERTIDA.)

## 3. `Try` fica nó CORE (early-return baixa no codegen). Rejeitei block-expr-with-return.
**Why:** `?` NÃO é açúcar como `??`/`?.` — é control-flow genuíno (early-return); nó de 1ª
classe mantém legível (honra P4). A alternativa "block-expression-com-return" FERE RD-1 (=> é o
ÚNICO yield; blocos não rendem) e RESSUSCITA o `BlockExpr` morto ([[identity-yield-and-nao-fazer]]).
O "custa 1 nó / P11" do craftsman está mal-citado — P11 é codegen build-time, não nós de AST;
o princípio em jogo é RD-1.
**How to apply:** `Try` core, baixa no codegen. Reabrir RD-1 p/ block-expr = emenda de dono.

## 4. Higiene de gensym — namespace lexicamente reservado + visível no dump. Resolvi o invariante.
**Why:** (a) dump DEVE mostrar sintéticos honestamente (P4 — esconder seria a mágica). (b) prefixo
de gensym tem de ser LEXICAMENTE IMPOSSÍVEL ao usuário (lexer rejeita), não só "improvável".
**How to apply:** `_it` (proposto p/ `for`) é INSEGURO — é ident de usuário válido → captura;
REJEITADO. Convenção CRAVADA pelo dono (2026-07-12): `$`+tag → `$it0`, `$tmp0`. `$` é o sigil que o
lexer proíbe em ident de usuário; reservar ANTES da Fase 3 emitir binder. Invariante (reservado no
léxico + visível no dump) resolvi pela visão; glifo `$` escolhido pelo dono.
