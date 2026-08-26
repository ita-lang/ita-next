---
name: match-lowering-kernel
description: Lowering de `match` do Itá para nós Kernel PRIMITIVOS (is/==/if/Let) por família de escrutínio — a spec 013 §7.4e detalhada. Os nós de pattern do Dart 3 (kPatternSwitchStatement, kIfCaseStatement, kPatternVariableDeclaration) são CFE-internos e PROIBIDOS no .dill que a VM lê. List slice está GATED pela spec 012.
metadata:
  type: reference
---

# `match` → Kernel (design W1 da F7, 2026-07-19). Vendor 3.12.2.

## A trava dura: NÃO emitir nós de pattern do Dart 3
`runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc`, switch de `BuildStatement` (tag 3.12.2,
verificado — ver [[builtin-dispatch-forin]]): `kIfCaseStatement`, `kPatternSwitchStatement`,
`kPatternVariableDeclaration` estão na MESMA cláusula que `kForInStatement` — *"internal to the front
end and removed by the constant evaluator"* → `ReportUnexpectedTag; UNREACHABLE()`. ⟹ o `match` do Itá
**tem de baixar para nós primitivos** (`IsExpression`/`EqualsCall`/`EqualsNull`/`IfStatement`/
`ConditionalExpression`/`Let`/`AsExpression`), nunca para os pattern-nodes. Não é escolha de estilo — é
o que a VM aceita. `SwitchStatement` clássico (int/enum-sem-payload) É aceito, mas o oracle não o usa
(right-fold de `ConditionalExpression`); manter a árvore de `is` é uniforme.

## RD-1 decide a forma (statement vs expression)
- **`=>` rende (expression):** right-fold de `ConditionalExpression(cond, armValue, elseResult)`;
  subject hoisted em `Let(tmp, …)` (avaliado 1×); binds de pattern = cadeia de `Let`. Tipo estático =
  tipo do join dos braços (nº1). Oracle `_compileMatch` (`codegen.dart:10954`). Ver [[desugar-kernel-lowering]].
- **bloco (statement):** cadeia de `IfStatement`; subject hoisted em `VariableDeclaration` de bloco
  (⚠️ NÃO `Let` — regra dart2js: var capturada por closure de braço deve ser block-var, não `Let`;
  ADR-0005, ver [[desugar-kernel-lowering]]); binds = `VariableDeclaration`.

## Por família de escrutínio (o alvo do §7.4e)
| Família | cond do braço (teste) | destructure/bind |
| :-- | :-- | :-- |
| enum-com-payload (sealed class + subclasse) | `IsExpression(subject, InterfaceType(VarianteCls))` | payload = `InstanceGet(AsExpression(subject, VarianteCls), field, getterRef)` — o `as` é NECESSÁRIO: sem flow-promotion no Kernel cru, o receptor precisa do tipo da subclasse. Ou bind 1× em `Let/VarDecl(v = AsExpression(...))` e ler campos de `v` |
| `Option<T>` ≡ `T?` | `.none` → `EqualsNull(subject)` (`expressions.dart:2419`); `.some(x)` → complemento (`Not(EqualsNull)`) | `.some(x)` bind `x = subject` (o próprio valor não-nulo; `AsExpression` p/ non-nullable se o binder-type nº6 exigir). **custo zero** — sem classe Option no .dill |
| escalar Int/String/Float literal | `EqualsCall(subject, literal, interfaceTarget=…==)` (`expressions.dart:2471`; `==` é nó especial, não `InstanceInvocation`) | nenhum (literal não binda). ⚠️ Float `==` é footgun de igualdade — política é da F6, não da emissão |
| range `lo..hi` (Int) | `LogicalExpression(&&, InstanceInvocation(subject,'>=',lo), InstanceInvocation(subject,'<=',hi))` — operadores relacionais vêm da tabela `Ops` (§7.5), dart:core, **EM ESCOPO** (NÃO é membro-de-builtin da 012) | nenhum |
| produto struct | `IsExpression` se refinamento de tipo, senão sem teste (irrefutável) | `InstanceGet(subject, field, getterRef)` — getter é NOSSO membro emitido (struct→Class), não builtin. Sub-patterns recorrem |
| produto record | idem | ⚠️ se Itá record → Dart `RecordType`: destructure é `RecordIndexGet`/`RecordNameGet`, NÃO `InstanceGet`. A CONFIRMAR contra a decisão de lowering de record (structs vs RecordType nativo) |
| **`List` (slice)** | `.length` == / >= N + índice `xs[i]` | **GATED pela spec 012** — ver abaixo |

## ⚠️ Acoplamento com a spec 012 — `match` sobre `List` está GATED
CA9 da spec 014 (`match xs { [] => …, [a] => …, [a, ..resto] => … }`) precisa de `.length` (teste de
comprimento) e indexação `xs[i]` (bind de elemento). Ambos são **membros de built-in** — spec 013 §1
não-objetivo nº1 os roteia à **spec 012 (RESERVADA)**, e a F5 os recusa hoje (`builtin-member-unsupported`).
⟹ o gabarito de `match` sobre `List` fica **especificado mas gated**; destrava quando a 012 produzir
`.length`/`[]`. Confirmado: spec 013 §1 (tabela de não-objetivos, linha "Membros de built-in") e o
princípio de escopo ("programa que a F5 recusa nunca chega à F7"). As demais famílias (enum, Option,
escalar, range, struct) NÃO dependem da 012 — usam `is`/`==`/Ops/getters próprios.

## Exaustividade e o throw defensivo — dois fatos distintos (spec 014 §7)
1. **Exaustividade NÃO vira código.** Pós-F6 todo `match` é exaustivo por POLÍTICA de fase (spec 014 §7,
   ~l.194-196: *"A F7 emite match sem default-branch porque a fase passou, não porque leu um bit"*). O
   right-fold/if-chain termina no último braço sem `else` de segurança semântico.
2. **MAS o fim-de-corpo de função non-`Void` precisa de throw defensivo.** Side-table **nº8 `flowFacts`**
   = `completesNormally` por corpo (spec 014 §7, ~l.183-185). Onde o corpo pode cair do fim (a is-chain
   crua não prova o último `else` inalcançável), a F7 emite um `Throw` terminal (`ItaPanic`/análogo ao
   `ReachabilityError` que o CFE emite) — senão a VM devolve `null` implícito e o verifier NÃO pega
   (*"does not include any kind of type checking"*). A F7 **lê** o bit, não recomputa (ADR-0004).

## binds de pattern → binderTypes nº6
Todo bind de pattern = `VariableDeclaration(type = binderTypes[nó])`. `VariableDeclaration.type` é
**non-nullable** no Kernel e ADR-0013 **proíbe `dynamic`** — a F5 entrega o tipo pronto. Ver [[f5-export-contract]].
