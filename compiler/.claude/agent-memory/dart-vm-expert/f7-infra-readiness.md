---
name: f7-infra-readiness
description: Estado da infra F7 em ita-next (vendor pkg/kernel fmt 130, SDK pinado, wiring de pubspec ainda pendente) + a receita comprovada do oracle p/ ligar kernel e executar o .dill cru
metadata:
  type: project
---

# F7-readiness da infra Kernel/VM (ita-next, medido 2026-07-24)

Auditoria de F7-readiness do backend. Fronteira Art. III: emitimos Kernel (Cap 6); VM roda (Grupo B).

## O que JÁ está no lugar (Gate 2 real)
- **Vendor presente e versionado:** `ita-next/third_party/dart/3.12.2/pkg/{kernel,_fe_analyzer_shared}`.
  `kernel/lib/binary/tag.dart:230` → `BinaryFormatVersion = 130` (lido, Classe A). Casa com
  `EXPECTED_KERNEL_FORMAT=130` do `dart-sdk.pin` e com a tag SDK `3.12.2`.
- **SDK materializado:** `.dart-sdk/3.12.2/dart-sdk/…/vm_platform.dill` existe (gitignorado, ~586MB).
  Mesma stable 3.12.2 ⟹ `vm_platform.dill` é fmt 130 por construção (o `pin-dart.sh` `kver()` assere).
- **`pkg/kernel` É a lib de construção do `.dill`:** tem a AST inteira + `BinaryPrinter`
  (`ast_to_binary.dart`, `writeComponentToBytes`). É exatamente o que o codegen usa — não é só leitura.

## ⚠️ GAP de wiring (não é infra faltando — é passo diferido, mas trava a linha 1 do codegen)
- `compiler/pubspec.yaml` é o "Fase 1 mínimo" e **proíbe explicitamente** path-deps de `kernel`.
- `compiler/.dart_tool/package_config.json` **NÃO tem entrada `kernel`** (o `_fe_analyzer_shared`
  lá é o `104.0.0` de pub.dev, transitivo do `test`/`analyzer` — NÃO o vendorado). ⟹ hoje o codegen
  **não consegue** `import 'package:kernel/ast.dart'`. `pub get` sem kernel no pubspec não o liga.
- **Receita COMPROVADA (oracle `ita/compiler/pubspec.yaml`), path idêntico p/ ita-next:**
  ```yaml
  dependencies:
    kernel: { path: ../third_party/dart/3.12.2/pkg/kernel }
    _fe_analyzer_shared: { path: ../third_party/dart/3.12.2/pkg/_fe_analyzer_shared }
  dependency_overrides:            # kernel declara `_fe_analyzer_shared: any` → forçar path (fix provado)
    _fe_analyzer_shared: { path: ../third_party/dart/3.12.2/pkg/_fe_analyzer_shared }
  ```
- **Watch-item:** o `kernel/pubspec.yaml` vendorado tem `resolution: workspace`. O oracle liga com
  path+override (sem workspace root) — se um `pub get` 3.12.2 reclamar do `resolution: workspace`,
  strip da linha no vendor (é vendor local, editar é legítimo). 1 linha, não é bloqueador.

## Executar o `.dill` cru (Grupo B) — precedente do oracle
- Construção: `loadComponentFromBinary(vm_platform.dill)` → achar `dart:core::print`/ops (Reference) →
  `Procedure main` → `component.setMainMethodAndMode(main.reference, true)` → `computeCanonicalNames()`
  → `writeComponentToBytes()`. Provado em `ita/compiler/docs/generate_dill.dart` (roda de verdade).
- Entrypoint = `Component.mainMethod` (`fn main` aridade 0). VM religa canonical names ao `dart:core`
  embutido no snapshot (não embarcamos platform). Build no `pin-dart.sh`: `itac hello.tu out.dill PLAT`;
  run: `dart --dfe=<vm_platform.dill> out.dill`. AOT: `dart compile exe out.dill`; JS: `dart compile js`.

## Gates §0.6 (spec 013) — todos caídos p/ COMEÇAR
- Gate 1 F6: ✅ (spec 014, exaustividade+redundância). Gate 2 pin/vendor: ✅. Rulings §12-1/3/4/5: ✅.
  §12-2 (async × transformer CFE) roteado à fase async — **não** bloqueia 013.
