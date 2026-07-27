---
name: variable-local-let
description: Local let/var → VariableDeclaration/VariableGet no vendor 3.12.2 (novo modelo sealed) + isFinal de local NÃO interage com o sanitize
metadata:
  type: reference
---

# `let`/`var` local → VariableDeclaration/VariableGet (3.12.2, fmt 130)

O vendor 3.12.2 tem um **novo modelo de variável** (sealed), mas o padrão CLÁSSICO
funciona verbatim:

- `k.VariableDeclaration(name, {initializer, type, isFinal, ...})` é uma **factory
  que redireciona para `VariableStatement`** (`variables.dart:121-138`).
- `class VariableStatement extends Statement implements LegacyVariableDeclaration`
  (`statements.dart:1660`) — logo é `Statement` (vai direto no `Block`) e
  `VariableStatement.variable => this` (`statements.dart:2026`).
- `k.VariableGet(VariableDeclaration variable, [promotedType])`
  (`expressions.dart:203-210`); tipo estático = `promotedType ?? variable.type`.

## O verifier ACEITA o padrão legacy (o gate CA12 passa)
`verifier.dart`:
- `_isNewModelVariable(n) = n is VariableDeclaration && n is! LegacyVariableDeclaration || n is FunctionParameter`
  (`:272-274`) ⟹ **`VariableStatement` NÃO é "novo modelo"** (implementa
  `LegacyVariableDeclaration`).
- `visitVariableGet` (`:1189-1195`): p/ legacy roda `checkVariableInScope(node.variable, node)`;
  p/ novo modelo faz early-return (TODO não suportado).
- `_verifyVariableInitialization` (`:1149-1181`): exige a decl **filha DIRETA de
  `Block`** (entre outros pais) e faz `declareVariable(node.variable)`.
  `node.variable` do `VariableStatement` é `this` ⟹ identidade casa com o alvo do
  `VariableGet`. `checkVariableInScope` (`:393`) só checa `contains` no stack.

⟹ Emitir: `VariableStatement` como statement do `Block` (ordem-fonte, decl ANTES do
uso), referenciar por `VariableGet(mesmo objeto)`. `type` non-nullable (ADR-0013):
`InterfaceType(coreClass, Nullability.nonNullable)` — `int`/`String`/`bool` de `dart:core`.

## isFinal de LOCAL não interage com o sanitize
O passe `isFinal⟺setter` (bidirecional) do `OffsetNormalizer` é **escopado a
`k.Field`** (`sanitize.dart:83`, `node is k.Field`) — Field tem `setterReference`.
`VariableStatement` local **não é Field**, não tem setterReference ⟹ o normalizer
NUNCA reescreve o `isFinal` de um local. `let`→`isFinal:true`, `var`→`isFinal:false`
saem intactos no `.dill`. (Secundário `fileEqualsOffset == -1` do VariableStatement
fica -1 — legal, ver [[kernel-offsets]].)

## No emitter do Itá (F7)
`let x = 1+1` → VariableStatement; `${x}` → `VariableGet`. Binder = o `BindPattern`
(`ast.dart:634`), objeto único que casa `LocalRes.binder` (F4, `scope.dart:45`),
`binderTypes` (nº6, `check.dart:531`) e a 2ª side-table `Map.identity<Object,
VariableDeclaration>` do `_Emitter`. Runtime `${x}`: StringConcatenation → VM chama
`toString()` (Grupo B). Ver [[kernel-field-mutability]].
