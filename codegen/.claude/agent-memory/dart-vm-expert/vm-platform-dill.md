---
name: vm-platform-dill
description: Onde vive o vm_platform.dill no SDK pinado e como o itac o auto-descobre; a VM relinka o próprio platform no load (Grupo B)
metadata:
  type: reference
---

# `vm_platform.dill` — localização e auto-descoberta (B3, `itac run`/`build`)

**Layout confirmado** (Glob, 2026-07-26) no SDK pinado `.dart-sdk/3.12.2/`:
o SDK root tem um aninhamento EXTRA `dart-sdk/`, ou seja
`.dart-sdk/3.12.2/dart-sdk/bin/dart` é o executável, e ao lado:

- `.dart-sdk/3.12.2/dart-sdk/lib/_internal/vm_platform.dill`   ← o que usamos (JIT)
- `.dart-sdk/3.12.2/dart-sdk/lib/_internal/vm_platform_strong.dill`
- `.dart-sdk/3.12.2/dart-sdk/lib/_internal/vm_platform_product.dill`

**Auto-descoberta** (spec 013 §7.2; `codegen/bin/itac.dart` `_platformDillPath`):
NÃO pedir o platform como arg. Derivar de `Platform.resolvedExecutable` (o dart
pinado que roda o `itac`): `<sdk>/bin/dart` → `<sdk>/lib/_internal/vm_platform.dill`.
No código: `File(resolvedExecutable).parent.parent` (= `<sdk>` Directory, cujo
`.uri` tem barra final) `.uri.resolve('lib/_internal/vm_platform.dill')`. Garante
que o SDK que COMPILA é o mesmo que EXECUTA.

**Grupo B — a VM relinka o próprio platform:** o `.dill` que emitimos sai MÍNIMO
(só as libs do programa; ver `finalize.dart` `finalizeProgram` + `libraryFilter`).
As refs a `dart:core` entram por canonical name no link table, SEM corpo do
platform. Ao rodar `dart <out.dill>`, a VM carrega o kernel e relinca o SEU
platform no load — não embarcamos plataforma no `.dill`. Por isso o platform só
precisa estar PRESENTE durante o `verifyComponent` (declarar membros p/
`seenByVerifier`), não serializado.

**Execução:** `Process.start(Platform.resolvedExecutable, [dillPath], mode:
inheritStdio)` roda o `.dill` na VM JIT; o `exitCode` do processo é o exit code
do PROGRAMA (§7.3: 0 normal, panic ⟹ ≠0), propagado pelo `itac run`.
Relacionado: [[kernel-offsets]] (o `.dill` fmt 130).
