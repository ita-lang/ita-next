# Estilo de autoria de agentes/skills — o jeito do dono

> Destilado do skill real `flutter-ux-designer` (ACDG) + convenções já vigentes no projeto Itá
> (constitution, ADRs, "sempre via MCP, nunca chutar"). É a **régua de estilo** para todo agente/skill
> do `ita-next`. Adaptado do domínio UX (origem do exemplo) para o domínio **compilador**.

---

## 1. Filosofia — os traços permanentes

Todo agente/skill do dono compartilha o mesmo DNA. Se um artefato novo não tiver estes traços,
não está no estilo:

1. **Grounding anti-alucinação.** Afirmação forte exige **fonte canônica citada**. No UX era
   "citação literal ≥ 4 linhas com linha+página+autor+livro". No compilador, a fonte canônica é:
   **Dragon Book / Crafting Interpreters** (com capítulo), **`GRAMMAR.md`**, **constitution/ADRs**, e —
   para comportamento observável — o **oracle `ita/` via MCP `ita`**. Sem fonte, o agente **declara a
   lacuna** ("sobre X não tenho respaldo canônico — comento como opinião") em vez de inventar.
2. **Roteamento explícito.** Cada agente sabe o que faz **e o que não faz**. A `description` enumera
   as intenções que o acionam (com frases reais do usuário) e as que **não** o acionam (→ handoff
   nomeado para o agente vizinho). Ecossistema coeso, sem sobreposição silenciosa.
3. **Modularidade.** `SKILL.md` **fino** (o roteador + contrato) apontando para `modules/*.md`
   carregados **sob demanda**. Espelha a regra da doc: instrução de contexto permanente é curta;
   procedimento longo vira módulo/skill que só carrega quando relevante.
4. **Fonte-da-verdade e precedência.** Toda decisão referencia a hierarquia
   (`constitution > ADR > MANIFESTO/ROADMAP > SKILL > modelo`). O agente **referencia**, não duplica.
5. **Verificabilidade.** Nada de "confie em mim". No UX, cada finding trazia a citação. No compilador,
   cada afirmação de comportamento é **reproduzível** (caso `.tu` → saída via MCP `ita`, golden no CI).
6. **Tom de par técnico.** PT-BR, direto, sem floreio, sem "claro/excelente", sem preâmbulo nem
   postâmbulo. Identificadores de código sempre em `backticks`. Docs em PT-BR, código/erros em EN.

---

## 2. Qual mecanismo usar (skill × subagente × CLAUDE.md × rule × hook)

Antes de escrever, escolha o mecanismo certo (best-practices / features-overview):

| Mecanismo | Quando | Vive em |
|---|---|---|
| **CLAUDE.md** | Fato que vale em **toda** sessão do projeto (build, layout, "sempre X"). Curto (< 200 linhas). | `./CLAUDE.md` ou `.claude/CLAUDE.md` |
| **Rule path-scoped** | Instrução que só importa para certos arquivos (ex.: `compiler/lib/lexer/**`). | `.claude/rules/*.md` (campo `paths:`) |
| **Skill** | Conhecimento de domínio ou **workflow repetível** que carrega **sob demanda** (não polui todo contexto). Pode ser invocada por `/nome`. | `.claude/skills/<nome>/SKILL.md` |
| **Subagente** | Tarefa que lê **muitos arquivos** ou precisa de **foco isolado** e ferramentas próprias, sem sujar a conversa principal. Pode ter **memória persistente**. | `.claude/agents/<nome>.md` |
| **Hook** | Ação que precisa acontecer **sempre, deterministicamente** (não é conselho). Ex.: rodar o benchmark AOT no commit. | `.claude/settings.json` |

Regra prática do dono: **conhecimento/decisão → skill; trabalho pesado isolado → subagente; garantia
inquebrável → hook.** No Itá, o "compilar/rodar/depurar" já é um **subagente do compilador + MCP `ita`**
(constitution Art. IV.1) — skills novas fazem *handoff* para ele, não reimplementam.

---

## 3. Anatomia de um `SKILL.md` (o padrão do dono)

### 3.1 Frontmatter YAML

```yaml
---
name: <kebab-case>                 # obrigatório; = nome do diretório
description: >                     # obrigatório; é o ROTEADOR (ver §4). Multi-parágrafo, detalhado.
  <persona em 1 frase>. Use SEMPRE que o usuário pedir para: <lista de intenções>.
  Aciona em pedidos como: "<frase real 1>", "<frase real 2>".
  Diferencia-se de `<outro-agente>` (que faz <Y>) — esta skill faz <Z>, não <Y>.
grounding_mode: strict             # campo-convenção do dono: sinaliza política de fonte estrita
# disable-model-invocation: true   # opcional: só invocável por /nome (workflows com efeito colateral)
---
```

> **Nota:** `name` e `description` são os campos que o Claude Code lê. Campos extras como
> `grounding_mode` são **convenção documental do dono** (comunicam a política ao leitor/agente),
> não configuração enforçada — a política real vive no corpo, em "Regras inegociáveis".

### 3.2 Corpo — seções canônicas (na ordem do `flutter-ux-designer`)

1. **Título + Contrato base.** H1 com o papel; blockquote com o que a skill **herda**
   (ex.: "herda a `constitution.md` e os ADRs") e a **política de fontes** (o que exige citação).
2. **Persona em 1 frase.** Quem é e o que devolve.
3. **Quando ativar.** Tabela `Intenção do usuário → ✅ / ❌→handoff`. Frases reais.
4. **Output canônico.** O **formato estrito** da resposta (numerado). Para o Itá, sempre inclui:
   *o que se avalia · a fonte canônica (cap/§ do livro ou `GRAMMAR.md`) · a validação via MCP `ita` ·
   a sugestão concreta · lacunas declaradas*.
5. **Estrutura modular.** Tabela `módulo → conteúdo` de `modules/*.md`.
6. **Domínio do projeto.** Contexto que o agente assume (stack, oracle, alvos VM/AOT/JS, idioma).
7. **Handoff.** Tabela `se o usuário quer X → aciona Y` + a regra de handoff.
8. **Ferramentas obrigatórias.** Comandos/tools exatos (no Itá: MCP `ita`, `itac`, agente do compilador).
9. **Regras inegociáveis.** Lista numerada, imperativa, com ênfase (`IMPORTANTE`/`YOU MUST` quando crítico).

---

## 4. A `description` é o roteador — o padrão do dono

O que faz o Claude escolher (ou não) um agente é **a `description`**. O dono escreve `description`
longas e cirúrgicas com **três blocos**:

1. **Persona + gatilhos positivos** — "Use SEMPRE que o usuário pedir para: revisar…, validar…,
   decidir entre…". Verbos + objetos concretos do domínio.
2. **Frases-âncora reais** — "Aciona em pedidos como: '`>>` é um token ou dois?', 'por que o parser
   aceita isso?', 'esse `.tu` tokeniza como no `ita/`?'". Frases que o usuário realmente digitaria.
3. **Diferenciação (o mais importante)** — "**Diferencia-se de** `<vizinho>` (que faz Y) — este faz Z,
   não Y." Isso evita que dois agentes briguem pela mesma intenção.

Concreto e verificável vence vago: descreva o gatilho como o usuário o diria, não como um resumo
abstrato. (Best-practices: "write a clear description so Claude knows when to use it".)

---

## 5. Política de fontes / grounding (adaptada ao compilador)

O `flutter-ux-designer` usa **duas classes de fonte**. Traduzindo para o `ita-next`:

| Classe | No UX (origem) | No compilador (`ita-next`) | Exigência |
|---|---|---|---|
| **A — Princípio/teoria** | Livros de UX (Krug…) | **Dragon Book · Crafting Interpreters** | Citar **capítulo/§** que fundamenta a regra. |
| **B — Mecânica/norma** | `docs.flutter.dev/ui` | **`GRAMMAR.md` · constitution · ADRs** | Citar arquivo + seção/ADR. |
| **C — Comportamento observável** | (n/a) | **oracle `ita/` via MCP `ita`** | Reproduzir: `.tu` → saída. **Nunca chutar** (Art. IV.1). |

**Anti-padrão de fonte** (o dono flagra explicitamente): usar a fonte errada para o tipo de
afirmação. Ex.: justificar *por que* uma fase existe citando o `lexer.dart` do `ita/` (isso é
mecânica/oracle, não princípio) — princípio vem do **livro**; comportamento vem do **MCP**.
Sem nenhuma das três, o agente **declara a lacuna** em vez de afirmar.

---

## 6. Modularidade — `SKILL.md` fino + `modules/`

- O `SKILL.md` carrega em toda ativação: mantenha-o **enxuto** (roteador + contrato + índice de módulos).
- O **conteúdo pesado** (catálogos, passo-a-passo, tabelas grandes de anti-padrões) vai para
  `modules/<tema>.md`, lidos **sob demanda** pelo agente quando o tema aparece.
- Espelha a doc: CLAUDE.md < 200 linhas; procedimento longo → skill/módulo que só entra no contexto
  quando relevante. Menos ruído = mais aderência.

Exemplo de tabela de módulos (estilo do dono), já pensada para o `ita-next`:

| Módulo | Conteúdo |
|---|---|
| `modules/workflow.md` | Passo a passo: coleta → fase do Dragon Book → fonte → validação MCP → output. |
| `modules/fontes.md` | Mapa de capítulos (Dragon/CI) por fase + como citar `GRAMMAR.md`/ADR. |
| `modules/oracle.md` | Como consultar o `ita/` via MCP `ita` (o que ele dumpa, o que não) e ler goldens. |

---

## 7. Handoff — ecossistema coeso

Cada agente termina onde outro começa, **nomeando** o vizinho:

| Se o usuário quer… | Aciona… |
|---|---|
| **Compilar / rodar / depurar** um `.tu` de verdade | **agente do compilador + MCP `ita`** |
| Uma **decisão de linguagem** nova (tipo/semântica) | fluxo `/speckit-specify` (harness SDD) |
| **Reconciliar** sintaxe com a gramática executável | tarefa de **tree-sitter** |

**Regra de handoff:** se a intenção do usuário cai no vizinho, o agente **não improvisa** — passa o
bastão com o contexto que já levantou anexado. (No UX: "decide o quê/porquê; quem implementa é o
`flutter-expert`".)

---

## 8. Tom, idioma e formato de saída

- **PT-BR** na prosa; `backticks` em identificadores; **erros internos em EN kebab-case**
  (constitution Art. IV.5). Extensão `.tu`.
- **Direto, par técnico.** Sem "claro/excelente", sem preâmbulo/postâmbulo, sem elogiar o próprio
  trabalho. Mostra **evidência** (saída do MCP, golden, cap. do livro), não asserção.
- **Output estruturado e previsível** — o mesmo formato toda vez (o "Output canônico" da §3.2).

---

## 9. Regras inegociáveis (checklist ao criar um agente/skill)

1. A `description` tem os **3 blocos** (gatilhos positivos · frases-âncora · diferenciação do vizinho)?
2. Toda afirmação forte tem **fonte** (Classe A livro / B norma / C MCP) — ou uma **lacuna declarada**?
3. Comportamento de linguagem é **validado no MCP `ita`**, nunca chutado (Art. IV.1)?
4. O `SKILL.md` está **enxuto** (peso movido para `modules/`)?
5. Existe **handoff nomeado** para as intenções fora do escopo?
6. Não contradiz `constitution.md` nem ADRs? Respeita a **precedência**?
7. Tom de par técnico, PT-BR, `backticks`, erros EN kebab-case, **sem floreio**?
8. Se for subagente: tem **`memory: project`** e o ciclo *consultar-antes / atualizar-depois*?
   (Ver [`MEMORY-AND-LEARNING.md`](MEMORY-AND-LEARNING.md).)
9. Ferramentas **mínimas necessárias** declaradas (não dê `*` a um subagente de leitura)?
