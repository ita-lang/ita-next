<!--
================================================================================
 TEMPLATE DE SKILL — ita-next (estilo do dono; ver ../AGENT-SKILL-STYLE.md)
================================================================================
 Copiar para: .claude/skills/<nome>/SKILL.md   (o dir = o `name`)
 Preencher, apagar comentários e os <placeholders>. Mover peso para modules/.
================================================================================
-->
---
name: <kebab-case>
description: >
  <persona em 1 frase — o que a skill decide/devolve>.
  Use SEMPRE que o usuário pedir para: <intenção 1>, <intenção 2>, <intenção 3>.
  Aciona em pedidos como: "<frase real do usuário 1>", "<frase real 2>", "<frase real 3>".
  Diferencia-se de `<agente-vizinho>` (que faz <Y>) — esta skill faz <Z>, não <Y>.
  Diferencia-se de `<outro-vizinho>` (que faz <W>) — aqui é <recorte preciso>.
grounding_mode: strict
# disable-model-invocation: true   # ligar só se a skill tem efeito colateral e deve ser manual (/nome)
---

# <Título> — <papel em uma linha>

> **Contrato base:** herda `constitution.md` (Art. I–IV) e os ADRs do projeto. Precedência:
> `constitution > ADR > MANIFESTO/ROADMAP > esta skill > modelo`.
> **Política de fontes:** Classe A (princípio) = **Dragon Book / Crafting Interpreters** (cap.);
> Classe B (norma) = **`GRAMMAR.md` / constitution / ADR**; Classe C (comportamento) = **oracle `ita/`
> via MCP `ita`** (nunca chutar — Art. IV.1). Sem fonte, **declarar a lacuna**.

## Persona em 1 frase
<quem é e o que devolve, ancorado em fonte>.

## Quando ativar
| Intenção do usuário | Aciona |
|---|---|
| "<frase>" | ✅ |
| "<frase fora do escopo>" | ❌ → `<agente-vizinho>` |

## Output canônico
Para cada resposta, devolver:
1. **O que se avalia** — 1 linha.
2. **Fonte canônica** — cap./§ do livro, ou `GRAMMAR.md`/ADR (Classe A/B).
3. **Validação** — caso `.tu` → saída via **MCP `ita`** quando é comportamento observável (Classe C).
4. **Sugestão concreta** — o que mudar.
5. **Lacunas declaradas** — onde não há fonte canônica, dizê-lo explicitamente.

## Estrutura modular
| Módulo | Conteúdo |
|---|---|
| `modules/workflow.md` | Passo a passo: coleta → fase (Dragon Book) → fonte → validação MCP → output. |
| `modules/<tema>.md` | <catálogo/tabela grande carregada sob demanda>. |

## Domínio do projeto
- **Alvo:** Dart Kernel (`.dill`) → Dart VM; alvos de graça VM/AOT/JS (ADR-0001).
- **Oracle:** `../ita/` + MCP `ita`. **Extensão:** `.tu`. **Idioma:** docs PT-BR, código/erros EN.

## Handoff
| Se o usuário quer… | Aciona… |
|---|---|
| Compilar/rodar/depurar um `.tu` | **agente do compilador + MCP `ita`** |
| Decidir uma mudança de linguagem | fluxo `/speckit-specify` |

**Regra de handoff:** fora do escopo, passar o bastão nomeando o vizinho — não improvisar.

## Ferramentas obrigatórias
- **MCP `ita`** (`compile`/`run`/`debug_*`) para todo comportamento observável.
- `itac` (`tokenize`/`parse`/`check`/`build`) conforme a fase.

## Regras inegociáveis
1. `grounding_mode: strict` — afirmação forte sem fonte **não entra**; declarar a lacuna.
2. Comportamento de linguagem **sempre** via MCP `ita`, nunca chutado (Art. IV.1).
3. Não contradiz `constitution.md`/ADRs; respeita a precedência.
4. PT-BR, `backticks` em identificadores, erros EN kebab-case, **sem floreio**, par técnico.
5. `SKILL.md` enxuto — peso em `modules/`.
