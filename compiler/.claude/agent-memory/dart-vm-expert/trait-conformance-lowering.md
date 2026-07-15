---
name: trait-conformance-lowering
description: Lowering de conformance de trait para Kernel — o Kernel NÃO tem default method, mixedInType é descartado pela VM, conformance retroativa em tipo foreign é impossível, e a CHA da VM funciona para interfaces (implementor_cid)
metadata:
  type: reference
---

# Conformance de trait → Kernel (fatos provados, tag 3.12.2)

Vendor: `ita/third_party/dart/3.12.2/pkg/kernel/lib/`. Runtime C++ **não** vendorizado → via
`raw.githubusercontent.com/dart-lang/sdk/3.12.2/...` (sempre a TAG).

## 1. Membro de conformance TEM de estar dentro da `Class`. Não há default method no Kernel.
`Resolver::ResolveDynamicAnyArgsWithCustomLookup` (`runtime/vm/resolver.cc`) sobe **só** por
`cls.SuperClass()`; nunca consulta `interfaces()`. ⇒ `implements`/`implementedTypes` transporta
**tipo, nunca corpo**. Isto é a diferença estrutural com JVM (default methods desde Java 8) e CLR
(DIM do C# 8): **Scala/Kotlin têm a topologia "corpo na interface"; o Itá NÃO tem.**
- Procedure top-level (o lowering de `extension`, `B|bark(A #this)`): `isInstanceMember => !isStatic`
  = false (`members.dart:1198`) e `enclosingClass => parent is Class ? … : null` = null
  (`members.dart:63`). `verifier.dart:1604-1625` (`_checkInterfaceTarget`) barra ambos.
- Do lado da VM não é o verifier que barra (a VM não roda o verifier): `BuildInstanceGet/Set/Invocation`
  faz `H.LookupMethodByMember(itarget_name, …)`; `EnclosingName` tem
  `ASSERT(IsLibrary(enclosing) || IsClass(enclosing))` e `LookupClassByKernelClass` assume `IsClass`
  (`runtime/vm/compiler/frontend/kernel_translation_helper.cc`).
- Modo de falha em silêncio: `StaticInvocation` para `b.bark()` com `b: Barker` roda e chama o
  **default**, ignorando o override de `D`. Sem erro. Resultado errado.

## 2. `Class.mixedInType` é INÚTIL — a VM lê e joga fora
`ClassHelper::ReadUntilExcluding` (`kernel_translation_helper.cc`): `case kMixinType: … SkipDartType()`.
`KernelLoader::LoadPreliminaryClass` (`runtime/vm/kernel_loader.cc`) faz
`class_helper->ReadUntilIncluding(ClassHelper::kMixinType);` e segue — nunca copia membro nenhum.
Só `if (class_helper->is_transformed_mixin_application()) { ASSERT(interface_count > 0); … }`.
- Quem elimina: `pkg/vm/lib/modular/transformations/mixin_full_resolution.dart` — "Replaces all mixin
  applications with regular classes, **cloning all fields and procedures from the mixed-in class**,
  cloning all constructors from the base class"; ao fim: `implementedTypes.add(mixedInType!);
  mixedInType = null; isEliminatedMixin = true;`. Rodado por `performModularTransformationsOnLibraries`
  em `pkg/vm/lib/modular/target/vm.dart` — **pipeline que o Itá bypassa**.
- ⇒ Emitir `mixedInType` = método some em runtime (NoSuchMethod). **O `MixinFullResolution` é a
  receita, não o mecanismo**: o Itá tem de clonar/forwardar ele mesmo.
- `class_finalizer.cc` (`ClassHiearchyUpdater::Register`) confirma:
  `mixin_index = cls.is_transformed_mixin_application() ? interfaces_.Length()-1 : -1`.

## 3. Conformance retroativa em tipo foreign é ESTRUTURALMENTE impossível
`binary.md:243-272`: `Library` contém `List<Class> classes` inline; `binary.md:312-339`: `Class`
contém `List<Procedure> procedures` inline. Não há como emitir um Procedure numa Class de outra
Library sem reemitir a Library inteira. E se reemitir: `KernelLoader::LoadLibrary` faz
`if (library.Loaded()) return library.ptr();` — **a VM descarta a nossa versão em silêncio**.
⇒ o Itá **herda a orphan rule do Rust de graça**. Não é escolha de design.
- Saídas que NÃO servem: `Extension` (sem `implementedTypes`, vira Procedure top-level, a VM nunca
  despacha por ele); `ExtensionTypeDeclaration.implements` (`declarations.dart:890`) — a spec
  (`language/accepted/3.3/extension-types/feature-specification.md`) exige que o rep type JÁ seja
  subtipo da superinterface não-extension (circular) e "At run time … there is _no_ reification of
  `V` associated with `o`" (erasure serializada: `ast_to_binary.dart:2563`).
- Saída que serve: **wrapper/newtype** (`class OrdInt implements Ord { final int v; … }`) — paga
  alocação e perde a subsunção. Dictionary/witness passing é possível mas mata a subsunção e é
  mágica invisível (contra P4).

## 4. A CHA da Dart VM FUNCIONA para interface — a lição do Scala NÃO transfere
`runtime/vm/compiler/cha.h` / `cha.cc`:
```cpp
// Return true if there is only one concrete class that implements 'interface'.
static bool HasSingleConcreteImplementation(const Class& interface, intptr_t* implementation_cid);
```
usa `interface.implementor_cid()`; se != kIllegal/kDynamic → devirtualiza, guardando com
`AddToGuardedClassesForImplementorCid` sob `FLAG_use_cha_deopt` (JIT, deopt quando surge 2º
implementador) **ou** `all_classes_finalized()` (AOT, mundo fechado). `implementor_cid` é populado
por `ClassHiearchyUpdater::Register` → `MarkImplemented` + `AddDirectImplementor` +
`NoteImplementor`, lendo `cls.interfaces()` = nosso `implementedTypes`.
⇒ HotSpot 2016 "disables CHA altogether for default methods" (regressão de 20-40% do Scala) **não
tem análogo no Dart**: aqui a interface é otimizável, e não há default method para desabilitar CHA.
- **Não existe pragma de dispatch.** Lista exaustiva de `runtime/docs/pragmas.md` não tem nada de
  devirtualização/CHA/sealed. `vm:prefer-inline`/`vm:never-inline` agem no ALVO, depois de
  devirtualizado. `has_dynamically_extendable_subtypes()` desliga a CHA (dynamic modules).

## Ferramenta de graça (Grupo B) que pegaria tudo isso em CI
`verifyComponent(Target, VerificationStage, Component, {skipPlatform, librarySkipFilter})`
— `pkg/kernel/lib/verifier.dart:65-79`. A VM não roda o verifier; nós deveríamos.

## Lacunas declaradas
- `TypeTranslator::BuildTypeInternal` para `kExtensionType` no lado VM: não localizado (WebFetch
  trunca `kernel_translation_helper.cc`). A spec da linguagem já é decisiva.
- `dart2js_target.dart`: não verifiquei se roda mixin_full_resolution. A conclusão "membro dentro da
  Class" é neutra nos 3 alvos de qualquer forma.
- Se `dart compile exe` sobre um `.dill` pré-existente roda o pipeline modular do `pkg/vm`: não
  verificado.
