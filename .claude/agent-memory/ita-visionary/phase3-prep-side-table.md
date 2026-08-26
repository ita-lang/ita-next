---
name: phase3-prep-side-table
description: ADR-0004 manda semântica via side-table (Map.identity nó→tipo); a AST fica imutável e SEM campos de tipo resolvido. Precedente recorrente ao revisar propostas de "adicionar campo na AST".
metadata:
  type: reference
---

# Preparo p/ Fase 3 — side-table, não campos no nó

**Regra (ADR-0004, `.specify/memory/adr/ADR-0004-fase-semantica-side-table.md`):** a fase
semântica usa uma **side-table `Map.identity()` nó→ResolvedType**; a AST imutável permanece
INTACTA (rota rustc `TypeckResults`). Regra de ouro: `UnknownType → dynamic`.

**How to apply:** ao revisar propostas de "adicionar `resolvedType`/`symbol` no nó da expr",
RECUSAR — fere ADR-0004. Tipos e resolução nome→decl (Fase 4/Binding, ADR-0011) ficam em
tabelas laterais keyed por identidade de objeto. A AST só precisa: (1) ser árvore imutável
sem nós compartilhados/interned (identidade estável), (2) zero-null — os `ErrorDecl`/`ErrorStmt`/
`ErrorExpr` já garantem placeholders bem-tipados p/ o walk do checker não achar `null`.

**Faseamento (ADR-0011):** pós-parsing = 5 fases (3 Desugaring, 4 Binding, 5 Semântica,
6 Análises/exaustividade-Maranget, 7 Codegen→Kernel). O que a Fase 2 deve ANTECIPAR na AST
p/ não haver retrabalho: nós que o desugaring (Fase 3) consome — `WhereExpr` ([[where-clause-identity]]),
e os campos das [[fase2-structural-gaps]] (init, membros async/stream, guard-let cond, conformances,
await race/all). Enum fechado de operadores idealmente antes da Fase 3.
