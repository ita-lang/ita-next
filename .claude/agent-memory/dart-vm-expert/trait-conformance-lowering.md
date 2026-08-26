---
name: trait-conformance-lowering
description: Fatos verificados (2026-07-16, tag 3.12.2) para a decisão de lowering de conformance de traits — mixin machinery, TFA por opção, restrições de int/String/bool, dedup de código AOT, pragmas VM×dart2js.
metadata:
  type: reference
---

# Lowering de conformance de traits — fatos verificados (tag 3.12.2)

Derivação assinada (Art. IV-6b) entregue em 2026-07-16 para o ADR `proposed` da conformance.
Cadeia-mãe re-confirmada: ver [[f5-export-contract]] (linhas exatas batem na 3.12.2).

## Mixin machinery — quem achata, e ONDE
- `pkg/vm/lib/modular/transformations/mixin_full_resolution.dart` (@3.12.2, GitHub — **não está no
  vendor**, que só tem `kernel` + `_fe_analyzer_shared`): "Replaces all mixin applications with regular
  classes, **cloning** all fields and procedures" via `CloneVisitorWithMembers`; ao fim `mixedInType =
  null; isEliminatedMixin = true`. Chamada por `VmTarget.performModularTransformationsOnLibraries`
  (`pkg/vm/lib/modular/target/vm.dart`) — pipeline da CFE que o **Itá bypassa**.
- **A VM NÃO achata**: `runtime/vm/kernel_loader.cc::LoadPreliminaryClass` só lê o flag
  `is_transformed_mixin_application` e pula `kMixinType` — assume front-end já clonou. ⟹ `.dill` do
  Itá com `mixedInType` cru = membros do mixin **não existem** na classe em JIT. Opção "mixin
  application" colapsa em "clonar nós mesmos".
- `binary.md:312-339` (vendor): nó `Class` tem flags `isEliminatedMixin` etc.; `:327-328`: *"For
  transformed mixin application classes (isEliminatedMixin), original mixedInType is pulled into the
  end of implementedClasses"*. Campo chama-se **`implementedClasses`** no binário.
- `mixin_deduplication.dart` roda em `runGlobalTransformations` (`pkg/vm/lib/kernel_front_end.dart`),
  **antes** da TFA (ordem: dynamic_interface_annotator → mixin_dedup → UCE → globalTypeFlow → …).
  `compileToKernel` tem caminho `fromDillFile != null → loadKernel(...)` (input .dill suportado no
  gen_kernel; se o CLI `dart compile exe foo.dill` aciona exatamente esse caminho, não verifiquei).

## ProcedureStubKind — o manual do CFE para corpos não-herdados (`members.dart:713-900`)
- `implements` **nunca** herda corpo; o CFE resolve com (a) clonagem (mixins) ou (b) stubs:
  `ConcreteForwardingStub` `=> super.method1(o)` (`:745-770`), `NoSuchMethodForwarder` (`:772-800`),
  `ConcreteMixinStub` `=> super.method()` (`:863-893`). `:855-856`: *"after loading from a VM .dill
  (which clones all mixin members)"*.

## Verifier — o que cobra/não cobra em membros dentro da Class
- Cobra: parent pointer (`verifier.dart:277-287`); flags coerentes (`:812-826` redirecting factory,
  `:831-833` abstract+external, `:834-876` stub flags); `isExtensionMember` setado ⟹ reference TEM de
  estar num `Extension.memberDescriptors` da library (`:686-693` `_findExtensionMember`) — membro
  movido pra Class **não pode** carregar esse flag; aridade de `InterfaceType` (`:1521-1527`).
- **NÃO cobra NADA de supertypes**: zero matches p/ `supertype|implementedTypes|mixedInType` no
  verifier — nem aridade do `implements`, nem completude (classe concreta sem membro do interface
  passa; vira NSM em runtime — caminho exato não verificado). Completude é 100% da F5.
- Duplicata homônima na mesma Class estoura na SERIALIZAÇÃO: `canonical_name.dart:198-223`
  `bindTo` lança `"$this is already bound to …"`.

## Foreign: int/String/bool (@3.12.2, sdk/lib/core/)
- `abstract final class int extends num` + doc *"Classes cannot extend, implement, or mix in `int`"*;
  `abstract final class String implements Comparable<String>, Pattern` + *"cannot be extended or
  implemented"*; `final class bool` + *"compile-time error … extend or implement bool"*.
- É regra de **linguagem** (CFE): `class_finalizer.cc` **não re-checa** (busca por cannot
  extend/implement/denylist = zero; outros pontos da VM não descartados). Emitir `implements int` via
  Kernel direto = UB (Smi/Mint cids, intrinsics). E mecanicamente: `implementedClasses` vive no nó
  `Class` da library declarante (vm_platform.dill); o .dill do Itá só tem
  `ClassReference{CanonicalNameReference}` (`binary.md:201-204`) ⟹ impossível editar de fora.
- Extension type NÃO serve p/ subsunção: *"At run time, there is absolutely no trace of the extension
  type"*; `is`/`as` veem o tipo de representação (dart.dev/language/extension-types).

## TFA/AOT — custos por forma
- Invocations keyed por (selector, args) com context-sensitivity limitada:
  `maxDirectInvocationsPerSelector` / `maxInterfaceInvocationsPerSelector`; excedeu ⟹ *"approximate
  extra invocations with a single invocation with raw arguments"* (`type_flow/analysis.dart` @3.12.2).
- Dedup de código: `runtime/vm/program_visitor.cc::DedupInstructions` — JIT funde Instructions
  byte-idênticas *"even if they have different static call targets"*; AOT (`CodeKeyValueTrait`) exige
  também `static_calls_target_table`/`pc_descriptors`/stackmaps iguais ⟹ cópias de corpo com targets
  distintos NÃO fundem; stubs `=> Trait$f(this)` com o MESMO target fundem bem.
- Unboxing por Member ([[contextual-typing-slice-c]]): static compartilhado = 1 decisão sobre o join.

## Dispatch existencial — **a VM NÃO tem vtable** (correção de vocabulário, 2026-07-29)
- Egorov, *Introduction to the Dart VM* (`https://mrale.ph/dartvm/`): *"VM currently does not use any
  form of virtual table or interface table based dispatch and instead implements dynamic calls using
  inline caching"*. Dizer "a VM resolve por vtable" numa §8 está ERRADO e envelhece mal.
- O quadro real: **JIT** = inline caches (`UntaggedICData` por call-site + stub de lookup compartilhado).
  **AOT** = (1) devirtualização por TFA quando prova alvo único; (2) **Global Dispatch Table** para
  receptor não-`dynamic` (isto sim é parente de vtable, mas global e comprimido por interleaving de
  selector rows); (3) switchable calls (unlinked → monomorphic → single-target → IC linear →
  megamorphic) para receptor `dynamic`.
- A conclusão prática NÃO muda: é Grupo B, o Itá só declara `implementedTypes` + `interfaceTarget` no
  procedure abstrato. Só a PALAVRA muda.
- Corolário do "verifier não cobra supertypes" (acima): conformer sem o membro do trait passa no gate
  e morre em `NoSuchMethodError` em runtime. E, com params **named** (§12-3), há um contrato NOVO:
  o call-site existencial usa os nomes do REQUISITO; se a implementação nomear diferente, é NSM em
  runtime (casamento named é por nome — `verifier.dart:1337-1354`, e `ArgumentsDescriptor` na VM).

## Pragmas (runtime/docs/pragmas.md + pkg/compiler/doc/pragmas.md @3.12.2)
- VM: `vm:prefer-inline`, `vm:never-inline`, `vm:always-consider-inlining`, `vm:entry-point` (só
  embedder/native — usar p/ manter wrapper vivo mata tree-shaking), `vm:deeply-immutable`.
- dart2js: `dart2js:prefer-inline`(=tryInline), `dart2js:noInline`; **não existe equivalente de
  `vm:entry-point`** ⟹ lowering que dependa de manter classe viva "por registro dinâmico" quebra no
  dart2js; wrapper tem que nascer de `ConstructorInvocation` alcançável.
