# Design notes — Fase 2 (Sintaxe → AST) · spec 004

> **Phase 0 do `/speckit-plan`.** Resolve as decisões de modelagem e **materializa as 4 decisões do
> dono** (§0.6 da spec). Cada decisão traz `Decisão / Racional / Alternativas`. Fundamentado no W1 pelos
> especialistas: **`compiler-craftsman`** (técnica + capítulo) e **`dart-vm-expert`** (forward-compat do
> Kernel). **Oracle** = `ita/compiler/lib/parser/{parser.dart,ast.dart}` + `GRAMMAR.md` §2–§6, confrontado
> no código real.
>
> **Convenção de citação:** **CI** = *Crafting Interpreters* (Nystrom); **DB** = *Dragon Book* cap 4
> (`references/livro-compiladores/04-analise-sintatica/`). Toda afirmação forte tem capítulo **e** linha do
> oracle verificada.
>
> **Nota de sessão:** o W1 rodou com os 3 especialistas **encarnados** via `general-purpose` (os agentes
> custom em `ita-next/.claude/agents/` não entram no registro de `subagent_type` quando o cwd é `ita-lang/`,
> só sob `ita-next/` — ver [[ita-rewrite-ita-next-dragon-book]]). Fundamentação idêntica; só o disparo muda.

---

## D0 — Terminologia: **cascata de precedência**, não *Pratt table-driven* `[P4]`

- **Decisão:** o parser de expressões é uma **cascata de precedência recursivo-descendente estilo jlox**
  (**CI cap 6.2** — gramática estratificada, *uma função por nível* de §4.2), **não** um Pratt
  table-driven (tabela `ParseRule[]` + `parsePrecedence(minPrec)`, que só aparece no clox, **CI 17.5–17.6**).
- **Racional:** **P4 (sem mágica).** O nome de cada função **é** o nível de precedência do `GRAMMAR.md`
  §4.2 — verificável 1:1. A tabela numérica do Pratt esconde a precedência (a "torre ilegível" que o
  próprio `GRAMMAR.md` §4 recusa). A spec §0.6 já fixou essa terminologia; aqui ela vira lei do plano.
- **Alternativas:** Pratt table-driven — **rejeitado** (viola P4: precedência vira dado opaco).
  Trade-off aceito: ~13 frames de pilha por folha de expressão (recursão mais funda) → é o item de
  compile-time vigiado pelo benchmark-guard do CI (§9), **não** motivo para trocar de técnica.

---

## Materialização das 4 decisões do dono (§0.6)

### D1 (Q1) — Bloco-nu `{…}` **não** é expressão (statements-only, modelo Swift 6.3) `[P3, P4]`

- **Decisão:** `{…}` **nunca** é valor. O poder expressivo vem de `if`/`match`(/`do`)-expressions com valor
  **explícito**, jamais última-expressão-implícita à la Rust. O nó `BlockExpr` do oracle é **removido**.
- **Racional:** **CI cap 8.2.1** — "there are two levels of precedence for statements": posições que
  aceitam statements vs. posições que só aceitam expressões. Como bloco-nu **não** é expressão, a
  **posição-de-expressão nunca considera "bloco" como leitura de `{`** — restam exatamente **duas** (map
  literal ou trailing-closure), ambas dirigidas por estado de parser, **sem terceira opção e sem
  backtrack**. É isso que colapsa a ambiguidade histórica do `{`. Casa com **P3** (tudo é expressão *quando
  possível* — via `if`/`match`, não via bloco mágico) e **P4** (valor sempre explícito).
  - **CA23** (`let x = { let a = 1; a }`): o RHS de `=` é posição-de-expressão → `{` inicia **map** →
    `let a = 1` não casa `expr : expr` → **`parse-error`**. Correto e determinístico.
- **Alternativas:** bloco-como-expressão à la Rust (última-expr implícita) — **rejeitado** pelo dono
  (mágica de valor implícito, contra P4; e reabriria a 3ª leitura de `{`, forçando backtrack).

### D2 (Q2) — Type-args no call-site: **inference-only permanente** (sem turbofish) `[P4]`

- **Decisão:** colchetes angulares = generics **apenas onde um `type` é esperado** (em `NamedType` e em
  headers de declaração `genericParams`). Em **expressão**, `<` é **sempre** comparação (nível 7). Logo
  `Foo<Int>()` numa expressão parseia como `((Foo < Int) > ())`. Instanciação fica com a inferência (Fase 5).
- **Racional:** o `<` é **um token**; o papel é decidido por **posição** (DB 4.3.1). Manter **uma** regra
  uniforme (sem um 3º modo `::<>` que injete contexto-de-tipo em contexto-de-expressão) elimina a
  necessidade de **lookahead ilimitado** para distinguir `a < b > (c)` (call-com-type-args vs. cadeia de
  comparações) — a ambiguidade clássica de C++ que custa aos parsers reais um hack de lexer ou fallback
  GLR. Desambiguação O(1), P4-limpo.
- **Alternativas:** turbofish `Foo::<Int>()` (Rust) — **rejeitado** (dono): novo sigilo + reintroduz o
  scan-ahead de `<`. Trade-off aceito: perde-se type-arg explícito no call-site (débito preservado, agora
  decisão consciente).

### D3 (Q3) — `pub` sem sentido → **`parse-error: meaningless-pub`** `[P4]`

- **Decisão:** rejeitar `pub` onde é no-op (`impl` / `extension` / `import` / `operator`) com
  `parse-error: meaningless-pub` + **span do token `pub`**. `pub` continua válido em
  `fn`/`struct`/`class`/`enum`/`trait` (e membros).
- **Racional:** **oracle confirmado** — `parser.dart:343` faz `isPublic = _match(kwPub)` e, para
  `impl`/`extension`/`import`/`operator` (l.353–356), despacha **sem** repassar a flag → é **descartada
  silenciosamente**. Consumir mudo um token sem efeito é a mágica escondida que **P4** proíbe. É uma
  **error production** (**DB 4.1.4** / **CI 6.3**): a gramática reconhece a forma errônea de propósito, para
  dar diagnóstico dirigido em vez de um genérico "expected declaration".
- **Alternativas:** manter o consumo mudo (oracle) — **rejeitado** (P4); warning em vez de erro —
  **rejeitado** (a Fase 2 não tem canal de warning; e a spec pede erro).

### D4 (Q4) — `await`/`spawn` ligam no nível **unário** (`await a + b` = `(await a) + b`) `[P4]`

- **Decisão:** mover `await`/`spawn`/`panic`/`await race·all`/async-closure **para fora** do `primary` e
  **para o nível 12 (unário)**, mesma tier de `! - ~`. `await a + b` ⟹ `(+ (await a) b)`;
  `spawn f() + 1` ⟹ `(+ (spawn (call f)) 1)`.
- **Racional:** **oracle confirmado** — `await` chamava `_expression()` (`parser.dart:1650`) → **guloso**,
  engolia `a + b` inteiro; `spawn` (l.1656) já usava `_postfix` (mais apertado) — **inconsistente**. O
  `GRAMMAR.md` §4.2 já dizia "prefixos ligam mais forte que binários" — a chamada `_expression()` violava a
  própria doc. Em `_unary`, ao ver `await`/`spawn`, consome e recursiona em **`_unary()`** (permite
  `await -x`, `await await f`); pós-fixo (nível 13) liga mais forte, então `await a.b()` = `await (a.b())`
  — o operador se aplica à cadeia pós-fixa inteira, que é o desejado.
- **Alternativas:** `await` guloso à direita (oracle) — **rejeitado** (surpreende em `await a + b`, contra
  P4 e contra §4.2).

---

## Modelagem da AST — `ast.asdl` (Zephyr ASDL) `[A.1]`

- **Decisão:** definição canônica em **Zephyr ASDL** (`sum` = união etiquetada; `product` = registro),
  gerada para `compiler/lib/frontend/parser/ast.dart` por **script Dart do dev** (saída commitada) **ou**
  escrita à mão — **nunca** build-time (**P11**; mesma tolerância do `tree-sitter generate`, ADR-0010).
- **Racional:** **CI 5.2.2 "Metaprogramming the Trees"** — o `GenerateAst` de Nystrom é um mini-ASDL; o
  `ast.asdl` é essa ideia formalizada (Wang et al. 1997, modelo do `Python.asdl`). Hierarquias `sealed`
  (sum) → **CI 5.2.1** + Visitor **CI 5.3.2**; em Dart, `sealed class` dá `switch` exaustivo de graça (a
  semântica e as análises herdam exaustividade).
- **Sum types principais:** `decl` · `stmt` · `expr` · `type` · `pattern`. Products: `param`,
  `genericParam`, `field`, `enumCase`, `matchArm`, `arg`, `importMember`, `fieldPattern`, e o crucial
  **`strPart = Lit(string value) | Interp(expr e)`**.

### M1 — `span` em **todo** nó, via `attributes (int offset, int length)`

- **Decisão:** cada sum carrega `attributes (int offset, int length)` — o span reusa o `Token` da Fase 1
  (**D2** do léxico): `offset = firstToken.offset`, `length = lastToken.end − firstToken.offset`.
- **Racional (forward-compat, `dart-vm-expert`):** todo `TreeNode` do Kernel tem `int fileOffset`
  (`pkg/kernel .../misc.dart:71`), fonte da posição no `.dill`. Em **AOT** os stack traces são **DWARF**,
  cujo line-number program deriva desses offsets (`runtime/docs/dwarf_stack_traces.md`); em JIT idem, e o
  `dart2js` usa os mesmos offsets para **source-maps**. **Só o parser enxerga o offset de byte** — se não
  gravar, não há como reconstruir. **Upgrade sobre o oracle**, que carrega `line, column` (`ast.dart:52`);
  a Fase 2 troca por offset+length byte-preciso (IDE-ready). A **Fase 3 herda o span** nos nós sintetizados
  (§0.6). Atenção especial aos nós que aparecem em stack trace/breakpoint: `Call`, `Member`, `Panic`,
  `Await`, entrada de `Fn`.

### M2 — Nós de erro `ErrorDecl`/`ErrorStmt`/`ErrorExpr` embutidos em cada sum

- **Decisão:** cada sum ganha uma variante de erro (`ErrorDecl` em `decl`, `ErrorStmt` em `stmt`,
  `ErrorExpr` em `expr`), carregando os tokens descartados. A recuperação **enxerta** um placeholder
  bem-tipado no lugar da produção falha — **não** retorna `null`.
- **Racional:** árvore **total** e bem-tipada > buraco `null` (§0.6): a semântica percorre os irmãos, o LSP
  dá completion parcial. **Divergência do oracle**, que **lança** `ParseError` e acumula numa lista,
  descartando a subárvore (`parser.dart` throw + `_synchronize` l.2302). Ver **Recuperação N2** abaixo.

### M3 — Interpolação de string parseada em **parse-time**: `Str(strPart* parts)`

- **Decisão:** o nó de string interpolada guarda **partes ordenadas** `Lit(value) | Interp(expr)`, com as
  literais **já com escapes decodificados**. Substitui `StringLiteral` + interpolação deferida.
- **Racional (forward-compat, `dart-vm-expert`):** o Kernel lowera `"x=${e}!"` para
  `StringConcatenation { List<Expression> expressions }` (`pkg/kernel .../expressions.dart:3385`), uma
  **lista ordenada** avaliada estritamente E→D. A ordem `literal → expr → literal` **só o parser
  testemunha** — depois que tokens viram AST a fronteira texto/código se perde. **Divergência do oracle**,
  que difere ao codegen (`ast.dart:524`: a expressão embutida fica como **string de source crua**,
  re-parseada depois — AST incompleta). CA20.

### M4 — Literal **inteiro vs. float** distinguível na AST

- **Decisão:** o nó de literal numérico **preserva a forma escrita** (inteiro vs. fracionário; idealmente
  radix/raw): `Int(...)` ≠ `Float(...)`.
- **Racional (forward-compat, `dart-vm-expert`):** o Kernel tem nós distintos `IntLiteral`
  (`expressions.dart:4174`) e `DoubleLiteral` (`4210`). Colapsar `1` e `1.0` recria o débito histórico
  **G4 (Float `.0`)**. É também o **único ponto de paridade VM×JS** que a *modelagem* precisa preservar
  (ADR-0005): em `dart2js` `int`/`double` são o mesmo `number`; a divergência se resolve no codegen, mas
  **começa a existir se a AST perder qual literal era `Int` e qual era `Float`**. A Fase 1 já tokeniza
  separado (`intLiteral`/`floatLiteral`) — a Fase 2 só preserva.

### M5 — Async-marker `Sync` / `Async` / `AsyncStar` (sem `SyncStar`)

- **Decisão:** o nó `Fn`/`Closure` carrega um marker `Sync | Async | AsyncStar` (`fn` / `async fn` /
  `stream fn`). `SyncStar` **fica de fora** hoje.
- **Racional (forward-compat, `dart-vm-expert`):** o Kernel tem
  `enum AsyncMarker { Sync, SyncStar, Async, AsyncStar }` (`pkg/kernel .../functions.dart:306`, com o
  comentário normativo "Do not change the order… frontends depend on it"). O mapeamento é direto. `SyncStar`
  (gerador síncrono `sync*` → `Iterable`) **existe no Kernel**, mas o Itá **não expõe sintaxe de gerador
  lazy** — não há como escrevê-lo. É escolha **forward-compatible** (o slot já existe no destino; se o Itá
  ganhar geradores, adiciona-se sem tocar no Kernel), não limitação. A distinção é **sintática** e governa
  o desugaring da Fase 3.

### M6 — `Call` preserva **ordem-fonte** dos argumentos; posicional/nomeado separados no consumo

- **Decisão:** o nó `Call` guarda os `arg*` **na ordem em que foram escritos**, com o label preso ao
  nomeado — sem reordenar.
- **Racional (forward-compat, `dart-vm-expert`):** o Kernel `Arguments` separa `positional` +
  `named` (`expressions.dart:1534`), mas o Dart avalia argumentos **na ordem-fonte**. Preservar a ordem na
  AST deixa o codegen montar `Arguments` com eval-order correta.

### M7 — `(a,)` 1-tupla → **`parse-error: single-element-tuple`**

- **Decisão:** rejeitar a 1-tupla `(a,)` (vírgula final com 1 elemento) com erro de parse. `(a)` já é
  agrupamento; `(a, b)` é 2-tupla.
- **Racional:** §0.6 sinalizou "`(a,)` decidir (erro)"; **oracle** tolera (`parser.dart:1760–1768` vira
  `TupleExpr([a])`). 1-tupla é degenerada e ambígua com agrupamento — reportar (P4). *Micro-decisão de
  modelagem; não é uma das 4 rulings principais — registrada aqui por completude. Reversível se o dono
  preferir tolerar.*
- **Alternativas:** tolerar como `TupleExpr([a])` (oracle) — rejeitado (degenerado). *(Não vira CA nesta
  fatia; documentada no golden se um caso a exercitar.)*

---

## Dump S-expression determinístico — `itac parse --dump` `[A.3]`

- **Decisão:** nó = `(tag campos…)`, modelo direto do `parenthesize()` (**CI 5.4**). **Spans elididos por
  padrão**; `--spans` anexa `@offset+len` por nó. Conferível byte-a-byte com goldens `.ast`.
- **Convenções:**
  - **Binários usam o operador como tag:** `(+ a (* b c))`, `(** a (** b c))`.
  - **Literais:** `(int 2)`, `(float 1.0)` (float normalizado com `.0` — M4), `(str "x")`, `(bool true)`,
    `nil`, `(id a)`.
  - **Interpolação:** `(str "x=" (+ (id a) (int 1)) "!")` (partes ordenadas — M3).
  - **Prefixos:** `(await a)`, `(spawn (call f))`, `(! x)`, `(neg x)`.
  - **Pós-fixos:** `(member obj field)`, `(opt-chain e m)`, `(call f a b)`, `(force-unwrap e)`,
    `(try e)`, `(index xs i)`, `(tuple-index t 0)`, `(copy-with p (field x (int 1)))`.
  - **Estruturais:** `(fn "add" (params (param "a" (type Int)) (param "b" (type Int))) (ret (type Int))
    (=> …))` — coerente com o exemplo §1 da spec.
  - **Erro:** `(error-decl …)` / `(error-stmt …)` / `(error-expr …)`.
- **Determinismo:** ordem de filhos = ordem gramatical/fonte; **zero** iteração de hash-map; floats e
  strings com escaping canônico.
- **Racional de validação:** o **MCP `ita` não dumpa AST** (executa programas) → o golden `.ast` é o output
  de `itac parse --dump` do `ita-next`, tendo o **parser do `ita/` como referência de comportamento** (mesmo
  esquema da Fase 1 léxico). Onde o `ita/` tem bug/dead-code, o golden = comportamento **correto**, marcado.

---

## Os 8 cantos de desambiguação (§3.3) — técnica + lookahead

| # | Canto | Técnica | Lookahead |
| :-- | :-- | :-- | :-- |
| 1 | **dangling-else** | binding guloso: após o then-block, `if (_match(else))` antes de retornar → `else` liga ao `if` mais interno. **CI 9.2** / **DB 4.3.2**. | **k=1** (token `else`) |
| 2 | **`<` genérico vs comparação** | por posição (D2): expr-pos → `<` comparação; generics só em `type`/header. | **k=1** (papel fixado pela posição) |
| 3 | **`{` map vs block** | por posição (D1): stmt-pos → block; expr-pos → map; pós-fixo-mesma-linha → closure. **CI 8.2.1**. | **estado de parser** (k=0/1) |
| 4 | **`if`/`match` expr vs stmt** | dispatch por posição: `_statement()` vê `if` → `IfStmt`; `_primary()` vê `if` → `IfExpr`; `match` só em expr-pos. Nós limpos (§0.6). | **k=1** (keyword líder) |
| 5 | **struct-pattern `IDENT "{"`** | em `_pattern`, `IDENT` + `{` → `StructPattern`; `IDENT` só → binding. | **k=2 fixo** (`_checkAt(1, lbrace)`) |
| 6 | **`await race/all`** | ident contextual: `await` + lexeme `race`/`all` + `(` → `AwaitRace`/`AwaitAll`; senão `await expr`. (oracle l.1620/1634). | **k=2 fixo** (peek lexeme) |
| 7 | **trailing-closure mesma-linha (+ supressão; `guard` não suprime)** | (a) `{` abre closure só se `_peek().line == operando.line` — **e também no `_finishCall`** (o oracle l.1578 **não** checa → bug CA13). (b) supressão: flag `_noTrailingClosure` na condição de `if`/`while`/`for`/`match`; **`guard` não seta** (assimetria CA21 — guard só tem `else {}`, o `{` da condição *é* closure legítimo). | supressão = **O(1) estado**; mesma-linha = **k=1 + `Token.line`** |
| 8 | **token-splitting `>>`→`>`+`>`** | `_consumeTypeGt`: em `gtGt`, consome um `>` e **reescreve o token in-place** para `>` (col+1); `>=`→`=`. **Local a tipos**; em expressão `>>` continua compose. **DB 4.4** (maximal-munch do lexer vs. fecha-template). | **k=1 + rewrite de 1 token** (sem re-lex, sem backtrack) |

- **Nenhum dos 8 exige scan-ahead** — todos são k≤2 fixos ou estado de parser. O **único** scan-ahead
  ilimitado do parser é **`_isClosureStart`** (`( params ) =>` vs `( expr )`, `parser.dart:1773`:
  salva/restaura `_current` com contador de parênteses) — pertence a **§3.4**, não aos 8 cantos. É *o* item
  de compile-time a vigiar (§0.6): **mantido** (é correto e necessário), com o **benchmark-guard** de olho.

---

## Recuperação de erro N2 (nó→nó, sem cascata) `[§3.6, A.2]`

- **Decisão:** **panic-mode com sync-sets**. Ao detectar erro: reportar **um** diagnóstico (EN kebab-case +
  span), descartar tokens até um do **sync-set ativo** (boundary de statement/decl), e **enxertar** um nó
  `Error*` (M2) no lugar da produção falha, retomando.
- **Racional:** **DB 4.1.3** (tratamento de erro) + **DB 4.1.4** (modo pânico / nível de frase / error
  productions) + **DB 4.4.5** (sync-sets derivados de FOLLOW; a heurística *hierárquica* — juntar ao
  sync-set de nível inferior as keywords que iniciam construções de nível superior). Espelho em **CI 6.3.1**
  (panic mode) + **CI 6.3.3** (`synchronize`) + **CI 8.2.2** ("declaration() is where we synchronize").
  O `_synchronize` do oracle (l.2302) já faz o sync-set contextual e **para** em `}`/`)`/`]` que um contexto
  ativo espera, sem atravessá-los — reusar esse modelo, trocando o `throw`+lista por **enxerto de `Error*`**.
- **Boundaries de resync:** statement (próximo FIRST-de-statement ou o `}` do bloco) · declaração (próxima
  keyword FIRST-de-declaração ou EOF). **CA18** (`fn f( {`): `ErrorDecl` para o `fn` quebrado, e o
  **próximo** top-level parseia — resync no decl-boundary, **sem cascata**.

---

## Ordem das fatias e dependências `[fatiamento §0.6]`

O eixo é **bottom-up sobre o grafo de chamadas** (**DB 4.4.1**): num descendente recursivo, callees
(folhas) antes de callers (nós internos), para cada fatia ser testável isolada contra goldens.

| Fatia | Conteúdo | Depende de | Por quê |
| :-- | :-- | :-- | :-- |
| **0 — Fundação** | ASDL + `ast.dart` + `itac parse --dump` + infra de recuperação + **`type` e `pattern`** (folhas) | — | Folhas do grafo (DB 4.4.2): `matchArm` precisa de `pattern`; `param`/`closure`/`let x: T`/`field` precisam de `type`. Quase não dependem da cascata (só literais em default/`LiteralPattern` tocam `primary` — stub resolve). |
| **1 — Expressões** | cascata de 13 níveis (D0) + 8 cantos + interpolação (M3) | 0 | Maior risco. Closures têm `type`; `LiteralPattern` compartilha `primary`. |
| **2 — Statements** | `let`/`var`/`return`/`if`/`guard`/`while`/`for`/`break`/`continue`/`emit`/`block`/`exprStmt` | 1 | Statements consomem expressões (condição, RHS); condições ativam a supressão de trailing-closure (estado que só existe com a Fatia 1). |
| **3 — Declarações + reconciliação** | `fn`/`struct`/`class`/`enum`/`trait`/`impl`/`extension`/`actor`/`operator`/`import` + `grammar.ebnf` §Syntactic + deltas tree-sitter + corpus | 0,1,2 | Topo do grafo: corpos de `fn` são block/expr; campos têm `type`; params têm type/default. `_declaration()` é o boundary de sincronização. |

---

## O que **NÃO** portar do oracle (confirmado no código real)

| # | No oracle | Decisão `ita-next` |
| :-- | :-- | :-- |
| 1 | `BlockExpr` (`ast.dart:718`) — órfão; comentário "Transforma em BlockExpr" (l.1941) é mentiroso (retorna `IfLetExpr`) | **Remover** (D1 — bloco-nu não é expr) |
| 2 | `PartialAppExpr` (`ast.dart:740`), `StringInterpolationExpr` (`747`), `EnumAccessExpr.enumName` (`732`, sempre `null`) — AST órfã/campo morto | Não portar `PartialAppExpr`; trocar por `Str(strPart*)` (M3); dropar `enumName` |
| 3 | `IfLetExpr name: ''` (`parser.dart:1942`) — if-expr modelado como if-let de nome vazio | Separar `IfExpr` limpo e `IfLetStmt` (§0.6) |
| 4 | Consumo mudo de `pub` (`343`+`353–356`) | **`meaningless-pub`** (D3) |
| 5 | `await` guloso (`1650` `_expression()`); `spawn` usa `_postfix` (`1656`) — inconsistente | Unificar ambos no **unário** (D4) |
| 6 | `_finishCall` sem checar linha (`1578`) — bug CA13 | Portar **com** a guarda de mesma-linha (que o pós-fixo l.1466/1495 já tem) |
| 7 | `_range` com `if` (`1403`) — parseia `a..b` e retorna, deixa `..c` solto; não emite erro | **`range-non-associative`** (CA10 — checagem nova) |
| 8 | Interpolação deferida (`ast.dart:524` — expr embutida como string crua re-parseada) | Partes ordenadas parse-time (M3) |
| 9 | `guard let` usa `_equality()` p/ o valor (`1192`) | Valor liga em `expression`; `&&`/`else` delimitam (§0.6) |
| 10 | `_isClosureStart` scan-ahead ilimitado (`1773`) | **Manter** (correto/necessário) — sinalizado como o único lookahead ilimitado, com benchmark-guard |
| 11 | Operador custom fiado na gramática de expressão | Parsear só a **declaração** (`OperatorDecl`); não fiar na cascata (débito preservado, §0.6) |

**Lacunas declaradas (fora da Fase 2 — a AST *representa*, não valida, §3.6):** exaustividade de `match`,
aridade de chamada/enum-variant, `break`/`continue`-em-loop, definite-return, use-before-def → **Fases 4–6**.
Aridade **não** é parse-error (**CI 10.1.1** — limites reportados sem pânico). Terminais mortos do lexer
(`const unsafe effect signal state`, `@ # & | ^ <<`, etc.) são **Fase 1** — fora de escopo.

---

## §8 (runtime) desta fase — sem dependência da Dart VM

Confirmado (`dart-vm-expert`): a **Fase 2 é análise sintática pura** — nenhum interop `dart:`, nenhuma
emissão de `.dill`, nenhuma execução na VM. O único artefato observável é o **dump S-expr** de
`itac parse --dump`. O papel do backend aqui é só **forward-looking** (M1–M6 acima). Nenhum risco de
paridade VM×JS material nesta fase — a **única** coisa que a modelagem preserva por paridade é a distinção
`Int`/`Float` do literal (M4).
