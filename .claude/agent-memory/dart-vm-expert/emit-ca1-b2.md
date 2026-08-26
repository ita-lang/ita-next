---
name: emit-ca1-b2
description: O EMITTER da F7 (B2) — mapa nó-do-Itá → construção-de-Kernel para o CA1 (hello world) e o handoff do B1 (GroundRes). Onde estão os ICEs, e por que o emitter anda check.program (desaçucarado) e não o parsed.
metadata:
  type: reference
---

# `emit.dart` — o EMITTER B2 (CA1 mínimo, spec 013 §7.4/§7.6/§11)

Arquivo: `codegen/lib/emit.dart` · harness: `codegen/bin/build.dart`. Escopo é SÓ o
CA1 (`fn main() { print("olá") }`); tudo fora vira ICE honesto (`ice-codegen-*`, §7.8).

## Assinatura
`emitProgram(CheckResult check, k.Component platform, {Uri? sourceUri}) → ({List<k.Library> libs, k.Procedure main})`.
Devolve as libs do programa + o `Procedure` de `main`; o `finalizeProgram`
(`codegen/lib/finalize.dart`) fixa `main` como `Component.mainMethod`.

## Mapa nó-do-Itá → Kernel (o que a emissão CONSTRÓI)
- `FnDecl` `main` (aridade 0, `sync`, `Void`) → `Procedure` static top-level,
  `ProcedureKind.Method`, `FunctionNode(block, returnType: const VoidType())`,
  `..fileOffset = fn.offset`.
- `BlockBody` → `k.Block([...stmts])`; `ExprBody` → ICE `expr-body`; corpo `null` (trait) → ICE.
- `ExprStmt` → `ExpressionStatement`.
- `Call` cujo callee resolve p/ o CHÃO → `StaticInvocation.byReference(printRef, Arguments([...]))`,
  `..fileOffset = c.opOffset` (o `(` — span aponta p/ o seletor). Dispatch ESTÁTICO
  (top-level, `isInstanceMember==false` ⟹ não é `interfaceTarget`, ver [[f5-export-contract]]).
- `Str` só com `StrLit` → `StringLiteral` (concatena os valores num literal).
  `StrInterp` → ICE `str-interp` (é `StringConcatenation`, fatia seguinte — [[kernel-nodes]]).

## O handoff do B1 (confirmado no código, 2026-07-26)
- O callee `print` é um `ast.Ident` cuja `check.resolution[ident]` é
  **`GroundRes('print')`** (variante sealed nova em `binding/scope.dart`; F4 a resolve
  por FALLBACK de prelúdio). O emitter reconhece `GroundRes` e mapeia name→`dart:core::print`.
- `checkTypes` (`check.dart:111-124`) promove `resolution:` para o `CheckResult` como a
  **MESMA referência `Map.identity`** do resolver (não cópia) — o `Ident` que o emitter
  anda É a chave da tabela. Sem isto o `GroundRes` não chegaria.
- `printRef` = receita do `hello.dart`: `platform.libraries.firstWhere(importUri=='dart:core')`
  → `.procedures.firstWhere(name=='print')`.reference. É o único interop de I/O do §8.2.

## ⚠️ Anda `check.program`, NÃO `parsed.program`
`check.program` é o programa **DESAÇUCARADO** (F3) e `check.resolution` é keyada por
SEUS nós. Andar o `parsed.program` (F2) erraria a identidade e o `resolution[ident]`
viria `null`. O `build.dart` passa `res.check` de `flowProgram(parsed.program)`.

## Gate F6 (antes de emitir)
`build.dart` usa `flowProgram(parsed.program)`: `flow == null` ⟹ F4/F5 reprovou (gate I3);
`flow.hasErrors` ⟹ F6 reprovou. Só F5+F6-verde chega ao `emitProgram`.

## Os ICEs (§7.8 — F7 não tem erro de usuário)
`class CodegenIce implements Exception {code, offset, length}`; helper
`Never _ice(suffix, node)` → `throw CodegenIce('ice-codegen-$suffix', ...)`. Sítios:
top-level ≠ main (`toplevel-<Type>`, `main-duplicate`, `missing-main`); `main` com
params/generics/async (`main-arity`/`main-generic`/`main-async`); `ExprBody`/corpo nulo;
stmt ≠ ExprStmt (`stmt-<Type>`); expr ≠ Call/Str (`expr-<Type>`); callee não-Ident/não-ground
(`call-nonident`/`call-nonground`/`ground-<name>`); arg com label (`named-arg`); `StrInterp`.

## Rodar (o dono fiscaliza)
`dart run bin/build.dart <hello.tu> <vm_platform.dill> <out.dill>` depois `dart <out.dill>` → `olá`.
Higiene de campo + verify: herdada de `finalizeProgram`/`sanitizeLibraries` ([[kernel-raw-api-field-hygiene]], [[dill-platform-linking]]).
