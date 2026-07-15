# ADR-0002: Extensão de arquivo `.tu` (migração `.glu`→`.tu`)

- **Status:** Accepted
- **Data:** 2026-03-26
- **Supersedes:** a extensão histórica `.glu` (nome "Glu" da linguagem, com `glu.toml`, `glu.lock`, cache `~/.glu/` e env `GLU_*`).

## Contexto

Antes de virar **Itá**, a linguagem se chamava "Glu" e seus artefatos carregavam o prefixo `glu`:
código-fonte em `.glu`, config de projeto em `glu.toml`, lock em `glu.lock`, cache central em
`~/.glu/` e variáveis de ambiente `GLU_*`. Com a consolidação da identidade **Itá**, essa
nomenclatura ficou inconsistente com o nome, a org (`ita-lang`) e a ergonomia pretendida.

## Decisão

**`.tu` é a única extensão de arquivo-fonte do Itá; `.glu` é aposentado.** A migração foi total e
atômica, cobrindo extensão, config, lock, cache e env:

- Fonte: `.glu` → `.tu`. Config: `glu.toml` → `ita.toml`. Lock: `glu.lock` → `ita.lock`.
- Cache central: `~/.glu/` → `~/.ita/`. Convenção de registry: `glu-pkg` → `ita-pkg`.
- Env vars: `GLU_*` → `ITA_*`, **com backward-compat** (aceita ambos, prioriza `ITA_*`).

## Consequências

- **Renomeados:** 38 exemplos em `ita/examples/` e 12 módulos em `stdlib/` (`.glu` → `.tu`).
- **Compilador atualizado:** `bin/itac.dart`, `lib/pm/pm.dart`, `lib/codegen/codegen.dart`,
  `test/test_runner.dart` (inclusive o path antigo `compiler/gluc.dart` → `compiler/bin/itac.dart`).
- **Tooling irmão migrado:** extensão VS Code (grammar/theme/snippets, scope `source.glu` → `source.tu`,
  language ID `glu` → `ita`) e gramática tree-sitter (`tree-sitter-glu` → `tree-sitter-ita`, todos os
  bindings; `src/parser.c`/`grammar.json` exigem `npx tree-sitter generate`).
- **Docs alinhados:** 7 arquivos `.md` (CLAUDE.md, MANIFESTO.md, READMEs e specs/planos).
- Smoke final: `itac run examples/hello.tu` compilou e executou com sucesso.

## Nota

O backward-compat vale **apenas** para env vars (`GLU_*`); não há tolerância a `.glu`/`glu.toml` no
resto do pipeline. Qualquer referência remanescente a `.glu` é resíduo a remover.
