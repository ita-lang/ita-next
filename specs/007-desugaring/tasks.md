# Tasks 007: Fase 3 — Desugaring / lowering

> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler`. Type-agnostic (antes do binding).
> **Regras:** transformer à mão (P11); spans preservados; gensym `$`+tag; **sem git durante subagente ativo**.

## Infra
- [ ] T001 `compiler/lib/frontend/desugar/desugar.dart` — transformer visitor post-order sobre a AST `sealed` (retorna `AstNode`); gensym reservado (`$`+tag, contador por passe).
- [ ] T002 `driver/driver.dart` + `bin/itac.dart` — comando `itac desugar <f.tu> --dump [--spans]` (parse → desugar → `AstDumper`); função pura `desugarProgram`/`desugarDump` testável.

## Reescritas (§5.2) — cada uma preservando span
- [ ] T003 Nulabilidade sobre `.some`/`.none`: `??`, `?.` (chain achatado), `!` (com `Panic`).
- [ ] T004 `if let` → `match .some/.none`; `guard let` → `match` com else no braço `.none`.
- [ ] T005 `where` → `match`/let-in (bind irrefutável, gensym); `>>` → closure `($c) => g(f($c))`; `|>` → `Call` (x 1º posicional).
- [ ] T006 `for x in it` → `while` + protocolo-iterador (`$it`); `$0`-closure → aridade por scan do corpo.
- [ ] T007 Retenção: `Try`, copy-with, `**` NÃO expandem (passam inalterados). Assertion pass de boa-formação do core.

## Conformância + testes + gate
- [ ] T008 `conformance/desugar/*.tu` → `.desugar` goldens (CA1–CA9) gerados ao vivo pelo orquestrador.
- [ ] T009 `desugar_test.dart` — unit por regra; **idempotência** (CA10); **span dentro do range** (CA11); assertion de core.
- [ ] T010 `dart analyze` limpo + `make test` verde + goldens de parse (001–006) inalterados.
