---
name: builtin-members-ground-012
description: Gabarito de codegen do CHÃO de built-in (spec 012 — .length/[]/+ e os literais de coleção): interfaceTarget via LibraryIndex, functionType SUBSTITUÍDO (o genérico dá 2 erros no verifier), ListLiteral/MapLiteral com isConst PROIBIDO, out-of-bounds RangeError(VM) × IndexError(JS). Reverificado contra o pin local 3.12.2 em 2026-08-31.
metadata:
  type: reference
---

# Chão (spec 012) → Kernel. Reverificado 2026-08-31 contra fontes LOCAIS do pin.

> **Descoberta de método (2026-08-31):** o repo tem o SDK inteiro em
> `ita-next/.dart-sdk/3.12.2/dart-sdk/` — `lib/core/`, `lib/_internal/vm/lib/` **e**
> `lib/_internal/js_runtime/lib/`. Paridade VM×JS se verifica por **Grep local**, sem WebFetch.
> O vendor `third_party/dart/3.12.2/` só tem `pkg/kernel` + `pkg/_fe_analyzer_shared`.

## 1. Declarações em `dart:core` (linhas do pin local)
- `List<E>` (`lib/core/list.dart`): `E operator [](int index);` **:356** · `int get length;` **:408**
  (GETTER, não field) · `List<E> operator +(List<E> other);` **:723** (**existe**; doc `:720`:
  *"The default behavior is to return a normal growable list."*).
- `String` (`lib/core/string.dart`): `String operator [](int index);` **:206** · `int get length;` **:224**
  · `String operator +(String other);` **:351**.
- `Map<K,V>` (`lib/core/map.dart`): **`V? operator [](Object? key);` :270** — parâmetro é `Object?`,
  NÃO `K`; `int get length;` **:460**. Doc `:263-269` verbatim: *"The value for the given [key], or
  `null` if [key] is not in the map. Some maps allow `null` as a value. For those maps, a lookup using
  this operator cannot distinguish between a key not being in the map, and the key being there with a
  `null` value."* ⟹ com `Option` = nulidade nativa, o Itá **herda** essa ambiguidade.
- Literal é **growable** por semântica de linguagem (`list.dart:26` *"The default growable list, as
  created by `[]`"*; `:48` *"`<String>['A','B']; // Creates growable list`"*) — nos 3 alvos.

## 2. A RECEITA canônica (elimina a classe inteira de erro de tipo)
Não montar `functionType`/`resultType` à mão. `pkg/kernel` já tem tudo:
```dart
final recv = k.InterfaceType(listClass, k.Nullability.nonNullable, [k.InterfaceType(intClass, nn)]);
final sub  = Substitution.fromInterfaceType(recv);              // type_algebra.dart:584 — E := int
// .length  →  Procedure getter
final g = index.getMember('dart:core','List','get:length') as k.Procedure;
k.InstanceGet(k.InstanceAccessKind.Instance, r, lengthName,
    interfaceTarget: g, resultType: sub.substituteType(g.getterType))..fileOffset = off;
// []  /  +  →  Procedure operador
final p = index.getMember('dart:core','List','[]') as k.Procedure;
k.InstanceInvocation(k.InstanceAccessKind.Instance, r, indexGetName, k.Arguments([i]),
    interfaceTarget: p,
    functionType: sub.substituteType(p.computeSignatureOrFunctionType()) as k.FunctionType)..fileOffset = off;
```
- `Procedure.getterType` (`members.dart:1305-1310`) = `signatureType?.returnType ?? function.returnType`.
- `Procedure.computeSignatureOrFunctionType()` (`members.dart:1254-1257`).
- `Substitution.fromInterfaceType` (`type_algebra.dart:584`); nulidade combina certo:
  `visitTypeParameterType` faz `replacement.withDeclaredNullability(combineNullabilitiesForSubstitution(...))`
  (`type_algebra.dart:1076-1088`) ⟹ **`V?` com `V:=int` vira `int?`** — literalmente o `T?` do Itá.
- `Name`s vendorados em **`pkg/kernel/lib/names.dart`**: `lengthName` :31, `indexGetName` :25,
  `plusName` :47, `containsKeyName` :57. Usar (o verifier compara `node.name == interfaceTarget.name`).
- **Field × Procedure é NÃO-PROBLEMA na construção**: `getNonNullableMemberReferenceGetter`
  (`src/ast/helpers.dart:142-145`) = `if (member is Field) return member.getterReference; return member.reference;`
  ⟹ o construtor de alto nível resolve os dois. Só o **lookup** difere: getter = `'get:length'`
  (`LibraryIndex.getterPrefix`, `library_index.dart:15`), field = `'length'`. Fallback `get:`→cru
  imuniza contra upgrade de pin; `getMember` já sugere (`:436-440` *"Did you mean 'get:length'?"*).

## 3. functionType GENÉRICO = 2 erros no verify (a prova que faltava)
`verifier.dart:1495-1511` — `visitTypeParameterType`:
`"Type parameter '$parameter' referenced out of scope, declaration is: '...'"` **+**
`"Type parameter '$parameter' referenced from static context"` (quando `declaration is Class` e
`!classTypeParametersAreInScope`). O `E` de `dart:core::List` num nó dentro de `main()` dispara **ambos**.
Reforço no construtor: `assert(functionType.typeParameters.isEmpty)` (`expressions.dart:1912`).
Doc normativa dos campos (verbatim): `resultType` *"includes substituted type parameters from the
static receiver type"* (`expressions.dart:558-571`); `functionType` *"includes substituted type
parameters from the static receiver type and generic type arguments"* (`:1869-1883`).
⟹ Para o chão, `_especializa` (trocar só o `returnType`) é **insuficiente** — `List<E>::+` tem `E`
no PARÂMETRO. Substituição inteira, não patch de retorno.

## 4. Literais de coleção
- Formato (`binary.md`): `ListLiteral` tag **49** (`:1100-1105`: fileOffset, typeArgument, values);
  `MapLiteral` tag **50** (`:1128-1134`: fileOffset, keyType, valueType, entries); `MapEntry`
  **sem tag e sem fileOffset** (`:1144`).
- VM: `case kListLiteral: return BuildListLiteral(position);` / `case kMapLiteral: return BuildMapLiteral(position);`
  — **ACEITOS** (`kernel_binary_flowgraph.cc` @3.12.2, WebFetch). `kSetLiteral` = **`UNREACHABLE()`**
  (*"Set literals are currently desugared in the frontend"*) ⟹ nunca emitir `SetLiteral` cru.
- ⚠️ **`isConst: true` é a armadilha análoga à do default de parâmetro** — e morre DUAS vezes:
  (a) serializa como `Tag.ConstListLiteral`(58)/`ConstMapLiteral`(59) (`ast_to_binary.dart:2154/2170`),
  tags que a VM joga no bloco *"internal to the front end and removed by the constant evaluator"*;
  (b) o verifier reprova antes: `if (afterConst && node.isConst && !inUnevaluatedConstant) problem(node,
  "Constant list literal.")` (`verifier.dart:1360-1362`, map em `:1380-1382`). Constante de verdade =
  `ConstantExpression(ListConstant(...))`. Ver [[vm-node-acceptance]] e [[const-globals-f6-kernel]].
- ⚠️ `typeArgument` / `keyType` / `valueType` **defaultam para `const DynamicType()`**
  (`expressions.dart:4536`, `:4667-4668`) — higiene de campo clássica; o gate `visitDynamicType` do
  Itá pega. `fileOffset` é serializado ⟹ setar (ver [[kernel-raw-api-field-hygiene]]).
- Perde-se só otimização por não rodar `pkg/vm/.../list_literals_lowering.dart` (`_GrowableList._literalN`,
  citado em `_internal/vm/lib/growable_array.dart:568`). Grupo B; `BuildListLiteral` cobre o caso cru.

## 5. Out-of-bounds — a classe DIVERGE, o prefixo da mensagem NÃO
- **VM/AOT**: bounds-check intrínseco (`growable_array.dart:269-272` `external T operator []` com
  `vm:recognized "other"`+`prefer-inline`+`idempotent`; string idem `string_patch.dart:288`). Falha →
  `DEFINE_RUNTIME_ENTRY(RangeError)` → `Exceptions::ThrowByType(Exceptions::kRange, …)` →
  **`RangeError.range`** (`runtime/vm/{runtime_entry,exceptions}.cc` @3.12.2, WebFetch).
- **JS (dart2js)**: `JSArray.operator []` faz o teste em Dart e lança `diagnoseIndexError`
  (`js_array.dart:792-797`) → **`IndexError.withLength(index, length, indexable:…, name:'index')`**
  (`js_helper.dart:1294-1310`). `JSString.operator []` idem (`js_string.dart:454-459`).
- Reconciliação: `IndexError extends ArgumentError implements RangeError` (`core/errors.dart:445`) e
  **`String get _errorName => "RangeError";`** (`:535`) ⟹ os dois alvos imprimem prefixo
  **`RangeError`**, com CAUDA diferente (VM: *"Invalid value: Not in inclusive range …"*; JS:
  *"Index out of range: index should be less than N"* — `errors.dart:536-546` + `:227-238`).
  ⟹ **CA pode assertar `exit != 0` + `stderr` contendo `RangeError`. NÃO pode assertar a mensagem
  inteira nem `runtimeType`.** Ambos são `Error` (não `Exception`) ⟹ nada captura (P7) ⟹ panic.
- Exit: VM/AOT **255** (`runtime/bin/error_exit.h`, `kErrorExitCode`); JS/Node ≠ 0 mas ≠ 255. Ver [[panic-exit-code]].

## 6. Grupo B / não emitir
- Bounds-check, unboxing e alocação: intrínsecos. `_GrowableList.length` e `_StringBase.length` têm
  `@pragma("vm:exact-result-type","dart:core#_Smi")` + `graph-intrinsic` + `prefer-inline`
  (`growable_array.dart:221-231`, `string_patch.dart:296-300`) ⟹ o `int` do `length` já vem unboxed.
- `InstanceInvocation.flags`: `FlagInvariant`(1) e **`FlagBoundsSafe`**(2) (`expressions.dart:1852-1853`,
  serializados — `binary.md:788/801`). **NÃO setar**: default 0 é o conservador; setar sem prova
  desliga o bounds-check (mesma classe de transferência-de-soundness que `AsExpression.isUnchecked`).
  Não verificado se a VM honra o flag — irrelevante enquanto for 0.
- O que compra precisão de TFA é o `interfaceTarget` **instanciado corretamente** (poda pelo cone do
  `enclosingClass`, ver [[contextual-typing-slice-c]]), não pragma nenhum. Itá não emite annotations (P6).

## 7. Lacunas declaradas (2026-08-31)
- **Corpo** de `BuildListLiteral`/`BuildMapLiteral`: WebFetch trunca `kernel_binary_flowgraph.cc` antes.
  O `case` foi lido; o corpo não. Falta: mirror paginável ou checkout do `runtime/`.
- **dart2js `visitListLiteral`/`visitMapLiteral`**: `pkg/compiler` não é vendorado e o WebFetch trunca
  `ssa/builder.dart`. Sustenta a expectativa um argumento de NECESSIDADE (o dart2js consome o mesmo
  Kernel do CFE; se rejeitasse `ListLiteral`, nenhum `[1,2]` compilaria para JS) — não é citação.
  Fecha em minutos com o golden-runner no alvo JS.
