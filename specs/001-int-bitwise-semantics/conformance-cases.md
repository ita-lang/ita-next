# Conformance cases — Spec 001 (Int width & bitwise)

> Phase 1 do `/speckit-plan`. Deriva de `spec.md` §11 os casos `.tu` que virarão corpus de conformância. Valores **VM confirmados ao vivo via MCP `ita`**; valores **JS são inferidos** (dart2js mascara shift-count a 5 bits e trunca bitwise a 32-bit) e serão **confirmados no `/implement`** rodando `dart2js` + `node`.

## Alvo de corpus

- **Novo exemplo:** `ita/examples/int_width.tu` + `ita/examples/int_width.expected` (golden da VM), no padrão de `examples/bits.tu`.
- **Paridade:** entrada `int_width` em `ita/compiler/test/js_parity/expected.txt`.
- **Oracle:** VM (JIT). AOT deve empatar. JS conferido por paridade.

## Casos (mapeados aos CA da spec §11)

| CA | Expressão (`.tu`) | VM / AOT (confirmado) | JS (inferido — confirmar) | Paridade |
| :-- | :-- | :-- | :-- | :-- |
| CA1 | `Bits.not(0)` | `-1` | `-1` | **MATCH** (coincide em 32/64-bit) |
| CA2 | `Bits.shr(-1, 1)` | `-1` | `-1` | **MATCH** (shift aritmético) |
| CA3 | `Bits.shl(1, 40)` | `1099511627776` | `256` (40 & 31 = 8; `1<<8`) | **divergência documentada** (≥ 2³¹) |
| CA4 | `Bits.shl(1, 63)` | `-9223372036854775808` | `-2147483648` (63 & 31 = 31) | **divergência documentada** |
| CA5 | `9223372036854775807 + 1` | `-9223372036854775808` (wrap) | perda de precisão IEEE-754 | **divergência documentada** |
| CA6 | os casos ≥ 2³¹ acima, agregados | — | — | registrados como divergência documentada; benchmark AOT sem regressão |

## Casos de sanidade (dentro do range seguro — devem ser MATCH)

Para provar que a paridade **se mantém** onde deve (não é um "desistir" geral do JS):

- `Bits.and(255, 15)` = `15` · `Bits.or(240, 15)` = `255` · `Bits.xor(255, 15)` = `240` · `Bits.shl(1, 4)` = `16` — todos **MATCH**.

## Decisão pendente para o `/tasks` (Risco 1 do plan)

Como marcar CA3–CA6 no `js_parity` sem que o CI os leia como **regressão**. Duas rotas:

1. **`MISMATCH_DOC`** — estender `run_js_parity.sh` + `expected.txt` com um status de MISMATCH esperado (allowlist), que o CI aceita mas reporta.
2. **Corpus no range seguro + doc** — o exemplo de corpus fica ≤ 2³¹ (sempre MATCH); o gap ≥ 2³¹ é exercitado só na prosa da doc (`LANGUAGE_SPEC`) + um teste isolado não-golden.

Recomendação inicial: **rota 1** (mais fiel — o corpus documenta a divergência real), com a **rota 2** como fallback se estender o runner custar caro. Decidir com o dono no `/tasks`.

## Superfícies tocadas (RFC "contracts")

- **Tipos/semântica:** nenhuma regra nova em `compiler/lib/semantic/` (as de `Bits.*`/`~` já existem). Opcional: `int-literal-out-of-range`.
- **Codegen:** nenhuma mudança de emissão (Q1 best-effort).
- **Sintaxe:** não tocada (sem `grammar-delta.md`).
- **Documentação:** `LANGUAGE_SPEC.md` (largura `Int` 64-bit + wrap) e `GRAMMAR.md` (reforço "sem operadores bitwise binários").
