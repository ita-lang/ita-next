# ADR-0008: Harness SDD (spec-kit adaptado ao compilador)

- **Status:** Accepted
- **Data:** 2026-07-10
- **Relacionados:** [[ADR-0007]] (templates derivados do Dragon Book), [[ADR-0001]] (constitution §Art. II). Fonte: [[ita-harness-sdd-speckit]].

## Contexto

Faltava um processo padrão para especificar e implementar mudanças no compilador — em especial as
decisões de spec do M4 (largura de `Int`, Float em container genérico) precisavam de um veículo
formal. Referências: o GitHub **spec-kit** e o harness turbinado do `core-api`. O workspace `ita-lang/`
não é git (cada sub-repo é git próprio), o que condicionou o versionamento.

## Decisão

**Adotar o workflow spec-kit adaptado ao compilador**, no nível do workspace:

- **Fluxo:** `/speckit-constitution` → `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` →
  `/speckit-tasks` → `/speckit-implement`. Artefatos gerados em **PT-BR**.
- **Skills** `speckit-*` em `.claude/skills/` (6 núcleo, re-domadas para compilador — grep limpo de
  TS/DDD/web, mecânica spec-kit intacta).
- **`.specify/`:** `constitution.md` (fonte única de veto, 4 artigos) + templates **derivados do Dragon
  Book** (spec-template RFC multi-fase citando capítulos; plan/tasks fail-first
  RED→GREEN→VALIDATE→QUALITY, VALIDATE via MCP `ita` + paridade VM×JS) + `init-options.json`/`extensions.yml`
  (numbering `specs/NNN-nome/`, hooks git `enabled: false` até versionar).
- **Specs** de feature em `specs/`.

## Consequências

- **Piloto executado end-to-end (2026-07-10):** `specs/001-int-bitwise-semantics/` com pacote SDD
  completo (spec clarified · checklists · plan · design-notes · conformance-cases · **18 tasks**
  fail-first). `/speckit-implement` da 001 ainda pendente (mexe no `ita/` → via agente + MCP).
- **Não versionado por ora** (workspace não é git); git-hooks registrados porém desativados.
- **Débito:** `.specify/scripts/bash/` do spec-kit não foi copiado (plan/tasks feitos manualmente).
- **Fase 2 (futura):** pipeline fail-first formal + experts por fase + hooks bloqueantes (itac check,
  benchmark, conformance).
