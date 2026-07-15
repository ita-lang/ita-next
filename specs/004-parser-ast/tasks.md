# Tasks 004: Sintaxe completa → AST (Fase 2)

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md) · **Design:** [`design-notes.md`](./design-notes.md) · [`conformance-cases.md`](./conformance-cases.md) · [`grammar-delta.md`](./grammar-delta.md) · **Escopo:** `ita-next/` (caminhos relativos a `ita-next/`)
>
> Fail-first de **fase sintática**: SETUP (golden-runner de parsing + CI) → RED (goldens `.ast` + erros que
> falham no scaffold sem parser) → GREEN (`ast.asdl`/`ast.dart`/`parser.dart`/`itac parse`/`grammar.ebnf`) →
> VALIDATE (`itac parse --dump` vs goldens + referência parser do `ita/`) → QUALITY (CI + benchmark).
>
> **Adaptação (parser):** o MCP `ita` **NÃO dumpa AST** (executa programas) → o VALIDATE é por
> **`itac parse --dump`** conferido com o `.ast` golden, tendo o **parser do `ita/` como referência** (exceto
> as **6 divergências** que consertamos — §0.6/§10). **Não há paridade VM×JS** nesta fase (sem codegen).
> **Ordem de ataque = as 4 fatias** (plan §5): **0 Fundação → 1 Expressões → 2 Statements → 3 Declarações**
> (bottom-up no grafo de chamadas, DB 4.4.1). Cada fatia tem seu ciclo RED→GREEN→VALIDATE.
>
> **Regras operacionais:** implementar via **agente do compilador**; **sem git durante subagente ativo**;
> comportamento observável NÃO é chutado (aqui: `itac parse --dump` + parser do `ita/`, não MCP run).

## Fase 1 — Setup

- [x] T001 Golden-runner de parsing em `conformance/` (script `run_parse.sh` ou runner Dart): roda `itac parse <f.tu> --dump` e confere byte-a-byte com o `.ast` de `valid/*.tu`; para `invalid/*.tu`, confere o **erro esperado** (kebab-case + span) declarado inline (`// EXPECT: parse-error: … @off+len`). Convenção de layout: `valid/<nome>.tu`+`<nome>.ast`, `invalid/<nome>.tu`.
- [x] T002 Estender `.github/workflows/ci.yml`: step **conformance de parsing** (após o léxico) + manter placeholder do benchmark AOT (o `itac` só vira AOT completo com pipeline até `.dill`; a Fase 2 para em `parse`).

## Fase 2 — RED (goldens `.ast` / erros que falham sem parser)

> Um caso por CA da spec §11. Devem **falhar hoje** (não há `itac parse`). Todos `[P]` (arquivos distintos).
> Fontes e AST esperada já fixadas em [`conformance-cases.md`](./conformance-cases.md).

**Fatia 0 — Fundação (tipos, patterns, recuperação)**
- [x] T003 [P] [CA15] (RED) `conformance/valid/type_generics_nested.tu` + `.ast` — `Map<String, List<Int>>` (generics aninhados, token-splitting `>>`).
- [x] T004 [P] [CA16] (RED) `conformance/valid/pattern_struct_wildcard.tu` + `.ast` — `match p { P { x, .. } => x, _ => 0 }` (struct-pattern lookahead `IDENT "{"` + wildcard).
- [x] T005 [P] [CA17] (RED) `conformance/valid/type_fn_mut_optional.tu` + `.ast` — `(Int, Int) -> Int` e `mut Foo?`.
- [x] T006 [P] [CA18] (RED) `conformance/invalid/recover_unclosed_paren.tu` — `fn f( {` seguido de `fn g() => 1`; espera `parse-error: expected-token` + `error-decl` **e** `fn g` parseado (resync sem cascata).

**Fatia 1 — Expressões**
- [x] T007 [P] [CA8] (RED) `conformance/valid/expr_prec_pow.tu` + `.ast` — `a + b * c` ⟶ `(+ a (* b c))`; `a ** b ** c` ⟶ `(** a (** b c))` (direita).
- [x] T008 [P] [CA9] (RED) `conformance/valid/expr_pipe_coalesce.tu` + `.ast` — `x |> f >> g` ⟶ `(>> (|> x f) g)`; `a ?? b || c` ⟶ **`(?? a (|| b c))`** (golden corrigido).
- [x] T009 [P] [CA10] (RED) `conformance/invalid/expr_range_nonassoc.tu` — `a..b..c` ⟶ `parse-error: range-non-associative` @ 2º `..` (**checagem nova** vs oracle).
- [x] T010 [P] [CA11] (RED) `conformance/valid/expr_postfix_chain.tu` + `.ast` — `obj.field?.m()!.x` (cadeia member/`?.`/call/`!`/member).
- [x] T011 [P] [CA12] (RED) `conformance/valid/expr_postfix_kinds.tu` + `.ast` — `p.{ x: 1 }` (copy-with), `t.0` (tuple-index), `xs[i]` (index).
- [x] T012 [P] [CA13] (RED) `conformance/valid/expr_trailing_closure.tu` + `.ast` — `f(x) { $0 + 1 }` (mesma linha = trailing) **e** `f(x)`⏎`{…}` (call sem closure + block). **Conserta bug do oracle.**
- [x] T013 [P] [CA14] (RED) `conformance/valid/expr_match_enum.tu` + `.ast` — `match o { .Some(v) => v, .None => 0 }`.
- [x] T014 [P] [CA19] (RED) `conformance/valid/expr_await_binds_unary.tu` + `.ast` — `await a + b` ⟶ `(+ (await a) b)`; `spawn f() + 1` ⟶ `(+ (spawn (call f)) 1)` (Q4).
- [x] T015 [P] [CA20] (RED) `conformance/valid/expr_string_interp.tu` + `.ast` — `"x=${a + 1}!"` ⟶ `(str "x=" (+ (id a) (int 1)) "!")` (partes ordenadas parse-time).
- [x] T016 [P] [CA23] (RED) `conformance/invalid/expr_bare_block.tu` — `let x = { let a = 1; a }` ⟶ `parse-error` (bloco-nu não é expr; `{` em expr-pos = map; Q1).

**Fatia 2 — Statements**
- [x] T017 [P] [CA5] (RED) `conformance/valid/stmt_let_destructure.tu` + `.ast` — `let { x, y } = p` e `let [h, ..t] = xs`.
- [x] T018 [P] [CA6] (RED) `conformance/valid/stmt_if_dangling_else.tu` + `.ast` — `if a { x } else if b { y } else { z }` (dangling-else ao `if` interno).
- [x] T019 [P] [CA7] (RED) `conformance/valid/stmt_for_await_guard.tu` + `.ast` — `for await x in xs { }` e `guard let v = o else { return }`.
- [x] T020 [P] [CA21] (RED) `conformance/valid/expr_cond_closure_suppression.tu` + `.ast` — `if f(x) { a } else { b }` (`{`=bloco, suprime) **e** `guard f(x) { } else { r }` (`guard` **não** suprime).

**Fatia 3 — Declarações**
- [x] T021 [P] [CA1] (RED) `conformance/valid/decl_fn_generic_default.tu` + `.ast` — `fn add<T: Ord>(a: T, b: T = zero) -> T => a`.
- [x] T022 [P] [CA2] (RED) `conformance/valid/decl_struct_field_method.tu` + `.ast` — `struct P { x: Int, fn mag() -> Int => x }` (intercalados).
- [x] T023 [P] [CA3] (RED) `conformance/valid/decl_enum_adt.tu` + `.ast` — `enum Opt<T> { Some(v: T), None }`.
- [x] T024 [P] [CA4] (RED) `conformance/valid/decl_import.tu` + `.ast` — `import { a as b } from "m"` e `import * as m from "m"`.
- [x] T025 [P] [CA22] (RED) `conformance/invalid/decl_meaningless_pub.tu` (`pub impl T for U { }` ⟶ `parse-error: meaningless-pub`) **e** `conformance/valid/decl_pub_fn.tu`+`.ast` (`pub fn f() => 1` OK).

**Unit RED**
- [x] T026 [P] [CA18] (RED) `compiler/test/parser_test.dart` — asserts que golden não pega bem: shape de `ErrorNode`/`ErrorExpr`, `span` (offset+length) preciso, associatividade de `**`/range. Falha hoje (sem `ast.dart`).

## Fase 3 — GREEN (implementar até passar, por fatia)

**Fatia 0 — Fundação**
- [x] T027 [CA15] [CA16] [CA17] [CA18] (GREEN) `compiler/docs/spec/ast.asdl` — Zephyr ASDL: sums `decl`/`stmt`/`expr`/`type`/`pattern` + products (`param`/`genericParam`/`field`/`enumCase`/`matchArm`/`arg`/`importMember`/`fieldPattern`/`strPart`) + variantes `ErrorDecl`/`ErrorStmt`/`ErrorExpr` + `attributes (int offset, int length)`. Ver `design-notes.md` §Modelagem.
- [x] T028 [CA…] (GREEN) `compiler/lib/frontend/parser/ast.dart` — nós `sealed` (Visitor, CI 5.3) do `ast.asdl`, **à mão OU por script Dart do dev** (saída commitada — **P11**, nunca `build_runner`). Depende de: T027.
- [x] T029 [CA…] (GREEN) `compiler/lib/driver/driver.dart` + `compiler/bin/itac.dart` — comando **`itac parse <f.tu> --dump [--spans]`**: pretty-printer S-expr determinístico (`(tag campos…)`, CI 5.4; spans elididos por padrão). Depende de: T028.
- [x] T030 [CA18] (GREEN) `compiler/lib/frontend/parser/parser.dart` — infra: `_current`/`_peek`/`_advance`/`_match`/`_check`; **recuperação N2** (`ParseError` + `_synchronize` com sync-set consciente de boundary-closer; enxerta `Error*` — **não** `null`). Depende de: T028.
- [x] T031 [CA15] [CA17] (GREEN) `parser.dart` — `type`: `mut`/`async`/função/tupla/grupo/generics/optional `?` + **token-splitting `>>`→`>`+`>`** em posição de tipo (`_consumeTypeGt`). Depende de: T030.
- [x] T032 [CA16] (GREEN) `parser.dart` — `pattern`: `_`, enum-variant `.Ident(...)`, list, **struct-pattern** (lookahead `IDENT "{"`, k=2), range/literal, binding, `..rest`. Depende de: T030.

**Fatia 1 — Expressões**
- [x] T033 [CA8] (GREEN) `parser.dart` — **cascata de precedência** de 13 níveis (uma função por nível, CI 6.2): `where`/assign(**dir.**)/…/`+`/`*`/`**`(**dir.**)/unário/pós-fixo. Depende de: T031.
- [x] T034 [CA9] (GREEN) `parser.dart` — níveis 2–7: `|>`/`>>` (compose, esq.), `??`(3), `||`(4), `&&`(5), `==`/`!=`(6), comparação(7). Depende de: T033.
- [x] T035 [CA10] (GREEN) `parser.dart` — `_range` (nível 8) **não-assoc**: após `a..b`, um novo `..`/`..=` ⟶ `range-non-associative` + span. **Conserta oracle.** Depende de: T033.
- [x] T036 [CA19] (GREEN) `parser.dart` — `await`/`spawn` no **nível unário** (12), recursão em `_unary` (Q4). **Conserta oracle guloso.** Depende de: T033.
- [x] T037 [CA11] [CA12] (GREEN) `parser.dart` — `_postfix` (nível 13): call, member `.`, `?.`, index `[]`, force-unwrap `!`, try `?`, copy-with `.{…}`, tuple-index `.N`. Depende de: T033.
- [x] T038 [CA13] [CA21] (GREEN) `parser.dart` — trailing-closure **mesma-linha** (`_peek().line == operando.line`, também no `_finishCall` — conserta bug) + supressão via flag `_noTrailingClosure` na condição de `if`/`while`/`for`/`match`; `guard` **não** seta (assimetria). Depende de: T037.
- [x] T039 [CA20] (GREEN) `parser.dart` — interpolação **parse-time**: nó `Str(strPart*)` com partes ordenadas `Lit|Interp(expr)`. **Conserta oracle** (defer ao codegen). Depende de: T033.
- [x] T040 [CA14] (GREEN) `parser.dart` — `matchExpr` + `matchArm` (pattern + `if`-guard + `=>` expr). Depende de: T032, T033.
- [x] T041 [CA23] (GREEN) `parser.dart` — `primary`: bloco-nu **não é expr** (`{` em expr-pos = map literal; erro se não casar `expr : expr`); `BlockExpr` **removido** (Q1). Depende de: T033.
- [x] T042 [CA9] (GREEN) `parser.dart` — cantos restantes: `<` genérico-vs-comparação (D2, sem turbofish); if-expr; enum shorthand `.Ident`; `parenOrClosure` (`_isClosureStart` scan-ahead — **único lookahead ilimitado**, vigiar); `(a,)` 1-tupla ⟶ erro (M7). Depende de: T033.

**Fatia 2 — Statements**
- [x] T043 [CA5] (GREEN) `parser.dart` — `let`/`var` + destructure `{}`/`[]` + `..rest`; `exprStmt`; `emit`; `return` (vazio se `}`/EOF). Depende de: T033, T032.
- [x] T044 [CA6] (GREEN) `parser.dart` — `ifStmt`/`guard` + **dangling-else** (liga ao `if` interno, CI 9.2). Depende de: T043.
- [x] T045 [CA7] (GREEN) `parser.dart` — `while`/`for`/`for await` + `guard let … else` + `break`/`continue` + `block` (`;` separadores opcionais). Depende de: T043.

**Fatia 3 — Declarações & reconciliação**
- [x] T046 [CA1] (GREEN) `parser.dart` — `fnDecl` (+ `async`/`stream fn`) + `genericParams` com bounds (`T: A + B`) + `paramList` (labels+nomes+defaults + grupo nomeado `;`) + `fnBody` (`=>` block|expr). Depende de: T031, T045.
- [x] T047 [CA2] [CA3] (GREEN) `parser.dart` — `struct`/`class`/`enum`(ADT) com campos **e** métodos intercaláveis + variantes com payload. Depende de: T046.
- [x] T048 [CA22] (GREEN) `parser.dart` — `impl`/`extension`/`trait`/`actor`/`operator`/`import` (ES6 3 formas) + **`meaningless-pub`** em `impl`/`extension`/`import`/`operator` (D3, error production); `pub` repassado a `fn`/`struct`/`class`/`enum`/`trait`. Depende de: T046.
- [x] T049 [CA18] (GREEN) `parser.dart` — `_declaration()` como **boundary de sincronização** (`program = declaration* EOF`); fecha a recuperação N2 (CA18: próximo top-level parseia). Depende de: T030, T046.
- [x] T050 [P] (GREEN) `compiler/docs/spec/grammar.ebnf` — seção **"Syntactic grammar"** (W3C EBNF) reconciliada com `GRAMMAR.md` §2–§6 + comentários de aperto (grammar-delta §3). Independe do código.

## Fase 4 — VALIDATE (`itac parse --dump` vs goldens + referência `ita/`)

- [x] T051 [CA15] [CA16] [CA17] [CA18] (VALIDATE) Fatia 0: `itac parse --dump` dos casos → conferir byte-a-byte com `.ast`; cruzar com o parser do `ita/` (referência).
- [x] T052 [CA8] [CA9] [CA10] [CA11] [CA12] [CA13] [CA14] [CA19] [CA20] [CA23] (VALIDATE) Fatia 1: idem; **documentar as divergências** vs oracle (CA9 golden corrigido, CA10/CA13/CA19/CA20/CA23 consertos).
- [x] T053 [CA5] [CA6] [CA7] [CA21] (VALIDATE) Fatia 2: idem (dangling-else, `for await`, supressão/assimetria de trailing-closure).
- [x] T054 [CA1] [CA2] [CA3] [CA4] [CA22] (VALIDATE) Fatia 3: idem; `meaningless-pub` (conserta consumo mudo do oracle).
- [x] T055 [CA10] [CA18] [CA22] [CA23] (VALIDATE) `invalid/*.tu` → conferir mensagem **kebab-case + span** e, no CA18, o **resync sem cascata** (o `fn g` seguinte parseia). *(Sem paridade VM×JS nesta fase — sem codegen.)*

## Fase 5 — QUALITY (gate final)

- [x] T056 `dart test` (`parser_test.dart`) verde no CI.
- [x] T057 Conformance de parsing verde (`valid/*.ast` + `invalid/` erros) via golden-runner (T001).
- [x] T058 Benchmark de compile-time (`itac` AOT) sem regressão — **PLACEHOLDER** (o `itac` AOT completo só com pipeline até `.dill`; vigiar em especial o **scan-ahead ilimitado** de `_isClosureStart` e a recursão da cascata — §0.6/plan §6).
- [x] T059 Reconciliação: `GRAMMAR.md` §2–§6 ↔ `grammar.ebnf` §Syntactic; **deltas tree-sitter registrados** em `grammar-delta.md` §4 (correção no repo `tree-sitter-ita` = fora de escopo).
- [x] T060 Constitution check final (P3/P4/P6/P11 + Art. IV) + **DoD da spec** satisfeita. Commit no `ita-next/` (via agente; **sem git durante subagente ativo**).

## Dependências

- **Setup** (T001–T002) antes de tudo. **RED** (T003–T026) após o golden-runner (T001) — todos `[P]`.
- **GREEN por fatia** (bottom-up): **Fatia 0** T027→T028→{T029, T030, T031, T032}; **Fatia 1** T033→{T034, T035, T036, T037, T039, T041, T042}, T037→T038, T040←{T032, T033}; **Fatia 2** T043→{T044, T045}; **Fatia 3** T046→{T047, T048, T049}. T050 (grammar.ebnf) `[P]` com o código.
- **VALIDATE** de cada fatia após seu GREEN (T051 após Fatia 0, etc.). **QUALITY** por último.
- **`ast.asdl`/`ast.dart` (T027/T028) destravam TUDO** — são a raiz do grafo.

## Execução paralela (`[P]`)

- **RED** T003–T026: todos `[P]` (arquivos `.tu`/`.ast` distintos).
- **GREEN:** T050 (`grammar.ebnf`) ‖ o código; dentro da Fatia 1, os níveis independentes da cascata
  (T034/T035/T036/T037/T039/T041/T042) após T033. Fatias 2 e 3 são **sequenciais** entre si (grafo de chamadas).

## Estratégia de implementação (incremental, fatia a fatia)

1. **Fatia 0 primeiro** (T027–T032): `ast.asdl`+`ast.dart`+`itac parse --dump`+recuperação+tipos/patterns.
   Fecha CA15–18 no VALIDATE (T051) — **primeiro loop RED→GREEN→VALIDATE verde**.
2. **Fatia 1** (T033–T042): expressões (maior risco). Fecha CA8–14,19,20,23 (T052).
3. **Fatia 2** (T043–T045): statements. Fecha CA5–7,21 (T053).
4. **Fatia 3** (T046–T050): declarações + reconciliação. Fecha CA1–4,22 (T054) e o resync de CA18 (T049).
5. **QUALITY** (T056–T060): CI verde + benchmark + reconciliação + DoD.

> **Primeira fatia sugerida (menor loop):** **Fatia 0** — `ast.asdl`/`ast.dart`/`itac parse --dump` são a
> fundação de tudo; CA17 (tipos) é o caso mais simples para fechar o primeiro ciclo end-to-end.
