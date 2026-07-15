---
name: spec-005-forward-compat
description: Veredito de forward-compat com Kernel dos nós novos da spec 005 (InitDecl, traits, GuardLetStmt.condition, async member) — todos ✅, com débitos de codegen registrados
metadata:
  type: project
---

# Spec 005 (superfície declarativa Fase 2) — forward-compat com Kernel: ✅ com débitos

Avaliação de MODELAGEM (sem codegen) dos nós/campos novos em
`ita-next/compiler/lib/frontend/parser/ast.dart`. Veredito: os 4 são forward-compatible; nenhum campo
parse-only faltando. Nenhuma edição feita. Ver [[kernel-nodes]] para o grounding.

**Why:** garantir que a sintaxe de hoje não gere retrabalho quando o codegen→Kernel (Fase 7) chegar.
**How to apply:** ao chegar a Fase 7, lembrar destes 4 débitos de codegen (não de modelagem):

1. **`InitDecl(params, body)` → `Constructor`:** ✅. Sem campo faltando. Débito de codegen: HOISTAR
   `self.field = e` do body para `FieldInitializer` (campo `let` = `final`). name implícito (`''`),
   const-ness e factory-ness derivam de política via side-table (ADR-0004), não de parse.
2. **`traits: List<TypeNode>` → conformance:** ✅. `ClassDecl.superclass`→`supertype`,
   `traits`→`implementedTypes`/`mixedInType`. struct→`Class` comum (sem flag value-type no Kernel;
   semântica de valor é codegen). Débito: `extension Int: Ord` precisa de `extension type`/witness
   (Extension clássico não tem `implements`).
3. **`GuardLetStmt.condition: Expr?`:** ✅. `Expr` único já cobre `a && b && c` (Binary aninhado); não
   precisa de List. Desugar (Fase 3) → IfStatement + VariableDeclaration.
4. **`async`/`stream fn` em membro (`asyncMarker`):** ✅. Mapeia 1:1 p/ `FunctionNode.asyncMarker` de um
   `Procedure`. Idêntico a top-level.

**Débito a registrar:** política const/factory de `init` (structs querem const ctor p/ literais const) —
não precisa de campo de parse, mas precisa de ruling na Fase 3/7.
