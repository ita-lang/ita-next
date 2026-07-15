# Conformance cases — Épico 002 (reescrita)

> Phase 1 do `/speckit-plan`. Mapeia os CA1–CA6 do épico (spec §11) às **fontes-oracle no `ita/`**. Como é
> um épico, os "casos" são conjuntos herdados do `ita/`, não `.tu` individuais novos — cada sub-spec por
> fase seleciona o subconjunto que ela habilita. Oracle = `ita/` via MCP `ita`.

## CA → fonte-oracle no `ita/`

| CA (épico §11) | O que valida | Fonte-oracle no `ita/` | Quando (fase) |
| :-- | :-- | :-- | :-- |
| **CA1** | corpus de conformância (`valid/` passa, `invalid/` falha), mesmas mensagens de erro | `ita/compiler/test/conformance/{valid,invalid}` (54+22) via `itac check` | cresce por fase; completo na Fase 5 |
| **CA2** | goldens de output byte-a-byte (VM/AOT) | `ita/examples/*.expected` (33 goldens) via `test_runner` | por fase, conforme as construções entram |
| **CA3** | paridade VM×JS; `itac build --target=js` | `ita/compiler/test/js_parity/expected.txt` (placar atual) | Fase 7 (codegen) |
| **CA4** | `itac` AOT, compile-time perto do Go | `ita/compiler/test/bench/compile_bench.sh` (mediana < 0,5 s/arq) | Fase 1 (desde o início) |
| **CA5** | todos os testes rodam no CI | espelhar `ita/.github/workflows/ci.yml` (enxuto) | Fase 1 |
| **CA6** | invariantes de arquitetura | inspeção estrutural: `codegen/` é diretório (não classe única); `conformance/` ⊥ `examples/`; sem `runtime/` | verificado a cada fase |

## Superfícies tocadas (o épico como um todo)

- **Sintaxe:** herdada do `GRAMMAR.md` do `ita/` — reconciliada na Fase 2 (sem `grammar-delta.md` aqui).
- **Tipos/semântica:** reescritos na Fase 5 (side-table, ADR-0004) — contra o oracle.
- **Codegen:** reescrito na Fase 7, fatiado; paridade VM×JS via golden-runner herdado.
- **Toolchain:** reaproveitada do `ita/` (ADR-0003) — não reescrita.
