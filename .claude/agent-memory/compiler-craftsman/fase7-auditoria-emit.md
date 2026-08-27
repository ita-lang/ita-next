---
name: fase7-auditoria-emit
description: Auditoria técnica do emit.dart (F7, 2026-07-29) — a classe "resolução por NOME" reincide em 3 sítios; a F5 NÃO valida StructPattern.typeName (buraco de contrato); tipos não têm two-pass
metadata:
  type: project
---

# Auditoria do `codegen/lib/emit.dart` (W3, 2026-07-29)

## Buracos de CONTRATO F5→F7 (o mais durável daqui)

1. **`StructPattern.typeName` NUNCA é lido pela F5.** `check.dart:541` faz
   `_bindFieldPatterns(n.fields, t, n)` — casa os CAMPOS contra o tipo do escrutínio e ignora o nome do
   tipo escrito no pattern. Grep de `typeName` = ast/parser/printer/desugar apenas. ⟹ Qualquer emissão que
   resolva por `p.typeName` (hoje `_structFieldsFor`) está fundada numa garantia INEXISTENTE. A docstring
   do `_structFieldsFor` afirma o contrário (cita `pattern-type-mismatch`) — é afirmação falsa, não
   imprecisão.
2. **`none`/`some`/`ok`/`err` NÃO são nomes reservados de variante.** `_bindEnumPattern`
   (`check.dart:662-719`) só resolve `.x` contra `info.variants` do enum do escrutínio; um
   `enum Estado { none, ativo }` é Itá legal. ⟹ Todo despacho da F7 por `variant == 'none'|'some'|'ok'|'err'`
   ANTES de olhar o tipo do escrutínio é miscompilação silenciosa.

## A técnica que falta (régua Dragon)

- **Two-pass de módulo aplicado só a `fn`.** `emitTopLevel` faz assinaturas→corpos para `FnDecl` (correto,
  letrec), mas emite TIPO por tipo em fase única (`_struct` cria classe + campos + ctor + métodos de uma vez)
  e em ordem fixa traits→structs→enums→classes. ⟹ campo/param/retorno cujo tipo é declarado "depois"
  (qualquer struct com campo de `enum` ou de `class`) cai em `ice-codegen-type-unemitted-*`. A cura é a
  MESMA que eles já escreveram para `fn`: 1a-i cria os SHELLS (`k.Class` vazia registrada em `_classes`),
  1a-ii preenche membros. Dragon 2.7/6.3 (tabela de símbolos completa antes do uso).
- **Ordem de emissão ≠ ordem de avaliação, mas duplicar `_expr` do receptor duplica EFEITO.**
  `_assignMember` chama `receiver()` 2× no compound (`c.n += 1`). Certo para node-sharing, errado para
  side-effect: pede hoisting em `Let` temp (o mesmo remédio que o `match` já aplica ao subject).

## Régua para invariantes (`invariants.dart`)

- `checkNoSharedNodes` está OK: `RecursiveVisitor` sobrescreve `defaultNode`, e `VisitorDefault` roteia
  TODO `visitX` de `TreeNode` → `defaultTreeNode` (`visitor.dart:774-857`) ⟹ a subclasse alcança tudo que é
  `TreeNode`. Ele NÃO vê `DartType`/`Constant`/`Name` (compartilhá-los é legal) nem parent errado sem
  compartilhamento.
- `_hasDynamic` cobre menos do que afirma: falta `FunctionType.namedParameters` (e o Itá baixa TUDO named),
  e nenhum sítio checa `ConstantExpression.type` — cujo default É `DynamicType`
  (`expressions.dart:5084`). O único `DynamicType` que a emissão produz hoje é o que o invariante não olha.

Ver [[fase7-codegen-skeleton]], [[fase7-conformance-lowering]], [[audit-frontend-2026-07]] (nota de
exaustividade DESATUALIZADA — `analysis/match_analysis.dart` implementa Maranget + `match-not-exhaustive` +
`match-exhaustiveness-unsupported` honesto).
