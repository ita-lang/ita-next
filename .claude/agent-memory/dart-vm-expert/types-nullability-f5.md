---
name: types-nullability-f5
description: Fatos confirmados do sistema de tipos Kernel/VM p/ a Fase 5 do ita-next — nullability nativa, Never, reified generics, unboxing por TFA, records, extension types, mut.
metadata:
  type: reference
---

# Kernel/VM — tipos (base do ruling da F5, 2026-07-15)

Oracle local: `ita/third_party/dart/3.12.2/pkg/kernel/` (`BinaryFormatVersion = 130`,
`lib/binary/tag.dart:230` — bate com ADR-0003).

## Nullability é NATIVA em todo DartType
- `sealed class DartType` tem `declaredNullability` + `nullability` (getters abstratos) —
  `pkg/kernel/lib/src/ast/types.dart:518-590`. `enum Nullability {undetermined, nullable, nonNullable}` (`types.dart:12-38`).
- `DartType.toNonNull()` (`types.dart:571`), `withDeclaredNullability` (`563`), `isPotentiallyNullable` (`577`).
- ⚠️ **Armadilha de serialização:** `ast_to_binary.dart:2525+` escreve `node.nullability.index`
  (undetermined=0, nullable=1, nonNullable=2), mas `pkg/kernel/binary.md:1548` documenta
  `{nullable=0, nonNullable=1, neither=2}` — **binary.md está desatualizado**. Codegen próprio deve seguir o índice do enum Dart.
- `T?? = T?` (achata). Nullability nativa NÃO expressa `Option<Option<T>>` aninhado.

## Unboxing exige NON-NULLABLE (o custo real do Option boxed)
- `pkg/vm/lib/transformations/type_flow/unboxing_info.dart`: `if (type is! NullableType) { … kInt / kDouble … }`
  senão `UnboxingType.kBoxed`. Nullable ⇒ nunca unboxed.
- `static const int numRecordFieldsForReturnValueUnboxing = 2;` — retorno de **record com exatamente 2 campos** é unboxed.
- `_cannotUnbox`: "dynamic calls always use boxed values"; entrypoints/natives/intrinsics/dynamically-overridden ⇒ fully boxed.
- Campos: unboxing de campo em AOT depende de TFA provar non-nullability — `dart-lang/sdk#40004`
  ("We can rely on TFA to proof if fields are non-nullable and can therefore be unboxed").
- `Smi` = "signed integer with one bit less than a full word… **An immediate object**";
  `Mint` = int 64-bit **heap object** (`runtime/docs/glossary.md`). ⇒ `int?` pequeno não aloca; `Option<int>` aloca 1 objeto sempre.

## TFA (Grupo B, AOT) — o que faz e o que NÃO faz
- `pkg/vm/lib/transformations/type_flow/transformer.dart`: devirtualização, inferência de tipos concretos,
  remoção de checks, tree shaking, unboxing info, direct-call marking. Closed-world.
- Lattice: `EmptyType` ("empty set of instances"), `NullableType`, `ConcreteType`, `SetType`, `ConeType`, `WideConeType`
  (`type_flow/types.dart`). `EmptyType` = dead code / função que não retorna.
- **NÃO faz monomorfização/especialização de genéricos** (não há clonagem de código por type-arg); só especializa call-sites.
- Escape analysis = `AllocationSinking` no backend (IL), roda **também em AOT**
  (`runtime/vm/compiler/compiler_pass.cc`: `COMPILER_PASS(AllocationSinking_Sink, { if (flow_graph->try_entries().is_empty()) … })`)
  — ⚠️ **desligado em função com try/catch**; é intra-procedural (pós-inline).

## Genéricos são REIFIED (custo declarado)
- `runtime/docs/types.md`: instâncias guardam `type_arguments` field; vetores achatados pela hierarquia;
  instantiator + function type arguments; canonicalização global; cache de instanciação (3-tupla).
- Verifier EXIGE aridade: `InterfaceType.typeArguments.length == classNode.typeParameters.length`
  (`pkg/kernel/lib/verifier.dart:1521`) e `node.arguments.types.length == expectedTypeParameters` (`verifier.dart:1308`).
  ⇒ não dá pra "omitir" type-args; dá pra preencher com `dynamic` (erasure pobre, custa TFA).
- is/as: `runtime/docs/compiler/type_testing_stubs.md` — cid-range check (rápido) vs.
  "load the instance type arguments vector and perform a type check for each Ti" quando algum Ti não é top ⇒
  **is-test com type-args top é mais barato**.

## Contrato Kernel que a F5 tem de honrar
- `InstanceInvocation` exige `interfaceTarget` + **`FunctionType functionType` já substituído**
  ("includes substituted type parameters from the static receiver type") — `expressions.dart:1850-1883`.
- `InstanceGet` exige `interfaceTarget` + **`DartType resultType` substituído** (`expressions.dart:551-571`).
- Sem tipo estático ⇒ `DynamicInvocation`/`DynamicGet` com `DynamicAccessKind {Dynamic, Never, Invalid, Unresolved}`
  (`expressions.dart:455-486`) ⇒ boxed + sem devirtualização + tree-shaking pior.
- `InstanceAccessKind {Instance, Object, Inapplicable, Nullable}` (`expressions.dart:1797`) — `Object` é o kind
  p/ receptor nullable/não-interface; `Nullable`/`Inapplicable` só dentro de `InvalidExpression` (= erro).

## `undetermined` NÃO é "não sei" (corrige leitura errada — review spec 009)
- Doc literal (`types.dart:12-25`): *"Non-legacy types not known to be nullable or non-nullable statically"*,
  exemplo `class A<T extends Object?>`: `x = null` é **erro** E `Object y = x` é **erro**. Ou seja `undetermined`
  = informação PRECISA sobre tipo aberto (nega as duas coisas), oposto do `UnknownType` curinga do oracle.
- Provas de que é estado legítimo: predicados dedicados `isPotentiallyNullable`/`isPotentiallyNonNullable`
  (`types.dart:577-589`); e o Kernel PROÍBE onde não cabe — `NeverType.internal` tem
  `assert(declaredNullability != Nullability.undetermined)` (`:852`) + `StateError` (`:861-865`).
- ⇒ `TypeParameterType` com bound `Object?` **exige** `undetermined`. Emitir `nonNullable` ali é mentira de tipo
  (TFA é closed-world e acredita). Invariante "nulidade sempre decidida" só é verdadeiro **sem genéricos**.
- `void`/`dynamic`/`invalid`/`bottom` têm nullability **fixa** — o emissor não escolhe (`types.dart:559-563`).
- `T??` é **inexprimível** no Kernel (nullability é byte, não wrapper) — mais forte que "idempotente".

## `num` é veneno para unboxing (munição p/ zero-coerção)
- `unboxing_info.dart` só reconhece `_intTFClass` e `_doubleTFClass` — **`num` não está na lista** ⇒ `kBoxed`.
  Em Dart `int + double` ⇒ `num`. Zero coerção (spec 009 §4.5) mantém o Itá fora do `num` = ganho de backend.

## Covariância: invariância na superfície não remove o check
- `VariableDeclaration.isCovariantByClass` (`statements.dart:1501-1507`): *"indicates whether the method
  implementation needs to contain a **runtime type check** to deal with generic covariance"*. Reusar `dart:core List`
  ⇒ `add`/`[]=` carregam check na entrada; TFA pode remover, não é garantido. Medir.

## Option no oracle: já é INTRÍNSECO, não membro
- `codegen.dart:829-837` — *"Registry de métodos built-in que são resolvidos em tempo de compilação"*;
  `_addBuiltinMethod(type, name, n, (args,self) => Expression)` **expande inline no call-site** (`:10270-10274`).
  **Não existe `Procedure` `Option.unwrapOr`.** E o corpo atual usa `DynamicGet(DynamicAccessKind.Dynamic,…)` +
  `DynamicType()` (`:693-700`) = o pior caso da §8.3.
- Fallback do oracle quando não infere o receptor: coleta builtins **por NOME** e chama se só há 1 candidato
  (`:10276-10284`) — resolução por adivinhação; é o que a F5 mata.
- Stdlib: `Option<T>` usado 33× **só como tipo**; `.unwrapOr`/`.map`/`.unwrap`/`.isSome` = **0 chamadas**.
  Já existe `Option<(T, Stack<T>)>` (`stdlib/collections.tu:42`) = Option de record, genérico (fatia D).

## Never / bottom
- `class NeverType extends DartType` (`types.dart:844-918`), tag binária 98 (`binary.md:1554`),
  nullability nonNullable/nullable (undetermined proibido por assert).
- `Throw` tem tipo Never; `DynamicAccessKind.Never` existe para receptor Never.

## Tuplas / valor / mut
- `class RecordType extends DartType {positional, named, declaredNullability}` (`types.dart:2304`);
  **named devem estar ordenados lexicograficamente** (assert). Nós: `RecordLiteral` (`expressions.dart:4798`),
  `RecordIndexGet` (326), `RecordNameGet` (384).
- `ExtensionType` (`types.dart:1532`) = zero-cost wrapper com `extensionTypeErasure` ("the type used at runtime…
  in is-tests and as-checks") — só 1 campo de representação; is-test vê o tipo apagado.
- **Não existe tipo-valor multi-campo no Kernel/VM.** `struct` do Itá ⇒ classe no heap. Mitigação: `final`
  (`Field.immutable` sem setterReference, `members.dart:294/320`; `VariableDeclaration.isFinal`, `statements.dart:1522`)
  + `@pragma('vm:deeply-immutable')` ⇒ "Deeply immutable instances can be shared across isolates within the same group"
  (`runtime/docs/deeply_immutable.md`; exige todos os campos final/non-late e classe `final`/`sealed`).
- **`mut` NÃO é tipo no Kernel** — é flag no nó (`isFinal`) / ausência de setter. `MutType` deve ser qualificador da F5, não DartType.
- Kernel **não tem `SwitchExpression`** (grep em `expressions.dart` — não existe) ⇒ match do Itá segue is-chain (ver [[desugar-kernel-lowering]]).
