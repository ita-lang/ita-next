# ADR-0003: Un-fork para Dart stable 3.12.2 (SDK pinado, Kernel 130)

- **Status:** Accepted
- **Data:** 2026-07-06
- **Supersedes:** o fork build-from-source do SDK em `google_tools/dart-sdk-source` (Dart `main` limpo, preso ao formato de Kernel 128), agora apenas fallback.
- **Relacionados:** [[ADR-0001]] (habilita o backend permanente), [[ADR-0004]] (o fix depende de `LocalFunctionId` do kernel ≥3.12). Fonte: [[ita-backend-dartvm-bootstrap-fork-evitavel]].

## Contexto

O `itac` dependia de um **fork build-from-source** da Dart VM. Diagnóstico provado: o fork não é um
Dart modificado — é build de um `main` limpo, preso ao **formato binário de Kernel 128**. A única
coisa que amarra o `itac` ao fork é o **número do formato de Kernel** (do `pkg/kernel` linkado, não do
binário `dart`). Build-from-source é lento — contra o objetivo nº1 do Itá (pipeline rápido).

## Decisão

**Abandonar o fork e seguir sempre o SDK stable oficial pinado.** Alvo: **Dart stable 3.12.2**
(formato de Kernel **130**). A receita, sem rebuild de VM:

- **Pin versionado:** `ita/dart-sdk.pin` + `ita/tools/pin-dart.sh` (baixa e valida o SDK por sha256).
- **Vendor:** `pkg/kernel` (+ `_fe_analyzer_shared`) da tag 3.12.2 em `ita/third_party/dart/3.12.2/pkg`.
- **2 fixes de codegen** que a v130 exigiu (dispatch mais estrito): (1) tear-off →
  `ConstantExpression(StaticTearOffConstant)`; (2) passe **`_LocalFunctionIdAssigner`** que atribui
  `LocalFunctionId` sequencial (≥1) por Member — replica o `LocalFunctionIdGenerator` do CFE. A v130
  keya o `ClosureFunctionsCache` por `local_function_id` (default 0), não por `kernel_offset`; sem o
  passe, closures de um mesmo Member colidem na chave 0.

## Consequências

- **Fork aposentado:** o fix usa `LocalFunctionId` (API só existente em `package:kernel ≥ 3.12`) →
  o `itac` agora **exige** ser buildado contra o kernel vendorizado 3.12.2 (CFAIL contra o v128).
- **Suíte v130: 43/50, zero regressão de linguagem** (falhas restantes são pré-existentes não-código).
- **M0 FECHADO:** mergeado no `main` (PR #2, merge `d8e37d7`) + CI em `macos-14` (arm64) que roda
  `pin-dart.sh`, **asserta formato de Kernel == 130** e smoke de `hello.tu`. O CI pegou 2 bugs de
  checkout-limpo (`build/` ausente; golden `url_env` amarrado ao `HOME` da máquina). Examples 48/48,
  unit 219/219.
- Alvos JIT/AOT/JS passam a vir do SDK stable oficial, sem manter uma VM órfã.
