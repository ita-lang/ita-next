---
name: dill-platform-linking
description: Como finalizar um .dill de PROGRAMA que referencia dart:core — o verify exige o platform PRESENTE no Component (declareMember percorre TODAS as libs), skipPlatform só pula os CORPOS, e libraryFilter serializa só o programa (app-only .dill que a VM relinca no load). Verificado no vendor 3.12.2, 2026-07-26 (W3 LT-F7a Passo A).
metadata:
  type: reference
---

# `.dill` de programa × platform linking (tag 3.12.2, verificado 2026-07-26)

**O problema:** todo programa real referencia `dart:core::print` (etc.). Se o Component só
tem a lib do programa (platform descartado após pegar a `Reference`), o `verifyComponent`
reprova: `Dangling reference to 'print', parent is: 'dart.core'`. O oracle (`ita/`) nunca bate
nisso porque **NÃO roda verify** — a F7 ADICIONA o gate (CA12), logo herda o problema.

## Mecanismo (fonte `pkg/kernel/lib/verifier.dart` @3.12.2)
- A mensagem nasce em `defaultMemberReference` (`:1465-1472`): a ref é "dangling" sse o Member
  alvo NÃO tem o flag `TransformerFlag.seenByVerifier`.
- O flag é setado por `declareMember` (`:401-409`), chamado em `visitComponent` (`:416-434`)
  sobre **`component.libraries` INTEIRO, incondicionalmente** — NÃO respeita `skipPlatform`.
  ⟹ **o membro-alvo (`print`) TEM de estar PRESENTE no Component verificado.**
- `skipPlatform:true` só faz `visitLibrary` (`:456-462`) retornar cedo para libs `dart:*`
  (path≠'test') — pula a verificação dos **CORPOS** do platform, mas NÃO a declaração dos
  membros. Ao fim, `undeclareMember` (`:440-448`) limpa os flags (sem resíduo).
- ⟹ **par correto e suficiente = platform PRESENTE no Component + `skipPlatform:true`**:
  resolve a ref E não paga pra verificar o corpo do platform.

## Serialização app-only (fonte `pkg/kernel/lib/binary/ast_to_binary.dart` @3.12.2)
- `BinaryPrinter(Sink, {LibraryFilter? libraryFilter})` (`:70`); `typedef bool LibraryFilter(Library)`
  (`:3399`); `BytesSink` (`:3686`, público mas NÃO exportado por `kernel.dart` — importar
  `package:kernel/binary/ast_to_binary.dart`).
- Filtro retornando **`true` = INCLUIR**. Gates: `writeLibraries` (`:820`), `indexLinkTable`
  (`:561`), `writeComponentIndex` (`:632-640`), `_computeCanonicalNames` interno (`:584`).
- **Ref externa a lib NÃO-escrita entra no `.dill` por canonical name**: `writeNonNullReference`
  (`:998`) → `checkCanonicalName` (`:1049-1063`) indexa recursivamente o path `@dart:core::print`
  no link table mesmo com o CORPO de `dart:core` fora — a VM relinca no seu platform no load.
  É como o SDK produz `.dill` app-only. `.dill` sai mínimo (CA11/§7.1, Grupo B).
- `uriToSource`/sources: só as fileUris REFERENCIADAS pelos nós escritos entram (o `_sourceUriIndexer`
  popula durante a escrita das libs filtradas) ⟹ sources do platform não incham o `.dill`.

## mainMethod sobrevive ao filtro — SE sua lib passar
- `writeComponentFile` (`:615-620`) garante o canonical name do main; `writeComponentIndex`
  (`:864-872`) grava `main.index+1`. O index vem de `indexLinkTable` (só libs filtradas) ⟹
  **o main resolve porque sua lib (do programa) passa o filtro.** Se fosse filtrada FORA, quebraria.
- `Component.setMainMethodAndMode(Reference?, bool overwriteIfSet)` (`components.dart:116`) — o main
  é uma `Reference`, não sofre com o filtro além do canonical name.

## Decisão de design: platform vira a BASE do Component (não o inverso)
- **Aprovado (approach A):** `platform.libraries.addAll(programLibs); platform.adoptChildren();`
  depois sanear/verify/serializar. Motivos: (1) `loadComponentFromBinary` (`kernel.dart:26`)
  devolve Component FRESCO e não-compartilhado por chamada ⟹ mutar é seguro; (2) o `root`
  CanonicalName do platform já possui as libs do platform corretamente — só bindar a nossa
  sob ele é mínima perturbação; (3) **`isExternal` fica irrelevante** — as libs do platform
  ficam como carregadas (não-external, com corpos; `skipPlatform` as pula no verify, o filtro
  as exclui do `.dill`). O approach B (Component fresco + adicionar libs do platform) forçaria
  re-parent dos canonical names (`adoptChildren`, `components.dart:47-58`) e a pergunta do
  `isExternal` — evitado.
- `adoptChildren()` pós-add é idempotente: p/ platform libs `name.parent==root` já ⟹ skip;
  p/ a lib nova (canonicalName==null) seta só `parent=this`. `computeCanonicalNames()` é
  idempotente via flag `dirty` (`declarations.dart:357-370`; `Library.ensureCanonicalNames:932`).
- **Sanear SÓ o programa** (`sanitizeLibraries(Iterable<Library>)`, novo em `codegen/lib/sanitize.dart`):
  zerar offsets ou reescrever `isFinal` do platform corromperia libs válidas.
- ⚠️ **Risco a lembrar:** NÃO reutilizar o mesmo `platform` carregado para 2 programas — as
  libs se acumulam. Recarregar por programa. Ver [[kernel-raw-api-field-hygiene]] (higiene de campo).

## Onde vive no ita-next
- `codegen/lib/finalize.dart`: `finalizeProgram(Component platform, List<Library> programLibs, {Procedure? mainMethod})`
  (novo) vs. `finalizeComponent` (mantido p/ o caso sem platform dos testes).
- `codegen/bin/hello.dart`: Passo A do hello (`fn main(){print("olá")}`) usa `finalizeProgram`.
