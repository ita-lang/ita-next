---
name: phase4-binding-identity-rulings
description: Três rulings de identidade do Binding/resolução de nomes (Fase 4, spec 008) — namespace unificado, redeclaração/shadowing, top-level letrec. Vereditos itaianos + fronteira F4/F6.
metadata:
  type: project
---

# Rulings de identidade do Binding (Fase 4 / spec 008)

Emitidos 2026-07-12 a pedido do `compiler-craftsman` (levantamento técnico F4: CI cap 11 +
Dragon Book 1.6/2.7 + oracle `ita/semantic/`). F4 = namespace de VALOR, escopo léxico, resolve
para o NÓ-declaração via side-table (`Map.identity<Ident, ResolvedName>`, ADR-0004). Os três
resolvi pela VISÃO — nenhum exige emenda de dono; nenhum bloqueia a 008.

## 1. Namespace valor vs. tipo — UNIFICADO. Resolvi (P4+P2).
Um nome = um significado. NÃO separar (rustc separa). **Why:** separar faz o significado de `Foo`
depender da POSIÇÃO sintática (o resolver escolhe silenciosamente qual `Foo`) — máquina escondida
que P4 proíbe; P2 diz "nunca ambíguo". Argumento decisivo: `Foo(x:1)` é o TIPO invocado como
construtor — o construtor É o tipo, não há entidade de valor separada para pôr num 2º namespace.
Precedente oracle: `scope.dart` usa UM `Map<String,Symbol>` por escopo (fn+tipo+var na mesma
chave). Convenção PascalCase/camelCase já separa na prática; colisão real (`let Point`) vira o
`duplicate-declaration` honesto. **How to apply:** unificar. Separação rust-style (`struct Foo`+
`fn Foo`) = EMENDA de dono (contra P4) — recomendo recusar.

## 2a. Redeclaração no MESMO escopo — `duplicate-declaration` (erro). Resolvi (P1+P4).
`let x=1; let x=2` no mesmo escopo é reatribuição do binding por baixo do pano (é p/ isso que `var`
+`=` existe) → backdoor à imutabilidade (P1); "o 2º vence" (Lox) esconde a qual `x` a ref se liga
(P4). Vale p/ TODA decl do namespace unificado (let/var/fn/struct/enum). `scope.dart::define` já
devolve `false` na colisão local — infra feita p/ diagnosticar.

## 2b. Shadowing em escopo ANINHADO — permitido. Resolvi (P5).
`x` interno = binding NOVO em escopo NOVO; externo intacto e imutável → NÃO fere P1 (não é mutação),
é lexical/determinístico (não fere P4). Shadowing é AMIGO da imutabilidade: reencadeia nome p/ valor
derivado sem cair em `var`. Oracle já permite (`scope.dart`: "shadowing é ok"). **Sliver aberto (não
bloqueia 008):** warning de shadowing (lint, não erro) é polimento de ergonomia — dono decide depois;
default itaiano = permitido sem warning.

## 4. `self` explícito vs. implícito (bare-field) — RECOMENDEI A; é DECISÃO DE DONO. (review 2026-07-12)
Tensão exposta pela impl F4: um `x` nu (não-local/param) dentro de método vira `unresolved-name`
(impl **A**, exige `self.x`). Contradiz o "self implícito" do oracle? **Desambiguei "self implícito":**
tem DOIS sentidos e o oracle usa os dois. (1) `self` = param IMPLÍCITO (não se declara na lista) —
report `2026-07-07…md:70` "remover `self` param"; ROADMAP:127 "definido pelo dono". **A impl já honra (1)**
(`_selfType` injetado, `self` binder sintético). (2) bare `x`→campo — `codegen.dart:3193-3205` faz
`InstanceGet(this,x)` iterando `_currentClass!.fields` (**type-directed**). MAS a stdlib canônica
(`collections.tu`) escreve `self.items` EXPLÍCITO em todo lugar — NUNCA usa (2). **Recomendo A** (P4/sem-
mágica: bare `x` com 2 significados conforme campos-do-tipo = máquina escondida; contrato F4↔F5 ADR-0011
limpo — bare-field é type-directed=F5, não F4; = estilo da stdlib atual). **Mas é decisão de dono:** (2) é
comportamento oracle atribuído ao dono. **Não bloqueia F4:** A é conservador/forward-compat — se dono
escolher B, é follow-up BOUNDED em F5 (F4 defere possível-campo em vez de erro), não redo; corpus stdlib
(self. explícito) fica verde nos dois. Pergunta formulada p/ Gabriel no review.

## 3. Top-level = LETREC do módulo no nível do NOME. Resolvi (P5 + coerência where-letrec).
Módulo inteiro = grupo de binding mutuamente recursivo NO NÍVEL DO NOME — uniforme p/ fn/type E
let/var GLOBAIS (um global vê outro definido textualmente depois). NÃO tratar globais como
sequenciais (modelo C briga com recursão mútua e leitura top-down; un-itaiano). **Why:** P5; MESMA
forma do `where`-letrec ([[where-clause-identity]], spec 006 §3.6 — ordem=dependência, não textual)
→ consistência exige. Oracle: `analyzer.dart` Passada 2.5 registra NOMES de let/var top-level antes
do `_check` ("a fn pode ser declarada ANTES do `let`"). **Fronteira F4↛F6 (handoff compiler-craftsman):**
F4 só concede VISIBILIDADE DE NOME; NÃO rejeita forward-ref entre globais. O hazard use-before-init
(`let a=b`/`let b=a`; `let a=f()` com `f` lendo global iniciado depois) é F6 (ordem de inicialização/
definite-assignment) — runtime, não identidade. Espelha o `where` (reordenar por dependência +
rejeição de impureza deferida).
