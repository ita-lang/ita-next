---
name: contextual-typing-slice-c
description: Contrato de backend p/ a fatia C da F5 (tipagem contextual) — closures/FunctionInvocation, dynamic NÃO impede devirtualização (corrige mito), DynamicSelector vs InterfaceSelector, pow/num, CopyWith e AllocationSinking.
metadata:
  type: reference
---

# Fatia C (tipagem contextual) → Kernel/VM — confirmado 2026-07-15 (vendor 3.12.2 / SDK main)

## Kernel NUNCA força honestidade de tipo — só força PREENCHIMENTO
- `PositionalParameter({required this.type, …})` / `NamedParameter({required this.type})`
  (`pkg/kernel/lib/src/ast/variables.dart:1016/1160`): `DartType type` **non-nullable + required**.
  Não existe "tipo ausente" — existe `const DynamicType()`.
- `LocalVariable({required DartType? type}) : type = type ?? const DynamicType()` (`variables.dart:210-217`);
  idem `CatchVariable` (`:516-521`). `FunctionNode({this.returnType = const DynamicType()})` (`functions.dart:109`).
  ⇒ **o default do Kernel é a mentira**; ser honesto é opt-in. O verifier não confere acurácia de tipo de param.
- ⚠️ **Hierarquia NOVA em 3.12.2** (corrige `VariableDeclaration extends Statement` antigo):
  `sealed class VariableDeclaration extends VariableBase implements IVariable, Statement, VariableInitializationBase`
  (`variables.dart:75`). Subclasses: `LocalVariable`(197), `VariableStatement`, `CatchVariable`(507),
  `PositionalParameter`(1006), `NamedParameter`(1147), `ThisVariable`(1300), `SyntheticVariable`(1568).
  ⇒ débito D1 (binder→VariableDeclaration) precisa dispatchar por subclasse: param ≠ local.

## Chamar closure: 3 nós, não 1 (`expressions.dart`)
- `DynamicInvocation(kind, receiver, name, args)` + `isImplicitCall` (`:1699-1731`) — receptor `dynamic`. Pior caso.
- `FunctionInvocation(kind, receiver, args, {required FunctionType? functionType})` (`:2237-2271`).
  `functionType` é **nullable**: "null if the static type of the receiver is not a function type or is not
  bounded by a function type" ⇒ receptor `Function` cru ⇒ null. `enum FunctionAccessKind {Function, FunctionType,
  Inapplicable, Nullable}` (`:2191`); `Inapplicable`/`Nullable` só dentro de `InvalidExpression`.
- `LocalFunctionInvocation(variable, args, {required FunctionType functionType})` (`:2336-2363`) —
  functionType **non-nullable**; `variable.parent as FunctionDeclaration`.

## MITO CORRIGIDO: `dynamic` NÃO impede devirtualização em AOT
- `pkg/vm/lib/transformations/devirtualization.dart`: a `Devirtualization` **visita** `visitDynamicInvocation`,
  `visitDynamicGet`, `visitDynamicSet`, `visitFunctionInvocation` — não só os `Instance*`.
  `visitDynamicInvocation(n) => _handleMethodInvocation(n, null, n.arguments)` (target=**null**);
  `visitFunctionInvocation(n) => getDirectCall(node, null)`. ⇒ TFA devirtualiza por **dataflow**, não pela anotação.
- O ganho real do tipo está na **precisão do receptor** (`type_flow/analysis.dart::_collectTargetsForSelector`):
  - `InterfaceSelector` ⇒ `receiver.intersection(selector.member.enclosingClass.coneType)` — poda pelo cone do tipo estático.
  - `DynamicSelector` ⇒ `hierarchyCache.getDynamicTargetSet(selector)` = **todos os membros com aquele Name no mundo
    fechado**. `DynamicSelector` só guarda `Name`, `member => null` (`type_flow/calls.dart`).
  - Selectors: `DirectSelector`("Direct call to [member]"), `InterfaceSelector`("Interface call via known interface
    target"), `VirtualSelector`("Virtual call (using 'this' as a receiver)"), `DynamicSelector`("Dynamic call").
- `_handleMethodInvocation` exige ainda `isLegalTargetForMethodInvocation` + `!hasExtraTargetForNull(directCall)`
  ⇒ **receptor potencialmente nulo adiciona alvo e BLOQUEIA devirtualização** (liga nullability a perf).
- ⚠️ JIT **não tem TFA** (mrale.ph/dartvm/): dispatch é IC (`UntaggedICData`, "maps receiver's class to a method")
  → megamórfico (`MegamorphicCache`). AOT: switchable calls (unlinked → monomorphic → single target → linear IC →
  megamorphic) + GDT (`movzx cid,[obj+15]; call [GDT + cid*8 + …]`). TFA em AOT "only devirtualizes the call site if
  it can prove that it always invokes a specific method" (não-especulativo).

## Unboxing é **Member-only** — closure não ganha
- `type_flow/transformer.dart`: `_unboxingInfo.getUnboxingInfoOfMember(member)` — chaveado por `Member`
  (Procedure/Field/Constructor). **Não há registro de unboxing p/ `FunctionExpression`/`FunctionDeclaration`/closure**;
  `visitFunctionExpression` só aloca `node.id` via `LocalFunctionIdGenerator`.
  ⇒ tipar `$0: Int` **não** compra convenção de chamada unboxed p/ a closure. Compra o **corpo**:
  `$0 * 2` vira `InstanceInvocation(*, interfaceTarget: int::*)` em vez de `DynamicInvocation(*)`.
- `unboxing_info.dart::_getUnboxingType`: `if (type is! NullableType) { isSubtypeOf(_intTFClass)→kInt;
  isSubtypeOf(_doubleTFClass)→kDouble; if(isReturn && ConcreteType && cls.isRecord && numFields==2)→record }`
  senão `kBoxed`. `num` fora da lista (ver [[types-nullability-f5]]).

## `**` / pow — NÃO existe operador; `pow` retorna `num`
- `dart:math`: `external num pow(num x, num exponent)` (`sdk/lib/math/math.dart:193`). **`num` não tem `operator **`**
  (grep em `sdk/lib/core/num.dart` = 0). Doc (`math.dart:156-163`): "If [x] is an [int] and [exponent] is a
  non-negative [int], the result is an [int], otherwise both arguments are converted to doubles first, and the result
  is a [double]" + "For integers, the power is always equal to the mathematical result… only limited by available memory".
- `sdk/lib/_internal/vm/lib/math_patch.dart`:
  `@patch @pragma("vm:prefer-inline") num pow(num x, num exponent) { if ((x is int) && (exponent is int) &&
  (exponent >= 0)) { return _intPow(x, exponent); } return _doublePow(x.toDouble(), exponent.toDouble()); }`
  - `_doublePow`: `external double` + `@pragma("vm:recognized","other")` + `@pragma("vm:exact-result-type","dart:core#_Double")`.
  - `_intPow`: **corpo Dart puro** (exponenciação por quadrados), `@pragma("vm:recognized","other")`.
  - `recognized_methods_list.h`: `V(MathLibrary, ::, _doublePow, MathDoublePow, …)`, `V(MathLibrary, ::, _intPow,
    MathIntPow, …)`. **O `pow` público NÃO é recognized** — só os privados.
  ⇒ `Int ** Int` via `pow` = tipo estático `num` (poison p/ unboxing) + `as int` (AssertAssignable) p/ voltar a Int.
  ⇒ `2 ** -1` = `0.5` (Double): **`**` não é fechado sobre Int** na semântica do `dart:math`. Decisão de linguagem.
  ⇒ stdlib Itá com `intPow(Int,Int)->Int` typed não perde nada: `_intPow` também é só Dart.

## CopyWith / alocação — não há reconhecimento de padrão
- Nenhum doc em `runtime/docs/` sobre closures/Context/allocation sinking (índice conferido: README, async, gc,
  glossary, pragmas, types, compiler/{type_testing_stubs, optimization_levels, exceptions, ffi_pragmas,
  pragmas_recognized_by_compiler, data_dep_for_control_dep}, compiler/aot/entry_point_pragma). **Lacuna declarada.**
- Fonte = código (confiança: source-level): `runtime/vm/compiler/compiler_pass.cc`
  `COMPILER_PASS(AllocationSinking_Sink, { // TODO(vegorov): Support allocation sinking with try-catch.
  if (flow_graph->try_entries().is_empty()) {` ⇒ **desligado em função com try/catch**.
  `COMPILER_PASS(DelayAllocations, { DelayAllocations::Optimize(flow_graph); })` — via `INVOKE_PASS_AOT` (**AOT-only**,
  junto de ApplyClassIds/TypePropagation/ApplyICData/OptimizeTypedDataAccesses).
- ⇒ **P7 (zero try/catch) tem reforço de backend**: se o codegen do Itá nunca emitir `TryCatch`
  (Try/`?`→BlockExpression+return, `panic`→`Throw` — ver [[desugar-kernel-lowering]]), `try_entries()` fica vazio e
  AllocationSinking permanece ligado. **Não verificado:** se a transformação async da VM introduz try_entries. Medir.
- `runtime/docs/glossary.md` **não** define Context/Closure/Capture/Boxing/AllocationSinking (só Smi, Mint,
  Inline Cache, Megamorphic, Deoptimization).
