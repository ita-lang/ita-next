# ADR-0007: Roadmap guiado pelo Dragon Book (Grupo A implementa / Grupo B herda)

- **Status:** Accepted
- **Data:** 2026-07-04
- **Relacionados:** [[ADR-0001]] (Dart VM permanente é a razão do split), [[ADR-0004]] (a Fase 4 é o P0). Fonte: [[ita-roadmap-dragon-book]].

## Contexto

O "Dragon Book" (Aho/Lam/Sethi/Ullman, 2ª ed.) foi extraído por OCR e dividido por capítulo/seção em
`references/livro-compiladores/` (~136 arquivos `.md`). Dele nasceu o **roadmap oficial de evolução do
compilador** (`references/livro-compiladores/ROADMAP.md` — fonte da verdade — + artifact visual
`roadmap-visual.html`). Como a Dart VM é o backend permanente ([[ADR-0001]]), boa parte do livro
descreve trabalho que o Itá **herda** em vez de implementar.

## Decisão

**Partir o livro em dois grupos e só construir o Grupo A:**

- **Grupo A — o que o Itá IMPLEMENTA (caps 2–6):** front-end (léxico/sintaxe), análise semântica, IR e
  codegen para **Dart Kernel**. **A fronteira do Grupo A é a emissão de código intermediário — Cap 6 → Dart
  Kernel (`.dill`); tudo até aí é implementado.**
- **Grupo B — o que a Dart VM ENTREGA DE GRAÇA (caps 7–12):** **runtime/execução (Cap 7)**, ambiente de
  runtime, GC, **otimização e geração de código de máquina (Caps 8–12)**, alocação de registradores e
  paralelismo. **Que o Cap 8 (código de máquina) seja Grupo B não faz do codegen→Kernel (Cap 6) algo
  herdado — o Kernel é emitido pelo Itá.**

## Consequências

- **A Fase 4 — semântica + IR (Cap 6) — é o único P0** e o desbloqueador universal: sem LLVM, gerar
  **Kernel tipado** é a **única** alavanca de performance (recupera ~7,7×), além de consertar os bugs
  "compila mas roda errado", fechar o gate de erro e destravar a stdlib.
- **Foco de esforço** fica na linguagem e stdlib (Grupo A); runtime/GC/máquina não são reimplementados.
- Cada fase do compilador se ancora num capítulo do livro, o que também guia os templates do harness SDD
  ([[ADR-0008]]).
- **Nota sobre os multiplicadores de perf (reconciliação):** os números **~7,7×** e **~16×** que circulam na
  memória **não se contradizem** — têm **baselines diferentes**. **~7,7×** é o **custo do dinamismo no AOT**
  (baseline = Kernel dinâmico atual, o que a fase semântica recupera). **~16×** é o **ganho medido no M1** com
  a fase semântica (medição sobre um baseline distinto). São eixos de medição diferentes, não valores rivais.
