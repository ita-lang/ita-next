# Spec 003: Léxico completo + scaffold do `ita-next` (Fase 1)

> **Tipo:** fase-do-compilador (Fase 1 da reescrita horizontal) · **Marco:** `Reescrita` · **Épico-pai:** [`002`](../002-rewrite-compiler-dragon-book/spec.md)
> **Status:** `clarified`
> **Autor / Data:** harness SDD · 2026-07-10 · **Escopo:** `ita-next/` (o `ita/` é oracle/referência, não é tocado)

## §0 Metadados

- **Classe da mudança:** primeira fase da reescrita **horizontal** (ADR-0011) — o **léxico COMPLETO** da
  linguagem + o **scaffold/toolchain/CI** do `ita-next` (que deixaram de ser um "mini-tradutor").
- **Fases tocadas:** [x] **Léxico (§2)** — completo · [ ] Sintaxe · [ ] Semântica · [ ] Codegen. **+ Infra** (§S).
- **Princípios/ADRs:** ADR-0011 (abordagem horizontal), ADR-0003 (SDK pinado), ADR-0006 (itac AOT),
  ADR-0009 (CI `scanning.md` = referência de implementação), ADR-0010 (formato: W3C EBNF), ADR-0007 (Grupo A).

### §0.5 Constitution check

| Fonte | Exigência | Como a Fase 1 adere |
| :-- | :-- | :-- |
| ADR-0011 | fase completa + validada por dump | léxico **inteiro** (não subconjunto); `itac tokenize` dumpa tokens; goldens vs oracle. |
| ADR-0003 | SDK stable pinado (Kernel 130) | toolchain reaproveitada do `ita/`; `pin-dart.sh` asserta formato 130. |
| ADR-0010 | artefato em formato formal | a spec de tokens vira **W3C EBNF** em `compiler/docs/spec/grammar.ebnf` (seção lexical). |
| Princípio 11 | zero codegen em build-time | scanner **à mão** (CI `scanning.md`); nenhum gerador de lexer (Flex/ANTLR proibidos, ADR-0010). |
| Princípio 4 | sem mágica | a `grammar.ebnf` documenta cada token; nada implícito. |

**Conflito aberto:** nenhum.

## §1 Motivação e resumo

A Fase 1 dá o **primeiro código** do `ita-next` (a reescrita horizontal — ADR-0011): o **scaffold + toolchain
+ CI** e o **léxico completo** — todos os tokens da linguagem Itá, num scanner à mão. Fonte-da-verdade: o
`GRAMMAR.md` §1 do `ita/` + o `lexer.dart` do `ita/` como oracle. A fase é **completa e verificável sozinha**:
`itac tokenize x.tu` imprime a lista de tokens, sem precisar de parser/codegen.

**Antes → Depois:**

```tu
// antes — ita-next/ é só README; nada tokeniza
```

```
// depois — itac tokenize x.tu → dump de tokens (formato: TAG 'lexeme' @L:C):
$ itac tokenize x.tu     // conteúdo: let n = 0xFF
kwLet 'let' @1:1   identifier 'n' @1:5   eq '=' @1:7   intLiteral '0xFF' @1:9   eof @1:13
```

**Não-objetivos:** parsing (AST), semântica, codegen — são as fases 2, 5, 7. A Fase 1 **não** monta árvore;
só produz o fluxo de tokens.

## §S Scaffold, toolchain e CI (infra da reescrita — entra aqui, ADR-0011)

- **Scaffold** (§A do épico): dirs `compiler/lib/frontend/{lexer,parser,desugar,binding,semantic,analysis}`,
  `codegen/`, `driver/`, `bin/`, `test/`, `conformance/{valid,invalid}`, `examples/`, `docs/spec/`; pacote
  `ita_next_compiler` (`pubspec.yaml`), **package-imports** (não relativos); `.gitignore`, `Makefile`.
- **Toolchain** (ADR-0003): copiar do `ita/` — `dart-sdk.pin`, `tools/pin-dart.sh`, vendor
  `third_party/dart/<tag>/pkg`. Rodar `pin-dart.sh`; **assertar Kernel 130**.
- **CI** (`.github/workflows/ci.yml`, enxuto): `pin-dart` → `dart test` (**desde o dia 1**) → conformance de
  léxico → benchmark de compile-time (ADR-0006).
- **Git:** `git init` do `ita-next/` ao fim; commit inicial = scaffold + léxico funcionais.

## §2 Léxico completo — `[cap 3.3]` · impl. `scanning.md` (CI)

Scanner **à mão** (maximal munch; `advance/peek/match`; keywords via mapa; erro léxico **não-abortante** com
linha). Reconhece **todas** as categorias de token do Itá (fonte: `GRAMMAR.md` §1 do `ita/`).

**2.1 Literais** (definições regulares):

```
IDENT             = [a-zA-Z_] [a-zA-Z0-9_]*                   (exceto keywords reservadas; "_" sozinho → underscore, ver 2.1a)
CLOSURE_PARAM     = "$" [0-9]+                                (closure shorthand: $0, $1 → Tag identifier; teto $0..$255, ver 2.1a)
INT               = [0-9] ("_"? [0-9])*                       (decimal)
                  | 0 [xX] [0-9a-fA-F] ("_"? [0-9a-fA-F])*    (hex)
                  | 0 [bB] [01] ("_"? [01])*                  (binário; SEM octal)
FLOAT             = [0-9] ("_"? [0-9])* "." [0-9] ("_"? [0-9])* ( [eE] [+-]? [0-9]+ )?
STRING            = '"' ( char | escape | interpolation )* '"'
MULTILINE_STRING  = '"""' … '"""'
interpolation     = "${" … "}"     (só em STRING, não em MULTILINE_STRING)
escape            = "\" [ n r t \ " 0 ]
```

> **Separador `_` (aperta o `GRAMMAR.md` §1, que é frouxo):** o padrão `("_"? [dígito])*` só admite `_`
> **entre** dígitos — proíbe `_` inicial, final ou duplo. `_1`, `1_`, `1__0`, `0xFF_` são **erro**
> (`lex-malformed-number`, §2.7 / D4). A regex `[0-9][0-9_]*` do `GRAMMAR.md` §1 casaria `1_`/`1__0`; a
> reconciliação é anotada no `grammar.ebnf`.
>
> **2.1a — `_` isolado e `$` (closure):** `_` **sozinho** (sem sufixo) → Tag `underscore` (wildcard de
> pattern/lambda); `_x`, `_1` (com sufixo) → Tag `identifier`. `$` seguido de um ou mais dígitos (`$0`, `$1`,
> `CLOSURE_PARAM`) → Tag `identifier` (closure shorthand). **Teto `$0..$255`** — acima disso,
> `lex-dollar-index-range`. A fonte é o **`grammar.ebnf` §1** (§2.5 abaixo: é ele a fonte-da-verdade do
> léxico), com rationale de **engenharia**, não de identidade: *"a Fase 3 sintetiza 1 param por índice até o
> maior `$k` do corpo, logo um índice sem teto seria OOM (`{ $3000000 }` → 3M params). 255 = teto clássico de
> params."* *(Reconciliação de 2026-07-16 — esta spec definia `CLOSURE_PARAM` sem teto e divergia do
> `grammar.ebnf`; inconsistência apontada pelo ADR-0014 §3, fechada junto com o ADR-0016.)*

**2.2 Keywords reservadas** (40, via mapa, após maximal munch do `IDENT`) — as **36** do `GRAMMAR.md` §1:
`pub fn async stream actor struct class enum trait impl extension import operator let var return if else
guard while for await in match self mut where emit spawn panic break continue true false nil as`
**+ 4 vivas usadas em declarações** (`init` construtor, factory `static`, `override`, `precedence`):
`static init override precedence`.
**Contextuais** (NÃO reservadas — tokenizadas como `identifier`): `from left right all race`.

**2.3 Operadores e pontuação** (todos, com **maximal munch** — o mais longo vence):
`+ - * / % ** ! ~ && || ?? == != < > <= >= .. ..= |> >> ?. ? = += -= *= /= -> => : , ; . ( ) { } [ ] _`.

**2.4 Comentários** (ignorados entre tokens): `// linha` e `/* bloco */` — **bloco aninhável** (contador de
profundidade). Whitespace ignorado. **Nota:** comentário de bloco **aninhado NÃO é linguagem regular** — o
aninhamento é resolvido por **contador de profundidade** (fora da gramática regular), não por regex; por isso
fica **fora** das definições regulares (2.1) e é anotado como tal no `grammar.ebnf`.

**2.5 Terminais "mortos" do lexer:** `# & | ^ <<` são **tokenizados** (Tags `hash amp pipe caret ltLt`; o parser
é que nunca os consome — ver `GRAMMAR.md` Apêndice B). O léxico é **completo**: produz o token; filtrar é papel
de fases posteriores. (`@` **não** entra aqui: é **erro** `lex-annotation-unsupported` — P6, §2.7 / D5 / CA9a.)

**2.6 Sensibilidade a layout:** cada token carrega `line` (e coluna). A quebra de linha **não** é token, mas
`line` incrementa — o parser (Fase 2) a usará para continuação de `call`/`member`.

**2.7 Erros léxicos** (EN kebab-case + `line:col`, **sem abortar** — coleta N erros e emite `Tag.invalid` p/
resync): `lex-unexpected-char`, `lex-unterminated-string`, `lex-unterminated-multiline-string`,
`lex-unterminated-block-comment`, `lex-annotation-unsupported` (`@`, P6), e `lex-malformed-number` — número
mal-formado: `0x`/`0b` **sem dígito**, `2.0e` **sem expoente**, `_` inicial/final/duplo (`1__0`). **Nota:** o
oracle (`ita/`) **crasha** nesses (`int.parse('')`); o `ita-next` os trata como erro léxico (D3).

## §Artefato — `grammar.ebnf` (seção lexical, ADR-0010)

A especificação acima é formalizada em **W3C EBNF** em `compiler/docs/spec/grammar.ebnf` (seção "Lexical
grammar"), reconciliada com o `GRAMMAR.md` §1 do `ita/`. É a fonte-da-verdade citável do léxico. Além das
definições de 2.1, o artefato inclui: `CLOSURE_PARAM` (`$` + dígitos → `identifier`), a regra de `_` isolado
(→ `underscore`) vs `_x`/`_1` (→ `identifier`), e os separadores `_` **apertados** (`("_"? [dígito])*`, proíbem
inicial/final/duplo) que reconciliam o `GRAMMAR.md` §1 (frouxo). O comentário de bloco **aninhado** é anotado
como **não-regular** (resolvido por contador de profundidade, fora da gramática regular — §2.4).

---

## §9 Checklist de completude (Apêndice A)

- [ ] `token.dart` — enum de **todas** as categorias (`Tag`) + `class Token(tag, lexeme, line, [literal])`
- [ ] `lexer.dart` — scanner à mão cobrindo 2.1–2.7; maximal munch; comentário aninhado; erro não-abortante
- [ ] `grammar.ebnf` (seção lexical) versionado — reconciliado com `GRAMMAR.md` §1 do `ita/`
- [ ] `driver`/`bin` — comando `itac tokenize <file.tu>` (dump)
- [ ] scaffold + toolchain (`pin-dart.sh` assert 130) + CI (`dart test` dia 1) + `git init`

## §10 Compatibilidade e migração

- **Breaking?** Não — código novo em `ita-next/`, isolado; o `ita/` não é tocado.
- **Oracle do léxico:** o `ita/` **não dumpa tokens via MCP** (o MCP `ita` roda programas, não tokeniza). O
  oracle da Fase 1 é a **spec** (`GRAMMAR.md` §1) + o **`lexer.dart`/`test_lexer.dart` do `ita/`** como
  referência de comportamento. Casos duvidosos: comparar com o lexer do `ita/` (leitura/execução do teste).

## §11 Critérios de aceite (viram conformance de tokenização)

Cada CA = um `.tu` → **sequência de tokens esperada** (golden), em `conformance/valid/` (ou `invalid/` p/
erros). Verificados por `itac tokenize` + `dart test`; referência = léxico do `ita/`.

- **CA1** (keywords) — `let x = fn` ⟶ `kwLet, identifier(x), eq, kwFn, eof`; e `from` ⟶ `identifier` (contextual).
- **CA2** (INT 3 bases) — `42 0xFF 0b1010 1_000` ⟶ 4× `intLiteral` com os lexemas exatos.
- **CA3** (FLOAT) — `3.14 2.0e10 1_000.5` ⟶ 3× `floatLiteral`; `1.` **não** é FLOAT (falta dígito) → `intLiteral`+`dot`.
- **CA4** (STRING + interpolação) — `"hi ${name}!"` ⟶ `stringLiteral` com segmento interpolado reconhecido.
- **CA5** (MULTILINE_STRING) — `"""a\nb"""` ⟶ `multilineString`; `${}` **não** interpola dentro dela.
- **CA6** (comentário aninhado) — `/* a /* b */ c */ x` ⟶ só `identifier(x), eof` (bloco aninhado consumido).
- **CA7** (maximal munch) — `>> > <= < ..= .. != !` ⟶ tokens do operador **mais longo** primeiro (`gtGt, gt, ltEq, lt, dotDotEq, dotDot, bangEq, bang`).
- **CA8** (terminais mortos) — `& | ^ <<` ⟶ `amp, pipe, caret, ltLt` (tokenizados, não erro léxico) — §2.5.
- **CA9** (erro léxico) — char inválido / string não-terminada ⟶ `lex-unexpected-char` / `lex-unterminated-string` com **linha**, sem abortar (coleta múltiplos).
- **CA11** (keyword viva de declaração) — `static fn f()` ⟶ `kwStatic, kwFn, identifier(f), lparen, rparen, eof` (uma das 4 vivas de declaração — §2.2, D1).
- **CA12** (bordas do léxico — detalhadas no `conformance-cases.md`) — comentário de linha `//` (ignorado); string vazia `""` ⟶ `stringLiteral`; `_` sozinho ⟶ `underscore` e `_x` ⟶ `identifier` (§2.1a); `$0`/`$1` ⟶ `identifier` (closure, §2.1); `"""…` não-terminada ⟶ `lex-unterminated-multiline-string`; número mal-formado (`0x`, `0b`, `2.0e`, `1__0`) ⟶ `lex-malformed-number`; **contagem de linha** (`\n` incrementa `line`, não é token — §2.6).
- **CA10** (infra) — `itac tokenize` roda; `dart test` verde no CI; benchmark AOT sem regressão; `git init` feito.

## Definition of Done

- [ ] CA1–CA12 cobertos por goldens de tokenização; `dart test` verde; conferidos contra o léxico do `ita/`.
- [ ] `grammar.ebnf` (léxico) versionado e reconciliado (ADR-0010).
- [ ] Scaffold + toolchain + CI + `git init` (§S) prontos.
- [ ] Constitution check sem conflito; scanner à mão (sem gerador — P11).
