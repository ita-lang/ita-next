# ADR-0005: Alvo JavaScript via `dart2js` (Rota A; Oxc/Deno descartados)

- **Status:** Accepted
- **Data:** 2026-07-08
- **Relacionados:** [[ADR-0001]] (3 alvos de graça da toolchain Dart), [[ADR-0004]] (o JS é test-oracle da Fase 4). Fonte: [[ita-alvo-js-dart2js]].

## Contexto

O M4 pede um alvo JavaScript. Duas rotas: (A) reaproveitar o pipeline `.tu → .dill → dart2js`, ou (B)
escrever um 2º backend inteiro (AST-Itá → AST-JS) via Oxc/SWC/Deno. O formato de Kernel 130 do SDK
pinado ([[ADR-0003]]) casa com o motor dart2js já presente no SDK — esforço de codegen ~zero.

## Decisão

**Rota A: `.tu` → `.dill` → `dart2js`.** Oxc/Deno/SWC **descartados** — só imprimem AST de JS/TS;
usá-los exigiria um 2º backend + runtime Itá-em-JS + arrastar Rust/Node (fere "zero node_modules"), e
o papel de minificador já é coberto por `dart compile js -O4`. O alvo JS é um **test-oracle da Fase 4**:
o dart2js (consumidor estrito de Kernel) expõe débitos de codegen que a VM leniente mascara.

## Consequências

- **Requisito do CLI reescrito (ita-next):** o comando `itac build --target=js` (encadeia
  `dart compile js` após gerar o `.dill`; **fiação só no CLI, codegen intocado**) foi **provado no spike
  de 2026-07-07** (report `2026-07-07_spike_js_target.md` — `dart compile js` aceita o `.dill` como
  entry point posicional, saída Node bate byte-a-byte com a VM) **mas NUNCA foi mergeado no main**.
  Fica como requisito do CLI do compilador reescrito.
- **`Int` 64-bit é best-effort no JS** (≥2³¹ = divergência documentada, sem emulação — ver spec 001).
- **Golden-runner VM×Node** no CI (`run_js_parity.sh` + `expected.txt`, 33 examples) como oráculo de
  não-regressão. Trinca de Fase 4 landada (G4 Float `.0` #33, G1 Uint8List #34, G3 type-args #36) +
  item W (#37): paridade **5→16 MATCH/33**.
- **O que resta NÃO é Fase 4:** isolates + `dart:io` = M5; resíduos de spec (`bits`, `errors`,
  `generics`, `streams`).
