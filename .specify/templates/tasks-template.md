<!--
================================================================================
 TEMPLATE DE TASKS — Itá (decomposição fail-first "compiler-shaped")
================================================================================
 Gerado por `/speckit-tasks`. Copiado para: specs/<NNN>-<short-name>/tasks.md
 Pré-requisito: plan.md pronto.

 Ordem fail-first adaptada a compilador:
   RED       → escreve casos de conformância (.tu) que FALHAM, derivados dos CA (spec §11)
   GREEN     → implementa em semantic/codegen até os casos passarem
   VALIDATE  → roda via MCP `ita` (VM) + confere paridade VM×JS
   QUALITY   → CI verde (conformance + unit + benchmark de compile-time AOT)

 Convenções:
   - Cada task tem caminho de arquivo concreto e critério de conclusão binário.
   - `[P]` = pode rodar em paralelo (arquivos independentes, sem dependência de ordem).
   - Nenhuma task de código antes das tasks RED correspondentes (fail-first).
   - Toda validação de comportamento é via MCP `ita` — nunca "chutar" saída.
 Apague este bloco ao finalizar.
================================================================================
-->

# Tasks <NNN>: <título da mudança>

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md)

## Fase RED — casos de conformância que falham

<!-- Um caso por CA da spec §11. Devem falhar ANTES da implementação. -->

- [ ] **T001** — `examples/<caso>.tu` + saída esperada (`<caso>.expected`) para **CA1**. Confirmar que FALHA hoje via MCP `ita`.
- [ ] **T002** `[P]` — caso de erro para **CA2** (`<erro-interno-kebab-case>` com span).
- [ ] **T003** `[P]` — se toca codegen: registrar o exemplo no `js_parity/expected.txt` com o status atual (pré-fix).

## Fase GREEN — implementação até passar

<!-- Ordenada por dependência de fase (tipo antes de codegen). -->

- [ ] **T010** — <mudança na fase X> em `compiler/lib/<...>.dart`. Critério: CA1 passa na VM (via MCP `ita`).
- [ ] **T011** — <mudança na fase Y> em `compiler/lib/<...>.dart`. Depende de: T010.
- [ ] **T012** `[P]` — mensagem de erro de tipo (§4.6) em `semantic/type_checker.dart`.

## Fase VALIDATE — comportamento e paridade

- [ ] **T020** — rodar todos os CA via **MCP `ita`** (`run`) na VM; conferir saídas byte-a-byte com o esperado.
- [ ] **T021** — se toca codegen: conferir **paridade VM×JS** (dart2js) e atualizar `js_parity/expected.txt` (status novo, ex.: `NUM→MATCH`).
- [ ] **T022** — atualizar `GRAMMAR.md` / tree-sitter se a spec tocou sintaxe (§3.5).

## Fase QUALITY — gate final

- [ ] **T030** — suíte de conformância verde (casos novos incluídos).
- [ ] **T031** — testes unitários do compilador verdes.
- [ ] **T032** — **benchmark de compile-time (`itac` AOT) sem regressão**.
- [ ] **T033** — Constitution check final sem conflito; Definition of Done da spec satisfeita.

## Notas de execução

<!-- Dependências não óbvias, o que NÃO paralelizar, e o lembrete operacional: -->
- Não mexer no git (checkout/branch/commit) enquanto um subagente edita o mesmo repo.
- Toda saída de programa é validada via MCP `ita`, nunca assumida.
