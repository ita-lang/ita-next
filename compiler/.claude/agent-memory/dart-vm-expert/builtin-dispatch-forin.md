---
name: builtin-dispatch-forin
description: Fatos da VM/Kernel para dispatch de método, membros de built-in (dart:core::List), extension→static, trait→Class abstrata e a PROIBIÇÃO de emitir ForInStatement — grounding da spec 011
metadata:
  type: reference
---

# Dispatch, built-ins, extension e for-in — fatos confirmados

Vendor: `ita/third_party/dart/3.12.2/pkg/kernel/`. SDK on-disk p/ `dart:core`:
`~/flutter/flutter/bin/cache/dart-sdk/lib/core/`. Platform dills:
`~/flutter/flutter/bin/cache/dart-sdk/lib/_internal/vm_platform{,_strong,_product}.dill`.

## ⚠️ ForInStatement é PROIBIDO no .dill que a VM lê (achado forte)
Verificado NA TAG EXATA do vendor (3.12.2), em
`runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc`, no switch de `BuildStatement`:
```
case kForInStatement:
case kAsyncForInStatement:
case kIfCaseStatement:
case kPatternSwitchStatement:
case kPatternVariableDeclaration:
// These nodes are internal to the front end and
// removed by the constant evaluator.
default:
  ReportUnexpectedTag("statement", tag); UNREACHABLE();
```
- `ForInStatement` (tag 70, `pkg/kernel/binary.md`) existe no FORMATO mas é nó **CFE-interno**;
  a CFE o remove antes da VM. Frontend que bypassa a CFE (= Itá) **deve desaçucarar for-in
  ele mesmo** (while + iterator/moveNext/current, ou o protocolo que quiser).
- ⚠️ **Versionado**: em commit antigo (`cb61275`) o switch TINHA `case kForInStatement: return
  BuildForInStatement(false)`. Mudou. Sempre reconferir na tag vendorizada — não confiar em
  `main` nem em memória de treino.
- Consequência boa p/ Itá: não há fast-path da VM em for-in que estejamos abrindo mão. O
  `Iterator` próprio do Itá (`next() -> Option<T>`) fica em pé de igualdade.
- **Lacuna**: onde exatamente a CFE faz esse lowering — não localizei (`pkg/vm/.../for_in_lowering.dart`
  = 404; não achei `visitForInStatement` em `constant_evaluator.dart`). O requisito não depende disso.

## interfaceTarget exige Member REAL do dart:core
`InstanceGet` (`expressions.dart:551`) / `InstanceInvocation` (`:1850`): `Reference
interfaceTargetReference` non-nullable. Origem do Member = carregar o platform dill.
- `loadComponentFromBinary(platformDill)` → `CoreTypes(component)` (`lib/core_types.dart:98`)
  → `LibraryIndex.coreLibraries` (`lib/library_index.dart:44`) indexa toda lib `dart:`.
- Lookup por nome: `index.getProcedure('dart:core', 'List', 'get:length')` — **getter/setter exigem
  prefixo `get:`/`set:`** (`library_index.dart:15-17`).
- **Não é preciso EMBARCAR dart:core no nosso .dill**: `writeNonNullReference` grava só
  `canonicalName.index+1` (`ast_to_binary.dart:998`); `checkCanonicalName` (`:1049`) adiciona a
  cadeia de pais sob demanda; `libraryFilter` (`:47,561,584,632`) restringe as libs serializadas.
  A VM religa os canonical names ao dart:core do próprio snapshot no load.
- Precedente no oracle: `ita/compiler/docs/generate_dill.dart` já faz exatamente isso com `print`.
- ⚠️ Reter 1 `Reference` retém o Component inteiro da platform via cadeia `parent` (node→Library→
  Component→libraries). "Descartar a platform" é ilusório salvo se os canonical names já foram
  computados. Custo de tempo/memória do load: **NÃO MEDIDO** (lazy reading é default-ON:
  `BinaryBuilder(disableLazyReading: false)`, `ast_from_binary.dart:169-205`; `Class.lazyBuilder`/
  `ensureLoaded` em `canonical_name.dart:446-464` carregam corpo de classe sob demanda).

## extension → Procedure top-level estático (o nó Extension é METADADO)
`declarations.dart:605-608`: "The members are converted into top-level procedures and only
accessible by reference in the [Extension] node." `ExtensionMemberDescriptor` (`:747-790`) documenta
o lowering da CFE:
```
extension B on A { get bar => this.foo; }   ==>   B|get#bar(A #this) => #this.foo;
```
nome manglado + `#this` como 1º parâmetro sintético. `memberReference` "can be cleared by certain
back-ends (e.g. VM/AOT) if member is not used" → a VM treeshaka como procedure top-level qualquer.
**A VM nunca despacha através do nó `Extension`** — emitir o nó é opcional (serve a tooling).

## Dispatch: a VM NÃO distingue interface de classe concreta
Fonte: https://mrale.ph/dartvm/ (switchable calls) + `runtime/docs/glossary.md`
(mono/poly/megamórfico). Dispatch é por **selector × cid do receptor**, não por "é interface?":
- JIT: switchable call — unlinked → monomorphic (guarda de cid) → single-target (range de cids,
  explora atribuição depth-first de cid) → megamorphic (hash cid→target).
- AOT: devirtualiza se a TFA prova alvo único; senão GDT `gdt[numClasses * #m.id + o.cid]`.
  **GDT não é mecanismo "de interface"** — vale p/ qualquer call não devirtualizada.
- ⇒ `trait` do Itá → `Class` abstrata + `implementedTypes` **não tem custo de dispatch por ser
  interface**. O que custa é o nº de alvos no call-site (grau de polimorfismo). Não deixar
  decisão de trait pender em "custo de interface" — não existe.

## dart:core::List — o que é e não é possível
- `ListLiteral` (`expressions.dart:4529`) tem `getStaticTypeInternal` → `typeEnvironment.listType(...)`:
  **hard-wired a `dart:core::List`**. Se o `List` do Itá NÃO for o do Dart, `[1,2]` não pode ser
  `ListLiteral` — vira ConstructorInvocation/StaticInvocation da classe própria.
- `abstract interface class List<E> implements Iterable<E>, _ListIterable<E>` (`core/list.dart:120`).
  `_ListIterable` (`:9`) é shim VAZIO só p/ "hide EfficientLengthIterable from the public declaration"
  — **não é blocker** p/ `implements List`.
- `void add(E value)` (`:442`) está na interface `List` → não há como "esconder" no Kernel.
  Mas esconder é decisão do RESOLVER do Itá (tabela de membros própria); a VM não impõe nada.
- Imutabilidade: **a VM não oferece List imutável no nível de tipo**. `runtime/docs/deeply_immutable.md`
  (`@pragma('vm:deeply-immutable')`) **não cobre List** (só primitivos/SIMD/Pointer/classes marcadas).
  `List.unmodifiable` (`core/list.dart:244`) e const lists lançam em **runtime**, não em compile-time.
  ⇒ P1 (imutável por default) é preservado pelo FRONTEND, não pela VM. O vazamento real é na
  fronteira `dart:` (código Dart muta a lista) — argumento de PRINCÍPIO/interop, não de perf.
