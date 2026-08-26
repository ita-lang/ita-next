---
name: gate-design-kernel
description: Como um gate sobre Kernel tem de ser desenhado (visitor com default que FALHA, nunca lista-branca de sítios) + o escopo REAL do verifyComponent + os gates de graça já vendorados (NaiveTypeChecker, VerifyGetStaticType, CoverageVisitor, checkEquivalence) + a prova de que a VM DESCARTA functionType/resultType.
metadata:
  type: reference
---

# Desenho de gate sobre Kernel — 3.12.2 (vendor local + WebFetch VM), 2026-07-29

## 1. `RecursiveVisitor` DESCE em `DartType` — a premissa contrária é FALSA
`codegen/lib/invariants.dart:222-224` afirma *"a travessia de TreeNode NÃO desce em DartType"*. **Falso**:
`visitChildren(Visitor v)` recebe um `Visitor` (que É um `DartTypeVisitor`, `visitor.dart:1748-1754`), e os
nós chamam `type.accept(v)`:
- `InstanceGet.visitChildren → resultType.accept(v)` (`expressions.dart:618-623`)
- `InstanceInvocation.visitChildren → functionType.accept(v)` (`:1970-1976`)
- `ConstantExpression.visitChildren → type.accept(v)` (`:5101-5104`); `IsExpression` (`:3893-3896`)
- `FunctionType.visitChildren` → typeParameters + positional + **named** + returnType (`types.dart:1151-1156`);
  `NamedType.visitChildren → type.accept(v)` (`:1774-1776`); `InterfaceType` → typeArguments (`:1031-1034`)
- `DynamicType.accept(DartTypeVisitor v) => v.visitDynamicType(this)` (`types.dart:761`)
⟹ **UM** `@override void visitDynamicType(...)` num `RecursiveVisitor` cobre TODO sítio de tipo, presente e
futuro. A enumeração manual de sítios (`_hasDynamic` + 4 overrides) é desnecessária E incompleta.

## 2. Por que lista-branca manual sempre diverge — e qual é a forma correta
- `RecursiveVisitor.defaultNode(node) => node.visitChildren(this)` (`visitor.dart:2005-2012`): o default é
  **descer e CALAR**. Nó não-sobrescrito = APROVADO em silêncio. Divergência ⟹ falso NEGATIVO (a pior direção).
- A árvore é definida por pacote **externo e versionado**; a lista é interna. Não há link em tempo de
  compilação entre "nós que carregam DartType" e "overrides escritos".
- **A peça certa já existe**: `mixin VisitorThrowingMixin<R>` (`visitor.dart:1868-1876`) — `defaultNode` lança
  `UnimplementedError` nomeando o nó. Gate = `class X extends VisitorDefault<void> with VisitorThrowingMixin<void>`
  + override explícito de cada nó permitido (descer vira explícito). Grau máximo: `implements Visitor<void>`
  (`:1748`, sem defaults) ⟹ erro de COMPILAÇÃO quando o pkg/kernel ganha nó; preço ~200 métodos.
- Lista exaustiva e versionada de kinds: `pkg/kernel/lib/src/coverage.dart` (**arquivo GERADO pela SDK**) —
  `CoverageVisitor implements Visitor<void>` + enums `ExpressionKind`/`StatementKind`/`DartTypeKind`/…
  ⟹ gate "kinds no `.dill` ⊆ allow-list declarada" é ~20 linhas.

## 3. `verifyComponent` — escopo REAL (o que cobra / o que não)
Doc do próprio arquivo: *"Checks that a kernel component is well-formed. **This does not include any kind of
type checking.**"* (`verifier.dart:127-129`).
**COBRA**: pai correto (`enterParent` `:277-291` ⟹ **nó com dois pais É pego**, ressalva `_isNewModelVariable`
`:272-275`, hoje inócua porque `VariableDeclaration(...)`=`VariableStatement` que implementa
`LegacyVariableDeclaration` — `variables.dart:121-138` + `statements.dart:1660`); escopo de variável/type-param;
aridade de `Arguments`; named sorted no `FunctionType`; Field imutável×setter; dangling reference; ciclo de
typedef; const inlinado (`afterConst`).
**interfaceTarget: só 4 checagens** (`_checkInterfaceTarget` `:1604-1625`, usado por
`visitInstanceInvocation/Get/Set/TearOff` `:1628-1677`): (a) `node.name == interfaceTarget.name`,
(b) `isInstanceMember`, (c) `enclosingClass != null`, (d) não é `RepresentationField`.
**NÃO COBRA**: type-check; `DynamicType` (as 2 menções — `:1884`, `:2219` — não são gate: `dynamic` é legítimo
p/ o Kernel, a proibição é 100% do Itá/ADR-0013); **se o interfaceTarget pertence à hierarquia do receptor**
(zero `getTypeAsInstanceOf` no arquivo); `checkInitializers` vazio (`:2194-2196`); `localFunctionId`; offsets
secundários. Ver [[kernel-verifier-invariants]].

## 4. A VM DESCARTA os tipos estáticos do `.dill` (WebFetch `kernel_binary_flowgraph.cc` @3.12.2)
- `SkipDartType();  // read function_type.` (InstanceInvocation) e `SkipDartType();  // read result_type.`
  (InstanceGet) ⟹ **`functionType.returnType` errado é INVISÍVEL para a VM**; ela usa `InferredTypeMetadata`
  (escrita pela TFA, Dart-side, só em AOT).
- `interface_target` é **usado**: `H.LookupMethodByMember(itarget_name, …)` → passado ao `InstanceCall`.
⟹ Regra: **tipo estático errado no `.dill` = zero custo no JIT, custo integral em AOT/dart2js.** Só a execução
prova comportamento, e só no alvo em que se executou.

## 5. Gates de graça, vendorados, que o projeto NÃO usa (custo ~zero, sem `front_end`)
- **`NaiveTypeChecker` + `ErrorFormatter`** (`pkg/kernel/lib/naive_type_checker.dart`, `error_formatter.dart`) —
  imports SÓ pkg/kernel (`:5-9`) ⟹ **não puxa `front_end`/`analyzer`** (o conflito da spec 013 §0-A não se
  aplica). Pega interfaceTarget de classe errada: `fail('$member is not accessible on a receiver of type $type')`
  (`type_checker.dart:376`, em `getReceiverType`), aridade (`handleCall` `:396-409`), assignability.
  Ressalvas: `checkAssignable` PERMITE downcast implícito (`naive_type_checker.dart:321-326`); e para `+ - * % remainder`
  de int/num/double ele IGNORA o `functionType` e usa `getTypeOfSpecialCasedBinaryOperator`
  (`type_checker.dart:1424-1435`) ⟹ NÃO acusa `returnType: num`. `ignoreSdk: true` pula `dart:*` (`:32/:50`).
- **`VerifyGetStaticType`** (`verifier.dart:2126-2192`) — classe pública; chama `getStaticType` em toda expressão
  e explode nomeando o nó. 3 linhas.
- **`writeComponentToText(component, path:, showOffsets: true)`** (`kernel.dart:81-98`) — dump textual; usar como
  artefato de falha por fixture, não como golden churnoso.
- **Round-trip**: `writeComponentToBytes` → `loadComponentFromBytes` → verify de novo + `checkEquivalence`
  (`pkg/kernel/lib/src/equivalence.dart`, imports = ast + printer + union_find). Hoje os invariantes rodam sobre
  `emitted.libs` (árvore em memória, `compile.dart:119-125`), **não** sobre o que foi serializado.
- `ClassHierarchy(component, coreTypes, onAmbiguousSupertypes: …)` — hierarquia ambígua, que o verifier ignora.
- **NÃO existe** `--verify-ir` de CLI para `.dill` de terceiro; `pkg/front_end/tool/compile.dart --verify` compila
  Dart-fonte e puxa `front_end`. Lacuna declarada.

## 6. `int + int` deve ter tipo estático `int`, não `num` — a regra é vendorada
`TypeEnvironment.isSpecialCasedBinaryOperator` (`type_environment.dart:186-201`: `+ - * remainder %` em
int/num/double) + `getTypeOfSpecialCasedBinaryOperator` (`:217-253`: T<:int ∧ S<:int ⟹ **int**).
`InstanceInvocation.getStaticTypeInternal => functionType.returnType` (`expressions.dart:1958-1960`) ⟹ o campo É
a verdade para quem lê `getStaticType`, mas o `TypeChecker` aplica a regra especial ⟹ **`.dill` inconsistente
consigo mesmo**. `ConstantExpression(this.constant, [this.type = const DynamicType()])` (`:5084`) — o default é
`dynamic`: mesma classe de bug do `localFunctionId` (ver [[kernel-raw-api-field-hygiene]]).
⚠️ Gap: não reverifiquei o que o **CFE** escreve nesse `functionType`.
