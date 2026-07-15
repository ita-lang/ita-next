# Design notes — Fase 1 (léxico + scaffold)

> Phase 0 do `/speckit-plan`. Fixa as decisões de design da Fase 1, derivadas da leitura do léxico do `ita/`
> (oracle, via agente do compilador). Princípio-guia: o `ita/` é **referência**, mas a reescrita **conserta**
> seus bugs e alinha à constituição — o `ita-next` nasce limpo e correto.

## D1 — Conjunto de `Tag` limpo (sem dead code)

- **Decision:** o `enum Tag` do `ita-next` inclui **apenas o que é emitido**. Derivar do `GRAMMAR.md` §1
  (normativo), não do `token.dart` do `ita/`. **Fora:** `newline` (nunca emitido), `gsx*` (UI futura),
  `at` como token (`@` é erro), `kwLeft/kwRight` (contextuais → `identifier`), e as **keywords mortas**
  `const unsafe effect signal state` (Apêndice B do `GRAMMAR.md`). **Keywords vivas** (40) = as **36**
  reservadas do `GRAMMAR.md` §1 + as **4** usadas em declarações (`static init override precedence`).
  Contextuais (`from left right all race`) tokenizam como `identifier`.
- **Rationale:** "sem mágica" (P4) e código correto: um token que nunca é produzido é dívida. O `GRAMMAR.md`
  é a fonte normativa. `[cap 3.3]`
- **Alternatives:** espelhar o `token.dart` (47 kw + dead code) — rejeitado: importa o lixo que a reescrita
  existe para eliminar.

## D2 — `Token` com `offset` + `length` (melhoria sobre o `ita/`)

- **Decision:** `class Token { Tag tag; String lexeme; int line, col, offset, length; Object? literal; }`.
- **Rationale:** o `Token` do `ita/` só tem `line/col`, e por isso os spans de erro são quase sempre
  `length=1` (diagnóstico pobre) e o `fileOffset` do codegen é recomputado depois. Ter `offset`+`length` desde
  a Fase 1 dá spans reais (melhor erro) e serve à Fase 7 (codegen precisa de `fileOffset`). `[Apêndice A.3]`

## D3 — Erros léxicos em EN kebab-case

- **Decision:** o `code` do erro é sempre **EN kebab-case** com `line/col`/`length` reais; o `hint`/`label`
  humano fica em **PT-BR** (ruling do dono da revisão W3). Taxonomia (8):
  `lex-unexpected-char`, `lex-unterminated-string`, `lex-unterminated-multiline-string`,
  `lex-unterminated-block-comment`, `lex-annotation-unsupported`, `lex-malformed-number`,
  **`lex-integer-overflow`** (W3/B1) e **`lex-invalid-escape`** (W3/R1). Coletar múltiplos
  (não abortar) + emitir `Tag.invalid` para resync.
- **Rationale:** **Constituição Art. IV** (o `code` interno em EN kebab-case). O `ita/` usa português natural
  (`'Caractere inesperado'`) — o `ita-next` corrige o **code**; o **hint** permanece PT-BR (ruling W3/R2).
  `lex-unterminated-multiline-string` é o análogo de `-unterminated-string` para `"""` (M8).
  `lex-malformed-number` cobre `0x`/`0b` **sem dígito**, `2.0e` **sem expoente** e `_` inicial/final/duplo
  (`1__0`): onde o oracle **crasha** (`int.parse('')`), o `ita-next` emite erro léxico não-abortante (M5).
  `lex-integer-overflow` (W3/B1): INT **bem-formado** mas fora de Int64 (`99999999999999999999`,
  `0xFFFFFFFFFFFFFFFF`, `0x1FFFFFFFFFFFFFFFF`) — usa `int.tryParse`; onde o oracle crasharia com
  `FormatException`, o `ita-next` emite erro léxico. Por ora **todo** int que não cabe em Int64 é erro,
  inclusive hex unsigned-64 (TODO de spec futura: decidir se vira `-1` à la Dart). `lex-invalid-escape`
  (W3/R1): `\` seguido de char fora do conjunto `ESCAPE` (`\z`) — antes era tolerado como char cru; agora é
  erro não-abortante (o char é mantido no buffer para resync).
- **Alternatives:** replicar o português no `code` — rejeitado (viola o Art. IV); traduzir o `hint` para EN —
  rejeitado pelo ruling W3 (hints humanos em PT-BR).

## D4 — Consertar o separador numérico `_` (bug do `ita/`)

- **Decision:** `_` é aceito **entre dígitos** em `INT` (dec/hex/bin) e `FLOAT`: `1_000`, `0xFF_FF`,
  `0b1010_0101`, `3.141_59`. **Proibido** `_` inicial, final ou duplo (`_1`, `1_`, `1__0` → erro). O `literal`
  é computado sobre os dígitos sem `_`.
- **Rationale:** o `ita/` **promete** `_` mas está quebrado — o loop de dígitos é `while(isDigit)` e `_` não é
  dígito, então `1_000_000` lexa como `1` + `_000_000` (o `replaceAll('_','')` é dead code). A reescrita
  conserta. `[cap 3.3.2]`
- **Nota de golden:** este caso **diverge do `ita/`** (que erra) — o golden é o comportamento **correto**,
  marcado no `.tokens`.

## D5 — `@` proibido; `# & | ^ <<` tokenizados

- **Decision:** `@` → erro `lex-annotation-unsupported` (+ `Tag.invalid`); `# & | ^ <<` são **tokens lícitos**
  (`hash`, `amp`, `pipe`, `caret`, `ltLt`) — o filtro é papel de fases posteriores (parser), não do léxico.
- **Rationale:** **Princípio 6 (zero annotations)** — `@decorators` nunca existirão, então `@` é erro no
  léxico, como no `ita/`. Os demais são operadores lícitos (alguns "mortos" no parser, mas o léxico é completo).

## D6 — Manter (por ora) comportamentos do oracle; melhorias anotadas

- **Decision:** replicar o comportamento do `ita/` nestes pontos (não são bugs, são escolhas):
  - `1e10` **sem** ponto **não** é `FLOAT` (expoente só no ramo com `.`); `.5` e `1.` também não são float.
  - Identificadores **ASCII-only** (`[A-Za-z_]` inicial); `$0`,`$1` → `identifier` (closure shorthand).
  - `MULTILINE_STRING` (`"""`) **não** processa escapes nem interpolação (texto cru).
  - **Literais pré-computados no lexer** (`literal`: hex/bin já em `int`, `true/false/nil` com valor, string
    com `List` de partes de interpolação).
  - Comentários capturados em `lexer.comments` (para `fmt`/doc futuro), **não** viram tokens.
  - ~~Escape desconhecido tolerado como char cru~~ **REVOGADO (W3/R1):** `\z` agora é `lex-invalid-escape`
    (erro não-abortante; o char é mantido no buffer só para resync), **não** mais texto cru silencioso.
- **Rationale:** consistência com o oracle e simplicidade; são escolhas de spec, não defeitos. **Melhorias
  futuras anotadas** (Unicode em ident, `\u`/`\xNN`, `1e10`, escapes em multiline) — cada uma seria uma spec
  própria, fora do escopo da Fase 1.

## Abordagem de implementação (CI `scanning.md`)

Scanner à mão: `scanTokens()` reseta `start` e chama `scanToken()`; `switch` no char; `match()` p/ maximal
munch. O que importa na ordem é **mais-longo-antes-do-mais-curto** (mesmo prefixo): `..=` antes de `..` antes
de `.`; `<=`/`<<` antes de `<`; `>=`/`>>` antes de `>`; `?.`/`??` antes de `?`. Casos que se distinguem já no
**2º char** (`->` vs `-=`, `==` vs `=>`) **não** competem por prefixo — ordem **irrelevante**. Keywords via
`Map<String,Tag>` **após** o scan do identificador. Erro não-abortante com `Tag.invalid`.
