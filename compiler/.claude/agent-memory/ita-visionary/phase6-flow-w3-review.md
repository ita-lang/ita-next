---
name: phase6-flow-w3-review
description: Review W3 do 1º lote da F6 (flow-walk, spec 014 §2–§3) — APROVA COM EMENDAS; o achado do "blueprint fantasma" estende a citação-ou-nome; write-only capture sustentada como itaiana.
metadata:
  type: project
---

# Review W3 — flow-walk da F6 (2026-07-17)

Veredicto: **APROVA COM EMENDAS** (parecer no scratchpad da sessão; emendas E1–E6).
Os 5 rulings do §12 implementados com fidelidade; nenhum princípio permanente tocado.

## Doutrina nova: registro exige endereço VERSIONADO (extensão da [[doctrine-citacao-ou-nome]])
O código citava "blueprint §14-L1..L4" em 7 pontos como o REGISTRO de recusas deliberadas
("registrada para não reabrir por acidente") — e o artefato **não estava no repo**. Citação sem
endereço versionado é a mesma doença da promessa-de-artefato (ADR-0014): o grep de amanhã acha
NADA e a recusa reabre por acidente. **Regra:** honestidade em comentário de código não é assento;
o que a spec/ledger não cataloga, não existe para o usuário da linguagem (lição 011 §1.2b, de novo).
Foi a E1 (BLOQUEIA-COMMIT): commitar o blueprint, dar assento na spec, ou re-apontar as citações.

## Ruling de identidade: write-only capture erra na criação — SUSTENTADA
`var x: Int; let f = { x = 1 }` ⟹ `capture-before-assign` (mais estrito que C#). É itaiano por 4
razões: a casa erra para o estrito (must-use/exaustividade/ADR-0013) · a captura é da CÉLULA
(atribuir também a usa) · o idioma morto — célula mutável via par de closures — é o contrabando de
estado que a visão de actors (D-V1, §12-4) recusa · relaxar depois é backwards-compatible. O risco
é só de ENSINABILIDADE (o erro num sítio de atribuição parece contradição) — resolve no corpus
(E3), não na regra. Sem discordância a registrar para o dono.

## Confirmados sem emenda
- CA21 (`panic("TODO")` verde) nomeado e ensinando — a tensão do §12-1 dissolvida em fixture.
- Never type-informed (P7): `Never` É o tipo do que não volta; sem canal paralelo de exceção.
- Never aninhado não propaga: corte conservador na direção certa (falso-positivo PEDE, nunca
  mente verde) — itaiano, desde que o registro exista (E1).
- Nomes EN kebab-case: todos nomeiam o pecado; `guard-must-exit` nomeia a obrigação (voz do
  diagnóstico Swift, §12-3) — desvio aceitável, não vira padrão.
- `itac flow` comando próprio = fase-por-comando (disciplina, não conveniência); gate I3 com razão
  dita ("cascata, não diagnóstico").

Relacionadas: [[phase6-flow-identity-rulings]] (na memória-raiz do repo) · [[doctrine-citacao-ou-nome]].
