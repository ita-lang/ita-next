---
name: kernel-verifier-invariants
description: Invariantes que o verifier do Kernel COBRA (tag 3.12.2, vendor local) — named params, type-params de extension, Field imutável, Arguments. O que a F7 tem de garantir.
metadata:
  type: reference
---

# O que o verifier do Kernel cobra — **tag 3.12.2** (vendor local)

Vendor: `ita/third_party/dart/3.12.2/pkg/kernel/lib/`. **Conferir na tag, não em `main`**
(o `case kForInStatement` já provou que comportamento é versionado).

## Named parameters — a ordem só morde no **DartType**
- `verifier.dart:1029-1037` — `visitFunctionType`: *"Named parameters are not sorted on
  function type"*. Compara com `>=` ⟹ duplicata também cai.
- **`FunctionNode.namedParameters` (declaração) NÃO precisa estar ordenada**:
  `functions.dart:179` e `:207` — `computeThisFunctionType()` faz `namedParameters.sort()`
  sozinho ao derivar o `FunctionType`.
- ⟹ ordenar no front-end é **errado**; ordenar é obrigação de quem constrói um
  `FunctionType` **à mão** — e isso acontece em **todo** `InstanceInvocation.functionType`
  (`expressions.dart:1883`, campo obrigatório).
- `Arguments.named` **não** precisa ordem: `areArgumentsCompatible` (`verifier.dart:1337-1354`)
  casa por nome. Mas **posicional só se omite do FIM** (`positional.length >=
  requiredParameterCount`) ⟹ default no MEIO (Swift/Itá) não tem imagem posicional.

## Type parameter de classe em contexto estático — **a armadilha do `extension`**
- `verifier.dart:1495-1511` — `visitTypeParameterType`: dois problemas distintos,
  *"referenced out of scope"* e *"referenced from **static context**"*.
- `classTypeParametersAreInScope = !node.isStatic` (`verifier.dart:830` Procedure, `:775` Field;
  `:906` Constructor = sempre true). `Procedure.isStatic` = `members.dart:1093`.
- **Extension member = top-level procedure** (`declarations.dart:605-608`, literal), com
  mangling `B|get#bar(A #this)` (`declarations.dart:764-777`) — e `Extension` tem
  `typeParameters` **PRÓPRIOS** (`declarations.dart:621-623`, `implements GenericDeclaration`).
- ⟹ o `T` do corpo de um extension **não pode** ser o `TypeParameter` da classe: tem de ser
  cópia fresca no `FunctionNode.typeParameters` do procedure, + substituição. Vale mesmo
  que `isStatic` fosse false — o procedure top-level nem é visitado dentro do
  `declareTypeParameters` do `visitClass` (`verifier.dart:949-959`).

## Field imutável × setter
- `verifier.dart:744-768`: `isImmutable = isLate ? (isFinal && initializer != null) : (isFinal || isConst)`;
  `isImmutable == hasSetter` ⟹ problema nos dois sentidos. Construtores: `Field.mutable` /
  `Field.immutable` (`members.dart:294` / `:320`).

## O que o verifier **NÃO** faz (não conte com ele)
- `checkInitializers(Constructor)` é **função vazia** (`verifier.dart:2194-2196`, *"TODO(ahe):
  I'll add more here in other CLs"*) ⟹ **campo non-nullable não inicializado passa**. A
  definite-assignment do `init` é 100% nossa.
- `Arguments.types` **é** conferido por aridade (`verifier.dart:1305-1314`), inclusive
  `Constructor` (usa `enclosingClass.typeParameters.length`) ⟹ a F5 tem de entregar os
  type-args resolvidos por call-site, não só o tipo do resultado.

## Field imutável × setter — a condição é SIMÉTRICA (bidirecional)
- `verifier.dart:744-768`: malformado `⟺ isImmutable == hasSetter`. Dois braços REAIS (`problem()`,
  não "só semântico"): **(fwd)** mutable+sem-setter → *"The mutable field … has no setter reference"*
  (`:761-765`); **(rev)** immutable+com-setter → *"The immutable field … has a setter reference"* (`:748-753`).
  ⟹ RED bidirecional calibrado: `Field.immutable`+`isFinal=false` E `Field.mutable`+`isFinal=true` são AMBOS malformados.
- `Field.hasSetter => setterReference != null` (`members.dart:485`); ctors `Field.mutable`(setter) / `Field.immutable`(null).

## O que `verifyComponent` NÃO pega — os furos que os passes de higiene cobrem (grep-confirmado, F7 W1 2026-07-20)
- **NÃO checa `localFunctionId`**: zero override de `visitFunctionExpression`/`visitFunctionDeclaration`
  no `verifier.dart`; o campo `.id` nunca é inspecionado. ⟹ `localFunctionId==0` PASSA o verifier.
- **NÃO checa offsets SECUNDÁRIOS**: ZERO referências a `fileEndOffset`/`fileStartOffset`/`startFileOffset`
  em `verifier.dart`. ⟹ o `-1` que causa bus error na VM é INVISÍVEL ao gate.
- **Teste geral de localização DESLIGADO**: `doTestLocation = false` (`verifier.dart:1786`). Só `checkLocation`
  (nós nomeados, `:1806-1825`) e `visitAsExpression` (`:1849-1863`) olham o offset PRIMÁRIO, e ambos com escape
  `target.verification.allowNoFileOffset`. Base `Verification.allowNoFileOffset` isenta só `Library` (`:54-55`)
  ⟹ membro sintético com primário `-1` PODE tropeçar em *"has no fileOffset"* (mais um motivo p/ normalizar `-1→0`).
  **VmTarget NÃO sobrescreve `verification`** (WebFetch `pkg/vm/lib/modular/target/vm.dart` @ 3.12.2: zero token
  'Verification' no arquivo) ⟹ herda `Target.verification => const Verification()` (`targets.dart:586`), IDÊNTICO ao
  `NoneTarget` (`:620-678`, concreto). ⟹ p/ o gate CA12 um Target mínimo `extends NoneTarget` (só `name='vm'`) é
  byte-idêntico ao VmTarget em verificação. Vendorar `pkg/vm` p/ o VmTarget PUXA `front_end`: `pkg/vm/pubspec.yaml`
  lista `front_end` em `dependencies`, e `modular/transformations/ffi/use_sites.dart` (dep incondicional do VmTarget)
  importa `package:front_end/src/{api_prototype/constant_evaluator,codes/cfe_codes}.dart`. Único divergência visível
  ao verifier: VmTarget sobrescreve `constantsBackend` (só morde em `stage>=afterConstantEvaluation` com const inlinável).
- **Assinatura**: `verifyComponent(Target, VerificationStage, Component, …)` (`:65-71`) — exige `Target` (VmTarget)
  + stage. `VerificationStage.afterModularTransformations` = *"final stage of a normal compilation"* (`:32-35`).
  Roda DEPOIS de `computeCanonicalNames` (precisa refs ligadas). NÃO faz type-check (`:128-129`).

## Interface target (side-table nº3 da F5)
- `InstanceGet` — `interfaceTargetReference` **non-nullable**, ctor pede `required Member
  interfaceTarget` (`expressions.dart:573-589`); `getNonNullableMemberReferenceGetter`
  escolhe `field.getterReference` p/ `Field` e `.reference` p/ o resto
  (`src/ast/helpers.dart:142-145`) ⟹ **a F5 não precisa distinguir getter/field reference**;
  basta o Member.
- `InstanceInvocation` pede `required Procedure interfaceTarget` (`expressions.dart:1892`)
  ⟹ campo de tipo-função chamado vira `InstanceGetterInvocation`/`FunctionInvocation`, não
  `InstanceInvocation`. Discriminador: a decl (campo vs método).
