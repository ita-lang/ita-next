# Subagentes-especialista de referência — `ita-next`

Três especialistas, um por pilar de referência do Itá. São **consultores/revisores**: fundamentam e
revisam decisões, mas **não executam** o `.tu` de verdade (isso é do agente do compilador + MCP `ita`).
Escritos seguindo [`../authoring/`](../authoring/) — cada um com `memory: project` e o ciclo
*consultar-antes / atualizar-depois*.

| Agente | Especialista em… | Fonte (grounding) | Cobre |
|---|---|---|---|
| [`ita-visionary`](ita-visionary.md) | a **IDEIA/identidade** do Itá | `constitution.md` Art. I/II · `MANIFESTO.md` · ADRs de visão | **o quê** — design intent |
| [`compiler-craftsman`](compiler-craftsman.md) | a **técnica** de linguagem/compilador | **Dragon Book + Crafting Interpreters** (cita cap.) · `GRAMMAR.md` | **como** — Grupo A, caps 2–6→Kernel |
| [`dart-vm-expert`](dart-vm-expert.md) | a **Dart VM** (backend permanente) | `dart-lang/sdk/runtime/docs` (WebFetch) · `mrale.ph/dartvm` · Kernel do `ita/` | **onde roda** — Grupo B, caps 7–12 |

## Mapa de disparo na pipeline (W0 → W3)

W0→W3 = as fases do harness SDD. Os disparos foram amarrados **dentro das skills speckit**
(`../../../.claude/skills/`), de forma graceful (se o agente não existir, a skill segue sem ele):

| Fase | Skill | Especialista disparado | Papel |
|---|---|---|---|
| **W0** specify | `speckit-specify` (§0.5) | **`ita-visionary`** | Constitution-check de identidade (Art. I/II); violação = conflito aberto. |
| **W1** plan | `speckit-plan` (Phase 0) | **`compiler-craftsman`** + **`dart-vm-expert`** | fundamenta o `design-notes.md`: técnica+capítulo · §8 runtime e comportamento por alvo. |
| **W2** tasks | `speckit-tasks` | — | fatiamento mecânico; sem consulta dedicada. |
| **W3** implement | `speckit-implement` (validação) | os **três** (contexto fresco) | revisão adversarial do diff: ergonomia · técnica · codegen→Kernel VM/AOT/JS. |

> **Como o disparo funciona de fato:** subagentes do Claude Code roteiam por **delegação via
> `description`** (por tema), não por gancho de estágio. O wiring acima é uma **instrução dentro da
> skill** para invocar o especialista na fase certa — determinístico o suficiente para a pipeline, sem
> depender de o modelo "adivinhar". Fora da pipeline, qualquer um pode ser chamado por tema a qualquer
> momento (ex.: *"pergunta ao `dart-vm-expert` se isso roda em AOT"*).

## Fronteiras (quem faz o quê)

- `ita-visionary` decide **identidade**, não técnica nem runtime.
- `compiler-craftsman` decide **técnica do front-end** (até Cap 6→Kernel), não identidade nem VM.
- `dart-vm-expert` cobre **o que a VM entrega/exige** (Cap 7+), não implementa codegen nem decide identidade.
- **Comportamento observável de verdade** (rodar `.tu`, conferir paridade VM×JS) → **agente do
  compilador + MCP `ita`**. Os três nunca chutam: citam fonte ou declaram a lacuna.
