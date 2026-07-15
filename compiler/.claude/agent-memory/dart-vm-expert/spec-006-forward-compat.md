---
name: spec-006-forward-compat
description: Veredito de forward-compat com Kernel dos nós novos da spec 006 (WhereExpr + enums BinaryOp/UnaryOp/AssignOp) — todos ✅, sem edição; débitos de codegen p/ Fase 3/7
metadata:
  type: project
---

# Spec 006 (where-expr + operadores tipados) — forward-compat com Kernel: ✅ sem edição

Avaliação de MODELAGEM (sem codegen) em `ita-next/compiler/lib/frontend/parser/ast.dart`.
Veredito: os 3 pontos são forward-compatible; nenhum campo parse-only faltando. Nenhuma edição.
Grounding em [[kernel-nodes]] (Let/BlockExpression/InstanceInvocation/EqualsCall).

**Why:** garantir que a modelagem de hoje não gere retrabalho na Fase 3 (desugaring, ADR-0011) nem na
Fase 7 (codegen→Kernel).
**How to apply:** ao chegar a Fase 3/7, lembrar destes débitos (de codegen, não de modelagem):

1. **`WhereExpr(value, List<Stmt> bindings)` → `Let`-chain OU `BlockExpression`:** ✅. Bindings em
   ordem-fonte; ordenação topológica por dependência é transformação da Fase 3 (derivada da AST + fato de
   binding da Fase 4), NÃO campo. `var` binding representável (VariableDeclaration não-final). Pureza =
   check Fase 3.
2. **enums `BinaryOp`/`UnaryOp`/`AssignOp` → ops do Kernel:** ✅ e AJUDA (switch exaustivo variante→
   emissão; printer reconstrói o símbolo, nada perdido vs string). Kernel NÃO tem nó "operador" — tudo
   vira call resolvida. Variantes SEM operador direto no Kernel (o enum captura bem, ADR-0011 as lista):
   `|>` pipe→aplicação `f(x)`; `>>` compose→closure `(x)=>g(f(x))` (NÃO bit-shift Dart!); `??` coalesce→
   `Let`+null-check; `**` pow→StaticInvocation (Dart não tem `**`). `~` bitNot→`InstanceInvocation '~'`
   (Dart int tem `operator ~`; §5 da spec omitiu `~`, código inclui — divergência já registrada, inócua).
3. **`Assign(assignOp, target:Expr, value)` composto:** ✅. `target` como Expr completa preserva o lvalue;
   codegen expande get+op+set inspecionando a forma. Débito Fase 7: single-eval de receptor/índice
   (`a[f()] += 1` chama `f()` 1×) via `Let`-hoist. Mutabilidade (`+=` só em `var`) = check Fase 5/6.

**Notas:**
- Mapa `Tag→enum` do parser (`parser.dart:1417-1442`) é FECHADO e casa 1:1 c/ os enums — não há `Binary`
  que o parser construa sem variante. Sem operadores bitwise BINÁRIOS no enum (`& | ^ <<`): bitwise do Itá
  (spec 001) é via método/fn, não op — fora do escopo 006. `%= ??= **=` também ausentes de AssignOp
  (aditivos futuros; o switch exaustivo sinalizaria todo site).
- Paridade VM×JS (ADR-0005): `pow`/`**` e bitwise (via métodos int) carregam a preocupação numérica usual
  (spec 001). `>>` compose = closures puras, SEM risco de paridade. Não é modelagem de 006 — flag p/ Fase 7.
