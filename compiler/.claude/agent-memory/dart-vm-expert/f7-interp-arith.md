---
name: f7-interp-arith
description: Fatos confirmados p/ o emitter da F7 — interpolação (StringConcatenation, toString implícito da VM) e aritmética de Int (InstanceInvocation de dart:core::num; div→~/); §7.4-a da spec 013
metadata:
  type: reference
---

# Interpolação + aritmética de Int no emitter (§7.4-a, spec 013)

Confirmado na tag 3.12.2 (vendor `pkg/kernel` + SDK pinado `.dart-sdk/3.12.2/.../core/`
+ VM via WebFetch). Emitter em `codegen/lib/emit.dart` (pacote IRMÃO de `compiler/`).

## `StringConcatenation` (interpolação) — toString é IMPLÍCITO da VM (Grupo B)
- Nó (`expressions.dart:3385`): só `List<Expression> expressions`. `binary.md` §tag 36:
  `List<Expression>` cru, SEM tag de toString por elemento.
- **O nó NÃO exige que as partes sejam String, e NÃO carrega toString:**
  `type_checker.dart:860-863` (`visitStringConcatenation`) só faz `forEach(visitExpression)`
  e devolve `String` — SEM `checkAssignable` dos elementos (contraste explícito com
  `visitStaticSet` `:853`, que chama `checkAssignable`).
- **A VM crua faz a conversão em runtime:** `kernel_to_il.cc`
  `FlowGraphBuilder::StringInterpolate`/`StringInterpolateSingle` fazem `StaticCall` para
  `StringBase._interpolate`/`_interpolateSingle`, que chamam `toString()` nos elementos.
- ⇒ **Emitter emite partes CRUAS**: `StrLit`→`StringLiteral`, `StrInterp`→a `expr` emitida.
  NÃO emitir `InstanceInvocation(expr,'toString')` — replica o que a CFE gera. `Str` SEM
  interp continua `StringLiteral` puro (não regride o hello).

## Aritmética de Int → `InstanceInvocation` de `dart:core::num` (NÃO `int`)
- **Os operadores aritméticos de `int` são HERDADOS de `num`.** `int` (core/int.dart) só
  sobrescreve `operator -()` UNÁRIO (int.dart:311). `+ - * % / ~/` vivem em `num`
  (num.dart:110-172). ⇒ interfaceTarget = membro de `num` — o que a CFE emite p/ `1+1`.
- ⚠️ **`div` (`/`) do Itá é `Int→Int`** (F5 `_primitiveOps`, `check.dart:65`), mas
  `num operator /` devolve **`double`** (num.dart:155). A divisão inteira é `~/`
  (`num operator ~/`, devolve `int`, num.dart:172). **`BinaryOp.div → k.Name('~/')`, nunca `/`**
  — senão vaza `double` (quebra tipo + paridade VM×JS).
- Mapa emitido: add→`+`, sub→`-`(binário; unário é `unary-`, `names.dart:55`/`members.dart:916`,
  não colide), mul→`*`, div→`~/`, mod→`%`. **pow(`**`), comparações (→Bool), lógicos → ICE.**
- Forma do nó (`expressions.dart:1850`): `InstanceInvocation(InstanceAccessKind.Instance,
  receiver, op.name, Arguments([arg]), interfaceTarget: proc, functionType: proc.function.
  computeFunctionType(Nullability.nonNullable))`. `op.name` sai do próprio Procedure resolvido
  ⇒ casa por construção com o interfaceTarget. `ProcedureKind.Operator` filtra o membro.
  `functionType` = `num Function(num)` (num::+ não é genérico; assert `typeParameters.isEmpty` ok).
- **Grupo B:** dispatch/execução da call são da VM. O verify resolve a ref a `num::+` porque o
  `declareMember` marca `seenByVerifier` em TODAS as libs (o `skipPlatform` só pula CORPOS) —
  mesma mecânica do `print` ([[builtin-dispatch-forin]], [[vm-platform-dill]]).

## Paridade (ADR-0005)
- `~/`, `+`, `*`, `%`, `StringConcatenation` rodam idênticos em VM/AOT/JS. `dart2js`: inteiros
  são doubles JS, mas `~/`/`%`/aritmética Int cabem no range seguro do CA1 (`1+1`); risco de
  paridade só apareceria em Int de 64 bits fora de 2^53 — NÃO no escopo desta fatia.
