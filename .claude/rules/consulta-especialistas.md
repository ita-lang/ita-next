---
paths:
  - "specs/**"
  - ".specify/memory/**"
---

# Quando consultar cada especialista — e o que pedir

Os três subagentes de `.claude/agents/` são **consultores de referência**: fundamentam e revisam,
não executam. Comportamento observável de verdade (rodar `.tu`, conferir paridade VM×JS) é do
agente do compilador + MCP `ita`.

Esta doutrina viveu dentro das skills `speckit-*` até 2026-08-26. Elas saíram — quatro das seis
quebravam na primeira instrução, chamando `.specify/scripts/bash/*.sh`, um diretório que nunca
existiu neste clone. O que tinha valor era só isto, e agora é mecanismo nativo: uma rule escopada
a `specs/**`, que carrega ao abrir uma spec e não custa nada no resto do tempo.

| ao escrever… | consulte | e peça exatamente |
|---|---|---|
| a **spec** (§0.5 constitution-check) | `ita-visionary` | *"respeita os 11 princípios permanentes (Art. I) e o posicionamento Itá:Dart::Elixir:Erlang (Art. II)? Vira mágica escondida? Trai imutabilidade ou o `Result`?"* |
| o **design** de uma fase tocada | `compiler-craftsman` | a técnica correta **com o capítulo** (Dragon Book / Crafting Interpreters) que a funda. O retorno é o `Rationale`, não a decisão |
| **runtime** e todo codegen→Kernel | `dart-vm-expert` | o que a VM **entrega** (Grupo B — não implementamos) vs. o que **exige**, e o comportamento **por alvo** (VM/AOT/JS) |
| a **revisão** do diff, no fim | os três, em **contexto fresco** | cada um vê só o diff + os CAs, nunca o raciocínio que os produziu |

**Veredicto de identidade é bloqueante.** Violação de princípio permanente apontada pelo
`ita-visionary` marca **conflito aberto**: a spec não avança sem emenda explícita do dono
(Governança). Os outros dois produzem **gaps de correção** contra os CAs do §11 — não preferências
de estilo.

**O disparo é por tema, não por estágio.** Subagentes do Claude Code roteiam pela `description`.
Não existe gancho de fase, e a tabela acima não é um pipeline: é quando a consulta *rende*. Fora
disso, qualquer um pode ser chamado a qualquer momento — *"pergunta ao `dart-vm-expert` se isso
roda em AOT"*.

**A régua que sobreviveu junto:** um CA do §11 é um caso do corpus de conformance — programa `.tu`
→ saída/erro esperado —, validado ao vivo. Quando o codegen é tocado, o comportamento se declara
**por alvo**, e a paridade VM×JS se marca. Isso não é herança do spec-kit: é a R9 e o ledger de CAs,
que têm executável (`make codegen-test`).
