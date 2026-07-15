# Tasks 001: Semântica de largura de `Int` e operações bitwise

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md) · **Risco 1:** rota 1 (`MISMATCH_DOC`)
>
> Natureza: **doc normativa + conformância**, sem mudança de codegen. Fail-first: o "vermelho" real é o `js_parity` tratando os casos ≥ 2³¹ como **regressão** (`MISMATCH`) antes de estender o runner. Todos os valores de VM são confirmados via **MCP `ita`**; os de JS via `dart2js`+`node`.
> **Regra operacional:** a implementação mexe no repo `ita/` → via agente do compilador + MCP; sem git durante subagente ativo.

## Fase 1 — Setup

- [ ] T001 Confirmar o padrão do corpus (`ita/examples/*.tu` + `*.expected`; como `compiler/test/js_parity/run_js_parity.sh`, `run_conformance.sh` e `run_runtime.sh` consomem os goldens), usando `examples/bits.tu`/`bits.expected` como referência de formato de `print`/`main`.

## Fase 2 — RED (casos que falham no compilador/CI de hoje)

- [ ] T002 [CA1] (RED) Linha `Bits.not(0)` ⟶ `-1` em `ita/examples/int_width.tu`; gravar golden em `ita/examples/int_width.expected` (valor confirmado via MCP `ita`).
- [ ] T003 [CA2] (RED) Linha `Bits.shr(-1, 1)` ⟶ `-1` em `ita/examples/int_width.tu` (mesmo arquivo; sequencial a T002).
- [ ] T004 [CA3] (RED) Linha `Bits.shl(1, 40)` ⟶ `1099511627776` em `ita/examples/int_width.tu`.
- [ ] T005 [CA4] (RED) Linha `Bits.shl(1, 63)` ⟶ `-9223372036854775808` em `ita/examples/int_width.tu`.
- [ ] T006 [CA5] (RED) Linha `9223372036854775807 + 1` ⟶ `-9223372036854775808` (wrap) em `ita/examples/int_width.tu`.
- [ ] T007 [CA6] (RED) Registrar `int_width` em `ita/compiler/test/js_parity/expected.txt`; rodar `run_js_parity.sh` e **constatar que os casos ≥ 2³¹ dão `MISMATCH`** (falha tratada como regressão = o vermelho). Confirmar os valores JS via `dart2js`+`node`: CA3 `256`, CA4 `-2147483648`.

## Fase 3 — GREEN (implementar até verde)

- [ ] T008 [P] [CA6] (GREEN) Documentar `Int` = **64-bit signed two's complement** e o **wrap** de overflow em `ita/compiler/docs/LANGUAGE_SPEC.md` (§ tipos primitivos) — entregável principal; fecha o Princípio 4.
- [ ] T009 [P] (GREEN) Reforçar em `ita/compiler/docs/GRAMMAR.md`: o Itá **não tem operadores bitwise binários** (`~` unário + API `Bits.*`; `& | ^ <<` mortos no lexer; `>>` = composição).
- [ ] T010 [CA6] (GREEN) Estender `ita/compiler/test/js_parity/run_js_parity.sh` + `expected.txt` com o status **`MISMATCH_DOC`** (allowlist de divergência esperada ≥ 2³¹): o CI aceita e reporta, sem tratar como regressão → `run_js_parity` verde.
- [ ] T011 [P] (GREEN · opcional) Erro semântico `int-literal-out-of-range` com span em `ita/compiler/lib/semantic/type_checker.dart` (hoje o codegen rejeita com `Undefined: <literal>`).

## Fase 4 — VALIDATE (comportamento e paridade via MCP)

- [ ] T012 [CA1] [CA2] [CA5] (VALIDATE) Rodar `int_width.tu` via **MCP `ita`** (VM) e conferir byte-a-byte com `int_width.expected` (CA1/CA2 = valores exatos; CA5 = wrap).
- [ ] T013 [CA3] [CA4] [CA6] (VALIDATE) Rodar `dart2js`+`node` sobre `int_width`; confirmar CA3 `256` / CA4 `-2147483648` e que o status `MISMATCH_DOC` do `run_js_parity` bate (divergência documentada, não regressão).

## Fase 5 — QUALITY (gate final)

- [ ] T014 Suíte de conformância verde com `int_width` incluído (`run_conformance.sh` / `test_runner`).
- [ ] T015 `run_js_parity` verde com `MISMATCH_DOC` aceito (nenhum caso lido como regressão).
- [ ] T016 Benchmark de compile-time (`itac` AOT) sem regressão no CI.
- [ ] T017 Testes unitários verdes (inclui o de `int-literal-out-of-range` se T011 foi feito).
- [ ] T018 Constitution check final + Definition of Done: largura de `Int` documentada (P4 fechado), sem conflito de princípio.

## Dependências

- **RED antes de GREEN:** T002–T006 (corpus) antes de T012; T007 (js_parity vermelho) antes de T010 e T013.
- **GREEN:** T008 e T009 são `[P]` entre si (arquivos distintos). T010 depende de T007. T011 é `[P]` independente (opcional).
- **VALIDATE** depois do GREEN correspondente. **QUALITY** por último (depende de tudo).

## Execução paralela (`[P]`)

- T008 (LANGUAGE_SPEC) ‖ T009 (GRAMMAR) ‖ T011 (type_checker) — arquivos independentes.
- T002–T006 **não** são `[P]` entre si (mesmo arquivo `int_width.tu`).

## Estratégia de implementação (fatia sugerida primeiro)

1. **Fatia 1 (a espinha):** T002–T006 (corpus + goldens via MCP) → T008 (doc LANGUAGE_SPEC) → T012 (validar VM). Fecha CA1/CA2/CA5 e o entregável de doc principal.
2. **Fatia 2 (o gap JS):** T007 (js_parity vermelho) → T010 (`MISMATCH_DOC`) → T013 (confirmar JS) → T015. Fecha CA3/CA4/CA6.
3. **Fatia 3 (polish):** T009 (GRAMMAR), T011 (erro opcional), T014/T016/T017/T018 (gate final).

**Total:** 18 tasks · RED 6 (CA1–CA6) · GREEN 4 · VALIDATE 2 · QUALITY 5 · Setup 1. Cada CA de §11 tem RED + GREEN/doc + VALIDATE.
