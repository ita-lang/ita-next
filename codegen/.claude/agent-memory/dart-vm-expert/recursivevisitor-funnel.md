---
name: recursivevisitor-funnel
description: Cadeia de despacho do RecursiveVisitor do pkg/kernel — todos os TreeNode afunilam em defaultNode (3.12.2)
metadata:
  type: reference
---

# RecursiveVisitor: todos os TreeNode afunilam em `defaultNode` (3.12.2)

`pkg/kernel/lib/visitor.dart`:
- `RecursiveVisitor.defaultNode(Node) { node.visitChildren(this); }` (2009-2011) — o sink de recursão.
- `VisitorDefault.defaultTreeNode(node) => defaultNode(node)` (1796); idem defaultDartType/defaultConstant.
- `defaultExpression/defaultStatement/defaultInitializer/defaultMember => defaultTreeNode` (849/853/855/857).
- `visitField/Procedure/Constructor => defaultMember` (630-634); statements → defaultStatement; expressions → defaultExpression.

Consequência: um visitor que sobrescreve `defaultNode` + chama `super.defaultNode(node)` roda p/ TODO TreeNode e recursa. É a base correta dos passes de saneamento (OffsetNormalizer despacha por `is` dentro do defaultNode). Overrides de `visitProcedure`/`visitFunctionExpression` etc. + `super.visitX` também recursam (via defaultMember/defaultExpression).
