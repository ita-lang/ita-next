---
paths:
  - "codegen/**"
  - "compiler/lib/**"
---

# R1 · R4 · R11 — a F7 traduz o que a F5 provou

As três formas de a emissão **redecidir** o que uma fase anterior já decidiu: com chave mais
fraca (R1), com tipo mais largo (R4), ou citando de memória uma garantia que não existe (R11).
Cinco dos oito bugs da auditoria de 2026-07-29 são a R1.

## R1 — A F7 não decide nada. Ela traduz.

Toda decisão em `codegen/lib/emit.dart` tem de ser rastreável a uma **side-table da F5**
(nº1 `exprTypes`, nº3 `resolvedMembers`, nº5 `resolvedCalls`, …) ou à **identidade da decl**
(`Map.identity`). Qualquer outra origem é **redecisão com chave mais fraca**.

❌ **Proibido:** comparar com string vinda do texto-fonte do usuário — `p.variant == 'none'`,
`name == p.typeName`, `type.classNode.name == 'int'`. Grafia não é injetiva: `enum Estado
{ none, ativo }` e `Option.none` têm o mesmo lexema e famílias diferentes.
✅ **Exceção única:** nomes de plataforma (`dart:core`, `num::+`) — vocabulário fechado e externo
ao programa do usuário —, confinados aos `_resolve*`.

```bash
# sinal — hoje volta 6 hits em emit.dart
rg -n "\.(variant|typeName|label)\s*==\s*'" codegen/lib/
```

Um hit só é legítimo quando o **tipo guarda antes** e o lexema apenas refina — o molde é
`emit.dart:1357` (`s.variant == 'none' && check.exprTypes[s] is OptionalType`). Os outros cinco
(`:2176`, `:2177`, `:2436`, `:2439`, `:2523`) decidem **sem olhar `subjectType`**, e são os bugs
2, 3 e 4.

## R4 — O tipo do nó emitido é IGUAL ao que a F5 provou

Nunca supertipo, nunca subtipo. `Int + Int` com `functionType` de `num::+` grava `num` no `.dill`
— passa no verify, roda igual no JIT, e **custa unboxing em AOT** (a TFA só concede `kInt` para
subtipo de `int`). `checkNoDynamic` é o caso degenerado desta regra.

Exceções só por ADR, em lista fechada. `pkg/kernel` já resolve:
`TypeEnvironment.getTypeOfSpecialCasedBinaryOperator`.

## R11 — Garantia de outra fase se cita com verbatim, ou não se cita

*"A F5 já cobrou X"* é afirmação sobre **outro arquivo** — que nem o autor nem o revisor
abrem. Toda garantia citada precisa do sítio (`arquivo:linha`) que a implementa, colado.

O custo de não fazer isso foi medido: `emit.dart` justificava resolver campos por NOME
dizendo *"a F5 já cobrou `pattern-type-mismatch`"* — a F5 **nunca lia `typeName`**. E
`type_table.dart` afirmava *"totalidade é invariante: todo nó de expressão tem entrada"* —
a F5 não descia em `InitDecl.body`, `OperatorDecl.body` nem no operando de `panic`, e a F7
**emite** o corpo do `init`. `Map[k]` devolve `null` igual para "ausente" e "nunca
visitado", o emitter absorvia, e `init(a: Float, b: Float) { self.r = a / b }` emitia `~/`
sobre doubles: **segfault da Dart VM**, em programa legal, sem uma linha de diagnóstico em
fase nenhuma.

A rede que sobrou disso, e que vale para a próxima região esquecida: **pré-condição na
porta do consumidor**. `_expr` começa com `if (!check.exprTypes.containsKey(e))
_ice('untyped-<T>')`. Converte "artefato errado em silêncio" em lacuna declarada — e foi
ela que achou o `panic` depois de o `init` estar curado.

```bash
rg -n "a F[0-9] (já|garante|acusa|reprova)|já (cobrou|reprovou|validou|barrou)|não chega aqui" codegen/lib/ compiler/lib/
```
