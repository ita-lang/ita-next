---
name: ci-portability-linux-x64
description: Por que o CI linux-x64 (setup-dart) é seguro para a F7 — vm_platform.dill não é parametrizado por OS/arch, header do .dill (magic+fmt BE nos bytes 0..7), e o sdkHash NULO que desliga a única checagem de mismatch de SDK
metadata:
  type: reference
---

# CI linux-x64 × pin macos-arm64 (verificado 2026-07-28, tag 3.12.2)

## 1. `vm_platform.dill` NÃO é parametrizado por OS/arch
- `runtime/vm/BUILD.gn@3.12.2`, template `gen_vm_platform` → `compile_platform`: os
  ÚNICOS defines são `-Ddart.vm.product=$is_product_flag`, `-Ddart.vm.{asan,msan,tsan}`,
  `-Ddart.isVM=true`. Entrada = `libraries_specification_uri =
  org-dartlang-sdk:///sdk/lib/libraries.json`. **Zero `target_cpu`/`target_os`.**
  3 invocações: `vm_platform` (postfix ""), `_product`, `_stripped` (`--exclude-source`).
- `single_root_scheme = "org-dartlang-sdk"` ⟹ fileUris embutidas são
  `org-dartlang-sdk:///sdk/lib/...`, **não** paths do bot de build.
- `sdk/lib/libraries.json@3.12.2`: target `vm`/`vm_common` único, sem condicional de OS/arch.
- `sdk/BUILD.gn@3.12.2`: `copy("copy_vm_dill_files")` tem `visibility = [":create_common_sdk"]`
  — o grupo **COMUM** (independente de arquitetura). O que é arch-específico no SDK são os
  BINÁRIOS (`bin/dart`, `gen_snapshot`, `dartaotruntime`), não o `.dill`.
- Ressalva: byte-identidade linux×macos NÃO foi medida (exigiria baixar os 2 zips). A
  afirmação é "não há parametrização por OS/arch na produção do artefato".
- Irrelevante na prática: `platformDillPath()` (`codegen/lib/compile.dart:111-116`) deriva o
  platform de `Platform.resolvedExecutable` ⟹ **o SDK que compila é sempre o que executa**,
  em qualquer runner. Não há cruzamento de plataformas.

## 2. Header do `.dill`: magic (0..3) + formatVersion (4..7), BIG-ENDIAN
- Vendor `pkg/kernel/binary.md:148-151`: `UInt32 magic = 0x90ABCDEF; UInt32 formatVersion = 130;
  Byte[10] shortSdkHash;`
- Escrita: `ast_to_binary.dart:605-607` (`writeUInt32(Tag.ComponentFile)`,
  `writeUInt32(Tag.BinaryFormatVersion)`, `writeBytes(ascii.encode(expectedSdkHash))`);
  `writeUInt32` (`:126-133`) grava MSB primeiro.
- VM `runtime/vm/kernel_binary.h@3.12.2`: `:18-19` `kMagicProgramFile=0x90ABCDEFu`,
  `kSupportedKernelFormatVersion=130`; `:167-170` `ReadUInt32At` usa `Utils::BigEndianToHost32`;
  `:272 KernelFormatVersionOffset = 4`; `:274 HeaderSize = 8`.
  ⚠️ `main` já está em **138** — a guarda tem de ler do `dart-sdk.pin`, nunca hardcode.
- `runtime/vm/kernel_binary.cc@3.12.2:104-129`: valida magic → versão → SDK hash, nessa ordem.
- Leitura sem Python (P9): `ByteData.getUint32(4)` — o default de `getUint32` é
  **`Endian.big`** (`.dart-sdk/3.12.2/.../lib/typed_data/typed_data.dart:635`). POSIX:
  `od -An -tu1 -j4 -N4 f | awk '{print $1*16777216+$2*65536+$3*256+$4}'`.
  `tools/pin-dart.sh:50` (`kver()`) usa `python3` — **viola o princípio 9 hoje**.

## 3. O `.dill` do Itá sai com sdkHash NULO — a checagem de SDK está DESLIGADA
- `tag.dart:257,264-273`: `expectedSdkHash` vem de `String.fromEnvironment('sdk_hash')` com
  default `'0000000000'`. Rodamos o `pkg/kernel` do SOURCE, sem `-Dsdk_hash` ⟹ gravamos hash nulo.
- `tag.dart:275-278` `isValidSdkHash`: passa se o hash lido for nulo **ou** se o esperado for nulo.
  Vale nos dois lados: a VM aceita nosso `.dill`, e nosso reader aceita qualquer `vm_platform.dill`.
- **Consequência:** só o FORMATO (130) é conferido de fato; mismatch de PATCH do SDK passa
  silenciosamente. É por isso que rodar os fixtures com o dart 3.12.1 do Flutter "funciona" —
  não prova intercambiabilidade, prova que a checagem está desligada.
- Reader do vendor: `ast_from_binary.dart:911-918` (magic → `InvalidKernelVersionError` →
  `_readAndVerifySdkHash`), erros em `:34-64`.

## 4. `setup-dart` não valida checksum
- `dart-lang/setup-dart` `lib/main.dart`: monta
  `https://storage.googleapis.com/dart-archive/channels/$channel/$flavor/$version/sdk/dartsdk-$os-$architecture-release.zip`,
  usa `toolCache.downloadTool` + `extractZip` + `cacheDir`. **Nenhuma verificação de integridade.**
  Integridade = TLS + GCS + toolcache. O archive PUBLICA `<zip>.sha256sum`
  (linux-x64 3.12.2 = `28e47b44cf075f36771046c068bb0d174201cf9c7608744aed1cc23204299c2d`),
  mas o zip é descartado pela action. Guarda equivalente e mais útil = **semântica**:
  `dart --version` + formato do `vm_platform.dill` + formato do `.dill` emitido, todos vs. o pin.
