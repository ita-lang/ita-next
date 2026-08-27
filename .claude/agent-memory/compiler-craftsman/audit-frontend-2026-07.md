---
name: audit-frontend-2026-07
description: Auditoria técnica F1→F6 (2026-07-17) — placar por fase e o gate F6→F7; a exaustividade de match (Maranget) é a lacuna load-bearing que trava a F7.
metadata:
  type: project
---

# Auditoria do front-end (F1→F6) — 2026-07-17

Revisão minuciosa (pediu o dono) contra Dragon Book (cap 3–6) + Crafting Interpreters.
Confrontado o código real em `compiler/lib/frontend/{lexer,parser,desugar,binding,semantic,analysis}`.

## Placar
- **F1 léxico** ✅ — maximal munch explícito, single-pass à mão (CI 4), erros não-abortantes c/ span, overflow-guard. Sólido.
- **F2 sintaxe** ✅ — recursivo-descendente + cascata de precedência (não Pratt, P4), grammar.ebnf formal, recuperação N2 (Dragon 4.1.4/4.4.5). Crash-B1 do `init`-no-início FOI corrigido (`parser.dart:132-135`).
- **F3 desugar** ✅ — AST→canônica post-order 1-walk (Dragon 5.3/6.1). guard-let RETIDO = lacuna declarada.
- **F4 binding** ✅ — scope-stack, resolve-a-nó, letrec de módulo (CI 11). Sólido.
- **F5 tipos** ✅ — collect(6.3)→check(6.5), bidirecional, subsunção em ponto único, join=id+bottom, unify Alg.6.19 (fatia D PRONTA — `unify.dart`), membros 1.6.4, coerção nº7. Débitos gated e DECLARADOS (for/builtin-member/list-pattern/struct-shorthand/operator/init-body).
- **F6 flow** ⚠️ — **lote 1 SÓ** (`flow.dart`): definite-return (JLS 14.21/8.4.7), DA (JLS 16, só var), unreachable, guard-must-exit, self-in-field-default. **Lote 2 (exaustividade Maranget + unreachable-arm) NÃO implementado** — só blueprint.

## O achado nº1 (load-bearing p/ F7)
**Exaustividade de `match` NÃO existe em NENHUM lugar do ita-next** (grep confirmou: 0 no
código; só em memória/blueprint). `check.dart:1660` delega explicitamente à F6; `flow.dart`
(lote 1) não a faz. ⟹ é regressão temporária vs oracle `ita/` (que tinha exaustividade flat)
e é o **gate DURO da F7**: spec 013 §0.6 crava "F6 implementada" e §7.4(e) diz que a F7 "confia"
na F6 p/ emitir o `match` (decision tree). Sem ela, `match` não-exaustivo chega ao codegen e
gera `.dill` que cai-do-fim → exatamente o "compila mas roda errado" que a reescrita mata.

## Débitos menores anotados
- **Doc defasada**: `driver.dart:283-284` diz "fatia D é a próxima" — D já está PRONTA (unify.dart wired).
- **Plumbing F6**: `resolution` (F4) passa por FORA do `CheckResult` (`flowProgram`, `driver.dart:356`);
  blueprint §14-L1 pede promover a campo do contrato quando a F7 aterrissar (F7 tb precisa Ident→binder).
- **F6 não é gate de `check`**: `itac flow` é comando à parte (correto hoje — não há `itac build`);
  quando a F7 nascer, `itac build` DEVE rodar F6 como gate (spec 013 §0.6 já diz).

## Ordem das fases: CORRETA
parse→desugar→bind→check→flow respeita dependências (desugar antes de bind; bind antes de check;
flow lê exprTypes c/ falha-alta I2 + gate I3 "só sobre F5 limpa"). Sem acoplamento errado.
