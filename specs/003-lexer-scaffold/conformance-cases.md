# Conformance cases — Fase 1 (léxico)

> Phase 1 do `/speckit-plan`. Casos de tokenização da Fase 1. Local: `ita-next/conformance/valid/*.tu` +
> `.tokens` (golden) e `invalid/*.tu` (erros). Formato do dump: `TAG 'lexeme' @linha:col`. Oracle = spec
> (`grammar.ebnf`/`GRAMMAR.md` §1) + léxico do `ita/` (referência; **exceto** os bugs que consertamos, D4).

## Casos válidos (spec §11)

| CA | `.tu` | Tokens esperados (golden) | Prova |
| :-- | :-- | :-- | :-- |
| CA1 | `let x = fn` | `kwLet, identifier'x', eq, kwFn, eof` | keywords via mapa |
| CA1b | `from all race` | `identifier'from', identifier'all', identifier'race', eof` | contextuais → `identifier` (D1) |
| CA2 | `42 0xFF 0b1010 1_000` | `intLiteral'42', intLiteral'0xFF', intLiteral'0b1010', intLiteral'1_000', eof` | 3 bases + **separador `_` consertado** ⚠️ diverge do `ita/` (D4) |
| CA3 | `3.14 2.0e10` | `floatLiteral'3.14', floatLiteral'2.0e10', eof` | float + expoente (só com ponto, D6) |
| CA3b | `1.` | `intLiteral'1', dot, eof` | `1.` **não** é float (D6) |
| CA4 | `"hi ${name}!"` | `stringLiteral` (literal = `['hi ', ['expr','name'], '!']`) | interpolação `${…}` |
| CA5 | `"""a` / `b"""` | `multilineString` (literal cru; `${}` **não** interpola, D6) | multiline |
| CA6 | `/* a /* b */ c */ z` | `identifier'z', eof` | comentário `/* */` **aninhado** (depth) |
| CA7 | `>> > <= < ..= .. != !` | `gtGt, gt, ltEq, lt, dotDotEq, dotDot, bangEq, bang, eof` | **maximal munch** (mais longo primeiro) |
| CA8 | `& \| ^ <<` | `amp, pipe, caret, ltLt, eof` | terminais tokenizados (D5) — não erro |
| CA11 | `static fn f()` | `kwStatic, kwFn, identifier'f', lparen, rparen, eof` | keyword **viva** de declaração (§2.2, D1) |
| CA12 | `// oi`⏎`x` | `identifier'x', eof` | comentário de linha `//` ignorado (B9) |
| CA13 | `""` | `stringLiteral''` (literal = `[]`) | string vazia (B9) |
| CA14 | `_` / `_x` | `underscore, eof` / `identifier'_x', eof` | `_` sozinho → `underscore`; `_x` → `identifier` (§2.1a, M7/B9) |
| CA15 | `$0 $1` | `identifier'$0', identifier'$1', eof` | closure shorthand `CLOSURE_PARAM` (§2.1, M6/B9) |
| CA16 | `a`⏎`b` | `identifier'a' @1:1, identifier'b' @2:1, eof` | quebra de linha **não** é token; incrementa `line` (§2.6, B9) |
| CA17 | `"x ${a`⏎`b} y"`⏎`z` | `stringLiteral @1:1, identifier'z' @3:1, eof` | **W3/B2**: `\n` dentro de `${…}` incrementa `line` → `z` fica em `@3:1` (prova a correção; `valid/interp_multiline.tu`) |

## Casos inválidos (`invalid/`, erros léxicos — não abortam)

| CA | `.tu` | Erro esperado (kebab-case + posição) |
| :-- | :-- | :-- |
| CA9a | `let x @ y` | `lex-annotation-unsupported` @1:7 (+ segue tokenizando `y`) — `@` proibido (P6, D5) |
| CA9b | `"abc` (sem fechar) | `lex-unterminated-string` @1:1 |
| CA9c | `/* aberto` (sem `*/`) | `lex-unterminated-block-comment` @1:1 |
| CA9d | `let ~x = §` | `lex-unexpected-char '§'` com `line:col`; **coleta** e continua (não aborta) |
| CA9e | `0x` / `0b` / `2.0e` / `1__0` | `lex-malformed-number` (dígito/expoente ausente; `_` inicial/final/duplo). O oracle **crasha** (`int.parse('')`); o `ita-next` = erro léxico (D3, M5) |
| CA9f | `"""abc` (sem fechar) | `lex-unterminated-multiline-string` @1:1 (M8) |
| CA9g | `"a\zb"` | **W3/R1**: `lex-invalid-escape 'z' @1:3` (span do `\z`); resync → `stringLiteral` ainda produzido (`invalid/invalid_escape.tu`) |
| CA9h | `99999999999999999999`⏎`0xFFFFFFFFFFFFFFFF` | **W3/B1**: 2×`lex-integer-overflow` (@1:1, @2:1); INT bem-formado > Int64 vira `invalid`, **sem crash** (`invalid/int_overflow.tu`) |

## Caso de infra

| CA10 | `itac tokenize conformance/valid/expr.tu` roda e imprime o dump; `dart test` (lexer_test com asserts) verde no CI; benchmark AOT sem regressão; `git init` do `ita-next/` feito. |

## Superfícies tocadas

- **Léxico:** `lib/frontend/lexer/{token,lexer}.dart` (à mão) + `docs/spec/grammar.ebnf` (W3C EBNF).
- **Driver:** `itac tokenize` (dump).
- **Nenhuma** outra fase (sintaxe/semântica/codegen) — Fase 1 é só léxico.
- **Divergência deliberada do `ita/`:** CA2 (separador `_`) — o `ita/` tem bug; o golden é o correto (D4).
