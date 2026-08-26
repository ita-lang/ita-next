---
name: parsing
description: Decisões técnicas de parsing do Itá (Fase 2) — cascata de precedência, 8 cantos de desambiguação, recuperação N2
metadata:
  type: project
---

# Parsing — Itá Fase 2 (spec 004)

## spec 005 — superfície declarativa (implementada; DB cap 4.2–4.3)
Fechou 4 lacunas de paridade com o oracle `ita/` (só sintaxe, sem semântica; "AST representa, não valida").
- **`InitDecl(param* params, block body)`** — construtor `init(...) { … }`. Despacho por `Tag.kwInit` em
  `_member` (k=1, LL(1)); `init` NÃO entra em `_declaration` (top-level `init` segue `expected-declaration`).
  Nó sem `isPublic` (pub antes de init é dropado — sem CA). Adicionado a `_isMemberStart` (FIRST de membro).
- **`GuardLetStmt += expr? condition`** — o `&&`-refino. Técnica escolhida: **greedy `_expression()` + split do
  `&&` de TOPO** (reusa nível 5 `_and`): se `refined is Binary && op=='&&'` → value=left, condition=right; senão
  condition=null (CA7). **Alternativa rejeitada:** parsear value com `_equality` (nível 6) p/ parar antes do
  `&&` — quebraria value com `??`/`||` (níveis 3–4, mais frouxos). Quirk conhecido (sem CA): multi-`&&`
  (`opt && a && b`) põe `a` dentro do value (left-assoc); aceitável.
- **Conformances inline** (`StructDecl/ExtensionDecl += type* traits`; `ClassDecl` já tinha `superclass`, += traits).
  Helper `_conformances()` = `( ":" type ( "," type )* )?` chamado em struct/class/extension. Papel por POSIÇÃO
  (sem lookahead): em `class`, 1º type=superclasse, resto=traits (GRAMMAR.md §2); em struct/extension todos=traits.
- **Dump** (printer): `(init (params …) (block …))`; `(traits (type …)…)` após generics/extends, antes dos membros;
  `(cond …)` no guard-let quando `condition!=null`. **Risco de golden:** a CA1 da spec escreve `(member (self) …)`
  mas o printer dumpa `SelfExpr` como `self` bare → golden real é `(member self "name")` (spec imprecisa, não bug).
- **CA6** (`async fn` como membro) já funcionava no parser (`_fnDecl` trata marker); só a `grammar.ebnf` precisava
  refletir (`member`/`enumMember` += `("async"|"stream")?`).


**Decisão-âncora (D0):** parser de expressões = cascata de precedência recursivo-descendente estilo jlox
(CI 6.2 — uma função por nível de `GRAMMAR.md` §4.2), **NÃO** Pratt table-driven (clox CI 17.5–17.6).

**Why:** P4 (sem mágica) — o nome de cada função É o nível de precedência, verificável 1:1. Tabela numérica
esconde precedência. Trade-off aceito: ~13 frames/folha (vigiado por benchmark-guard).

**How to apply:** ao revisar W3, cobrar "uma função por nível"; recursão à esquerda eliminada por iteração
(loop no operador), não por chamada recursiva do mesmo nível.

## Rulings do dono (§0.6)
- **D1:** bloco-nu `{…}` NÃO é expressão (Swift-like). `{` em pos-expr → map ou trailing-closure (2 leituras,
  sem backtrack). `BlockExpr` do oracle removido. (CI 8.2.1: dois níveis de precedência stmt/expr.)
- **D2:** type-args no call-site = inference-only permanente (sem turbofish). `<` em pos-expr = sempre
  comparação. Papel por posição (DB 4.3.1), desambiguação O(1), evita lookahead ilimitado do C++.
- **D3:** `pub` sem sentido (`impl/extension/import/operator`) → `parse-error: meaningless-pub` (error
  production, DB 4.1.4). No ASDL: esses decls NÃO têm campo `isPublic`.
- **D4:** `await`/`spawn` ligam no nível unário (12), não guloso. `await a + b` = `(+ (await a) b)`.

## 8 cantos — todos k≤2 fixo ou estado de parser (nenhum scan-ahead)
dangling-else (k=1, CI 9.2), `<` genérico (posição), `{` map/block (posição), if/match expr/stmt (dispatch
por posição), struct-pattern `IDENT{` (k=2), `await race/all` (k=2 lexeme), trailing-closure mesma-linha
(`Token.line` + supressão via flag `_noTrailingClosure`; `guard` NÃO suprime), token-split `>>`→`>`+`>`
(rewrite in-place, local a tipos, DB 4.4). Único scan-ahead ilimitado = `_isClosureStart` (§3.4, mantido).

## Recuperação N2 (nó→nó, sem cascata)
Panic-mode + sync-sets (DB 4.1.4 + 4.4.5; CI 6.3.1/6.3.3/8.2.2). ENXERTA `Error*` bem-tipado (não `null`,
divergência do oracle que faz throw+lista). Boundaries: FIRST-de-stmt / FIRST-de-decl. Reusa o `_synchronize`
do oracle trocando throw por enxerto.

**Correções vs oracle (marcadas nos goldens):** CA9 (`?? / ||` — golden da spec §11 invertido; correto
`(?? a (|| b c))`, GRAMMAR §4.2 é normativa > spec), CA10 (`range-non-associative` novo), CA13 (mesma-linha
no `_finishCall`), CA19 (await forte), CA20 (interpolação parse-time), CA22 (meaningless-pub), CA23 (bloco-nu).

## Revisão adversarial W3 (parser.dart) — achados
- **BLOQUEADOR — crash em `parseProgram`:** o `catch` calcula `_previous()` (span do `ErrorDecl`) ANTES da
  garantia de progresso, e `_synchronizeDecl` pode retornar sem avançar (token ofensor é ele próprio um
  decl-keyword — ex. `kwInit`, que está em `_isDeclKeyword` mas NÃO no `switch` de `_declaration`). Arquivo
  começando com `init` ⇒ `_current==0` ⇒ `_previous()` = `tokens[-1]` ⇒ RangeError (viola "nunca lança"/M2).
  Meio-de-arquivo ⇒ `ErrorDecl` com length NEGATIVO. Raiz: `_synchronizeDecl` não faz o advance-do-ofensor
  que o oracle faz (`_synchronize` l.2313). Fix: avançar ≥1 token antes do span + clamp.
- **AJUSTE:** (a) `_noTrailingClosure` é bool global, não resetado ao entrar em `(...)`/`[...]`/call-args ⇒
  suprime closures LEGÍTIMAS aninhadas na condição (`while xs.filter { $0 }.count > 0 {}` mis-parseia). Fix
  Swift/Kotlin: resetar flag dentro de brackets. (b) recuperação de bloco ausente (`_block`/`_typeBody` sem
  try/catch) ⇒ erro interno cascateia até decl-boundary, engole `}` (oracle resolve com sync-frame +
  `_boundaryClosers`; débito Fatia-2). (c) `_synchronizeDecl` sync-set incompleto: top-level aceita stmts mas
  só para em decl/let/var (falta return/if/while/for/guard/…); DB 4.4.5 FIRST-de-stmt. (d) `_consumeTypeGt`
  no caso `gtGt` não avança ⇒ `_lenFrom` do generic INTERNO exclui seu `>` (span curto 1 byte; math do
  rewrite está correta). (e) `_matchExpr` usa `do/while(_match(comma))` ⇒ EXIGE vírgula entre arms; oracle
  tolera newline (`while(!rbrace)`); inconsistente com `_enumDecl`. (f) `_letStmt` exige `= value` p/ let E
  var; oracle deixava opcional (confirmar GRAMMAR p/ `var x: T` sem init).
