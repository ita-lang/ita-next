---
name: builtin-members-ground-012
description: Gabarito de codegen dos membros de built-in (spec 012 — o CHÃO .length/[]/+): interfaceTarget exato via LibraryIndex, higiene de campo InstanceGet/InstanceInvocation, out-of-bounds=IndexError→panic. Vendor 3.12.2 confirmado.
metadata:
  type: reference
---

# Chão (spec 012) → Kernel. Confirmado contra `dart-lang/sdk@3.12.2` (2026-07-20, W1).

## Declarações em `dart:core` (fonte: `sdk/lib/core/{list,string,map}.dart` @ 3.12.2)
- `List<E>`: `int get length;` (~L365, GETTER) · `E operator [](int index);` (~L342) ·
  `List<E> operator +(List<E> other);` (~L603, **EXISTE** — concat) · `void operator []=(int,E);` (~L353, index-SET, fora de escopo).
- `String`: `int get length;` · `String operator [](int index);` (1 code-unit UTF-16) · `String operator +(String other);`.
- `Map<K,V>`: `int get length;` · **`V? operator [](Object? key);`** — ⚠️ parâmetro é **`Object?`**, NÃO `K`;
  retorno **`V?`** (ausência = `null`, doc: "null if key not in the map"). Casa com `T?` do Itá.

## interfaceTarget = getter⟹InstanceGet, operador⟹InstanceInvocation (CONFIRMA §7.2 da 012)
Resolução via `LibraryIndex` sobre `vm_platform.dill` (MESMA via do `print`, 013 §7.6):
`LibraryIndex(component, ['dart:core'])` → `getMember(lib, containerName, memberName)`
(`pkg/kernel/lib/library_index.dart` @ 3.12.2). Naming: getter usa prefixo **`get:`**
(`getterPrefix='get:'`, `setterPrefix='set:'`, `tearoffPrefix='get#'`, `topLevel='::'`).
Operador: `memberName` = o símbolo (`'[]'`, `'+'`) — `name.text` de operador É o símbolo.
- `xs.length` → `InstanceGet`, interfaceTarget=`getMember('dart:core','List','get:length')`, resultType=`int`.
- `xs[i]` → `InstanceInvocation`, interfaceTarget=`getMember('dart:core','List','[]')`, functionType=`(int)→E`.
- `xs+ys` → `InstanceInvocation`, `List::'+'`, functionType=`(List<E>)→List<E>`.
- `s.length`/`s[i]`/`s+t` → String idem. `m.length` → Map get:length. `m[k]` → `Map::'[]'`, functionType=**`(Object?)→V?`**.

## Higiene de campo (a lição cara — ver [[kernel-raw-api-field-hygiene]])
`InstanceGet(InstanceAccessKind kind, receiver, Name, {required Member interfaceTarget, required DartType resultType})`
`InstanceInvocation(InstanceAccessKind kind, receiver, Name, Arguments, {required Procedure interfaceTarget, required FunctionType functionType})`
(`pkg/kernel/lib/src/ast/expressions.dart` @ 3.12.2). **Em 3.12.2 são `required` named ⟹ o construtor não
compila sem eles** (melhora vs API posicional antiga). Mas o VALOR importa:
- `kind` = **`InstanceAccessKind.Instance`** (receptor é interface-type NON-NULLABLE — o chão só acessa
  sobre não-nulo; `T?` exigiria `?.`/unwrap antes ⟹ kind `Nullable`). Enum: `Instance`/`Object`/`Inapplicable`/`Nullable`.
- `resultType`/`functionType` = tipo **substituído** da nº1/nº5, não default. ⚠️ `Map[k]` functionType tem de
  ser `(Object?)→V?` (assinatura REAL do interfaceTarget), NÃO a `K` narrowed pela F5. A F5 estreita p/ K
  (type-safety), mas o Kernel casa com a decl de `dart:core`.

## Out-of-bounds `xs[i]` = panic (CONFIRMA ruling do dono §0.6)
`_GrowableList.operator []` é **`external`** com `@pragma("vm:recognized","other")` — bounds-check é
**intrínseco da VM (Grupo B)**, a F7 **NÃO emite guarda** (`sdk/lib/_internal/vm/lib/growable_array.dart`).
Lança **`IndexError`** (`extends ArgumentError implements RangeError`, `sdk/lib/core/errors.dart`) — um
**`Error`** (falha de programa "the programmer should have avoided"), NÃO `Exception`. Itá tem zero try/catch
(P7) ⟹ nada captura ⟹ isolate morre, exit≠0 = panic (013 §7.4f). Precisão: é `IndexError`, não `RangeError`
literal (a spec 012 diz "RangeError"; ambos são `Error`, o desfecho-panic não muda).

## Comportamento por alvo
- VM(JIT)=referência; AOT empata byte-a-byte (dart:core idêntico). JS(dart2js): `.length`/`[]`/`+`/`Map[]`
  todos existem (dart:core é compartilhado); out-of-bounds também lança IndexError (dart2js faz bounds-check
  em Dart sobre `JSArray`). MATCH nos CAs; divergência é só numérica (Int 2^53 vs 2^63, ortogonal — ADR-0005,
  ver [[parity-js]]). Marcar MATCH; runtime byte-a-byte só valida no golden-runner (pós-Gate 2).

## Corte design-vs-pin
- **Assentável agora (confirmado na fonte):** forma dos nós (getter→InstanceGet, op→InstanceInvocation),
  `List.+` existe, `Map[]→V?` com `Object?`, out-of-bounds=IndexError→panic, kind=Instance, campos required.
- **Só valida pós-Gate 2 (`verifyComponent` + golden-runner sobre o `vm_platform.dill` pinado):** que
  `getMember` resolve os nomes canônicos NO dill pinado (membros declarados-na-classe, não herdados — são);
  que a substituição de functionType/resultType casa com o InterfaceTypeInstantiator do verifier; goldens CA1–CA10.
- **Encaixe com match sobre List (013 §7.4e, ver [[match-lowering-kernel]]):** `.length`(InstanceGet) + `xs[i]`
  (InstanceInvocation) é exatamente o teste-de-comprimento + bind-de-elemento do slice-pattern. Quando a 012
  aterrissa o chão, a F5 para de recusar (`builtin-member-unsupported` some) e match-sobre-List destrava.
