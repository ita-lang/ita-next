# Spec 004: Sintaxe completa → AST (Fase 2)

> **Tipo:** feature-sintaxe · **Marco:** `Reescrita / Fase 2` (épico `002`, ADR-0011)
> **Status:** `draft`
> **Autor / Data:** GabrielAderaldo (via harness SDD) · 2026-07-10 · **Issue/PR:** `—`

## §0 Metadados

- **Classe da mudança** (Apêndice A):
  - [x] **Nova regra/fase** — atravessa uma fase inteira (a análise sintática do front-end).
- **Fases tocadas** (as demais foram **removidas** desta spec):
  - [x] Sintaxe (§3) · [x] Artefatos formais (§A) — grammar.ebnf §Syntactic + `ast.asdl`
  - (Léxico já feito na Fase 1 e é **reusado**; tipos/semântica/fluxo/codegen/runtime são fases seguintes.)
- **Princípios do Itá afetados:** P4 (sem mágica — gramática documentada), P11 (zero code generation em build-time — parser à mão; `ast.asdl`→`ast.dart` por script do dev, saída commitada, **nunca** build-time), P6 (zero annotations — não há `@` na sintaxe), P3 (tudo é expressão — `if`/`match` como expressão).

### §0.5 Constitution check

- **P4 (sem mágica):** ✅ toda a gramática vira artefato citável (`grammar.ebnf` §Syntactic + `GRAMMAR.md` §2–§6); os cantos de desambiguação (§3.3) são explícitos.
- **P11 (zero code generation em build-time):** ✅ parser **descendente recursivo + Pratt à mão** (sem yacc/ANTLR/PEG-gen). O `ast.asdl` é a definição canônica; o `ast.dart` é **escrito à mão** ou gerado por um **script Dart do dev** (saída commitada, fora do build) — mesma tolerância do `tree-sitter generate` (ADR-0010). **Nunca** `build_runner`.
- **P6 (zero annotations):** ✅ nenhuma produção introduz `@decorators`.
- **P3 (tudo é expressão):** ✅ `if`/`match` como expressão preservados. **Bloco-nu `{…}` NÃO é
  expressão** (statements-only) — decisão da validação (§0.6), seguindo o **Swift 6.3**: bloco-nu nunca é
  valor; o poder expressivo vem de `if`/`match`(/`do`)-expressions com valor **explícito**, não de bloco
  implícito. O `BlockExpr` órfão do oracle é **removido**.
- **Veredito:** **sem conflito** com princípio permanente. *(Nota operacional: check feito diretamente +
  validação adversarial dos 3 especialistas — ver §0.6; numa sessão nova o `ita-visionary` dispararia sozinho.)*

### §0.6 Decisões da validação adversarial (clarify — 2026-07-10)

Os 3 subagentes-especialista (`ita-visionary`/`compiler-craftsman`/`dart-vm-expert`) validaram esta spec
antes do `/speckit-plan`. **4 rulings do dono** + **gaps técnicos incorporados**:

**Rulings do dono:**
1. **Bloco-nu não é expressão** (statements-only) — modelo **Swift 6.3** (bloco-nu nunca vira valor; `if`/
   `match`/`do`-expressions com valor explícito, nunca última-expressão-implícita à la Rust — casa com P4).
   `BlockExpr` removido do ASDL.
2. **Type-args no call-site: inference-only permanente** — sem turbofish; `Foo<Int>()` em expressão é
   `((Foo<Int)>())` (débito preservado, virado decisão consciente). Confia na inferência (Fase 5).
3. **`pub` sem sentido → erro de parse** — rejeitar `pub` onde é no-op (`impl`/`extension`/`import`/
   `operator`) com `parse-error: meaningless-pub` + span (P4; conserta o consumo-mudo do oracle).
4. **`await a + b` = `(await a) + b`** — `await`/`spawn` ligam no nível **unário** (não guloso-à-direita);
   conserta o oracle e alinha à nota do `GRAMMAR.md` §4.2. Vira CA.

**Gaps técnicos incorporados (conserto/completude — refletidos em §3/§A/§11):**
- **Interpolação de string** parseada em **parse-time** (o oracle deferia ao codegen → AST incompleta):
  nó com **partes ordenadas** `str | expr` (§3.1, §A). Conserta o débito; o `dart-vm-expert` confirma que
  isso alimenta o `StringConcatenation` do Kernel (só o parser testemunha a ordem).
- **Supressão de trailing-closure na condição** de `if`/`while`/`for`/`match` (e `guard` **não** suprime —
  assimetria): é **estado de parser** (não CFG) — a desambiguação bloco-vs-closure central (§3.3).
- **CA10 (`range-non-associative`)** e **CA13 (trailing-closure mesma-linha em `f(args){}`)** são
  **checagens NOVAS além do oracle** (o oracle não emite o 1º; tem **bug** no 2º — não checa linha) →
  golden = comportamento correto, divergência marcada (§10).
- **Recuperação N2:** introduz `ErrorNode`/`ErrorExpr`/`ErrorStmt` no ASDL (melhor p/ IDE/downstream; o
  oracle só descarta+acumula numa lista) + resync por sync-set no boundary de statement/decl (§A, §3.6).
- **Notas de backend p/ o plan** (`dart-vm-expert`): a Fase 3 (desugaring) **herda o `span`** dos nós
  brutos nos nós sintetizados; taxonomia async-marker = **Sync/Async/AsyncStar** (sem `SyncStar` hoje).
- **Correções de modelagem** (`compiler-craftsman`, não portar sujeira do oracle): `IfExpr`/`IfLetStmt`
  limpos (o oracle reusa `IfLetExpr name=''`); `(a,)` 1-tupla decidir (erro); `guard let` liga em
  `expression` (não `_equality`); operador custom: parseia a **declaração**, não fia na gramática de
  expressão (débito preservado).

**Terminologia (P4):** o parser de expressões é uma **cascata de precedência** (uma função por nível — CI
cap 6, estilo jlox), **não** Pratt table-driven; `_isClosureStart` usa **scan-ahead** (não LL(k) fixo) —
implicação de compile-time a vigiar.

**Fatiamento recomendado p/ o `/speckit-plan`** (`compiler-craftsman`) — 4 fatias verticalmente testáveis
(cada uma com CAs + goldens `itac parse --dump`): **(0) Fundação** — ASDL + `ast.dart` + `itac parse
--dump` + infra de recuperação + **tipos/patterns** (folhas de dependência: `match` precisa de patterns,
params/closures precisam de tipos); **(1) Expressões** (maior risco: cascata de 13 níveis + cantos +
interpolação); **(2) Statements & controle de fluxo**; **(3) Declarações & reconciliação** (`grammar.ebnf`
§Syntactic + deltas tree-sitter + corpus completo).

## §1 Motivação e resumo

A Fase 1 entregou o **léxico** (`.tu` → tokens). A Fase 2 fecha o front-end sintático: transforma a
sequência de tokens na **AST** (árvore sintática abstrata) do Itá, cobrindo **toda** a gramática de
§2–§6 do `GRAMMAR.md` (declarações, statements, expressões com a escada Pratt de 13 níveis, tipos e
patterns), com **recuperação de erro N2** (nó→nó, sem cascata). É pré-requisito de todas as fases
seguintes (desugaring, binding, semântica, codegen), que consomem a AST.

**Antes → Depois** (exemplo mínimo):

```tu
// antes — a Fase 1 só produz tokens (itac tokenize):
fn add(a: Int, b: Int) -> Int => a + b * 2
// kwFn 'fn' @1:1 · identifier 'add' @1:4 · lparen '(' @1:7 · … (lista plana de tokens)
```

```tu
// depois — a Fase 2 produz a AST (itac parse --dump), com a precedência resolvida:
// (fn "add"
//   (params (param "a" (type "Int")) (param "b" (type "Int")))
//   (ret (type "Int"))
//   (=> (binary "+" (id "a") (binary "*" (id "b") (int 2)))))   ; * liga mais forte que +
```

**Não-objetivos:** (1) **não** faz binding/resolução de nomes (declarar-antes-de-usar, escopo → Fase 4);
(2) **não** faz checagem de tipos nem inferência (→ Fase 5); (3) **não** faz desugaring (`?`/`|>`/`>>`/
where/copy-with/currying → Fase 3 — a AST guarda essas formas **como escritas**); (4) **não** emite
Kernel (→ Fase 7). A validação da aridade, exaustividade de `match`, e `break/continue`-em-loop é
declarada aqui como "o que sobra para a semântica" (§3.6), **não** implementada.

---

## §3 Sintaxe — `[cap 4.2–4.4, 5.3]`

A gramática normativa é o **`GRAMMAR.md` §2–§6** do `ita/` — esta spec **não a recopia**; declara a
disciplina, os cantos e o que é observável. O parser do `ita/` (`ast.dart`/`parser.dart`, 3.649 linhas)
é o **oracle** de comportamento.

### 3.1 Produções cobertas (todas — abordagem horizontal)

- **Declarações (§2):** `fn` (+ `async fn`/`stream fn`), `genericParams` com bounds (`T: A + B`),
  `paramList` com labels+nomes+defaults e grupo nomeado (`;`); `struct`/`class`/`enum`(ADT)/`trait`/
  `impl`/`extension`/`actor`/`operator`; campos e métodos intercaláveis; `import` ES6 (3 formas). `pub`
  repassado a `fn/struct/class/enum/trait`; consumido-e-ignorado em `impl/extension/import/operator`
  (débito conhecido, preservado).
- **Statements (§3):** `let`/`var` (com `destructure` `{}`/`[]` e `..rest`), `return` (vazio se o próximo
  for `}`/EOF), `if`/`guard`/`while`/`for` (`for await`), `break`/`continue`, `emit`, `block`
  (`;` = separadores **opcionais**), `exprStmt`.
- **Expressões (§4):** a **escada Pratt de 13 níveis** do §4.2, do mais frouxo ao mais forte —
  `where`; assignment (**dir.**); `|>`/`>>` compose; `??`; `||`; `&&`; `==`/`!=`; comparação; range
  `..`/`..=` (**não-assoc**); `+`/`-`; `*`/`/`/`%`; `**` (**dir.**); unário prefixo `! - ~`; pós-fixos.
  `primary`: async closure, `panic(…)`, `await race/all(…)`, `await e`, `spawn e`, literais, `self`,
  paren/closure/tupla, list/map literal, `match`, if-expr, enum shorthand `.Ident`. Pós-fixos: call +
  trailing-closure (mesma linha), copy-with `.{…}`, tuple-index `.N`, member `.`, `?.`, index `[]`,
  force-unwrap `!`, try `?`.
- **Tipos e patterns (§5):** `type` (`mut`, `async`, função/tupla/grupo, generics, optional `?`);
  `pattern` (`_`, enum-variant, list, struct-pattern com lookahead `IDENT "{"`, range/literal, binding).

### 3.2 Precedência e associatividade

Dada pela **profundidade da escada de funções** (não por números — §4.2 do `GRAMMAR.md`). Regras não
óbvias que a AST deve refletir: `**` e assignment associam à **direita**; range é **não-associativo**
(`a..b..c` é erro de parse); `>>` é **composição de funções**, nunca shift; não há `+` unário nem `<<`
em expressão. `a + b * c` ⇒ `(+ a (* b c))`; `a ** b ** c` ⇒ `(** a (** b c))`.

### 3.3 Ambiguidade e cantos de desambiguação (§6)

Cada canto tem uma regra determinística e vira CA:
- **Dangling-else:** `else` liga ao `if` **mais próximo** `[cap 4.3.2]`.
- **`<` genérico vs. comparação:** generics só em **contexto de tipo/declaração**; em expressão, `<` é
  sempre comparação (**sem turbofish** — `Foo<Int>()` numa expressão vira `((Foo<Int)>())`; débito).
- **`{` = map vs. block:** em posição de statement, `{` é bloco; em expressão, é map literal; `{}` vazio
  decide por posição.
- **`if`/`match` expressão vs. statement:** `if` em statement é `ifStmt`; em expressão é `ifExpr`;
  `match` só existe como expressão.
- **Struct pattern precisa de 2 tokens:** `IDENT "{"` = struct-pattern; `IDENT` isolado = binding.
- **`await race/all(…)`:** `race`/`all` são IDENT contextuais → `AwaitRaceExpr`/`AwaitAllExpr`.
- **Trailing closure exige mesma linha:** `f(x) { … }` só é call-com-closure se `(`/`.` estão na linha
  do operando; senão a quebra de linha encerra o statement (reusa `Token.line` da Fase 1).
- **Token-splitting em posição de tipo:** `>>`→`>`+`>` e `>=`→`>`+`=` para fechar generics aninhados
  (`List<List<T>>`); em expressão, `>>` continua compose. `[cap 4.4]`

### 3.4 Adequação ao parser descendente `[cap 4.3.3–4.4]`

- **Recursão à esquerda:** as expressões binárias são left-recursive na gramática; a implementação usa
  **Pratt/precedence-climbing** (Crafting Interpreters cap 6), que resolve associatividade sem a
  transformação `A→Aα|β ⇒ A→βA'`. Declarações/statements são **descendente recursivo** direto.
- **Fatoração à esquerda / lookahead:** cantos que exigem lookahead > 1 (`let`-destructure vs. `let x`;
  struct-pattern `IDENT "{"`; closure `( params ) =>` vs. grupo `( expr )`) são resolvidos por
  lookahead limitado, documentado por CA.

### 3.5 Reconciliação

- **`grammar.ebnf`** ganha a seção **"Syntactic grammar"** (W3C EBNF), reconciliada com `GRAMMAR.md`
  §2–§6, abaixo da seção "Lexical grammar" da Fase 1.
- **`tree-sitter-ita`** (Apêndice A do `GRAMMAR.md`): a gramática tree-sitter é **derivada** e o parser
  é **normativo**. Esta fase registra (não necessariamente corrige no repo tree-sitter) os deltas:
  precedência em escada, map/tupla/async-closure/`static fn`/`?.`/`await race`/force-unwrap, `break`/
  `continue`, `>>` compose.

### 3.6 O que sobra para a semântica `[cap 4.3.5]`

Restrições **não expressáveis por CFG**, apenas **declaradas** aqui (implementadas nas Fases 4–6):
declarar-antes-de-usar e escopo (Fase 4); aridade de chamada e de enum-variant, tipos e inferência
(Fase 5); `break`/`continue` só dentro de loop, exaustividade de `match`, definite-return (Fase 6). A
AST as **representa**, sem validá-las.

> *(Re-roteamento de 2026-07-16 — spec 014 §8: `break`/`continue` só-em-loop foi implementado na
> **Fase 4** (`resolver.dart:368-371`, context-flags com reset na fronteira de fn — CI 11.5.1), não
> na F6 como esta linha previa: a legalidade cruza fronteira de FUNÇÃO, que é contexto de binding.
> Exaustividade e definite-return seguem na F6 — spec 014.)*

---

## §A Artefatos formais (ADR-0010)

- **A.1 `compiler/docs/spec/ast.asdl`** — a **definição canônica da AST** em **Zephyr ASDL**: os `sum`/
  `product` types dos nós (decl, stmt, expr, type, pattern), com seus campos. É a fonte-da-verdade dos
  nós; o `compiler/lib/frontend/parser/ast.dart` a implementa (à mão ou via script Dart do dev, saída
  commitada — **P11**: nunca build-time). Cada nó carrega `span` (offset+length, reusando o `Token` da
  Fase 1 — D2).
- **A.2 `compiler/docs/spec/grammar.ebnf` (seção Syntactic)** — as produções em **W3C EBNF**,
  reconciliadas com `GRAMMAR.md` §2–§6.
- **A.3 Dump determinístico** — `itac parse <file.tu> --dump` imprime a AST como **S-expression
  determinística** (nó = `(tag campos…)`, spans elididos por padrão, `--spans` para incluí-los),
  conferível byte-a-byte com os goldens `.ast`. O formato exato fecha no `/speckit-plan`.

---

## §9 Checklist de completude (Apêndice A)

- [ ] `parser` — recursão à esquerda tratada (Pratt), lookahead documentado nos cantos `[A.8]`
- [ ] `ast` — cada construção de §2–§6 tem um nó em `ast.asdl` (+ `ast.dart`)
- [ ] `parser` — `match`/precedência da escada §4.2 fiel (assoc. de `**`/assignment/range)
- [ ] recuperação de erro **N2** (nó de erro + resync no boundary, sem cascata)
- [ ] `tree-sitter` — deltas do Apêndice A **registrados**; `GRAMMAR.md` §2–§6 reconciliado com o `grammar.ebnf`
- [ ] **corpus de conformância** de parsing (`.tu` → `.ast`) cobre os CAs; erros de parse com span
- [ ] **benchmark de compile-time** (`itac` AOT) sem regressão

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** Não — `ita-next` é reescrita nova; nada externo depende ainda.
- **Oracle:** o parser do `ita/` (`ast.dart`/`parser.dart`) + `GRAMMAR.md` §2–§6. Onde o `ita/` tiver
  bug/dead-code (como no léxico), o `ita-next` **conserta** e marca a divergência no golden.
- **Divergências deliberadas vs oracle (validação §0.6):** (1) `await`/`spawn` ligam **forte** (oracle é
  guloso); (2) trailing-closure exige mesma-linha também em `f(args){}` (**bug** do oracle); (3) `a..b..c`
  → `range-non-associative` (oracle não emite); (4) `pub` no-op → **erro** (oracle consome mudo); (5)
  bloco-nu **não** é expressão (`BlockExpr` do oracle removido); (6) **interpolação** parseada em
  parse-time (oracle difere ao codegen). Em todas, o golden = comportamento **correto**, marcado.
- **Validação:** o MCP `ita` **não dumpa AST** (executa programas) → os goldens de `.ast` são conferidos
  por `itac parse --dump` tendo o parser do `ita/` como **referência de comportamento**, mesmo esquema da
  Fase 1 (léxico).
- **Alternativas descartadas:** parser gerado (yacc/ANTLR/PEG) — **veta P11**; combinator library — abstração
  desnecessária, esconde a escada de precedência (contra P4).

## §11 Critérios de aceite (viram casos no corpus `conformance/` → `.ast`)

Cada CA é um `.tu` → AST esperada (`.ast` golden) ou um erro de parse (EN kebab-case + span). Validação:
`itac parse --dump` vs golden, com o parser do `ita/` como referência.

**Declarações**
- **CA1** — `fn add<T: Ord>(a: T, b: T = zero) -> T => a` ⟶ AST com `fn` + generic-bound + param-default.
- **CA2** — `struct P { x: Int, fn mag() -> Int => x }` ⟶ `struct` com campo **e** método intercalados.
- **CA3** — `enum Opt<T> { Some(v: T), None }` ⟶ `enum` ADT com variantes (uma com payload).
- **CA4** — `import { a as b } from "m"` ⟶ `import` com alias; e `import * as m from "m"`.

**Statements**
- **CA5** — `let { x, y } = p` ⟶ `let` com **destructure** de registro; `let [h, ..t] = xs` com rest.
- **CA6** — `if a { x } else if b { y } else { z }` ⟶ **dangling-else** ligado ao `if` mais próximo.
- **CA7** — `for await x in xs { }` e `guard let v = o else { return }` ⟶ nós corretos.

**Expressões (precedência Pratt)**
- **CA8** — `a + b * c` ⟶ `(+ a (* b c))`; `a ** b ** c` ⟶ `(** a (** b c))` (**dir.**).
- **CA9** — `x |> f >> g` ⟶ pipe/compose corretos (`(>> (|> x f) g)`, ambos nível 2, esquerda);
  `a ?? b || c` ⟶ `(?? a (|| b c))` — `||` (nível 4) liga **mais forte** que `??` (nível 3) por
  `GRAMMAR.md` §4.2. *(Correção 2026-07-10 via `/speckit-plan`: o golden anterior `(|| (?? a b) c)` estava
  invertido — contradizia a §4.2 normativa e o `_nilCoalesce`→`_or` do oracle. Ver `conformance-cases.md`.)*
- **CA10** — `a..b..c` ⟶ **`parse-error: range-non-associative`** com span (range não-assoc). **Checagem NOVA** além do oracle (que não emite este erro — §0.6/§10).
- **CA11** — `obj.field?.m()!.x` ⟶ cadeia pós-fixa (member, `?.`, call, force-unwrap, member).
- **CA12** — `p.{ x: 1 }` (copy-with) e `t.0` (tuple-index) e `xs[i]` (index) ⟶ nós pós-fixos distintos.
- **CA13** — `f(x) { $0 + 1 }` ⟶ call com **trailing closure** (mesma linha); `f(x)`⏎`{…}` ⟶ **call sem** closure + block separado. **Conserta bug do oracle** (que não checa linha em `f(args){}` — §10).
- **CA14** — `match o { .Some(v) => v, .None => 0 }` ⟶ `match` com arms de enum-variant.

**Tipos e patterns**
- **CA15** — `let m: Map<String, List<Int>> = …` ⟶ generics aninhados via **token-splitting** de `>>`.
- **CA16** — `match p { P { x, .. } => x, _ => 0 }` ⟶ **struct-pattern** (lookahead `IDENT "{"`) + wildcard.
- **CA17** — `let f: (Int, Int) -> Int = …` e `let x: mut Foo? = …` ⟶ tipo função e `mut`/optional.

**Erros de parse (recuperação N2)**
- **CA18** — `fn f( { }` (parêntese não fechado) ⟶ `parse-error: expected-token` com span; e o **próximo**
  top-level decl ainda parseia (resync no boundary, **sem cascata**), via `ErrorNode`.

**Decisões da validação (§0.6)**
- **CA19** — `await a + b` ⟶ `(+ (await a) b)` (`await` liga **forte**, nível unário — Q4); `spawn f() + 1` ⟶ `(+ (spawn (call f)) 1)`.
- **CA20** — `"x=${a + 1}!"` ⟶ `stringLiteral` com **partes ordenadas** `['x=', (+ (id a) 1), '!']`, parseadas em **parse-time** (interpolação).
- **CA21** — `if f(x) { a } else { b }` ⟶ `{` é **bloco** (trailing-closure suprimida na condição); `guard f(x) { } else { r }` ⟶ `guard` **não** suprime (assimetria).
- **CA22** — `pub impl T for U { }` ⟶ **`parse-error: meaningless-pub`** com span (Q3); `pub fn f()` ⟶ OK.
- **CA23** — `let x = { let a = 1; a }` ⟶ **erro de parse** (bloco-nu **não** é expressão — Q1/Swift 6.3).

## Definition of Done

- [ ] CAs cobertos por casos no corpus `conformance/` (`.tu` → `.ast`) e verdes; erros de parse com span.
- [ ] `ast.asdl` + `grammar.ebnf` §Syntactic versionados e reconciliados com `GRAMMAR.md` §2–§6.
- [ ] Constitution check sem conflito (§0.5) — P4/P6/P11/P3.
- [ ] CI verde (conformance de parsing + unit + benchmark de compile-time do `itac` AOT).
