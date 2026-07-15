# ADR-0001: Dart VM como backend permanente (LLVM abandonado)

- **Status:** Accepted
- **Data:** 2026-07-04
- **Supersedes:** a visão original do `MANIFESTO` (pré-2026-07-04) — "Dart VM é o *bootstrap*, não o destino final; futuro backend em **LLVM IR** escrito em **Swift**".
- **Relacionados:** [[ADR-0003]] (un-fork stable), [[ADR-0004]] (perf via codegen tipado), [[ADR-0006]] (compile-time), [[ADR-0007]] (Dragon Book — Grupo B).

## Contexto

O plano inicial do Itá tratava a Dart VM como um **estágio de transição**: `.tu → .dill → Dart VM`
hoje, migrando no longo prazo para um backend nativo próprio via **LLVM IR**, com o compilador
reescrito em **Swift** (a linguagem que mais inspirou o Itá). A justificativa era "performance máxima /
zero runtime overhead".

Ao amadurecer o compilador (M0–M2), duas evidências mudaram o cálculo:

1. **O objetivo nº 1 do Itá é build/pipeline rápidos.** LLVM é **lento de compilar** e **pesado de
   manter** — um backend nativo próprio contradiz diretamente esse objetivo. Provado na prática: o fork
   build-from-source do SDK era lento; a virada para o SDK stable pinado ([[ADR-0003]]) tornou o
   pipeline muito mais ágil.
2. **A performance não precisa de backend nativo próprio.** O ganho vem de **gerar Kernel bem-tipado**
   que o type-flow-analysis do AOT da Dart VM otimiza. Medido no M1 ([[ADR-0004]]): tipar os locais
   deu ~16× no AOT **sem tocar em backend**. A toolchain Dart já entrega AOT nativo standalone
   (`dart compile exe`) e três alvos de graça.

## Decisão

**A Dart VM é o backend definitivo e permanente do Itá.** O horizonte LLVM/Swift está **abandonado**.

- **Modelo:** Itá : Dart :: Elixir : Erlang — duas linguagens sobre a mesma VM, com princípios próprios.
  O Itá usa a Dart VM sem ser Dart e sem depender do Flutter.
- **Não há "fase LLVM"** nem compilador Swift nem migração de backend futura.
- O Itá compila para **Dart Kernel (`.dill`)** e colhe, da toolchain Dart, três alvos:
  **JIT** (dev), **AOT nativo** (`dart compile exe`), **JavaScript** (`dart2js` — [[ADR-0005]]).

## Consequências

- **Foco no que é trabalho real:** a linguagem e a stdlib (o "Grupo A" do Dragon Book, caps 2–6). O
  runtime (GC, isolates, código de máquina — caps 7–12) é **herdado** da VM, não implementado
  ([[ADR-0007]]).
- **Performance** é responsabilidade da fase semântica/codegen tipado, não de um backend nativo.
- **Independência do Dart** vira norte estratégico (stdlib em `.tu`, built-ins migrados, self-hosting no
  horizonte) — mas sobre a Dart VM, não contra ela.
- **Documentos a manter alinhados:** `MANIFESTO.md` (reescrito 2026-07-10), `constitution.md` §Artigo II,
  `ROADMAP.md`. Qualquer texto que fale de "LLVM como futuro" é **regressão** e deve ser removido.

## Nota

Esta é a decisão-mãe que orienta o roadmap. Ao reescrever/reestruturar o compilador, o alvo é sempre
Kernel → Dart VM; nunca reabrir a rota LLVM sem um novo ADR que supersede este.
