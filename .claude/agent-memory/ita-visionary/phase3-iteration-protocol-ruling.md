---
name: phase3-iteration-protocol-ruling
description: Rulings de identidade do code review Fase 3 — protocolo iterador do `for` (sync/async) vaza Dart na AST canônica (tensão Norte independência-do-Dart); compose per-call vs single-eval. Direção itaiana + o que é dono.
metadata:
  type: project
---

# Rulings de iteração/compose — code review Fase 3 (2026-07-12)

Emitidos no code review de identidade da Fase 3 (spec 007, desugaring implementado e verde).
Base: Norte transversal "independência do Dart" (`ROADMAP.md` livro-compiladores) + Grupo A/B
(A = Itá implementa; B = a Dart VM entrega de graça, o Itá NÃO reimplementa) + ADR-0012 C
(bordas quadrante-Erlang, interop `dart:` fino/enumerado, não difuso).

## Doença comum (Rulings 2 e 3): protocolo de iteração FALSO na AST canônica
O desugar baixa `for x in xs {…}` → `$it = xs.iterator; while ($it.next()) { let x = $it.current; … }`.
`.next()` é um FANTASMA: não casa nem o Dart (`moveNext()`) nem um trait Itá definido. O
`await for` reusa a MESMA forma com `await $it.next()` — mas `Stream` do Dart não tem `.iterator`
→ não baixa (bug real, levantado pelo `dart-vm-expert`).

### Ruling 2 — `for` sync: direção itaiana = NÃO enterrar protocolo Dart cru difuso
Enshrinar `moveNext`/`current` (rota A) na AST canônica de TODO `for` (o loop mais ubíquo) é a
LEAKAGE Dart maximamente difusa — TENSIONA o Norte "independência do Dart" ("interop `dart:`
explícito e fino, nunca espalhado; modelo Elixir `Enum`/`Enumerable`"). NÃO fere Art. I (o Norte
é diretriz/corolário ADR-0012 C, não princípio permanente) → não bloqueio por constituição, mas
a direção itaiana é clara. Duas saídas fiéis:
- **(B) protocolo Itá-próprio** — trait `Iterator` na stdlib (`.tu`), idealmente `next() -> Option<T>`
  (Swift/Rust, unifica com o Option built-in); ponte `Iterable` Dart→trait CONCENTRADA num ponto
  fino da stdlib (modelo Elixir Enumerable). Nota: `next() -> Option` MUDA a forma do desugar (a
  cond do while vira `match $it.next() { .some… }`), não o `while ($it.next())` Bool-shape atual.
- **(alt) reter `for` como CORE** (como `Try`/`guard let`) → codegen emite `ForInStatement(isSync)`
  nativo → a VM itera Iterable de graça (Grupo B). DISSOLVE a leakage (AST fica limpa) sem trait
  novo, ao custo de manter `for`+`while` no core (contra o "small core", mas já há precedente).
**Meu (identidade):** a AST canônica NÃO deve enterrar protocolo Dart cru difuso; direção = (B)
ou reter-core. **Dono:** introduzir trait `Iterator`/`Iterable` na stdlib AGORA (bloqueia Fase 3?)
vs. aceitar ponte-Dart enumerada como interino + agendar; a forma exata do trait (`next()->Option`)
é surface nova = dono + `compiler-craftsman` + `dart-vm-expert`. **Bug duro (craftsman), qualquer
rota:** o `.next()` fantasma NÃO pode shipar como canônico — não tem referente.

### Ruling 3 — `await for` async: reter core → `ForInStatement(isAsync)` nativo (Grupo B)
Baixar async-for a um `while(await $it.next())` sobre `Stream` é QUEBRADO (Stream não tem
`.iterator`) E reimplementaria máquina de Stream que a VM dá de graça — FERE Grupo B ("o Itá não
implementa"). **Recomendação firme (grounded ROADMAP Grupo B):** o desugar NÃO baixa `await for`;
retém como nó CORE (mesmo carve-out de `Try`/`guard let`), codegen emite Kernel
`ForInStatement(isAsync:true)`, a VM faz o lowering do `StreamIterator`. Interop Dart num ÚNICO
ponto de codegen enumerado (Norte), não difuso. **Isto é correção da spec 007** (que dizia
for→while incondicional) — abençoável por mim + craftsman (espelha o carve-out Try/guard-let já
abençoado), NÃO exige emenda de dono (nenhum Art. I em jogo). Consequência: sync e async `for`
passam a divergir de tratamento (sync baixado/retido; async retido) — honesto e OK.

## Nota 4 — `f >> g` → `($c) => g(f($c))` reavalia f/g por-chamada
NÃO é violação de P4: a reavaliação está VISÍVEL no dump (`f`/`g` dentro do corpo da closure) e,
p/ operandos PUROS (99%: `parse >> validate`), é idêntica ao oracle. Divergência SÓ com operandos
efeituosos (`getF() >> getG()`), raríssimo. **Forma fiel = a do oracle (hoist 1×):** `>>` é
operador; operador avalia operandos UMA vez (como `a+b`). Mas hoist no nível AST exige let-then-yield
= block-expr = FERE RD-1 → não cabe na Fase 3. Logo o single-eval é **débito de CODEGEN (Fase 7,
Kernel `Let`-hoist)** — MESMO padrão do compound-assign (spec 006 §7-nota #3). **Não bloqueia Fase 3;
registrar como débito Fase 7** p/ não divergir do oracle em operando efeituoso.

## Itens que HONRAM a visão (confirmados no review)
- P4: `??`/`?.`/`!`/`if-let` → `match .some/.none` VISÍVEL no dump; gensym `$x0`/`$c0`/`$it0`
  visível. Honestidade, não magia (reafirma [[phase3-desugar-identity-rulings]] #2).
- if-EXPR booleano permanece CORE (não vira `match{true/false}`) — CORRETO: ternário total, mapeia
  Kernel ConditionalExpression; reduzir a match adicionaria máquina de decisão sem clareza (net-neg
  P4). Bifurcação correta: `binding==null`→core (bool), `if let`→match (Option). Separa bool×Option.
- `where` letrec/topológico — ver [[where-clause-identity]] (fiel, visível, puro).
- Zero traição: sem try/catch, sem BlockExpr ressuscitado, `Panic` p/ force-unwrap-on-none (mapeamento
  sancionado, [[identity-yield-and-nao-fazer]]).
