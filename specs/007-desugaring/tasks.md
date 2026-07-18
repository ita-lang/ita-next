# Tasks 007: Fase 3 — Desugaring / lowering

> **Status:** ✅ **IMPLEMENTADA** (com 1 divergência declarada — ver T004) — débito de bookkeeping fechado na auditoria de 2026-07-17. Evidência: `desugar.dart` (1169 ln), 46 goldens `conformance/desugar/*.desugar`, `desugar_test.dart` com CA10 (idempotência) + CA11 (span), `make test` 790 verde. Marcação retroativa.
>
> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler`. Type-agnostic (antes do binding).
> **Regras:** transformer à mão (P11); spans preservados; gensym `$`+tag; **sem git durante subagente ativo**.

## Infra
- [x] T001 `compiler/lib/frontend/desugar/desugar.dart` — transformer visitor post-order sobre a AST `sealed` (retorna `AstNode`); gensym reservado (`$`+tag, contador por passe).
- [x] T002 `driver/driver.dart` + `bin/itac.dart` — comando `itac desugar <f.tu> --dump [--spans]` (parse → desugar → `AstDumper`); função pura `desugarProgram`/`desugarDump` testável.

## Reescritas (§5.2) — cada uma preservando span
- [x] T003 Nulabilidade sobre `.some`/`.none`: `??`, `?.` (chain achatado), `!` (com `Panic`).
- [x] T004 `if let` → `match .some/.none` **FEITO**. ⚠️ **Divergência registrada (auditoria 2026-07-17, achado A5):** `guard let` **NÃO** é desaçucarado — foi **RETIDO como nó core** (`desugar.dart:14,197-201`), mesmo blocker do `Try` (early-return + binding-na-continuação excedem `=> expr`, RD-1). F4/F5/F6 tratam `GuardLetStmt` retido. A reescrita para `match` prevista nesta task foi abandonada por decisão de design; **pendente de ruling do dono/spec** para promover de "lacuna declarada" a decisão assentada.
- [x] T005 `where` → `match`/let-in (bind irrefutável, gensym); `>>` → closure `($c) => g(f($c))`; `|>` → `Call` (x 1º posicional).
- [x] T006 `for x in it` → `while` + protocolo-iterador (`$it`); `$0`-closure → aridade por scan do corpo.
- [x] T007 Retenção: `Try`, copy-with, `**` NÃO expandem (passam inalterados). Assertion pass de boa-formação do core.

## Conformância + testes + gate
- [x] T008 `conformance/desugar/*.tu` → `.desugar` goldens (CA1–CA9) gerados ao vivo pelo orquestrador.
- [x] T009 `desugar_test.dart` — unit por regra; **idempotência** (CA10); **span dentro do range** (CA11); assertion de core.
- [x] T010 `dart analyze` limpo + `make test` verde + goldens de parse (001–006) inalterados.
