# Authoring — como escrevemos os agentes e skills do `ita-next`

> Diretrizes e anotações de **autoria de agentes/skills do Claude** para este projeto.
> Não são agentes ainda — é o **guia de estilo** que os nossos agentes/skills vão seguir.
> Destilado de (1) o padrão real do dono nos seus skills (ex.: `flutter-ux-designer`
> da ACDG) e (2) a documentação oficial do Claude Code (memory · best-practices · sub-agents).

**Escrito:** 2026-07-10 · **Status:** referência viva (evolui conforme criamos os agentes).

## Por que esta pasta existe

Antes de escrever o primeiro agente/skill do `ita-next`, fixamos **como** escrevê-los — do
mesmo jeito que fixamos a `constitution.md` e os ADRs antes de reescrever o compilador. Assim
todo agente do projeto nasce com o mesmo DNA: roteamento explícito, grounding anti-alucinação,
modularidade, handoff nomeado e memória que aprende.

## Índice

| Arquivo | O que traz |
|---|---|
| [`AGENT-SKILL-STYLE.md`](AGENT-SKILL-STYLE.md) | **O estilo do dono** destilado: anatomia de um `SKILL.md`/agente, a `description` como roteador, política de fontes/grounding, modularidade, handoff, tom, e as regras inegociáveis. |
| [`MEMORY-AND-LEARNING.md`](MEMORY-AND-LEARNING.md) | **Harness de memória + auto-aprendizado**: `CLAUDE.md` vs auto memory, `.claude/rules/`, e a **memória persistente de subagente** (`memory: project` → `MEMORY.md`) com o ciclo *consultar-antes / atualizar-depois*. |
| [`templates/SKILL.template.md`](templates/SKILL.template.md) | Esqueleto pronto de skill no nosso estilo (frontmatter + corpo + `modules/`). |
| [`templates/AGENT.template.md`](templates/AGENT.template.md) | Esqueleto pronto de subagente com `memory: project` e as instruções de auto-aprendizado. |

## Onde os artefatos de verdade vão morar (quando criarmos)

```
ita-next/.claude/
├─ skills/<nome>/SKILL.md         # skills (workflows/conhecimento sob demanda)
│  └─ modules/*.md                # módulos carregados sob demanda pela skill
├─ agents/<nome>.md               # subagentes (contexto isolado, ferramentas próprias)
├─ agent-memory/<nome>/MEMORY.md  # memória persistente de subagente (memory: project)
└─ rules/*.md                     # regras path-scoped (carregadas por padrão de arquivo)
```

## Precedência (herda a disciplina do projeto)

```
constitution.md  >  ADRs  >  MANIFESTO/ROADMAP  >  SKILL.md/agente  >  conhecimento geral do modelo
```

Nenhum agente/skill do `ita-next` pode contradizer a `constitution.md` (Art. I–IV) nem os ADRs.
Em dúvida de comportamento da linguagem/compilador: **valida ao vivo no MCP `ita`, nunca chuta**
(constitution Art. IV.1). Ver [`constitution.md`](../../../.specify/memory/constitution.md).

## Fontes

- Claude Code — *How Claude remembers your project* (memory): CLAUDE.md, auto memory, rules, imports.
- Claude Code — *Best practices*: CLAUDE.md enxuto, skills/subagents/hooks, explore→plan→code, verificação.
- Claude Code — *Create custom subagents* (sub-agents): frontmatter, ferramentas, **`memory:` persistente**.
- Skill real do dono: `envolve/acdg/frontend/.claude/skills/flutter-ux-designer/` (SKILL.md + `modules/`).
