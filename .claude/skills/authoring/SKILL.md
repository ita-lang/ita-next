---
name: authoring
description: >
  O estilo do `ita-next` para escrever AGENTES, SKILLS e a memória deles — a `description`
  como roteador, política de grounding anti-alucinação, modularidade, handoff nomeado, e o
  ciclo consultar-antes/atualizar-depois da memória de subagente. Use ao criar ou revisar
  qualquer artefato de `.claude/`. Aciona em pedidos como: "cria um subagente para X",
  "escreve uma skill de Y", "essa `description` roteia bem?", "onde isso mora — CLAUDE.md,
  rule ou skill?", "como o agente aprende entre sessões?", "revisa este SKILL.md".
  NÃO é sobre a linguagem Itá — identidade é do `ita-visionary`, técnica de compilador é do
  `compiler-craftsman`.
---

# Authoring — como escrevemos os agentes e skills do `ita-next`

> O **guia de estilo** dos artefatos de `.claude/`. Destilado de (1) o padrão real do dono nos
> seus skills (ex.: `flutter-ux-designer` da ACDG) e (2) a documentação oficial do Claude Code
> (memory · best-practices · sub-agents · skills · hooks).

**Escrito:** 2026-07-10 · **Virou skill:** 2026-08-06 · **Status:** referência viva.

## Por que existe

Antes de escrever o primeiro agente/skill do `ita-next`, fixamos **como** escrevê-los — do
mesmo jeito que fixamos a `constitution.md` e os ADRs antes de reescrever o compilador. Assim
todo agente do projeto nasce com o mesmo DNA: roteamento explícito, grounding anti-alucinação,
modularidade, handoff nomeado e memória que aprende.

Isto era `.claude/authoring/` — um diretório que **o Claude Code não lê**: não está na árvore
de `.claude/` que a doc reconhece (`rules/`, `skills/`, `agents/`, `hooks/`, `workflows/`,
`agent-memory/`, `commands/`, `output-styles/`). Eram 19 KB de guia que só entravam em contexto
se alguém mandasse ler — a mesma falha de "declaração sem catraca" que a auditoria de 2026-07-29
achou no emitter, aplicada ao harness. Como skill, a `description` acima fica visível em toda
sessão e o corpo carrega sob demanda.

## Índice

| Arquivo | O que traz |
|---|---|
| [`AGENT-SKILL-STYLE.md`](AGENT-SKILL-STYLE.md) | **O estilo do dono** destilado: anatomia de um `SKILL.md`/agente, a `description` como roteador, política de fontes/grounding, modularidade, handoff, tom, e as regras inegociáveis. |
| [`MEMORY-AND-LEARNING.md`](MEMORY-AND-LEARNING.md) | **Harness de memória + auto-aprendizado**: `CLAUDE.md` vs auto memory, `.claude/rules/`, e a **memória persistente de subagente** (`memory: project` → `MEMORY.md`) com o ciclo *consultar-antes / atualizar-depois*. |
| [`templates/SKILL.template.md`](templates/SKILL.template.md) | Esqueleto pronto de skill no nosso estilo (frontmatter + corpo + `modules/`). |
| [`templates/AGENT.template.md`](templates/AGENT.template.md) | Esqueleto pronto de subagente com `memory: project` e as instruções de auto-aprendizado. |

## Onde os artefatos moram

Só o que a doc do Claude Code reconhece. Um diretório inventado sob `.claude/` não é lido por
ninguém — foi o que aconteceu com o antecessor desta skill.

```
ita-next/.claude/
├─ skills/<nome>/SKILL.md         # skills — conhecimento/workflow sob demanda (você está aqui)
├─ agents/<nome>.md               # subagentes — contexto isolado, ferramentas próprias
├─ agent-memory/<nome>/MEMORY.md  # memória persistente de subagente (frontmatter `memory: project`)
├─ hooks/*.sh                     # scripts chamados pelos hooks do settings.json
├─ rules/*.md                     # regras, opcionalmente path-scoped via `paths:` no frontmatter
└─ settings.json                  # permissões e hooks (versionado; o .local.json é por máquina)
```

Um `<nome>` em `skills/` **pode ser symlink** para um diretório em outro lugar do disco — é assim
que as seis `speckit-*` do workspace `ita-lang/` entram aqui. A doc de skills, verbatim: *"A
`<skill-name>` entry in the enterprise, personal, or project locations can be a symlink to a
directory elsewhere on disk."*

## Precedência (herda a disciplina do projeto)

```
constitution.md  >  ADRs  >  MANIFESTO/ROADMAP  >  SKILL.md/agente  >  conhecimento geral do modelo
```

Nenhum agente/skill do `ita-next` pode contradizer a `constitution.md` (Art. I–IV) nem os ADRs.
Em dúvida de comportamento da linguagem/compilador: **valida ao vivo no MCP `ita`, nunca chuta**
(constitution Art. IV.1). Ver [`constitution.md`](../../../.specify/memory/constitution.md).

## Escolher o mecanismo antes de escrever

A doc do Claude Code tem uma tabela de gatilhos; esta é a versão curta para este repo:

| se o conteúdo… | vai para |
|---|---|
| precisa valer em **todo turno**, em qualquer arquivo | `CLAUDE.md` (alvo: < 200 linhas) |
| só vale mexendo em certos caminhos | `.claude/rules/` com `paths:` — mas **não** é re-injetado após `/compact` |
| é referência/procedimento carregado às vezes | uma skill |
| precisa acontecer **sempre**, sem depender de eu lembrar | um **hook** — instrução em prosa é pedido, hook é enforcement |
| lê muitos arquivos e só o resultado importa | um subagente |

## Fontes

- Claude Code — *How Claude remembers your project* (memory): CLAUDE.md, auto memory, rules, imports.
- Claude Code — *Best practices*: CLAUDE.md enxuto, skills/subagents/hooks, explore→plan→code, verificação.
- Claude Code — *Create custom subagents* (sub-agents): frontmatter, ferramentas, **`memory:` persistente**.
- Claude Code — *Extend Claude with skills* (skills): onde as skills moram, symlinks, `disable-model-invocation`.
- Claude Code — *Automate actions with hooks*: `.claude/hooks/*.sh` + `$CLAUDE_PROJECT_DIR`, stdin JSON, exit 2.
- Skill real do dono: `envolve/acdg/frontend/.claude/skills/flutter-ux-designer/` (SKILL.md + `modules/`).
