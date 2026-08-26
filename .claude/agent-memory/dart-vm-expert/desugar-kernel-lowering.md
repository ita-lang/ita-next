---
name: desugar-kernel-lowering
description: Como as FORMAS canônicas da Fase 3 (desugar) do ita-next baixam para Dart Kernel; o protocolo iterador (moveNext, não next) e o furo do await-for/Stream.
metadata:
  type: reference
---

# Fase 3 (desugar) → Dart Kernel: formas canônicas confirmadas

Fonte oracle: `ita/compiler/lib/codegen/codegen.dart`. Formas reais: `ita-next/conformance/desugar/*.desugar`.

## match sobre `.some`/`.none` (`??`, `?.`, `!`, if-let) — ✅
- Oracle `_compileMatch` (codegen.dart:10954) NÃO gera `SwitchStatement`. Gera right-fold de
  `ConditionalExpression`(cond, armValue, elseResult); subject hoisted em `Let(tmp,…)` (avaliado 1×);
  bindings de pattern = cadeia de `Let`.
- `EnumPattern` → cond = `IsExpression(subject, InterfaceType(variantCls))` (`_compilePattern`:11065). Ou seja: **cadeia de `is`-tests**, não switch-on-tag.
- `Option<T>` built-in (codegen.dart:684 `_registerBuiltinEnum`) = base `abstract class Option` +
  subclasses `Option_some`(campo `value`)/`Option_none`, `supertype: base.asThisSupertype`.
  Payload em `.some` → hierarquia sealed é a ÚNICA codificação fiel (Dart `enum` não tem shape por-caso).
  Dart 3 sealed classes também baixam para `is`-chain na CFE → idiomático.
- Eficiência: 2 variantes = 1 `is` + 1 ConditionalExpression. AOT vira `is`→cid-check
  (`runtime/docs/compiler/type_testing_stubs.md`, Grupo B). Sum grande = `is`-chain O(n); decision-tree é otimização da VM.
- `.none` propagado em opt_chain = `EnumShorthand('none')` → codegen faz `ConstructorInvocation(Option_none)`.

## for → while + protocolo iterador — ⚠️ SYNC / ❌ ASYNC (o furo)
- Desugar (`_forStmt`) emite `$it = xs.iterator; while ($it.next()) { let x = $it.current; … }`.
- Dart REAL (confirmado `sdk/lib/core/iterator.dart` + `iterable.dart`):
  `Iterable<E>.iterator`→`Iterator<E>`; `Iterator` = `bool moveNext()` + `E get current`; **NÃO existe `next()`**.
- `.iterator` ✅ e `.current` ✅ casam Dart; `.next()` ❌ não existe → sobre um `List` Dart dá
  half-match (iterator/current resolvem, next → NoSuchMethodError). Pior tipo de bug.
- ASYNC (`await for`): `Stream` do Dart **não tem `.iterator`** (confirmado `sdk/lib/async/stream.dart`).
  Iteração async = `dart:async` `StreamIterator(stream)`: `Future<bool> moveNext()` + `current` + `Future cancel()`
  (api.dart.dev/StreamIterator). O desugar reusa `.iterator`/`.next()` awaited → NÃO mapeia p/ Stream.
- Kernel tem `ForInStatement{variable,iterable,body,isAsync,bodyOffset}`; `isAsync`="await for loop"
  (`pkg/kernel/.../statements.dart`) → a VM faz o lowering do Stream de GRAÇA (Grupo B). O desugar
  destrói o `for` → abre mão disso.
- Oracle `_compileForIn` (codegen.dart:2950) faz OUTRA coisa: while por índice `xs[i]`/`xs.length`
  (só List-indexável, não Iterable geral). Nem oracle nem ita-next usam `moveNext()`.
- RECOMENDAÇÃO: sync → adotar nomes exatos do Dart `iterator`/`moveNext()`/`current` (renomear `next`→`moveNext`):
  Dart Iterable funciona nativo, zero adapter, dart2js idêntico (parity-safe), AOT devirtualiza.
  async → NÃO reusar o protocolo sync; ou codegen emite `ForInStatement(isAsync:true)` nativo (defere ao VM),
  ou constrói `StreamIterator` + `cancel()` no finally. Nome do protocolo = decisão ita-visionary/stdlib.

### Trade-off das 2 rotas do `for` sync (p/ decisão do dono, 2026-07-11)
- **Op.1 = reter `for`→`ForInStatement` nativo (RECOMENDADO da lente VM):** herda protocolo custo-zero
  (`moveNext->bool`+`current->E`, sem alocar), devirtualização JIT/AOT-TFA sobre `List`, e `await for`
  DE GRAÇA pelo mesmo nó (`isAsync`) → resolve o furo async junto. Paridade VM×JS limpa. **Implica: desugar
  NÃO lowera `for` (nem sync nem async)** — contradiz a Fase 3 atual.
- **Op.2 = trait Itá `next()->Option<T>`:** `Option_some` é `Class` (heap) → **N alocações + N is-tests + N
  unwraps por laço** (não é enum de stack do Rust); escape-analysis AOT pode afundar mas é frágil; dart2js
  NÃO otimiza igual (ADR-0005) → alocação-por-elemento sobrevive no JS. Não cobre async. Ganho só de "pureza".
- Veredito: Op.1. Custo da Op.2 é perf/GC no hot loop + paridade JS pior, sem ganho de runtime.

## Try (`?`) retido como core — ✅ (e necessário)
- Oracle `_compileTryOperator` (11310): `let _try=e; if(_try is Result_err) return _try; _try.value`
  = `BlockExpression(Block([tmp, IfStatement(IsExpression(err), ReturnStatement)]), unwrap)`.
- `return` é Stmt → não cabe em `=> expr` (RD-1). Reter e baixar no codegen (onde há contexto de stmt) é correto.
- Legalidade Kernel: fn envolvente deve retornar `Result` (garantia Fase 4/5, não do desugar).

## where → match aninhado (binds irrefutáveis) — ✅
- Arms com `BindPattern` (irrefutável) → `_compilePattern` devolve cond=null + `Let`. `match` 1-arm-irrefutável
  = `Let(tmp, Let(binding, body))`. Kernel `Let`/let-in. Oracle `_compileWhere` faz `Let(a,Let(b,body))` direto.
- Ordem topológica já resolvida no desugar (Kahn) → codegen emite `Let`s em ordem de dependência,
  bem-escopados por construção, sem reordenar. Ganho real.
- Débito menor: 1 `_match` temp extra por nível vs `Let` direto; VM copy-prop dobra. Codegen pode
  reconhecer single-irrefutável e emitir `Let` direto (nice-to-have).

## compose `>>` → Closure fresh — ✅ (bug LocalFunctionId=0 NÃO reacende)
- Desugar: `($c0) => g(f($c0))`, `f`/`g` INLINE no corpo (não hoisted). Oracle `_compileCompose` (11338)
  → `FunctionExpression(FunctionNode(ReturnStatement(gCall), positional:[param]))`.
- Regra dart2js (ADR-0005): var capturada por `FunctionExpression` deve ser `VariableDeclaration` de bloco,
  NÃO `Let` ("Cannot find value local(main#_g)"; VM aceita, dart2js não). Oracle hoista `_f`/`_g` em block-var.
- compose do desugar NÃO cria var sintética capturada (`$c0` é PARÂMETRO, não captura; `f`/`g` são free-refs)
  → o bug do `Let`-capture NÃO bite aqui. Débitos codegen: (a) setar `FunctionNode.fileEndOffset` na closure
  sintética (`$c0` tem span zero-width — ok); (b) SEMÂNTICO (p/ ita-visionary): desugar reavalia `f`/`g`
  efetivos por-chamada; oracle avaliava 1× (hoist). Não é problema de Kernel.
