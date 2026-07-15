# Tasks 003: Léxico completo + scaffold (Fase 1)

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md) · **Design:** [`design-notes.md`](./design-notes.md) · **Escopo:** `ita-next/` (caminhos relativos a `ita-next/`)
>
> Fail-first de **fase léxica** (primeiro código do `ita-next`): SETUP (toolchain+scaffold) → RED (goldens de
> tokenização + testes que falham no scaffold vazio) → GREEN (token/lexer/itac tokenize/grammar.ebnf) →
> VALIDATE (`itac tokenize` vs goldens + referência léxico do `ita/`) → QUALITY (CI + `git init`).
>
> **Adaptação (léxico):** o MCP `ita` NÃO dumpa tokens → o VALIDATE é por **`itac tokenize`** (dump) conferido
> com o `.tokens` golden, tendo o **léxico do `ita/` como referência** (exceto os bugs que consertamos, D4).
> **A reescrita CONSERTA** o oracle onde ele erra (D1–D5). **Regra operacional:** implementar no `ita-next/`
> via agente do compilador; sem git durante subagente ativo.

## Fase 1 — Setup

- [x] T001 Copiar toolchain do `ita/` p/ `ita-next/`: `dart-sdk.pin`, `tools/pin-dart.sh` (adaptar paths), vendor `third_party/dart/<tag>/pkg/`; `.gitignore` (`.dart-sdk/`, `build/`, `*.dill`).
- [~] T002 Rodar `tools/pin-dart.sh` — materializa `.dart-sdk/` e **asserta Kernel 130**. **ADIADO** (não bloqueia a Fase 1): léxico é Dart puro, roda com o `dart` do sistema (3.12.1). O download do SDK pinado (~200MB) e o vendor `pkg/kernel` entram na **fase de codegen** (quando o `.dill` for emitido). `pin-dart.sh` já existe e aponta certo.
- [x] T003 Scaffold: dirs `compiler/lib/frontend/{lexer,parser,desugar,binding,semantic,analysis}`, `compiler/lib/{codegen,driver}`, `compiler/{bin,test,docs/spec}`, `conformance/{valid,invalid}`, `examples`; `compiler/pubspec.yaml` (`name: ita_next_compiler`, dep `kernel` via `path:`) + `Makefile` + `.github/workflows/ci.yml` (pin → `dart test` → conformance → benchmark).

## Fase 2 — RED (goldens/testes que falham no scaffold vazio)

- [x] T004 [P] [CA1] (RED) `conformance/valid/kw_ident.tu` (`let x = fn` / `from all race`) + `.tokens` (keywords + contextuais→`identifier`).
- [x] T005 [P] [CA2] (RED) `conformance/valid/int_bases.tu` (`42 0xFF 0b1010 1_000`) + `.tokens` (4× `intLiteral`; **separador `_` consertado — ⚠️ diverge do `ita/`, D4**).
- [x] T006 [P] [CA3] (RED) `conformance/valid/floats.tu` (`3.14 2.0e10` e `1.`) + `.tokens` (`floatLiteral`; `1.`→`intLiteral`+`dot`).
- [x] T007 [P] [CA4] (RED) `conformance/valid/string_interp.tu` (`"hi ${name}!"`) + `.tokens` (`stringLiteral` com partes de interpolação).
- [x] T008 [P] [CA5] (RED) `conformance/valid/multiline.tu` (`"""…"""`) + `.tokens` (`multilineString`, sem interpolação).
- [x] T009 [P] [CA6] (RED) `conformance/valid/nested_comment.tu` (`/* a /* b */ c */ z`) + `.tokens` (só `identifier'z'`, `eof`).
- [x] T010 [P] [CA7] (RED) `conformance/valid/maximal_munch.tu` (`>> > <= < ..= .. != !`) + `.tokens` (operador mais longo primeiro).
- [x] T011 [P] [CA8] (RED) `conformance/valid/terminals.tu` (`& | ^ <<`) + `.tokens` (tokenizados, não erro).
- [x] T012 [P] [CA9] (RED) `conformance/invalid/lex_errors.tu` (`@`, string não fechada, `/* aberto`, char `§`) + esperados (`lex-annotation-unsupported`/`lex-unterminated-string`/`lex-unterminated-block-comment`/`lex-unexpected-char`, com `line:col`, **não-abortante**).
- [x] T013 [CA1] (RED) `compiler/test/lexer_test.dart` — asserts de tokenização (o `test_lexer.dart` do `ita/` NÃO tinha asserts); falha hoje (sem lexer).

## Fase 3 — GREEN (implementar até passar)

- [x] T014 [P] [CA1] (GREEN) `compiler/lib/frontend/lexer/token.dart` — `enum Tag` **LIMPO** (só as **40** vivas — 36 do `GRAMMAR.md` §1 + 4 de declaração `static init override precedence`; **sem** `newline`/`gsx*`/`at`-token/`kwLeft/Right`/keywords mortas — D1) + `class Token{tag, lexeme, line, col, offset, length, literal?}` (D2) + `const Map<String,Tag> keywords`.
- [x] T015 [CA1] (GREEN) `compiler/lib/frontend/lexer/lexer.dart` — scanner à mão (CI `scanning`): `source/start/current/line/col/offset`, `advance/peek/peekNext/match`, `scanTokens/scanToken`; identificador→mapa `keywords`; whitespace ignorado; `_`-sozinho→`underscore`. Depende de: T014.
- [x] T016 [CA7] (GREEN) `lexer.dart` — **maximal munch** dos operadores. O que importa na ordem é **mais-longo-antes-do-mais-curto** (mesmo prefixo): `..=` antes de `..` antes de `.`; `<=`/`<<` antes de `<`; `>=`/`>>` antes de `>`; `?.`/`??` antes de `?`. Casos que se distinguem já no 2º char (`->` vs `-=`, `==` vs `=>`) têm ordem **irrelevante**. Depende de: T015.
- [x] T017 [CA2] (GREEN) `lexer.dart` — números `INT` dec/hex/bin **com separador `_` consertado** (D4: `_` entre dígitos; erro em inicial/final/duplo); `literal` pré-computado (radix). Depende de: T015.
- [x] T018 [CA3] (GREEN) `lexer.dart` — `FLOAT` (`.`+dígito; expoente só no ramo com ponto — D6). Depende de: T017.
- [x] T019 [CA4] [CA5] (GREEN) `lexer.dart` — `STRING` (escapes `\n\r\t\\\"0`, interpolação `${…}`→`List` de partes) + `MULTILINE_STRING` (cru, **sem** escape/interp — D6). Depende de: T015.
- [x] T020 [CA6] (GREEN) `lexer.dart` — comentários `//` e `/* */` **aninhado** (contador de profundidade); capturados em `comments`, **não** viram tokens. Depende de: T015.
- [x] T021 [CA9] (GREEN) `lexer.dart` — erros **EN kebab-case** (D3), **não-abortante** (coleta + emite `Tag.invalid`); `@`→`lex-annotation-unsupported` (P6, D5); `# & | ^ <<`→tokens (D5). Depende de: T015.
- [x] T022 [P] [CA1] (GREEN) `compiler/docs/spec/grammar.ebnf` — seção "Lexical grammar" em **W3C EBNF** (ADR-0010), reconciliada com `GRAMMAR.md` §1.
- [x] T023 [CA1] (GREEN) `compiler/lib/driver/driver.dart` + `compiler/bin/itac.dart` — comando `itac tokenize <file.tu>` (dump `TAG 'lexeme' @L:C`). Depende de: T015.

## Fase 4 — VALIDATE (léxico: `itac tokenize` + goldens + referência `ita/`)

- [x] T024 [CA1] [CA3] [CA6] [CA7] [CA8] (VALIDATE) `itac tokenize` dos `valid/*.tu` → conferir byte-a-byte com os `.tokens`; onde o `ita/` está correto, cruzar com o léxico do `ita/` (referência).
- [x] T025 [CA2] (VALIDATE) confirmar `1_000` → `intLiteral'1_000'` (correto) — **documentar a divergência** vs o `ita/` (que dá `intLiteral'1'`+`identifier'_000'`, D4).
- [x] T026 [CA4] [CA5] (VALIDATE) `itac tokenize` das strings → conferir interpolação (`List` de partes) e multiline (cru).
- [x] T027 [CA9] (VALIDATE) `itac tokenize` dos `invalid/*.tu` → conferir mensagens **kebab-case** + `line:col` e que **coleta múltiplos** (não aborta no 1º).

## Fase 5 — QUALITY (gate final)

- [x] T028 `dart test` (`lexer_test.dart` com asserts) verde no CI.
- [x] T029 Conformance de tokenização verde (`valid/` + `invalid/`).
- [~] T030 Benchmark de compile-time (`itac` AOT) sem regressão (ADR-0006). **PLACEHOLDER**: o `itac` AOT completo só existe quando houver pipeline até `.dill`; na Fase 1 (só `tokenize`) o passo de benchmark no CI está comentado. Vira gate real na fase de codegen.
- [x] T031 `git init` do `ita-next/` (D0.4) + commit inicial (scaffold + léxico funcionais).
- [x] T032 Constitution check final: `Tag` limpo (sem dead code), erros kebab-case (Art. IV), scanner à mão (P11), `@` proibido (P6), `grammar.ebnf` versionado; DoD da spec.

## Dependências

- **Setup** (T001–T003) antes de tudo. **RED** (T004–T013) após scaffold (T003).
- **GREEN:** T014 ‖ T022 (arquivos distintos); T015←T014; T016/T017/T019/T020/T021/T023←T015; T018←T017.
- **VALIDATE** após o GREEN da categoria. **QUALITY** por último.

## Execução paralela (`[P]`)

- Casos RED T004–T012 todos `[P]` (arquivos `.tu`/`.tokens` distintos).
- No GREEN: T014 (token) ‖ T022 (grammar.ebnf).

## Estratégia de implementação (fatia sugerida)

1. **Espinha (CA1):** T001–T003 → T014 (Tag+Token) → T015 (scanner base) → T023 (`itac tokenize`) → T024. Prova o pipeline léxico com keywords/identificadores.
2. **Categorias:** T016 (munch) · T017/T018 (números+float, com `_` consertado) · T019 (strings) · T020 (comentário aninhado) · T021 (erros) — cada uma fecha seu(s) CA(s).
3. **Gate:** T028–T032 (unit + conformance + benchmark + `git init` + constitution).

**Total: 32 tasks** · Setup 3 · RED 10 (CA1–CA9 + unit) · GREEN 10 · VALIDATE 4 · QUALITY 5. Cada CA tem RED + GREEN + VALIDATE.
