---
name: panic-exit-code
description: Como o panic do Itá (P7 zero try/catch = Throw não-capturado) mata o isolate e qual exit code em cada alvo — VM/AOT 255, JS ~1. Arquitetura do `itac run` propaga cru. Grupo B (VM entrega); a exigência do nosso lado é NÃO reinterpretar o código.
metadata:
  type: reference
---

# Panic → exit code por alvo (F7 W1, verificado 2026-07-20)

Itá tem **P7: zero try/catch**. `panic` = `Throw` NÃO-capturado. A propagação até a morte do isolate
e o exit code é **Grupo B** (a VM entrega); do nosso lado só exigimos NÃO reinterpretar o código.

## Exit code por alvo
- **VM (JIT `dart`) e AOT (`dart compile exe`)**: uncaught → **255**. Fonte: `runtime/bin/error_exit.h`
  @ tag 3.12.2 (WebFetch) — `kErrorExitCode = 255` (*"unhandled error that is not a compilation error"*);
  vizinhos: `kCompilationErrorExitCode=254`, `kApiErrorExitCode=253`, `kDartFrontendErrorExitCode=252`.
  AOT compartilha o mesmo embedder `runtime/bin` ⟹ mesmo 255 (A-VERIFICAR estrito: não busquei fonte AOT-específica).
- **JS (`dart2js`)**: uncaught → `throw` JS → host decide. Node sai **1** (não 255). **Risco de paridade ADR-0005**:
  só a propriedade "exit ≠ 0" é compartilhada; o VALOR difere (255 VM/AOT vs 1 JS). A-VERIFICAR valor exato no Node.

## Arquitetura do `itac run` — exit flui CRU (oracle `ita/`)
- `bin/itac.dart:762-769` (modo normal): `Process.runSync(dart, ['--dfe=$platformDill', dill])`; escreve
  `result.stdout`/`stderr` verbatim; `if (result.exitCode != 0) exit(result.exitCode)`. **Nenhuma reinterpretação**
  — o driver re-sai com o código do filho. Também em `:768` (AOT exe path). ⟹ exigência da F7: NÃO mapear/clampar o exit.

## O que a §8 registra
Só a DEPENDÊNCIA: "panic = Throw não-capturado; a VM mata o root isolate com 255 (JIT/AOT); dart2js/Node = não-zero
(valor diferente, ADR-0005); o driver propaga o exit code cru". Não reespecificar a morte do isolate (Cap 7+ da VM).
