---
name: binding
description: Fase 4 (Binding / resolução de nomes, spec 008) do Itá — IMPLEMENTADA; side-table, arquitetura do passe, dump, fronteira com Semântica
metadata:
  type: project
---

# Binding — Itá Fase 4 (spec 008, ADR-0011 + ADR-0004)

IMPLEMENTADA 2026-07-12 (W3). Roda sobre a AST CANÔNICA (pós-desugar Fase 3).
Fonte-mãe: CI cap 11 (resolver como passe separado) + Dragon 1.6.3/2.7 (tabela de símbolos encadeada).

## Materialização (arquivos)
- `compiler/lib/frontend/binding/scope.dart` — `Scope(parent,{isFnBoundary,isModule})` + `declare`/`define`/
  `lookupLocal`; `sealed ResolvedName`=`LocalRes(Object binder,int hops,bool captured)`|`TopLevelRes(AstNode decl)`|
  `SelfRes(AstNode receiver)`; `binderOffset(Object)` + `formatResolution(ResolvedName?)`.
- `compiler/lib/frontend/binding/resolver.dart` — `Resolver` (1-walk), `BindingError` (`resolve-error: <code> @off+len`),
  `ResolveResult`. Driver: `resolveProgram/resolveDump/resolveErrorDump/runResolve`; `itac resolve <f> --dump [--spans]`.
- `ast_printer.dart`: `AstDumper({annotate})` — callback opcional (NÃO importa binding → camada limpa; null=Fases1-3 intactas).
- Corpus `conformance/resolve/*.tu` (12 fixtures: local/capture/letrec/shadowing/self_method/guard_let/destructure/
  gensym + 5 `err_*`); `resolver_test.dart`. Goldens `.resolve`/`.errors` = orquestrador ao vivo.

## Decisões de implementação (além do design)
- **binder = `Object`** (não `AstNode`): `Param` carrega span mas NÃO é `AstNode` nesta AST (é produto). `LocalRes.binder`
  ∈ {BindPattern, RestPattern, Param}; `binderOffset()` faz o switch p/ o dump. `TopLevelRes.decl`/`SelfRes.receiver`=AstNode.
- **Formato do dump** (documentado em binding.md §Observável): cada `Ident`/`SelfExpr` ganha 1 filho:
  `->L<binderOffset>^<hops>[*]` (local; `*`=capturado, cruza fn/closure) | `->T<declOffset>` (top-level) |
  `->S<receiverOffset>` (self) | `->?` (não resolvido). ASCII, determinístico. Árvore idêntica ao `desugar --dump`.
- **captura**: `Scope.isFnBoundary`; ao subir a cadeia, cruzar uma fronteira de fn/closure marca `captured=true` (diagnóstico
  Grupo B, não load-bearing). `_inLoop` RESETA em fronteira de fn (break em closure dentro de loop = erro); `_selfType` PERSISTE
  (closure captura self). Método `static`→selfType null.
- **self** = nó do tipo envolvente (Struct/Class/Enum/Trait/Actor decl, ou `target` de Impl/Extension). Campos NÃO são
  léxicos: exige `self.x` explícito (P4); bare `x` numa método que quer campo → `unresolved-name` (o `.x` é F5).
- **read-in-own-init** só em bloco LOCAL (split declare/define); no módulo tudo é letrec/ready → `let a=a` no topo resolve, sem erro.
- **guard-let**: ordem `value → else(escopo-filho) → declara target no escopo ATUAL → cond(vê target)`. else NÃO vê o bind.

## Decisão-mãe (side-table)
- **`Map.identity<Expr, ResolvedName>`** (ADR-0004: por identidade; AST imutável). Chaves = nós de USO:
  `Ident` e `SelfExpr` (só eles ancoram resolução de valor). Valor `ResolvedName` = **nó-binder-alvo + hops**.
- **DIVERGE de CI 11.4:** o jlox guarda só `int` (hops) porque o runtime é env-linked-list (hops É load-
  bearing). O **Dart Kernel referencia `VariableDeclaration`/`Procedure` por OBJETO**, não por nome+hops →
  o dado load-bearing p/ codegen é a **IDENTIDADE DO NÓ-BINDER**. Hops vira deliverable secundário do
  contrato ADR-0011 (útil p/ detectar captura = cruza fronteira de fn, e cross-check), não p/ Kernel.
- `ResolvedName` sealed: `LocalRes(binder, hops)` | `TopLevelRes(decl)` (sem hops, escopo módulo) |
  `SelfRes(receiver)`. Binder = `BindPattern`/`Param`/`FnDecl`/type-decl (cada um tem identidade).

## Arquitetura do passe
- Visitor com **pilha de escopos** (CI 11.3; Dragon 2.7.1 "cadeia forma pilha"), O(n) 1 walk (CI 11.2.1).
- **Two-tier:** módulo = declare-ALL-then-resolve (forward-ref de `fn`/tipo/global mutuamente recursivos;
  Lox NÃO precisa disso pq globals são dinâmicos — Itá compila estático, PRECISA; espelha oracle 3-pass
  `_collect`). Bloco/fn = single-pass léxico estrito (decl precede uso, Dragon 1.6.3; senão erro/resolve-
  outer). Split declare/define (CI 11.3.2) p/ pegar `let a = a`.
- **GuardLetStmt = escopo de CONTINUAÇÃO** (Swift): binding entra no escopo ATUAL p/ os stmts SEGUINTES do
  bloco, não num filho. Armadilha #1 de implementação.
- **self**: injeta binder sintético no escopo do corpo de método; `SelfExpr`→ele. Fora de método = erro
  (`self-outside-method`, análogo a CI 11.5.1 return-outside-fn). SelfExpr é nó distinto (sem colisão).

## Fronteira Binding (F4) vs Semântica (F5) — contrato ADR-0011
- **F4:** `Ident` valor (local/param/fn-topo/global), `SelfExpr`, binders de pattern/param/for/guard-let,
  callee `Ident` de `Call`. Namespace de VALOR.
- **F5 (type-directed):** `Member.name`/`OptChain.name`/`TupleIndex` (precisa tipo do receptor, Dragon
  1.6.4), `EnumShorthand`/`EnumPattern.variant`/`StructPattern.typeName` (contexto/scrutinee), aridade/
  overload/currying de `Call`, e **resolução de NOME DE TIPO** (annotations/`NamedType`/bounds/generic-
  params) — namespace de TIPO, flatter, o oracle já resolve em `resolveAnnotation(ann, global)`. "Não
  reconstruir escopo" (ADR) = não refazer o escopo LÉXICO de valor (a parte cara/com hops).

## Erros de binding
- **F4:** `unresolved-name` (DIVERGE de Lox: Itá estático → erro de compilação, não runtime),
  `read-in-own-initializer` (`let a=a`, CI 11.3.2), `duplicate-declaration` mesmo escopo (CI 11.5).
- **F4 ou F6 (CI 11.5.1 põe no resolver via flag de contexto):** `break`/`continue` fora de loop,
  `return`/`emit` fora de fn/stream. Type-agnostic, context-stack. Recomendo F4 (barato, mesmo walk) OU
  consolidar em F6 — ruling do dono.
- **F5/F6 (deferido):** `assign-to-immutable-let` — F4 dá a resolução (1-line check), mas p/ UNIFORMIDADE
  com `obj.field=` (mutabilidade type-directed, F5) manter todo "is-assignable" junto em F5/F6.
- **F6:** definite-return, unreachable, use-before-ASSIGN (path-sensitive, precisa flow-graph).

## Closures + imutabilidade
- **NÃO marca capture set** (DIVERGE de clox upvalues): Dart VM faz closure-conversion nativa (Grupo B,
  ADR-0011). Kernel emite `VariableGet` referenciando o `VariableDeclaration` externo direto. Binding PODE
  anotar "cruza fronteira de fn" (via hops) p/ diagnóstico, mas não é obrigatório p/ correção.
- **Imune ao bug CI 11.1** (o vazamento `showA`/`var a`) por construção: resolução estática ao nó-binder +
  AST imutável + referência-por-objeto no Kernel. `let` imutável não muda RESOLUÇÃO (só carrega isVar p/ F5/F6).

## Observável
- `itac resolve <f.tu> --dump`: pipeline parse→desugar→bind; reusa `AstDumper` em modo `--resolve`
  anotando cada `Ident`/`SelfExpr` com alvo (span) + hops. Corpus `conformance/resolve/*.tu` + `.resolve`
  goldens + `.errors` (binding errors), oracle cross-check. Alinha tokenize/parse/desugar.

## Armadilhas
- Binding vê só CORE pós-desugar: NÃO vê `where`/`|>`/`>>`/`?.`/`!`/`??`/if-let (lowered). VÊ retidos:
  `GuardLetStmt`, `ForStmt`, `IfExpr`(bool), `MatchExpr`, `Closure`, `Try`, `CopyWith`, `Binary.pow`.
- Gensyms `$x`/`$c`/`$it` do desugar = binders ORDINÁRIOS (higiene garante unicidade; binding não trata
  especial). `$0`-closure sem `$k`: params vazios, nada a ligar (aridade contextual = F5).
- Destructuring `let (a,b)=` : binder MÚLTIPLO — mais completo que oracle (que dava `continue` em pattern).

## Rulings a escalar
- **ita-visionary:** value-vs-type namespace (separados? `Foo(x)` constructor = valor); forward-ref de
  global top-level (letrec-de-módulo?); redeclaração no topo é erro?; `self` fora de método.
- **Dono:** `break`/`continue` fora de loop em F4 vs F6; `assign-to-let` em F4 vs F5/F6.
