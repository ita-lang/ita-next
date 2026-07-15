---
name: struct-copywith-init
description: Contrato Kernel para struct/init memberwise/copy-with — Arguments TEM named (matching por nome), FunctionType.namedParameters DEVE ser ordenado, Field tem 3 References, Field.immutable vs .mutable é verificado
metadata:
  type: reference
---

# struct / init memberwise / copy-with → Kernel (vendor 3.12.2)

## Named args existem — não há mapeamento label→posição
`Arguments` (`expressions.dart:1533`) = `{List<DartType> types, List<Expression> positional,
List<NamedExpression> named}`. `NamedExpression(String name, Expression value)` (`:1634`).
`areArgumentsCompatible` (`verifier.dart:1337-1354`) casa named **por nome** (busca linear,
ordem irrelevante) e só checa: `positional.length >= requiredParameterCount`,
`positional.length <= positionalParameters.length`, e que todo named arg exista como named param.
⇒ **Não existe** exigência de "posicionais na ordem do construtor". `init(x:, y:)` → Constructor com
`namedParameters`; call-site usa `NamedExpression`. **Nenhuma side-table de label→posição.**
⚠️ Ele **não** checa se os named *required* foram todos passados — verifier não pega esse erro.

## ⚠️ ARMADILHA: duas ordens diferentes
- `FunctionNode.namedParameters` (`functions.dart:43`) = ordem de declaração, sem exigência.
- `FunctionType.namedParameters` **DEVE estar ordenado alfabeticamente**: `computeThisFunctionType`
  faz `namedParameters.sort()` (`functions.dart:179`) e o verifier rejeita
  "Named parameters are not sorted on function type" (`verifier.dart:1030-1037`).
⇒ `TypeInfo.fields` (ordem-fonte) e `TypeInfo.init : FunctionType` (alfabética) **divergem**.
Nunca zipar `fields[i]` com `init.namedParameters[i]` — corrompe silenciosamente.

## Field tem TRÊS References (`members.dart:267-292`)
- `getterReference` → alvo de `InstanceGet`/`StaticGet`/`SuperPropertyGet`
- `setterReference` → alvo de `InstanceSet` (**nullable**)
- `fieldReference` (= `super.reference`) → alvo de `FieldInitializer` e chave de `InstanceConstant`
- `Member.reference` em Field é **@Deprecated** (`:285`) — não usar.

## Field.immutable vs Field.mutable é VERIFICADO
`Field.immutable(...)` (`:320`) força `setterReference = null` (`:335`); `hasSetter => setterReference
!= null` (`:485`). Verifier (`:744-747`):
```
bool isImmutable = node.isLate ? (node.isFinal && node.initializer != null)
                              : (node.isFinal || node.isConst);
if (isImmutable == node.hasSetter) { problem(...) }
```
⇒ campo `let` do Itá → `Field.immutable(isFinal: true)`. Passar `isFinal: true` no `Field.mutable`
cria setter e **quebra o verifier**. `let`/`var` por campo tem de chegar na F7.

## Defaults de parâmetro
Verifier (`:1005-1016`): "An optional named parameter is expected to have a default value
initializer, defined or synthesized". ⇒ named param ou é `isRequired: true`, ou tem
`VariableDeclaration.initializer`. Campo com default (`x: Int = 0`) → default vai no **initializer do
PARÂMETRO**, não em `Field.initializer` (que rodaria p/ toda instância e colide com `FieldInitializer`
de campo final). `FieldInitializer` então lê `VariableGet(param)`.

## copy-with NÃO pode depender de defaults
`p.{ y: 9 }` deve emitir **todos** os campos: `P(x: p.x, y: 9)`. Omitir `x` pegaria o *default*, não
`p.x`. Receptor avaliado 1× → `Let(tmp = p, ConstructorInvocation(P, types:[...],
named:[x: InstanceGet(tmp,'x',getterReference), y: 9]))`.
`arguments.types.length` deve ser **exatamente** `target.enclosingClass.typeParameters.length`
(`verifier.dart:1305-1314`) ⇒ F7 precisa do `InterfaceType` do RECEPTOR com type-args.

## SuperInitializer: verifier não checa; EMITIR MESMO ASSIM
`checkInitializers(Constructor)` (`verifier.dart:2194-2196`) está **VAZIO** (`// TODO(ahe): I'll add
more here in other CLs.`). Fetch do `kernel_binary_flowgraph.cc` @3.12.2 diz que `BuildInitializers`
não exige Super/Redirecting nem tem fallback implícito — **mas é claim negativo de fetch, baixa
confiança; não verificado**. A CFE sempre emite `SuperInitializer` explícito. Regra: **emitir sempre**.
Com `Object` daria certo por acaso (ctor vazio); com herança real, omitir = pular a inicialização do
pai silenciosamente.

## deeply-immutable e struct
`runtime/docs/deeply_immutable.md`: `@pragma('vm:deeply-immutable')` exige campos deeply-immutable ou
função, `final`, non-late; classe `final`/`sealed`; subtipos e supertipo deeply immutable.
`struct P { x: Int, y: Int }` **qualificaria** (ganha compartilhamento entre isolates do mesmo grupo —
Grupo B). Struct com campo `List` **não** (List não é deeply immutable). É **opt-in, reforço** —
não usar como razão de design de struct.
