---
name: kernel-nodes
description: Estruturas confirmadas de nós do Kernel (Constructor, Class, Extension, FieldInitializer, AsyncMarker) e seus campos exigidos — grounding para mapear AST do Itá → .dill
metadata:
  type: reference
---

# Nós do Kernel — fatos confirmados (vendor local)

Vendor autoritativo (Oracle local): `ita/third_party/dart/3.12.2/pkg/kernel/lib/src/ast/`.
Tag SDK **3.12.2** (o "v130" do ADR-0003 é a versão do formato binário, não a tag). Ler daqui é
Classe A — é o formato real com que o codegen fala. Não chutar; conferir o `.dart` do vendor.

## Constructor (`members.dart:558`)
Campos EXIGIDos: `FunctionNode function` (params posicionais/nomeados + body + returnType + asyncMarker
+ typeParameters), `List<Initializer> initializers` (lista de inicializadores SEPARADA do body),
`Name name` (pode ser `''` = construtor sem nome), flags `isConst/isExternal/isSynthetic/isErroneous`.
- **`init` do Itá = generative `Constructor`.** **factory NÃO é `Constructor`** — é `Procedure` com
  `ProcedureKind.Factory` (`members.dart:1345`). Distinção real no Kernel, mas Itá só emite uma das duas
  a partir de `init` (sem sintaxe de factory), então não precisa de flag em parse-time.

## Initializer / FieldInitializer (`initializers.dart`)
`sealed Initializer`: `FieldInitializer` (`field = value` NA lista de inicializadores), `SuperInitializer`
(`super(...)`), `RedirectingInitializer` (`this(...)`), `LocalInitializer`, `AssertInitializer`.
- **`FieldInitializer` (`initializers.dart:105-113`)**: doc diz explicitamente que é a atribuição da LISTA
  de inicializadores, "nada a ver com initializer de declaração-de-campo (`Field.initializer`)".
- **Consequência p/ Itá (imutável-por-default):** campo `let` → `Field` `final`. A inicialização de campo
  final pertence à lista de inicializadores (`FieldInitializer`), não a `self.f = e` no body. Codegen deve
  HOISTAR `self.field = e` do body Block do `InitDecl` para `FieldInitializer`s. Toda info (campo, valor,
  span) está no body AST — recuperável, sem campo faltando em parse.

## Class (`declarations.dart:26`)
Conformance: `Supertype? supertype` (extends, 1), `Supertype? mixedInType` (with, 1 mixin direto),
`List<Supertype> implementedTypes` (implements, N). Múltiplos mixins → cadeia de classes anônimas
sintéticas `_Z&A&B` (`declarations.dart:129-141`), gerada pela CFE/codegen.
- Flags: Abstract, Enum, AnonymousMixin, EliminatedMixin, MixinDeclaration, HasConstConstructor, Macro,
  Sealed, MixinClass, Base, Interface, Final. **NÃO existe flag "struct"/"value type".**
- **struct do Itá → `Class` comum.** Semântica de valor (cópia, `==`/`hashCode` estrutural, copy-with) é
  100% realizada por codegen, não representada no Kernel. `traits` → `implementedTypes` (interface) ou
  `mixedInType`/cadeia (trait com default methods) — decisão semântica da Fase 3.

## Extension vs ExtensionTypeDeclaration (`declarations.dart:609 / :838`)
- `Extension` tem `onType` + `memberDescriptors`, **SEM `implementedTypes`/`implements`** — um `extension`
  Dart clássico NÃO declara conformance de interface.
- `ExtensionTypeDeclaration` (Dart 3 `extension type`) TEM `List<TypeDeclarationType> implements`
  (`declarations.dart:890`).
- **`extension Int: Ord` do Itá:** o `: Ord` não cabe num `Extension` clássico. Codegen deve escolher
  `extension type` (tem `implements`) ou witness-table/dispatch, ou retrofit tipo `impl`. Decisão de
  Fase 7 — `ExtensionDecl.traits` captura a intenção no nível sintático.

## Expression-com-bindings: Let / BlockExpression (`expressions.dart`)
- **`Let(VariableDeclaration variable, Expression body)` (`:5152`)**: UM binding (variable DEVE ter
  initializer) + `body` que é uma Expression. Encadear `Let(v1, Let(v2, … value))` = N bindings. Tipo
  estático = tipo do `body`.
- **`BlockExpression(Block body, Expression value)` (`:5211`)**: um `Block` de statements SEGUIDO de uma
  `value` Expression. É o análogo EXATO de `WhereExpr(value, bindings)` do Itá. Tipo estático = tipo de
  `value`.
- **`WhereExpr` do Itá → um dos dois.** `V where { let x=e; … }` baixa (Fase 3) para `Let`-chain OU
  `BlockExpression`. Ordem topológica por dependência (spec 006 §3.6) é TRANSFORMAÇÃO da Fase 3 derivada da
  AST (quais idents cada binding referencia — fato da Fase 4), NÃO campo do nó. Nenhum campo parse-time
  faltando. `var` binding = `VariableDeclaration` não-final (representável).

## Operadores → NÃO há nó "operador" no Kernel (todo op vira call resolvida)
- `InstanceInvocation(kind, receiver, Name, Arguments, functionType, interfaceTargetReference)`
  (`:1850`) — aritmética/relacional/`~`. EXIGE `interfaceTarget`+`functionType` RESOLVIDOS (pós-Fase 5).
  `DynamicInvocation` (`:1699`) p/ receptor `dynamic`.
- `EqualsCall(left, right, {functionType, interfaceTarget})` (`:2471`) — `==` (especial no Kernel).
  `EqualsNull` (`:2419`) p/ `== null`. `!=` → `Not(EqualsCall)`.
- `&&`/`||` → `LogicalExpression` (curto-circuito, NÃO é call). `??` (coalesce), `|>` (pipe), `>>`
  (compose), `**` (pow) → SEM operador no Kernel: viram desugaring/call. Por isso o **enum fechado**
  (spec 006) é acerto: a variante é TAG sintática; o alvo Kernel é derivado no codegen (Fase 7) por tipos.
  ⚠️ `>>` do Itá = COMPOSE (closure `(x)=>g(f(x))`), NÃO bit-shift Dart — o enum evita a confusão que
  `op:string ">>"` permitiria.
- **Compound assign (`+=` etc.)**: Kernel não tem `+=` (é get+op+set). `Assign(op, target:Expr, value)`
  preserva o lvalue como Expr completa → codegen inspeciona a forma (Ident→`VariableSet`; Member/Index→
  hoist receptor 1× via `Let` + `InstanceGet/InstanceSet` `:551`/`:878`). Single-eval de receptor/índice é
  débito de Fase 7, recuperável.

## AsyncMarker (`functions.dart:306`)
`enum { Sync, SyncStar, Async, AsyncStar }` (ordem fixa — frontends dependem). `FunctionNode.asyncMarker`.
- Itá `AsyncMarker { sync, async, asyncStar }`: sync→Sync, async→Async, `stream fn`→asyncStar→AsyncStar
  (retorna `Stream`). `syncStar` fica fora (Itá não expõe gerador lazy). Método = `Procedure(kind: Method)`
  cujo `function.asyncMarker` carrega o marcador — idêntico a `fn` top-level. async*/Stream roda em
  VM/AOT e dart2js (sem risco de paridade além do usual).
