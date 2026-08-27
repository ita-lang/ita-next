# Subagentes-especialista de referência — `ita-next`

Três especialistas, um por pilar de referência do Itá. São **consultores/revisores**: fundamentam e
revisam decisões, mas **não executam** o `.tu` de verdade (isso é do agente do compilador + MCP `ita`).
Escritos seguindo [`../skills/authoring/`](../skills/authoring/SKILL.md) — cada um com `memory: project`
e o ciclo *consultar-antes / atualizar-depois*. (Era `.claude/authoring/`, um diretório que o Claude
Code não carregava; virou **skill** em 2026-08-06 — ver `SKILL.md:29`.)

| Agente | Especialista em… | Fonte (grounding) | Cobre |
|---|---|---|---|
| [`ita-visionary`](ita-visionary.md) | a **IDEIA/identidade** do Itá | `constitution.md` Art. I/II · `MANIFESTO.md` · ADRs de visão | **o quê** — design intent |
| [`compiler-craftsman`](compiler-craftsman.md) | a **técnica** de linguagem/compilador | **Dragon Book + Crafting Interpreters** (cita cap.) · `GRAMMAR.md` | **como** — Grupo A, caps 2–6→Kernel |
| [`dart-vm-expert`](dart-vm-expert.md) | a **Dart VM** (backend permanente) | `dart-lang/sdk/runtime/docs` (WebFetch) · `mrale.ph/dartvm` · Kernel do `ita/` | **onde roda** — Grupo B, caps 7–12 |

## Quando consultar cada um

Ver [`../rules/consulta-especialistas.md`](../rules/consulta-especialistas.md) — a tabela de *o que
pedir a quem*, escopada a `specs/**` e `.specify/memory/**`, que carrega sozinha ao abrir uma spec
ou um ADR.

Até 2026-08-26 essa doutrina morava dentro das skills `speckit-*`, amarrada a uma pipeline W0→W3.
As skills saíram: quatro das seis quebravam na primeira instrução, invocando
`.specify/scripts/bash/*.sh` — um diretório que nunca existiu neste clone. O `feature.json` que as
alimentava apontava para a `specs/012`, três specs atrás.

**Subagentes roteiam por `description`, por tema — não há gancho de fase.** Era o que a pipeline
tentava simular; a rule declara quando a consulta rende, e qualquer um pode ser chamado a qualquer
momento (*"pergunta ao `dart-vm-expert` se isso roda em AOT"*).

## Fronteiras (quem faz o quê)

- `ita-visionary` decide **identidade**, não técnica nem runtime.
- `compiler-craftsman` decide **técnica do front-end** (até Cap 6→Kernel), não identidade nem VM.
- `dart-vm-expert` cobre **o que a VM entrega/exige** (Cap 7+), não implementa codegen nem decide identidade.
- **Comportamento observável de verdade** (rodar `.tu`, conferir paridade VM×JS) → **agente do
  compilador + MCP `ita`**. Os três nunca chutam: citam fonte ou declaram a lacuna.
