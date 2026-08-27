---
name: kernel-nodes
description: Mapa confirmado nó-da-AST-Itá → nó de Dart Kernel, com fileOffset/spans e citações do pkg/kernel. Base do W1/W3 do §8.
metadata:
  type: reference
---

# Itá AST → Dart Kernel (confirmado via `pkg/kernel/lib/src/ast/*`)

Raw base: `https://raw.githubusercontent.com/dart-lang/sdk/main/pkg/kernel/lib/src/ast/`
(o antigo `ast.dart` monolítico foi dividido em part-files: `expressions.dart`,
`statements.dart`, `functions.dart`, `misc.dart`).

## Spans / fileOffset
- Todo `TreeNode` do Kernel tem **um** `fileOffset` (int, um PONTO), não range.
- Alguns nós guardam offset EXTRA para precisão: `FunctionNode.fileEndOffset`
  (`functions.dart`), `Block.fileEndOffset`, `ForInStatement.bodyOffset`,
  `AssertStatement.conditionStart/EndOffset` (`statements.dart`). Ou seja: o Kernel
  às vezes quer MAIS que um ponto.
- AST do Itá guarda `(offset, length)` = range com `offset`=1º token. Mapa limpo:
  - `FnDecl (offset,length)` → `FunctionNode (fileOffset, fileEndOffset)` — length aproveitado.
  - Demais nós: Kernel usa só `fileOffset` → codegen pega `offset`. Risco só onde
    `offset`(início) ≠ o ponto que o Kernel quer (ver postfix/interpolação).
- Nós pós-fixos (`Member`/`Call`/`OptChain`/`Index`/`ForceUnwrap`) recebem TODOS
  `offset`=início da cadeia (parser `_postfix`, `start` capturado 1x). Kernel/CFE
  põe o fileOffset da invocação/acesso no SELETOR → em cadeia multi-linha reporta
  linha errada. Prefixos (`await`/`spawn`/`panic`/`!`/`neg`) têm offset no operador — OK.

## Mapa de nós (confirmado)
- `Str(strPart*)` → `StringConcatenation { List<Expression> expressions }` (`expressions.dart`), ordem L→R estrita. Codegen: 0 partes→`StringLiteral("")`; 1 literal→`StringLiteral`; com interp→`StringConcatenation`.
- `Call(callee, arg*)` ordem-fonte → `Arguments { positional, named }` SEPARADOS (`expressions.dart` ~L2320). Dart avalia args em ordem-fonte → codegen faz bucket + hoist de temps se ordem-fonte ≠ posicional-depois-nomeado.
- `IntLit`/`FloatLit` → `IntLiteral`(64-bit, só `value`, sem radix/raw)/`DoubleLiteral` (`expressions.dart` ~4174/4210). Débito raw/radix NÃO morde codegen (Kernel não carrega lexema). >2^63 barrado no lexer → `IntLit` sempre cabe. `BigInt` é tipo de lib, não literal Kernel.
- `AsyncMarker {sync,async,asyncStar}` → Kernel `enum AsyncMarker {Sync,SyncStar,Async,AsyncStar}` (`functions.dart:246-252`, comentário "Do not change the order… frontends depend on it"). Mapa por NOME (não índice). `stream fn`→AsyncStar (Stream); SyncStar de fora = sem sintaxe de gerador. `FunctionNode` tem `asyncMarker` + `dartAsyncMarker` (transformação async = Grupo B/VM).
- `Await(operand)` → `AwaitExpression` (`expressions.dart`). `Panic(operand)` → `Throw` (Expression, tipo Never — vale em posição de expr).
- `EmitStmt(value)` em `stream fn` → `YieldStatement {expression, isYieldStar}` (`statements.dart:1310`).
- `ForStmt.isAwait` → `ForInStatement.isAsync` ("True if this is an 'await for' loop", `statements.dart:659`).
- `IfExpr`/`IfStmt` → `ConditionalExpression`(`expressions.dart:2043`)/`IfStatement`(`statements.dart:1071`). If-expr com ramos-BLOCO precisa lowering via block-expression/temp+IfStatement (semântica do valor do bloco = débito do ita-visionary, não bloqueio de VM).

## `break`/`continue` de laço — o gabarito está NO VENDOR, verbatim (2026-07-29)
`statements.dart:351-388` (doc do `BreakStatement`): *"Both `break` and `continue` statements are
translated into this node"*, com os dois desugarings desenhados —
`break` ⟹ `L: while (x) { … break L; }`; `continue` ⟹ `while (x) { L: { … break L; } }` (label
envolve o CORPO). E a nota final: *"Compiler-generated LabeledStatements for WhileStatements and
ForStatements are only generated when needed"* ⟹ materializar o label só se usado é a POLÍTICA da CFE,
não otimização nossa. Não existe `ContinueStatement` de laço (só `ContinueSwitchStatement`).

## Alvo do operador numérico — precisão do `interfaceTarget`/`functionType`
- Aritméticos binários vivem em `num` (`num.dart:110`/`117`/`152`/`155`/`172`); `int` NÃO os declara.
  O `int+int → int` NÃO vem do `functionType`: vem do special-casing
  (`type_environment.dart:186-201` `isSpecialCasedBinaryOperator`), que cobre **só `+ - * % remainder`**
  em `int`/`num`/`double`.
- ⚠️ **`unary-` está FORA do special-casing** e `int`/`double` o SOBRESCREVEM (`int.dart:311`
  `int operator -()`, `double.dart:45` `double operator -()`, sobre `num.dart:190`). Resolver o `unary-`
  em `num` dá `functionType = num Function()` ⟹ `-x` com `x:Int` fica com tipo estático `num`. Resolver
  pelo tipo do operando (como o `div` faz com `~/`×`/`) é o certo.
- Comparações de ordem em `num`: `<` `:217`, `<=` `:224`, `>` `:231`, `>=` `:238` (a ordem citada na
  §7.4-a do emitter está trocada — cosmético, o código resolve por símbolo).

## Responsabilidade do codegen do Itá (não é Grupo B da VM)
- `MatchExpr`/`Pattern*`: a VM NÃO recebe nós de pattern de alto nível (é a CFE/front_end que os desugara). Como o Itá emite Kernel DIRETO (bypassa a CFE), o codegen do Itá DESUGARA match/patterns para Kernel core (is-tests, length-checks, let-bindings, ConditionalExpression). A riqueza do sum `pattern` é o certo.
- Legalidade que o VERIFICADOR do Kernel exige (Fases 4–6 do Itá precisam garantir ANTES do codegen): `AwaitExpression` só em fn async/asyncStar; `YieldStatement` só em gerador. AST só REPRESENTA.

## Verificados nesta sessão (2026-07-10)
StringConcatenation, Arguments, ConditionalExpression, AsyncMarker, FunctionNode
fileOffset+fileEndOffset, YieldStatement, ForInStatement.isAsync, IfStatement.
Não re-confirmados por fetch (cito por canonicidade/design-notes prévio): IntLiteral/
DoubleLiteral linhas exatas, AwaitExpression, Throw, NullCheck, BlockExpression.
