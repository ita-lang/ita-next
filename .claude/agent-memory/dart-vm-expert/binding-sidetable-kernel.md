---
name: binding-sidetable-kernel
description: Validação forward-compat da side-table de resolução da Fase 4 (Binding) do ita-next contra Dart Kernel; ResolvedName → nós estáticos/VariableGet/ThisExpression e débitos de codegen (F7).
metadata:
  type: reference
---

# Fase 4 (Binding) side-table → Dart Kernel — forward-compat (validado 2026-07-12)

Fonte oracle: `compiler/lib/frontend/binding/{scope,resolver}.dart`,
`compiler/docs/spec/binding.md`, goldens `conformance/resolve/*.resolve`.
Kernel confirmado via fetch: `raw.githubusercontent.com/dart-lang/sdk/main/pkg/kernel/lib/src/ast/expressions.dart`.

## Modelo da side-table
`Map.identity<Ident|SelfExpr, ResolvedName>`; `ResolvedName` =
`LocalRes(binder, hops, captured)` | `TopLevelRes(decl)` | `SelfRes(receiver)`.
Aponta o NÓ-binder (modelo rustc `Res::Local`/`DefId`), não hops-only (Lox). Correto:
Kernel referencia var POR OBJETO.

## Nós de Kernel confirmados (fetch 2026-07-12)
- `VariableGet` tem campo `Variable variable` = **ponteiro de objeto direto** (não Reference).
  → `LocalRes.binder` → codegen mantém `binder-node → VariableDeclaration`. `hops` NÃO entra na
  emissão (só diagnóstico/captura/ADR-0011).
- Estáticos usam `Reference targetReference` (indireção via canonical name), NÃO o objeto direto:
  `StaticGet`("static field/getter/method tear-off"), `StaticSet`, `StaticInvocation`(→Procedure),
  `StaticTearOff`(→Procedure isStatic/Method), `ConstructorInvocation`(→Constructor).
  → `TopLevelRes.decl` é só a chave-identidade; codegen precisa de `Decl → Kernel Member/Reference`.
- `InstanceGet`/`InstanceInvocation` EXIGEM `interfaceTarget` (Member/Procedure, via Reference) —
  "statically known interface target". → só existe com tipo do receptor = **Fase 5**. Adiar
  `.field`/`.método` é OBRIGATÓRIO, não opcional.
- `ThisExpression`: nó-folha implícito ao Member envolvente, SEM `VariableDeclaration`.
  (não re-confirmado por fetch — arquivo truncou; canônico.) → `SelfRes` → `ThisExpression()`.

## Veredito por ponto
1. ✅ LocalRes(binder) → VariableGet(VariableDeclaration) por objeto; hops fora da emissão.
2. ✅ `captured` (`*`) é diagnóstico-only. VM faz closure-conversion nativa (Grupo B); Kernel
   referencia o `VariableDeclaration` externo DIRETO. `isLate`/`isFinal` setados na baixa da DECL
   (não no uso) → captura não muda. Ressalva: freshness da var de laço por-iteração é Grupo B
   SÓ SE codegen reter nó de laço estruturado (`ForInStatement`) — cross-ref desugar `for` debt.
3. ✅ (com mapa do codegen) TopLevelRes(decl) basta como chave; codegen dono de `Decl→Member`.
4. ✅ self→ThisExpression; ponteiro p/ nó-tipo é suficiente (usado por F5 p/ tipar `this`).
5. ✅ deferral obrigatório (interfaceTarget = Member exige tipo = F5).

## Débitos de codegen (Fase 7) — NÃO bloqueiam F4
- D1: `binder-node → VariableDeclaration` (Param/BindPattern/RestPattern).
  ⚠️ **Atualizado 2026-07-15:** em 3.12.2 `VariableDeclaration` é **sealed** com subclasses distintas
  (`LocalVariable`, `VariableStatement`, `CatchVariable`, `PositionalParameter`, `NamedParameter`,
  `ThisVariable`, `SyntheticVariable` — `pkg/kernel/lib/src/ast/variables.dart:75+`). D1 tem de
  dispatchar por subclasse: param ≠ local. Ver [[contextual-typing-slice-c]].
- D2: `Decl → Kernel Member/Class Reference` (two-pass, espelha letrec). Heterogêneo: TopLevelRes.decl
  de um `let`/`var` global é um **BindPattern** (não FnDecl) → global read = StaticGet(Field).
- D3: dispatch por FORMA do uso p/ TopLevelRes: Call→StaticInvocation; valor-nu→StaticTearOff/StaticGet;
  tipo em `Foo(...)`→ConstructorInvocation (QUAL construtor = aridade/F5).
- **D4 (modelagem): colisão de binder em record/struct homônimo.** `FieldPattern` (ast.dart:762)
  NÃO é AstNode e NÃO tem span. Homônimo `{ x, y }` → `_declareFieldPattern` liga AMBOS com
  `binder = nó-RecordPattern/StructPattern` (mesmo objeto+offset). `LocalRes.binder`/`TopLevelRes.decl`
  NÃO distinguem x de y; o dump `->L<offset>` também colide. Recuperável no codegen via `Ident.name`
  do uso (homônimo ⟹ nome-campo==nome-local==nome-uso). Alcançável por `let { x, y } = p`. Fix limpo
  futuro: dar nó/offset próprio ao FieldPattern. Já documentado no comentário do resolver. Não-bloqueante.
- D5: extension `self`. Dart lowera método de `extension` p/ Procedure ESTÁTICA com param sintético
  `#this` → self vira `VariableGet(#this)`, NÃO `ThisExpression`. Codegen dispatcha pelo KIND de
  `SelfRes.receiver` (ClassDecl→ThisExpression; ExtensionDecl/impl-foreign→#this param).
- D6 (legalidade F5/F6): resolver permite `self` em `FieldDecl.defaultValue`; Dart proíbe `this` em
  inicializador de campo de instância — verificar legalidade antes do codegen (não é problema de estrutura).

## Veredito global
Side-table PRONTA p/ codegen do ponto de vista do Kernel. Estrutura sólida (binder-node = decisão
load-bearing correta). Débitos são mapas do lado do codegen + D4 (nit recuperável).
