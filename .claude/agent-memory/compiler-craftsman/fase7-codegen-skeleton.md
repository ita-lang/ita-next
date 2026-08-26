---
name: fase7-codegen-skeleton
description: F7 LT-F7a — técnica do esqueleto executável (menor .dill que roda): CodegenVisitor S-atribuído, isFinal como EQUIVALÊNCIA bidirecional, driver CommandRunner, PT-BR do --help (design W1, 2026-07-20)
metadata:
  type: project
---

# LT-F7a — esqueleto executável da F7 (parecer W1, 2026-07-20; NÃO editei repo, plano só)

Fonte: Dragon **6.2** (escolha de IR — Kernel é IR-árvore ⟹ traduz por SUBÁRVORE sintetizada, não 3-addr
linear), **6.4** (tradução de expressão = atributo sintetizado `E.code`), **5.1.1** (sintetizado). Cap 6→Kernel
= fronteira (Art. III / Dragon 8.1). Confrontado com oracle `ita/compiler/lib/codegen/codegen.dart`.

## (A) CodegenVisitor — S-ATRIBUÍDO, não L-atribuído
A emissão é tradução dirigida por sintaxe SOBRE AST já tipada (F5 fez o context-sensitive) ⟹ **puro
sintetizado** (Dragon 5.1.1/6.4): `emitExpr(Expr)->k.Expression`, `emitStmt`, `emitDecl(Member)`, cada um
constrói e RETORNA a subárvore Kernel. Sem "place" herdado (Kernel é árvore, não 3-addr ⟹ sem `E.addr` de
6.4). Dispatch por `switch` exaustivo (AST ita-next é `sealed` — vantagem sobre if-chains do oracle).
- lê **nº1 `exprTypes`** na ENTRADA de cada `emitExpr` (→ `_toKernelType`; hello só precisa Void+String).
- lê **nº5 `resolvedCalls`** em `emitCall`: reconhece `print` (chão), ordena args por `slot`, `typeArgs`.
- `print`→`StaticInvocation.byReference(printRef, Arguments([s]))` (oracle:3571). Ref via **facade Platform**
  que resolve EXATAMENTE o §8.2 enumerado (`print` agora; Ops depois) — NÃO os dezenas de `firstWhere` do
  oracle:499-558 ("portar a lição, não o estilo"). `Component(nameRoot: platform.root)` (oracle:668) mantém a
  ref válida; `setMainMethodAndMode(mainProc.reference, true)` (oracle:466).
- interpolação `${1+1}`→`StringConcatenation([...])`: o Kernel chama `toString()` de cada parte no runtime ⟹
  NÃO emitir toString explícito (não colide com gate-012 de membro built-in). `1+1`=Ops(+) da nº5/§7.5.

## (B) isFinal = EQUIVALÊNCIA bidirecional (ressalva W0, risco P2)
F5 marca let/var por campo em **`FieldInfo.isMutable`** (`type_table.dart:52`, de `collect.dart:467` ←
`m.isMutable`). Emissão: `isMutable==false`(let/struct)→`k.Field.immutable`(sem setter); `true`(var/class)→
`k.Field.mutable`(com setter). O passe de saneamento é `field.isFinal = field.setterReference == null` para
TODO Field — os DOIS sentidos. **O oracle (`codegen.dart:101-103`) só faz UM sentido** (`sem-setter && !isFinal
→ isFinal=true`); falta o reverso (setter-ful com isFinal=true ⟹ class-var vira imutável em silêncio, mata P2).
NÃO é "tudo final" hard-coded: a finalidade DERIVA do fato-de-setter (que codifica let/var).
Guard (hello NÃO emite Field): **teste unitário sobre Component SINTÉTICO** — Field A `immutable` corrompido
p/ isFinal=false + Field B `mutable` corrompido p/ isFinal=true; assertar pós-passe A.isFinal==true &&
B.isFinal==false. Trava a equivalência ANTES de struct/class (§7.4c). É a "bomba desarmada". PREPARADO-agora
(wired no finalize) / exercitado-depois pela emissão de tipo nominal.

## (C) Driver CommandRunner<int>
`bin/itac.dart`: `switch(args.first)`→`CommandRunner`. Cada `Command<int>.run()` = adaptador FINO: declara os
flags no `argParser` (p/ help+aceitação) e faz **`return runCheck(argResults!.arguments)`** (passthrough cru —
funções puras de `driver.dart` INTACTAS, §9/Art.IV-4). `main` vira async (`runner.run` é Future); `on
UsageException`→exit 64. Novos: `build` (F1→F7, `writeComponentToBytes`) e `run` (build+exec `dart` pinado —
observável é handoff MCP `ita`, não meu). Precisam `runBuild`/`runRun` novos em `driver.dart`.

## (D) PT-BR do --help
NOSSO (PT-BR trivial): `description`/`help` de cada Command/flag + descrição do runner. package:args-interno
(EN hardcoded, NÃO exposto): `Usage:`, `Available commands:`, `Global options:`, o `help` command e `-h`.
Recomendo: **override `usage`+`usageFooter`+`invocation`** num `ItacCommandRunner` p/ o TOPO (front-door, ~15
linhas, risco só de apresentação, re-verificar em bump); subcomandos ficam com descrições PT-BR + resíduo EN do
`Usage:` per-command (Rota 2, zero acoplamento). Trade-off explícito.

## pubspec + layout
`args`: dep normal pub.dev (`^2.x`, confirmar versão atual — pure-Dart; régua P9/P10/P11 do compilador, NÃO
P8). `kernel`+`_fe_analyzer_shared`: path-deps a `third_party/dart/3.12.2/pkg/*` — o comentário
`compiler/pubspec.yaml:13-18` PROÍBE hoje ("só na fase de codegen"); ESTA LT levanta o bloqueio. ⚠️
`kernel/pubspec.yaml` tem `resolution: workspace` + `_fe_analyzer_shared: any` ⟹ pode exigir
`pubspec_overrides.yaml`; o pin (Gate 2, 72d31da) diz `pub get` autocontido — VERIFICAR o que o pin produziu
antes de editar (com dart-vm-expert). Divergência de path: spec/tasks dizem `compiler/lib/codegen/`, guard do
pin (tasks:27) diz `frontend/codegen/`; recomendo `frontend/codegen/` (resto do pkg está sob `frontend/`).

Ver [[fase7-conformance-lowering]] (type-directed pós-F5), [[types]] (7 side-tables, chão fechado erra no
desconhecido).
