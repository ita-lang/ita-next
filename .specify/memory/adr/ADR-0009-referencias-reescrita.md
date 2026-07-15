# ADR-0009: Referências canônicas da reescrita (Dragon Book + Crafting Interpreters)

- **Status:** Accepted
- **Data:** 2026-07-10
- **Relacionados:** [[ADR-0007]] (roadmap Dragon Book), [[ADR-0008]] (harness SDD / épico 002), [[ADR-0001]] (Dart VM permanente — ver o guard de LLVM abaixo).

## Contexto

A reescrita do compilador (épico `002`) precisa de referências claras. O **Dragon Book** (já em
`references/livro-compiladores/`) dá a **teoria e os artefatos formais**, mas ensina o front-end no estilo
**gerado** (Lex/Yacc, tabelas LR) — enquanto o Itá é implementado **à mão** (scanner manual + recursive
descent + Pratt). Faltava a referência do **como implementar** nesse estilo.

## Decisão

Adotar **duas referências canônicas**, com papéis distintos:

1. **Dragon Book** (`references/livro-compiladores/`) = **o QUE especificar** — definições regulares,
   BNF/EBNF, SDD, regras de tipo, autômatos. Fonte dos **artefatos formais** de cada fase (ver ADR-0007).
2. **Crafting Interpreters** — R. Nystrom (`references/crafting-interpreters/`) = **o COMO implementar** —
   scanner à mão, **Pratt parser**, AST/Visitor. Só o **front-end** (Parte II + front-end da III + apêndices);
   a Parte III de bytecode VM foi omitida (Grupo B, herdado — ADR-0001/0007).

**Regra de uso:** cada fase da reescrita cita **ambas** — o artefato formal (Dragon, cap X) e o padrão de
implementação (CI, cap Y). Ex.: Fase 1 léxico = defs regulares [Dragon 3.3] + scanner à mão [CI "Scanning"].

## Guard — as "LLVM Frontend Performance Tips" NÃO reabrem o LLVM

Foram consultadas as *Frontend Performance Tips* do LLVM (llvm.org). **Isto NÃO altera o ADR-0001: a Dart VM
segue o backend permanente e o LLVM continua abandonado.** Apenas os **princípios gerais de frontend→IR**
(agnósticos de backend) são colhidos e **traduzidos para "gerar Dart Kernel que o TFA/AOT da Dart VM
otimize"**:

- **Linkage o mais privado possível** → emitir membros `private` no Kernel amplia a inferência do TFA
  (é, na prática, o insight do [[ADR-0004]]: receiver concreto/privado → devirtualização → ~16×).
- **Evitar blocos de fluxo com in-degree alto** → gerar fluxo de controle limpo.
- *(Descartado como LLVM-específico: data layout / target triple / intrinsics / passes do LLVM.)*

Esses princípios entram como guia da **Fase 5 (codegen)** do épico — não como um backend. Qualquer proposta
de reabrir LLVM como backend exige um **novo ADR que supersede o ADR-0001** (decisão do dono), não uma tip.

## Consequências

- `references/` passa a ter **duas** fontes; o `README.md` de cada uma mapeia capítulo → fase.
- O `plan.md` do épico ganha a referência de implementação (CI) por fase, ao lado do capítulo do Dragon.
- Registro anti-confusão: fica documentado que o LLVM foi **reconsiderado como fonte de princípios** e
  **rejeitado como backend** — ADR-0001 intacto.
