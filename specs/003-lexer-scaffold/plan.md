# Plan 003: Léxico completo + scaffold (Fase 1) — plano de execução

> **Spec:** [`spec.md`](./spec.md) · **Status:** `ready` · **Épico-pai:** `002` · **Escopo:** `ita-next/`

## 1. Resumo técnico

Materializar o `ita-next/` (scaffold + toolchain + CI) e o **léxico completo**, scanner à mão. A leitura do
léxico do `ita/` (oracle/referência, via agente do compilador) revelou que ele é uma boa referência **mas tem
bugs e dead code** — a reescrita **conserta** (não replica). O `ita-next` nasce **limpo e correto**, alinhado
à constituição (erros em kebab-case) e ao `GRAMMAR.md` normativo (só keywords vivas).

## 2. Arquivos a criar (em `ita-next/`)

### 2a. Toolchain + scaffold (ADR-0003)

| Arquivo | Origem/conteúdo |
| :-- | :-- |
| `dart-sdk.pin`, `tools/pin-dart.sh`, `third_party/dart/<tag>/pkg/` | cópia adaptada do `ita/` (assert Kernel 130) |
| `.gitignore`, `Makefile`, `compiler/pubspec.yaml` | `name: ita_next_compiler`; scaffold de dirs (§A do épico) |
| `.github/workflows/ci.yml` | enxuto: pin → `dart test` (dia 1) → conformance léxico → benchmark AOT |

### 2b. Léxico (`compiler/lib/frontend/lexer/`)

| Arquivo | Papel | Ref. |
| :-- | :-- | :-- |
| `token.dart` | `enum Tag` **limpo** (categorias abaixo, **sem** dead code) + `class Token{tag, lexeme, line, col, offset, length, literal?}` | D1, D2 |
| `lexer.dart` | scanner à mão: `source/start/current/line/col`, `advance/peek/peekNext/match`; keywords via mapa; comentário `/* */` **aninhado** (depth); erros **kebab-case, não-abortantes** (coleta + emite `invalid`) | CI `scanning`, D3–D5 |

### 2c. Artefato + driver + testes

| Arquivo | Papel |
| :-- | :-- |
| `compiler/docs/spec/grammar.ebnf` | seção "Lexical grammar" em **W3C EBNF** (ADR-0010), reconciliada com `GRAMMAR.md` §1 |
| `compiler/lib/driver/driver.dart` + `bin/itac.dart` | comando `itac tokenize <file.tu>` (dump legível: `TAG 'lexeme' @L:C`) |
| `compiler/test/lexer_test.dart` | **unit com asserts** (o `test_lexer.dart` do `ita/` NÃO tinha) — tokeniza e confere |
| `conformance/valid/*.tu` + `.tokens` (goldens) · `conformance/invalid/*.tu` | os CA1–CA10 (tokens/erros esperados) |

## 3. Decisões de reconciliação (ver [`design-notes.md`](./design-notes.md))

O léxico do `ita/` é referência, mas o `ita-next` **corrige**:

| # | Do `ita/` | Decisão no `ita-next` |
| :-- | :-- | :-- |
| D3 | erros em **português** natural (`'Caractere inesperado'`) | **EN kebab-case** (`lex-unexpected-char`) — Constituição Art. IV |
| D4 | separador `_` **QUEBRADO** (`1_000` → `1` + `_000`; `replaceAll` é dead code) | **consertar**: `_` no consumo de dígitos (não inicial/final/duplo) — dec/hex/bin |
| D5 | `@` → erro; `# & | ^ <<` → tokens | manter: `@` = `lex-annotation-unsupported` (**P6 zero annotations**); `# & | ^ <<` tokenizados |
| D1 | enum tem **dead code**: `newline`, `gsx*`, `at`(token), `kwLeft/Right`, e keywords mortas (`const unsafe effect signal state`) | `Tag` **limpo**: só o que é emitido; keywords = as **vivas** do `GRAMMAR.md` §1; `left/right/from/all/race` = contextuais (IDENT) |
| D2 | `Token` só `line/col` (sem offset); spans de erro `length=1` | adicionar **`offset` + `length`** ao `Token` (spans reais — melhor diagnóstico e útil ao codegen) |
| D6 | `1e10` sem ponto ≠ float; ASCII-only ident; multiline sem escape/interp; literais pré-computados | **manter** (comportamento do oracle) — melhorias (Unicode, `1e10`) ficam anotadas p/ fase futura |

## 4. Estratégia de goldens (validação — §10 da spec)

O MCP `ita` **não dumpa tokens** → o oracle é a **spec** (`grammar.ebnf` + `GRAMMAR.md` §1) + o **léxico do
`ita/`** como referência de comportamento. Goldens = `itac tokenize` do `ita-next` conferido:
- **casos onde o `ita/` está correto** (a maioria) → golden = comportamento do `ita/`;
- **casos de bug do `ita/`** (separador `_`) → golden = comportamento **correto** (diverge do `ita/`, **marcado** no `.tokens`).

## 5. Plano de teste

- **Unit:** `dart test` (`lexer_test.dart` com asserts) — CI dia 1.
- **Conformance:** `conformance/valid/*.tu` → `.tokens`; `invalid/*.tu` → erros esperados.
- **Benchmark:** compile-time do `itac` AOT (ADR-0006).

## 6. Ordem de ataque

1. Toolchain (2a) + `pin-dart.sh` (assert 130). 2. `pubspec.yaml` + scaffold. 3. `[P]` `token.dart` (Tags+Token) · `[P]` `grammar.ebnf`. 4. `lexer.dart` (depende de token). 5. `itac tokenize` (driver+bin). 6. testes + conformance + CI. 7. `git init`.

## 7. Riscos e mitigações

| Risco | Sev | Mitigação |
| :-- | :-- | :-- |
| Divergir do `GRAMMAR.md` no conjunto de Tags | média | `Tag` derivado do `GRAMMAR.md` §1 (normativo), não do `token.dart` (tem dead code); reconciliar. |
| Consertar `_` mudar goldens vs `ita/` | baixa | esperado e **documentado** (D4); golden = correto, com nota. |
| Montar spans (offset/length) certo | baixa | testes de posição no `lexer_test.dart`. |

## 8. Constitution check

- **P4** sem mágica (grammar.ebnf documenta tudo) · **P6** `@` proibido · **P11** scanner à mão (sem gerador) ·
  **Art. IV** erros kebab-case · **ADR-0003/0006/0010**. **Conflitos: nenhum.**
