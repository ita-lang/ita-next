# Checklist de Qualidade da Spec: Reescrita do compilador (épico Dragon Book)

**Propósito**: validar completude da spec-mãe (ÉPICO) antes de planejar
**Criado**: 2026-07-10
**Spec**: [../spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Formato de **épico** (spec-mãe) — as fases técnicas §2–§8 foram substituídas por §A Arquitetura-alvo / §B Faseamento / §C Estratégia oracle (adaptação justificada: um épico planeja, não implementa)
- [x] §1 tem motivação + "antes → depois" (de **arquitetura**, pois a *linguagem* não muda) e não-objetivos
- [x] Prosa em PT-BR; identificadores em `backticks`
- [x] Cada fase do faseamento (§B) ancorada no capítulo do Dragon Book (Cap 3→6)

## Completude do épico

- [x] Nenhum marcador [NEEDS CLARIFICATION] — decisões de arranque já tomadas pelo dono (reescrever do zero · `ita-next/` vazio · oracle `ita/` · épico primeiro)
- [x] §0.5 Constitution check mapeia ADR-0001…0011 + princípios → aderência; **conflito: nenhum**
- [x] §B Faseamento define as sub-specs (Fases 1–7) com capítulo e entrega; cada uma será um `/speckit` próprio
- [x] §C Estratégia oracle define "pronto" por fase (goldens + conformância + paridade vs `ita/`)
- [x] §10 registra o cutover como decisão futura (não trava o épico)
- ~~§4 formal / §7.3 por alvo~~ — **N/A nesta spec-mãe**; virão nas sub-specs de semântica (Fase 5) e codegen (Fase 7)

## Prontidão

- [x] CA1–CA6 (§11) são **testáveis** e observáveis: corpus `valid/invalid`, goldens byte-a-byte, paridade VM×JS, benchmark AOT, invariantes de arquitetura
- [x] CAs validáveis via MCP `ita` (o `ita/` gera o esperado; o `ita-next` confere) + CI
- [x] Constitution check sem conflito (a linguagem não muda; só a implementação)
- [x] Definition of Done coerente: todas as sub-specs verdes + CA1–CA6 + decisão de cutover

## Resultado

- **Status: `clarified` — todos os itens ✓** (com N/A justificado para as seções de fase técnica, próprias das sub-specs).
- **Pronta para `/speckit-plan`** — o plano do épico definirá: a Fase 1 (Léxico + scaffold) em detalhe, a ordem das sub-specs, e a mecânica do oracle.
