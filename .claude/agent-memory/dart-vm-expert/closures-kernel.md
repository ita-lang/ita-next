---
name: closures-kernel
description: Closures do Itá → Kernel (LT-F7c) — por que `FunctionType`/`FunctionNode` de closure têm de ser POSICIONAIS (e não named-required como o §12-3), qual nó de chamada é o certo (FunctionInvocation × LocalFunctionInvocation × InstanceInvocation), o que a captura exige (nada) e por que `break` cruzando fronteira de função MATA o BinaryPrinter.
metadata:
  type: reference
---

# Closures no Kernel — 3.12.2 (vendor local + VM WebFetch), 2026-07-29

Vendor: `third_party/dart/3.12.2/pkg/kernel/lib/`. VM: tag 3.12.2 via WebFetch.

## 1. `FunctionType` de closure é POSICIONAL — o §12-3 (named required) NÃO se estende a ele
- A regra §12-3 nasce da DECLARAÇÃO `fn` (label + default saltável no MEIO). **Tipo-função não tem
  nem um nem outro**: a gramática é `type ::= "(" (type ("," type)*)? ")" ("->" type)?` ⟹
  `(x: Int) -> Int` **não parseia** (`compiler/lib/frontend/semantic/type.dart:236-243`), e a F5 já
  crava *"Closure é posicional pura"* → `FunctionType.positional` (`check.dart:1079-1085`).
- `k.NamedType(String name, DartType, {isRequired})` (`types.dart:1728-1741`) **exige um nome**. Para
  uma anotação `(Int) -> Int` esse nome NÃO EXISTE (`ParamType.label == null`, `type.dart:227-228`).
- Sintetizar (`$0`,`$1`) é a armadilha: named param no Dart casa **por NOME** em runtime, e o param
  real da closure chama-se `$c` (gensym do `_compose`, `desugar.dart:812-814`) ou `x`. Divergência ⟹
  **`NoSuchMethodError` em runtime**, e NENHUM gate vê (o verifier não tem `visitFunctionInvocation`;
  o `NaiveTypeChecker` só devolve `functionType.returnType`, `type_checker.dart:1403-1411`).
- ⟹ Forma certa: `k.FunctionType([T1..Tn], ret, Nullability.nonNullable)` (`types.dart:1104-1113`,
  `requiredParameterCount` default = `positionalParameters.length`) + `FunctionNode` ESPELHO com
  `positionalParameters` e `requiredParameterCount = n`. `namedParameters` vazio ⟹ o check de ordenação
  (`verifier.dart:1029-1037`) fica vacuoso.
- **Preço declarado**: `fn` decl (named) ⊄ tipo-função (posicional) ⟹ usar o NOME de uma `fn` como
  VALOR exige eta-expansão `($x) => f(x: $x)`. Hoje é ICE `ident-nonlocal` (`codegen/lib/emit.dart:1481`)
  — não abrir sem ruling.

## 2. `FunctionExpression` — campos e defaults perigosos
- `FunctionExpression(this.function)` já liga `function.parent` (`expressions.dart:5033-5035`).
- `id = LocalFunctionId.invalid` (`:5031`) — serializado `writeUInt30(id.toInt())`
  (`ast_to_binary.dart:2205`, `binary.md:1173-1179`). Ver [[kernel-raw-api-field-hygiene]].
- `FunctionNode` (`functions.dart:103-124`): **`returnType = const DynamicType()`** (`:109`) ⚠️ ADR-0013;
  `fileEndOffset = -1` (`:19`); `emittedValueType` obrigatório se `asyncMarker == Async`
  (`verifier.dart:971-978`); `body` atribuído depois exige `parent` na mão.
- Param `VariableDeclaration`: **`type = const DynamicType()`** (`statements.dart:1691`) ⚠️. Posicional
  opcional (além do `requiredParameterCount`) SEM initializer = problem (`verifier.dart:990-1002`), e o
  initializer teria de ser `ConstantExpression` para a VM ⟹ **param de closure com default = ICE**
  (o parser aceita, `parser.dart:1386`; a F5 DESCARTA o default no tipo, `check.dart:1081`).
- `LocalFunctionIdAssigner` (reset por Procedure/Constructor/Field) **é a réplica certa**: o CFE tem UM
  `LocalFunctionIdGenerator` por `Member` (`expressions.dart:5006-5021`), e o próprio pipeline da VM
  mantém o invariante (`pkg/vm/lib/modular/transformations/lowering.dart` carrega um
  `_currentLocalFunctionIdGenerator` e atribui id a FunctionExpression/FunctionDeclaration).
- ⚠️ Ao emitir a 1ª closure, TIRAR `LocalFunctionIdAssigner` de `_vacuosDeclarados`
  (`codegen/test/golden_test.dart:100-103`) — a catraca é bidirecional (`:533-539`).

## 3. Qual nó de chamada
- **`f(v)` com `f` = variável de tipo-função → `FunctionInvocation(FunctionAccessKind.FunctionType,
  receiver, args, functionType: T)`** — o doc do enum é literal para o nosso caso
  (`expressions.dart:2200-2207`). `functionType` é nullable (`:2261`; binary usa `DynamicType` como null,
  `binary.md:836`) mas **preencher**: é a única fonte da TFA.
- **`LocalFunctionInvocation` só para `FunctionDeclaration` local**: `localFunction =>
  variable.parent as FunctionDeclaration` é **cast duro** (`:2366-2367`) e a TFA o chama —
  `pkg/vm/.../type_flow/summary_collector.dart` @3.12.2: `Closure(_enclosingMember!, node.localFunction)`
  → `getClosureCallMethod` → `DirectSelector`. Mentir aqui ⟹ **AOT quebra na TFA** (JIT não vê).
  Quando o alvo É um local fn, este nó é ESTRITAMENTE melhor (DirectSelector = devirtualizado) que o
  `FunctionInvocation` (`FunctionSelector(_staticType(node))`, dinâmico).
- **`InstanceInvocation` de `call` — não**: exige `required Procedure interfaceTarget`
  (`expressions.dart:1892`) e não há `Procedure call` num tipo-função.
- **Ninguém confere aridade/nome de arg em `FunctionInvocation`**: `checkTargetedInvocation` exige um
  `Member target` (`verifier.dart:1294-1315`) ⟹ só o golden-runner pega.

## 4. `break`/`continue` cruzando fronteira de função — o formato PROÍBE
- `binary.md:1371-1380`: `labelIndex` é *"the Nth LabeledStatement in scope … **within the same
  FunctionNode**. **Labels are not in scope across function boundaries.**"*
- `BinaryPrinter.visitFunctionNode` **zera o `_labelIndexer`** na entrada e restaura na saída
  (`ast_to_binary.dart:1569-1570`, `:1608`); `visitBreakStatement` faz `writeUInt30(_labelIndexer![node.target]!)`
  (`:2332-2336`) ⟹ **crash na SERIALIZAÇÃO** (`Null check operator used on a null value`), depois do
  verify, sem span do `.tu`. Não chega à VM; não é silencioso; é ilegível.
- `verifyComponent` NÃO checa alvo de `break` (zero `visitBreakStatement`/`visitLabeledStatement`) —
  embora CHEQUE `ContinueSwitchStatement` (`verifier.dart:1396-1411`): omissão, não política.
- No Itá `continue` também é `BreakStatement` (`emit.dart:1338`) ⟹ mesmo bug. O conserto barato é
  fronteira no `_loops` (salva/restaura ao entrar num `FunctionNode`, igual ao `_labelIndexer`), o que
  reaproveita o ICE `break-outside-loop` que já aponta o span.
- `return` dentro de closure = `ReturnStatement` do `FunctionNode` INTERNO (não há return não-local no
  Kernel) ⟹ retorna da CLOSURE. ⚠️ a decisão `return` × `ExpressionStatement` do `_fnBody`
  (`emit.dart:1240`) é contra o `returnType` do FunctionNode CORRENTE — usar o do procedure externo
  produz artefato errado em silêncio.

## 5. Captura — a VM resolve; o Kernel cru não pede NADA
- `binary.md:544-567`: `VariableReference` = (offset, stackIndex) e **"Variables ARE in scope across
  function boundaries."** O serializer prova: `visitFunctionNode` faz `enterScope(variableScope: true)`
  = só `pushScope()`; `_variableIndexer` só é zerado em MEMBER scope (`ast_to_binary.dart:706-721`).
- `verifier.dart:1021` → `visitWithLocalScope` só salva a ALTURA da pilha (`:297-304`) ⟹ `VariableGet`
  de var externa dentro da closure passa `checkVariableInScope` (`:393-397`).
- **`checkNoSharedNodes` não dispara**: `VariableGet.visitChildren` só visita `promotedType`
  (`expressions.dart:228-231`) — `variable` é referência, não filho. A decl tem UM pai (o `Block`).
- Contexto/boxing de `var` capturado = **Grupo B** (alocação de contexto no flowgraph da VM).
- O que É nosso: nunca reusar o mesmo `VariableDeclaration` como param de dois `FunctionNode`
  (`verifier.dart:325-331` *"declared more than once"* + o nosso invariante).

## 6. Landmine nova: `FunctionTearOff` é PROIBIDO
VM @3.12.2 `kernel_binary_flowgraph.cc`: `case kFunctionTearOff: // Removed by lowering kernel
transformation. UNREACHABLE();` — quem o remove é `pkg/vm/lib/modular/transformations/lowering.dart`
(`visitFunctionTearOff → return node.receiver`), transformer que o Itá **não roda** (classe 1 da
[[kernel-raw-api-field-hygiene]]). Nunca emitir `FunctionTearOff`.
