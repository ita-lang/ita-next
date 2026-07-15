# Plan 001: Semântica de largura de `Int` e operações bitwise

> **Spec:** [`spec.md`](./spec.md) · **Status:** `ready` · **Marco:** `M4`

## 1. Resumo técnico

Mudança **majoritariamente de documentação normativa + conformância**. Fixa `Int` = **64-bit two's complement** e o **wrap** de overflow no `LANGUAGE_SPEC.md` e no `GRAMMAR.md` (hoje omissos), e adiciona **casos de conformância** que exercitam o gap ≥ 2³¹, registrados no `js_parity` como **divergência documentada**. **Sem mudança de codegen/runtime** (Q1 = best-effort, custo zero; o comportamento já é o canônico). **Não toca léxico/sintaxe** (Q2 = só a API `Bits.*`).

## 2. Fases do compilador tocadas (ancoradas na spec)

| Fase | Arquivo(s) | Mudança | Ref. spec |
| :-- | :-- | :-- | :-- |
| Semântica/Tipos | *(nenhum código — regras já existem)* · **opcional** `compiler/lib/semantic/type_checker.dart` | fixa a **semântica** (largura/wrap), não novas regras; opcional: erro `int-literal-out-of-range` com span | §4 |
| Codegen | *(nenhum)* | emissão **inalterada**; a spec apenas **declara** o comportamento por alvo | §7 |
| **Documentação** (entregável principal) | `compiler/docs/LANGUAGE_SPEC.md`, `compiler/docs/GRAMMAR.md` | documentar `Int` 64-bit + wrap; reforçar "sem operadores bitwise binários" (`~` + `Bits.*`; `>>` = composição) | §4, §8 |
| **Conformância** | `examples/int_width.tu` (+ `.expected`), `compiler/test/js_parity/expected.txt` | casos que exercitam o gap; marcação de divergência documentada | §11 |

## 3. Estratégia por alvo

- **VM/AOT:** inalterado — o comportamento medido já é o canônico (64-bit, wrap).
- **JS (dart2js):** best-effort; casos ≥ 2³¹ **registrados como divergência documentada**, não emulados (sem *lowering*).

## 4. Plano de teste (o gate)

- **Corpus de conformância:** `examples/int_width.tu` + `int_width.expected` — cobre `Bits.shl(1,40)`, `Bits.shl(1,63)`, `Bits.not(0)`, `Bits.shr(-1,1)`, overflow `maxInt64+1`. Rodado por `test_runner` / `run_conformance.sh`.
- **Testes unitários:** apenas se implementar o erro opcional `int-literal-out-of-range` em `compiler/lib/semantic/`.
- **Validação ao vivo:** cada CA via **MCP `ita`** (`run`) na VM — valores já confirmados na fase de spec.
- **Paridade VM×JS:** entrada do novo exemplo em `js_parity/expected.txt` marcada como divergência documentada (ver Risco 1).
- **CI:** conformance + unit + **benchmark de compile-time (`itac` AOT) sem regressão**.

## 5. Ordem de ataque e dependências

1. Documentar `LANGUAGE_SPEC.md` + `GRAMMAR.md` (largura 64-bit + wrap + ausência de operadores) — depende de: —
2. `[P]` Adicionar caso de conformância `examples/int_width.tu` + `.expected` — depende de: —
3. Registrar no `js_parity/expected.txt` + resolver marcação de divergência documentada — depende de: 2
4. `[P]` *(opcional)* erro `int-literal-out-of-range` em `semantic/type_checker.dart` — depende de: —
5. CI verde + benchmark — depende de: 1, 2, 3

## 6. Riscos técnicos e mitigações

| Risco | Severidade | Mitigação |
| :-- | :-- | :-- |
| O `js_parity` (`expected.txt`) não distingue **divergência documentada** de **regressão** — casos ≥ 2³¹ dariam `MISMATCH` e falhariam o CI como se fosse regressão | **média** | Estender o runner/manifesto com status/allowlist para MISMATCH **esperado** (ex.: `MISMATCH_DOC`) nos casos ≥ 2³¹; **ou** manter o exemplo de corpus no range seguro e exercitar o gap só na prosa da doc + teste isolado não-golden. Decidir no `/tasks`. |
| Documentar `Int` = 64-bit pode conflitar com futura introdução de `Int32/Int64` | baixa | Q1 descartou tipos de largura fixa **por ora**; a doc afirma 64-bit como o `Int` default, sem fechar a porta a tipos explícitos futuros (nova spec). |
| Débito de infra: `.specify/scripts/bash/` do spec-kit não foi copiado | baixa | setup feito manualmente; criar os scripts (ou remover a dependência nas skills) na Fase 2 do harness. |

## 7. Constitution check (re-confirmação)

- Princípios reconfirmados: **P4** (sem mágica — a largura deixa de ser herança invisível), **P11** (zero codegen build-time — nada é gerado), **Artigo II** (3 alvos declarados em §7.3), **Artigo IV** (conformância no CI + validação via MCP). **Conflitos: nenhum.**

## 8. Artefatos auxiliares

- [`design-notes.md`](./design-notes.md) — as 3 decisões (Q1/Q2/Q3) com rationale e alternativas.
- [`conformance-cases.md`](./conformance-cases.md) — os casos `.tu` dos CA com saída esperada por alvo.
- *(sem `grammar-delta.md` — sintaxe não tocada; a edição do `GRAMMAR.md` é documentação, não delta de produção.)*
