# Conformance cases — Fase 2 (Sintaxe → AST) · spec 004

> **Phase 1 do `/speckit-plan`.** Os 23 CAs da spec §11 materializados como casos do corpus de parsing.
> Local: `ita-next/conformance/valid/*.tu` + `.ast` (golden) e `conformance/invalid/*.tu` (erros de parse).
> **Formato do dump:** S-expression determinística `(tag campos…)`, spans elididos por padrão (`--spans`
> inclui) — ver `design-notes.md` §"Dump S-expr". **Oracle** = `itac parse --dump` do `ita-next` conferido
> contra o parser do `ita/` + `GRAMMAR.md` §2–§6; onde o `ita/` tem bug/dead-code, o golden = comportamento
> **correto**, marcado.
>
> **Nota de fidelidade:** as S-exprs abaixo são **normativas na estrutura** (tags, aninhamento,
> associatividade). O byte-a-byte exato (espaçamento, quebras) **congela no `/speckit-implement`** (fase
> GREEN, task do `tasks.md`) — a spec §A.3 delegou "o formato exato fecha no plan"; aqui fixamos as
> convenções e a forma esperada de cada caso.
>
> **Convenção de tags do dump** (fechada aqui): binários e prefixos/pós-fixos usam o **símbolo do operador**
> como tag (`+`, `*`, `**`, `==`, `<`, `&&`, `||`, `??`, `|>`, `>>`, `..`, `..=`, `=`); `-` unário = `neg`;
> literais `(int N)`/`(float N.N)`/`(str …)`/`(bool …)`/`nil`/`(id nome)`/`self`; visibilidade `pub` = marker
> `:pub`. Detalhe completo no `design-notes.md`.

---

## ⚠️ Correção de golden na spec §11 (CA9, parte 2)

O golden de **CA9** na spec §11 (`a ?? b || c ⟶ (|| (?? a b) c)`) **contradiz a fonte normativa**: a
`GRAMMAR.md` §4.2 fixa **`??` = nível 3 (mais frouxo)** e **`||` = nível 4 (mais forte)**; o oracle
`parser.dart` implementa `_nilCoalesce` chamando `_or` como operando (⇒ `||` liga mais forte). O golden
**correto** é **`(?? a (|| b c))`**. Este corpus usa o valor correto (abaixo). **Ação recomendada:** corrigir
o texto de CA9 na `spec.md` §11 (proposta no relatório do `/speckit-plan`). Precedência da constituição:
`GRAMMAR.md` (normativa) > texto da spec.

---

## Declarações (Fatia 3)

### CA1 — `fn` com generic-bound + param-default
- **Corpus:** `valid/decl_fn_generic_default.tu`
- **Fonte:** `fn add<T: Ord>(a: T, b: T = zero) -> T => a`
- **AST:**
  ```
  (fn "add"
    (generics (generic "T" (bound (type Ord))))
    (params (param "a" (type T)) (param "b" (type T) (default (id zero))))
    (ret (type T))
    (=> (id a)))
  ```
- **Prova:** `genericParam` com bound `T: Ord` + `param` com `= default`.

### CA2 — `struct` com campo **e** método intercalados
- **Corpus:** `valid/decl_struct_field_method.tu`
- **Fonte:** `struct P { x: Int, fn mag() -> Int => x }`
- **AST:**
  ```
  (struct "P"
    (field "x" (type Int))
    (fn "mag" (params) (ret (type Int)) (=> (id x))))
  ```
- **Prova:** `structDecl` aceita `methodDecl | fieldDecl` intercalados.

### CA3 — `enum` ADT com variantes (uma com payload)
- **Corpus:** `valid/decl_enum_adt.tu`
- **Fonte:** `enum Opt<T> { Some(v: T), None }`
- **AST:**
  ```
  (enum "Opt"
    (generics (generic "T"))
    (case "Some" (payload (param "v" (type T))))
    (case "None"))
  ```

### CA4 — `import` com alias e star
- **Corpus:** `valid/decl_import.tu`
- **Fonte 1:** `import { a as b } from "m"` → `(import (named (item "a" (as "b"))) (from "m"))`
- **Fonte 2:** `import * as m from "m"` → `(import (star (as "m")) (from "m"))`

---

## Statements (Fatia 2)

### CA5 — `let` com destructure
- **Corpus:** `valid/stmt_let_destructure.tu`
- **Fonte 1:** `let { x, y } = p` → `(let (pat-record (bind "x") (bind "y")) (id p))`
- **Fonte 2:** `let [h, ..t] = xs` → `(let (pat-list (bind "h") (rest "t")) (id xs))`
- **Prova:** destructure de registro `{}` e de lista `[]` com `..rest`.

### CA6 — dangling-else (liga ao `if` mais próximo)
- **Corpus:** `valid/stmt_if_dangling_else.tu`
- **Fonte:** `if a { x } else if b { y } else { z }`
- **AST:**
  ```
  (if-stmt (id a)
    (block (expr-stmt (id x)))
    (else (if-stmt (id b)
      (block (expr-stmt (id y)))
      (else (block (expr-stmt (id z)))))))
  ```
- **Prova:** o 2º `else` liga ao `if b` (interno) — **CI 9.2 / DB 4.3.2**.

### CA7 — `for await` e `guard let … else`
- **Corpus:** `valid/stmt_for_await_guard.tu`
- **Fonte 1:** `for await x in xs { }` → `(for-await (bind "x") (id xs) (block))`
- **Fonte 2:** `guard let v = o else { return }` → `(guard-let (bind "v") (id o) (else (block (return))))`

---

## Expressões — precedência (Fatia 1)

### CA8 — precedência e associatividade de `**`
- **Corpus:** `valid/expr_prec_pow.tu`
- **Fonte 1:** `a + b * c` → `(+ (id a) (* (id b) (id c)))` (`*` nível 10 > `+` nível 9)
- **Fonte 2:** `a ** b ** c` → `(** (id a) (** (id b) (id c)))` (`**` nível 11, **direita**)

### CA9 — pipe/compose e `??`/`||` ⚠️ **(golden corrigido)**
- **Corpus:** `valid/expr_pipe_coalesce.tu`
- **Fonte 1:** `x |> f >> g` → `(>> (|> (id x) (id f)) (id g))` (`|>` e `>>` ambos nível 2, **esquerda**)
- **Fonte 2:** `a ?? b || c` → **`(?? (id a) (|| (id b) (id c)))`** — `||` (nível 4) liga mais forte que
  `??` (nível 3). **Corrige o golden invertido da spec §11** (ver topo).

### CA10 — range não-associativo (**checagem nova** além do oracle)
- **Corpus:** `invalid/expr_range_nonassoc.tu`
- **Fonte:** `a..b..c`
- **Erro:** `parse-error: range-non-associative` com span do 2º `..`.
- **Prova:** `..` é nível 8 **não-assoc** (§4.2); após `a..b`, um novo `..` ⇒ erro. O oracle **não emite**
  (`_range` usa `if`, deixa `..c` solto) — o `ita-next` **conserta** (§10).

### CA11 — cadeia pós-fixa
- **Corpus:** `valid/expr_postfix_chain.tu`
- **Fonte:** `obj.field?.m()!.x`
- **AST:**
  ```
  (member
    (force-unwrap
      (call
        (opt-chain (member (id obj) "field") "m")))
    "x")
  ```
- **Prova:** pós-fixos left-assoc (nível 13): member → `?.` → call → `!` → member.

### CA12 — copy-with, tuple-index, index
- **Corpus:** `valid/expr_postfix_kinds.tu`
- **Fonte 1:** `p.{ x: 1 }` → `(copy-with (id p) (field "x" (int 1)))`
- **Fonte 2:** `t.0` → `(tuple-index (id t) 0)`
- **Fonte 3:** `xs[i]` → `(index (id xs) (id i))`

### CA13 — trailing closure exige mesma linha (**conserta bug do oracle**)
- **Corpus:** `valid/expr_trailing_closure.tu`
- **Fonte 1 (mesma linha):** `f(x) { $0 + 1 }` →
  ```
  (call (id f) (id x) (closure (block (expr-stmt (+ (id $0) (int 1))))))
  ```
  (o `closure` na última posição = trailing closure)
- **Fonte 2 (quebra de linha):** `f(x)`⏎`{ … }` → **call sem closure** + block separado:
  ```
  (expr-stmt (call (id f) (id x)))
  (block …)
  ```
- **Prova:** `{` só vira trailing-closure se `_peek().line == operando.line`. O oracle **não checa linha no
  `_finishCall`** (bug) — o `ita-next` **conserta** (§10). Divergência marcada no golden.

### CA14 — `match` com arms de enum-variant
- **Corpus:** `valid/expr_match_enum.tu`
- **Fonte:** `match o { .Some(v) => v, .None => 0 }`
- **AST:**
  ```
  (match (id o)
    (arm (pat-enum "Some" (bind "v")) (id v))
    (arm (pat-enum "None") (int 0)))
  ```

---

## Tipos e patterns (Fatia 0)

### CA15 — generics aninhados via token-splitting de `>>`
- **Corpus:** `valid/type_generics_nested.tu`
- **Fonte:** `let m: Map<String, List<Int>> = e`
- **AST:**
  ```
  (let (bind "m")
    (type Map (type String) (type List (type Int)))
    (id e))
  ```
- **Prova:** o `>>` final é **splitado** em `>`+`>` por `_consumeTypeGt` (DB 4.4) para fechar
  `List<Int>` e `Map<…>`. Em expressão, `>>` continuaria compose.

### CA16 — struct-pattern (lookahead `IDENT "{"`) + wildcard
- **Corpus:** `valid/pattern_struct_wildcard.tu`
- **Fonte:** `match p { P { x, .. } => x, _ => 0 }`
- **AST:**
  ```
  (match (id p)
    (arm (pat-struct "P" (field-pat "x") (rest)) (id x))
    (arm (pat-wildcard) (int 0)))
  ```
- **Prova:** `IDENT "{"` (k=2) desambigua struct-pattern de binding.

### CA17 — tipo função e `mut`/optional
- **Corpus:** `valid/type_fn_mut_optional.tu`
- **Fonte 1:** `let f: (Int, Int) -> Int = e` →
  `(let (bind "f") (type-fn (params (type Int) (type Int)) (ret (type Int))) (id e))`
- **Fonte 2:** `let x: mut Foo? = e` →
  `(let (bind "x") (type-mut (type-optional (type Foo))) (id e))`
- **Prova:** `mut` envolve o tipo; `?` é optional-de-`Foo` (`mut (Foo?)`).

---

## Erros de parse — recuperação N2 (Fatia 0 / transversal)

### CA18 — parêntese não fechado + resync sem cascata
- **Corpus:** `invalid/recover_unclosed_paren.tu`
- **Fonte:**
  ```tu
  fn f( { }
  fn g() => 1
  ```
- **Erro:** `parse-error: expected-token` (esperava `)`), com span; a AST enxerta `(error-decl …)` no lugar
  do `fn f` quebrado **e o `fn g` seguinte parseia normalmente** (resync no boundary de declaração):
  ```
  (error-decl …)
  (fn "g" (params) (=> (int 1)))
  ```
- **Prova:** panic-mode + sync-set (**DB 4.4.5 / CI 6.3, 8.2.2**); `ErrorNode` bem-tipado, **sem cascata**.

---

## Decisões da validação (§0.6)

### CA19 — `await`/`spawn` ligam no nível unário (Q4)
- **Corpus:** `valid/expr_await_binds_unary.tu`
- **Fonte 1:** `await a + b` → `(+ (await (id a)) (id b))`
- **Fonte 2:** `spawn f() + 1` → `(+ (spawn (call (id f))) (int 1))`
- **Prova:** `await`/`spawn` no nível 12 (unário) > `+` nível 9. **Conserta o oracle guloso** (`_expression()`).

### CA20 — interpolação parseada em parse-time (partes ordenadas)
- **Corpus:** `valid/expr_string_interp.tu`
- **Fonte:** `"x=${a + 1}!"`
- **AST:** `(str "x=" (+ (id a) (int 1)) "!")`
- **Prova:** o nó `Str` guarda **partes ordenadas** `Lit | Interp(expr)` (M3). O oracle difere ao codegen
  (expr embutida como string crua) — o `ita-next` **conserta**; alimenta o `StringConcatenation` do Kernel.

### CA21 — supressão de trailing-closure na condição (assimetria `if` vs `guard`)
- **Corpus:** `valid/expr_cond_closure_suppression.tu`
- **Fonte 1 (`if` suprime):** `if f(x) { a } else { b }` → o `{ a }` é **then-block**, não trailing-closure:
  ```
  (if-stmt (call (id f) (id x))
    (block (expr-stmt (id a)))
    (else (block (expr-stmt (id b)))))
  ```
- **Fonte 2 (`guard` NÃO suprime):** `guard f(x) { } else { r }` → o `{ }` é **trailing-closure** de `f(x)`:
  ```
  (guard (call (id f) (id x) (closure (block)))
    (else (block (expr-stmt (id r)))))
  ```
- **Prova:** flag de estado `_noTrailingClosure` na condição de `if`/`while`/`for`/`match`; `guard` **não**
  seta (só tem `else {}`, o `{}` da condição *é* closure legítimo). Assimetria deliberada.

### CA22 — `pub` sem sentido → erro (Q3)
- **Corpus 1:** `invalid/decl_meaningless_pub.tu`
- **Fonte 1:** `pub impl T for U { }` → `parse-error: meaningless-pub` com span do `pub`.
- **Corpus 2:** `valid/decl_pub_fn.tu`
- **Fonte 2:** `pub fn f() => 1` → OK: `(fn :pub "f" (params) (=> (int 1)))`
- **Prova:** `pub` é no-op em `impl`/`extension`/`import`/`operator` (error production, DB 4.1.4); válido em
  `fn`/`struct`/`class`/`enum`/`trait`. **Conserta o consumo mudo do oracle.**

### CA23 — bloco-nu não é expressão (Q1)
- **Corpus:** `invalid/expr_bare_block.tu`
- **Fonte:** `let x = { let a = 1; a }`
- **Erro:** `parse-error` — o RHS de `=` é posição-de-expressão → `{` inicia **map literal** → `let a = 1`
  não casa `expr ":" expr` (chave de map) ⇒ erro. (Mensagem exata — `map-entry-expected` ou
  `expected-expression` — congela no GREEN.)
- **Prova:** bloco-nu nunca é valor (Swift 6.3); `BlockExpr` do oracle removido. O poder vem de
  `if`/`match`-expr com valor explícito (P4).

---

## Cobertura → checklist (spec §9)

| Área | CAs | Corpus |
| :-- | :-- | :-- |
| Declarações | CA1–CA4, CA22 | `valid/decl_*`, `invalid/decl_meaningless_pub` |
| Statements | CA5–CA7, CA21 | `valid/stmt_*`, `valid/expr_cond_closure_suppression` |
| Expressões/precedência | CA8–CA14, CA19–CA20, CA23 | `valid/expr_*`, `invalid/expr_*` |
| Tipos e patterns | CA15–CA17 | `valid/type_*`, `valid/pattern_*` |
| Recuperação N2 | CA18 | `invalid/recover_*` |

**Divergências deliberadas vs oracle marcadas nos goldens** (§10): CA9 (golden corrigido), CA10
(`range-non-associative` novo), CA13 (mesma-linha no `f(args){}`), CA19 (await forte), CA20 (interpolação
parse-time), CA22 (`meaningless-pub`), CA23 (bloco-nu não-expr).
