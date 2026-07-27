---
name: f7-if-cmp-logical
description: Fatos confirmados (3.12.2) p/ o emitter — if-expr (ConditionalExpression), comparações (EqualsCall vs num::< InstanceInvocation) e lógicos (LogicalExpression); spec 013 fatia B do if
metadata:
  type: reference
---

# if + comparações + lógicos no emitter (spec 013, pós-§7.4-a)

Vendor `ita-next/third_party/dart/3.12.2/pkg/kernel/lib/src/ast/expressions.dart`
+ SDK pinado `ita-next/.dart-sdk/3.12.2/dart-sdk/lib/core/`. Emitter `ita-next/codegen/lib/emit.dart`.

## `==` / `!=` → `EqualsCall` (nó ESPECIAL; NÃO InstanceInvocation)
- `EqualsCall(left, right, {required FunctionType functionType, required Procedure interfaceTarget})`
  (`expressions.dart:2471`). `getStaticTypeInternal` = `functionType.returnType`. É o que a CFE
  gera p/ `e1 == e2` quando NENHUM lado é `null` (docstring do próprio nó). `EqualsNull` (`:2419`)
  p/ `== null`.
- **`!=` → `Not(EqualsCall)`** (`Not` em `:3166`; docstring `:3164-65`: *"`is!` and `!=` operators
  are desugared into [Not] nodes"*) — confirmação canônica, não invenção.
- **`interfaceTarget` = o `operator ==` DE INTERFACE do tipo estático do receptor:**
  - `int` NÃO declara `==` (int.dart) → herda `num::==` (num.dart:47). ⇒ Int → `num::==`.
  - `double` idem → Float → `num::==`.
  - `String` declara o seu (string.dart:244) → `String::==`.
  - `bool` NÃO declara `==` (bool.dart) → herda `Object::==` (object.dart:53 `external`). ⇒ Bool.
  - ⚠️ `int implements num` (não `extends`) — um walk só de `supertype` NÃO acha `num::==`; por
    isso o emitter resolve por TIPO F5, não por caminhada de superclasse.
- `functionType` = `op.function.computeFunctionType(nonNullable)` (`bool Function(Object)`). O arg é
  o operando direito emitido cru (Int/String/Bool assignable a Object). **Grupo B:** dispatch/null
  fast-path do `==` é da VM.

## `< > <= >=` → `InstanceInvocation` de `num` (MESMA receita dos aritméticos)
- Vivem em `num` (num.dart:217/224/231/238), devolvem `bool`. interfaceTarget+functionType
  (`bool Function(num)`) saem do Procedure — reuso do `_numOp` (o que era o corpo aritmético).
- ⚠️ **Só receptor NUMÉRICO.** `String < String` PASSA a F5 (`comparison-type-mismatch` só cobra
  tipos IGUAIS, `check.dart:1720`) mas NÃO existe no Kernel (`String` não declara `<`). Emitter
  checa `check.exprTypes[b.left] is IntType||FloatType`; senão **ICE `ice-codegen-cmp-on-<Tipo>`** —
  nunca emitir um `<` que a VM rejeita. Mesmo ICE p/ `==` de receptor fora dos 4 escalares.

## `&&` / `||` → `LogicalExpression` (curto-circuito é do NÓ = Grupo B)
- `LogicalExpression(left, operatorEnum, right)` (`:3231`), `enum LogicalExpressionOperator {AND, OR}`
  (`:3219`). `getStaticTypeInternal` = `bool` fixo. Não emitimos nada além da variante — a VM baixa
  p/ desvios no flowgraph. F5 garante operandos `Bool` (`not-bool`, `check.dart:1716`).

## `if COND => then else orElse` (booleano) → `ConditionalExpression`
- `ConditionalExpression(condition, then, otherwise, staticType)` (`:3293`) — **`staticType`
  posicional OBRIGATÓRIO**; o nó o devolve cru em `getStaticTypeInternal`.
- **staticType = tipo do PRÓPRIO `IfExpr`** = `check.exprTypes[ifExpr]` (o join dos ramos, `_ifExpr`/
  `_join` em `check.dart:1808/1817`), baixado por `_emitType` (non-nullable, ADR-0013). Fora dos 4 do
  chão → `ice-codegen-type-<Tipo>`.
- `else` é obrigatório na AST do Itá (RD-1, `ast.dart:510`: `orElse` non-null) → sempre há `otherwise`.
- **if-let** (`IfExpr.binding != null`) → **ICE `ice-codegen-if-let`** (desembrulho de pattern, fatia
  do `match`). F5 já barra na síntese (`_ifExpr`→`_cannotInfer`); o guard do emitter é honestidade §7.8.

## Contrato F5→F7 usado
- `check.exprTypes` é TOTAL (§7-4, `check.dart:777` grava em `_synth`) — o tipo do operando esquerdo
  da comparação e o tipo do if-expr saem daí, sem recomputar. `BoolLit`(ast:365) → `k.BoolLiteral`.
