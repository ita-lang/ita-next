# Harness de memória e auto-aprendizado

> Como dar aos agentes/skills do `ita-next` uma **memória que persiste entre sessões** e **aprende com
> cada interação**. Fonte: docs oficiais do Claude Code — *memory*, *best-practices*, *sub-agents*.
> O objetivo: um agente do compilador que, ao longo do tempo, acumula os padrões do codegen, os bugs
> conhecidos do oracle `ita/`, e as decisões de fase — sem que a gente re-explique tudo toda vez.

---

## 1. Dois sistemas de memória (complementares)

| | **CLAUDE.md** | **Auto memory (`MEMORY.md`)** |
|---|---|---|
| Quem escreve | **Você** | **O Claude** (sozinho) |
| Contém | Instruções e regras | Aprendizados e padrões descobertos |
| Escopo | Projeto / usuário / org | Por repositório (ou por subagente) |
| Carregado | Toda sessão, **inteiro** | Toda sessão, **1ªs 200 linhas / 25KB** do `MEMORY.md` |
| Use para | Convenções, layout, "sempre X" | Comandos de build, insights de debug, preferências descobertas |

Os dois são **contexto, não configuração enforçada**. Para algo que precisa acontecer sempre e sem
exceção, use **hook**, não CLAUDE.md. (memory doc: *"Claude treats them as context, not enforced
configuration."*)

---

## 2. `CLAUDE.md` — onde vive e como escrever

**Locais** (carregados do mais amplo ao mais específico; o mais próximo do cwd é lido por último):

| Escopo | Local | Uso |
|---|---|---|
| Usuário | `~/.claude/CLAUDE.md` | preferências suas em todos os projetos |
| Projeto | `./CLAUDE.md` ou `.claude/CLAUDE.md` | instruções do time, versionadas |
| Local | `./CLAUDE.local.md` (no `.gitignore`) | suas notas pessoais do projeto |

**Escrever bem** (best-practices — o teste é *"remover isto faria o Claude errar?"* Se não, corte):

| ✅ Inclua | ❌ Exclua |
|---|---|
| Comandos que o Claude não adivinha (`tools/build-itac.sh`) | O que ele descobre lendo o código |
| Regras de estilo que fogem do padrão (erros EN kebab-case) | Convenções óbvias da linguagem |
| Como testar (corpus de conformância + MCP `ita`) | Documentação de API extensa (linke) |
| Decisões arquiteturais do projeto (aponta ADRs) | Explicações longas / tutoriais |
| Gotchas não-óbvios (o separador `_` do oracle é bugado) | "escreva código limpo" |

- **Tamanho:** mire **< 200 linhas**. Arquivo inchado faz o Claude **ignorar** metade — as regras
  importantes se perdem no ruído.
- **Estrutura:** headers + bullets. **Especificidade:** "use 2 espaços" > "formate direito".
- **Imports:** `@caminho/arquivo.md` expande outro arquivo no launch (profundidade máx. 4). Útil para
  modularizar sem duplicar (ex.: `@AGENTS.md`). *Importar não reduz contexto* — o arquivo entra inteiro.
- **`.claude/rules/`:** para instrução que só vale em certos arquivos, use rule **path-scoped**
  (frontmatter `paths: ["compiler/lib/lexer/**"]`) — carrega só quando o Claude toca esses arquivos.

---

## 3. Auto memory do repositório

Ligada por padrão (Claude Code ≥ 2.1.59). O Claude salva notas por conta própria quando julga que
serão úteis no futuro. Mora em `~/.claude/projects/<project>/memory/`:

```
MEMORY.md          # índice conciso, carregado toda sessão (1ªs 200 linhas / 25KB)
debugging.md       # notas detalhadas, lidas SOB DEMANDA
codegen-notes.md   # …
```

`MEMORY.md` é o **índice**: o Claude move o detalhe para arquivos-tema e mantém o índice enxuto.
Auditável e editável via `/memory`.

> Este projeto **já usa** essa memória de repo — é a pasta `memory/` com `MEMORY.md` que carrega no
> começo de cada sessão. As diretrizes abaixo são para dar o **mesmo poder a cada subagente**.

---

## 4. ⭐ Memória persistente de subagente (`memory: project`)

**É esta a peça central do pedido.** Um subagente pode ter o **seu próprio** diretório de memória que
sobrevive entre conversas — ele acumula conhecimento (padrões de código, insights de debug, decisões).

Basta um campo no frontmatter YAML do agente:

```yaml
---
name: code-reviewer
description: Reviews code for quality and best practices
memory: project
---

You are a code reviewer. As you review code, update your agent memory with
patterns, conventions, and recurring issues you discover.
```

**Escopos** (escolha por quão amplo o aprendizado deve valer):

| Scope | Local | Use quando |
|---|---|---|
| `user` | `~/.claude/agent-memory/<nome-do-agente>/` | o aprendizado vale em **todos** os projetos |
| `project` | `.claude/agent-memory/<nome-do-agente>/` | conhecimento **do projeto**, compartilhável via git |
| `local` | `.claude/agent-memory-local/<nome-do-agente>/` | do projeto, mas **não** versionado |

**Quando `memory:` está ligado, automaticamente:**

- o system prompt do subagente ganha instruções de **ler e escrever** no diretório de memória;
- entram nele as **1ªs 200 linhas / 25KB** do `MEMORY.md` daquele agente (com instrução de curar se passar);
- as ferramentas **Read, Write e Edit são habilitadas** para o agente gerir seus arquivos de memória.

> **`project` é o scope recomendado** para o `ita-next` — o conhecimento do compilador é do projeto e
> deve ser compartilhável via git (fica em `.claude/agent-memory/<nome>/`, entra no repositório).

---

## 5. ⭐ O ciclo de auto-aprendizado — consultar antes / atualizar depois

A essência (do pedido, e literal na doc *sub-agents › Persistent memory tips*):

> Adicione `memory: project` (ou `user`/`local`) no YAML do agente e ele terá um **diretório
> persistente** para manter um `MEMORY.md` que **aprende com cada interação**. Peça ao agente para
> **consultar sua memória antes de trabalhar** e **atualizá-la após completar tarefas**.

Como operacionalizar — **duas frentes**:

1. **No markdown do agente** (para ele manter a memória proativamente, sozinho):

   ```markdown
   Antes de começar, **consulte sua memória** (`MEMORY.md`) por padrões que já viu neste compilador.
   Ao terminar, **atualize sua memória** com o que descobriu — padrões de codegen, quirks do oracle
   `ita/`, decisões de fase, armadilhas. Escreva notas concisas: **o que** você achou e **onde**.
   Mantenha o `MEMORY.md` como índice enxuto; mova detalhe para arquivos-tema.
   ```

2. **No pedido pontual** (reforço quando você invoca o agente):
   - antes: *"Revise este passe de codegen e **cheque sua memória** por padrões que já viu."*
   - depois: *"Agora que terminou, **salve o que aprendeu** na sua memória."*

Com o tempo isso vira uma **base de conhecimento institucional** que torna o agente mais eficaz a
cada sessão — exatamente o que queremos para os agentes do compilador (o léxico/parser/codegen têm
muitos padrões recorrentes e quirks do oracle que não vale re-descobrir toda vez).

---

## 6. Como aplicaremos no `ita-next`

Agentes candidatos a **`memory: project`** (a criar depois — aqui só o desenho):

| Agente (futuro) | O que a memória acumula |
|---|---|
| **agente do compilador** (léxico→codegen) | quirks do oracle `ita/` (ex.: separador `_` bugado), formato de dump do MCP, padrões de passe. |
| **conformance/oracle** | mapeamento CA → caso `.tu` → saída esperada; casos que o `ita/` crasha. |
| **revisor de fase** (Dragon Book) | qual capítulo fundamenta cada fase; contratos entre fases (ex.: Binding × Semântica). |

**Higiene da memória** (para não repetir o vício do CLAUDE.md inchado):

- `MEMORY.md` é **índice**, não despejo — detalhe vai para arquivo-tema, lido sob demanda.
- Uma nota = um fato, concisa, com **onde** (arquivo/linha, ADR, cap.).
- Aprendizado que virou **decisão firme** graduou-se: promova-o a **ADR** ou à `constitution.md`
  (a precedência real do projeto), e deixe na memória só o ponteiro. Memória de agente é para o
  **tácito recorrente**, não para substituir o registro formal.
- Reveja/edite via `/memory`; memória é markdown puro, auditável.

---

## 7. Resumo operacional

1. **Instrução fixa e ampla** → `CLAUDE.md` (curto, específico, < 200 linhas).
2. **Instrução por tipo de arquivo** → `.claude/rules/*.md` com `paths:`.
3. **Garantia inquebrável** → hook.
4. **Subagente que aprende** → `memory: project` no YAML + o ciclo *consultar-antes / atualizar-depois*
   escrito no próprio markdown do agente.
5. **Sempre:** memória é **contexto**, não lei. A lei do projeto é `constitution > ADR`. Comportamento
   de linguagem se confirma no **MCP `ita`**, não na memória.
