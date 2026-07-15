# Plan 004: Sintaxe completa → AST (Fase 2) — plano de execução

> **Spec:** [`spec.md`](./spec.md) · **Status:** `ready` · **Épico-pai:** `002` (ADR-0011) · **Escopo:** `ita-next/`
> **Design:** [`design-notes.md`](./design-notes.md) · [`conformance-cases.md`](./conformance-cases.md) · [`grammar-delta.md`](./grammar-delta.md)

## 1. Resumo técnico

A Fase 2 transforma a sequência de tokens da Fase 1 na **AST** do Itá, cobrindo **toda** a gramática de
§2–§6 do `GRAMMAR.md` (declarações, statements, a escada de precedência de 13 níveis, tipos e patterns),
com **recuperação de erro N2** (nó→nó, sem cascata). Técnica: **descendente recursivo** (decl/stmt) +
**cascata de precedência estilo jlox** (expr — uma função por nível, **não** Pratt table-driven; CI cap 6),
com `ast.asdl` (Zephyr ASDL) como definição canônica → `ast.dart` **à mão ou por script do dev** (P11). O
observável é o **dump S-expression** de `itac parse --dump`, conferido byte-a-byte contra goldens `.ast`
tendo o parser do `ita/` como **referência**. A fase **conserta 6 débitos** do oracle (§0.6/§10) e **não
emite Kernel** (codegen é a Fase 7) — a AST guarda as formas "como escritas", carregando só o que o codegen
futuro exigirá (spans, ordem de interpolação, async-marker, Int≠Float).

## 2. Fases do compilador tocadas (ancoradas na spec §0)

Só a fase **Sintaxe** (§3) + os **artefatos formais** (§A). Léxico é reusado; tipos/semântica/fluxo/codegen
são fases seguintes. Arquivos em `ita-next/compiler/`:

| Área | Arquivo(s) | Mudança | Ref. |
| :-- | :-- | :-- | :-- |
| **AST (canônica)** | `compiler/docs/spec/ast.asdl` | **novo** — Zephyr ASDL: sums `decl`/`stmt`/`expr`/`type`/`pattern` + products; variantes `Error*`; `attributes (offset,length)` | §A.1, M1–M2 |
| **AST (impl)** | `compiler/lib/frontend/parser/ast.dart` | **novo** — nós `sealed` (Visitor), gerados do ASDL por script do dev **ou** à mão (saída commitada, P11) | §A.1 |
| **Parser** | `compiler/lib/frontend/parser/parser.dart` | **novo** — descendente recursivo (decl/stmt) + cascata de 13 níveis (expr) + 8 cantos + recuperação N2 | §3 |
| **Driver** | `compiler/lib/driver/driver.dart`, `compiler/bin/itac.dart` | comando **`itac parse <f.tu> --dump [--spans]`** (S-expr determinística) — estende o `tokenize` da Fase 1 | §A.3 |
| **Gramática formal** | `compiler/docs/spec/grammar.ebnf` | **+ seção "Syntactic grammar"** (W3C EBNF) reconciliada com `GRAMMAR.md` §2–§6 | §A.2, grammar-delta |
| **Testes** | `compiler/test/parser_test.dart` | **novo** — unit com asserts sobre a AST | §9 |
| **Corpus** | `conformance/valid/*.tu`+`.ast`, `conformance/invalid/*.tu` | **novo** — os 23 CAs (goldens/erros) | §11 |
| **CI** | `.github/workflows/ci.yml` | + step de conformance de parsing; benchmark AOT sem regressão | §9, Art. IV |
| **tree-sitter** | (registro em `grammar-delta.md`) | deltas **registrados**, correção no repo `tree-sitter-ita` é fora de escopo | §3.5 |

## 3. Estratégia por alvo (codegen) — **não se aplica nesta fase**

A Fase 2 **não toca codegen** — nenhuma emissão de `.dill`, nenhum interop `dart:`, nenhuma execução na VM
(confirmado pelo `dart-vm-expert`, §8 do `design-notes.md`). Não há comportamento VM/AOT/JS a declarar aqui.
O único compromisso com o backend é **forward-looking** — a modelagem da AST já carrega o que o codegen→Kernel
(Fase 7) exigirá, para não empacar depois:

- **`span` (offset+length) em todo nó** → `fileOffset` do Kernel (stack traces DWARF em AOT; source-maps em JS).
- **Interpolação com partes ordenadas** `str|expr` → `StringConcatenation` (só o parser testemunha a ordem).
- **Async-marker `Sync`/`Async`/`AsyncStar`** → `AsyncMarker` do Kernel (`SyncStar` fica de fora: sem sintaxe).
- **Literal `Int` ≠ `Float`** → `IntLiteral`/`DoubleLiteral` distintos (evita o débito G4; **único** ponto de
  paridade VM×JS que a modelagem preserva — ADR-0005).
- **`Call` em ordem-fonte** → `Arguments` com eval-order correta.

## 4. Plano de teste (o gate)

- **Corpus de conformância** (`conformance/`): os 23 CAs → `valid/*.tu`+`.ast` (goldens) e `invalid/*.tu`
  (erros de parse EN kebab-case + span). Ver [`conformance-cases.md`](./conformance-cases.md).
- **Testes unitários** (`compiler/test/parser_test.dart`): asserts sobre nós/associatividade/recuperação —
  o que golden não cobre bem (ex.: shape de `ErrorNode`, span exato).
- **Validação "ao vivo"** — o **MCP `ita` NÃO dumpa AST** (executa programas). Logo, como no léxico (Fase 1),
  o gate é **`itac parse --dump` vs golden**, com o **parser do `ita/` como referência de comportamento**;
  onde o `ita-next` diverge de propósito (6 consertos), o golden = correto, **marcado**. *(Desvio explícito
  de Art. IV.1, mesmo da Fase 1 — a AST não é observável via `compile`/`run`.)*
- **Paridade VM×JS:** N/A nesta fase (sem codegen).
- **CI:** conformance de parsing + unit + **benchmark de compile-time (`itac` AOT, sem regressão)** — Art. IV.3/IV.4.

## 5. Ordem de ataque e dependências (fatiamento §0.6 — bottom-up no grafo de chamadas, DB 4.4.1)

Cada fatia é **verticalmente testável** (CAs próprios + goldens `itac parse --dump`) antes da seguinte.

1. **Fatia 0 — Fundação** — depende de: —
   `ast.asdl` + `ast.dart` + `itac parse --dump` (pretty-printer S-expr, CI 5.4) + infra de recuperação
   (`ParseError` + sync-set, CI 6.3) + **`type` e `pattern`** (folhas do grafo). CAs: **15, 16, 17** (+ 18
   exercita a recuperação). *Por quê primeiro:* `matchArm` precisa de `pattern`; `param`/`closure`/`field`
   precisam de `type`; e o pretty-printer/recuperação são usados por todas as fatias.
2. **Fatia 1 — Expressões** — depende de: 0
   Cascata de 13 níveis (§4.2) + 8 cantos de desambiguação (§3.3) + interpolação parse-time. CAs: **8–14,
   19, 20, 23**. *Maior risco* (associatividade, `_isClosureStart` scan-ahead, cantos).
3. **Fatia 2 — Statements & controle** — depende de: 1
   `let`/`var` (+destructure), `return`, `if`/`guard`/`while`/`for`(`for await`), `break`/`continue`,
   `emit`, `block`, `exprStmt`. CAs: **5, 6, 7, 21**. *Depende de 1:* condições consomem expressões e ativam
   a supressão de trailing-closure.
4. **Fatia 3 — Declarações & reconciliação** — depende de: 0,1,2
   `fn`/`struct`/`class`/`enum`/`trait`/`impl`/`extension`/`actor`/`operator`/`import` + `meaningless-pub`
   + `grammar.ebnf` §Syntactic + deltas tree-sitter + corpus completo. CAs: **1–4, 22**. *Topo do grafo* e
   boundary de sincronização (`_declaration()`).

> As 4 fatias viram as 4 famílias de tasks do `/speckit-tasks` (fail-first: RED goldens → GREEN parser →
> VALIDATE `itac parse --dump` → QUALITY CI+benchmark).

## 6. Riscos técnicos e mitigações

| Risco | Sev. | Mitigação |
| :-- | :-- | :-- |
| **Compile-time** — `_isClosureStart` faz scan-ahead **ilimitado** (`(params)=>` vs `(expr)`); cascata de 13 níveis é recursão funda | média | Manter (é correto/necessário) mas **medir**: benchmark-guard AOT no CI falha em regressão (Art. IV.3). É o item que a §0.6 mandou vigiar. |
| **Golden errado** por causa das 6 divergências deliberadas vs oracle | média | Cada divergência tem **CA + golden marcado** (`conformance-cases.md` §Divergências); onde **não** diverge, o parser do `ita/` é a referência byte-a-byte. |
| **Dump não-determinístico** (iteração de hash-map, escaping) | alta | Ordem de filhos = ordem gramatical/fonte; **zero** iteração de hash; floats (`.0`) e strings com escaping canônico (`design-notes` §Dump). |
| **P11** — `ast.dart` gerado do ASDL reintroduz codegen em build-time | alta | Script Dart **do dev**, saída **commitada**, **nunca** `build_runner` (mesma tolerância do `tree-sitter generate`, ADR-0010). Ou escrever `ast.dart` à mão. |
| **Recuperação N2** entra em cascata/loop no resync | média | Sync-set **com consciência de boundary-closer** (não atravessa `}`/`)`/`]` que um contexto ativo espera) — modelo do `_synchronize` do oracle que já matou o bug do erro-fantasma. |
| **Achado do plan:** golden de **CA9** invertido na spec §11 (`(\|\| (?? a b) c)` vs correto `(?? a (\|\| b c))`) | baixa | Corpus usa o **correto** (GRAMMAR §4.2). **Propor patch** no texto da `spec.md` §11 (ver relatório). |

## 7. Constitution check (re-confirmação pós-design)

- **P4 (sem mágica):** ✅ gramática citável (`grammar.ebnf` §Syntactic + `GRAMMAR.md`), 8 cantos explícitos e
  determinísticos, dump determinístico, `meaningless-pub` conserta o consumo mudo do oracle.
- **P6 (zero annotations):** ✅ nenhuma produção introduz `@`.
- **P11 (zero codegen build-time):** ✅ parser descendente-recursivo **à mão**; `ast.dart` à mão ou por
  script do dev (saída commitada) — **nunca** `build_runner`/yacc/ANTLR/PEG-gen.
- **P3 (tudo é expressão):** ✅ `if`/`match`-expr preservados; **bloco-nu não é expressão** (poder via valor
  **explícito**, não última-expr implícita) — casa com P4.
- **Art. IV (operacional):** IV.1 (MCP `ita`) — **desvio explícito documentado** (a AST não é observável via
  `compile`/`run`; validação por `itac parse --dump` + oracle `ita/`, como na Fase 1); IV.3 (compile-time
  perto do Go) — benchmark-guard AOT; IV.4 (conformância no CI) — 23 CAs no corpus; IV.5 (`.tu`; docs PT-BR;
  erros EN kebab-case) — ✅.
- **Veredito:** **sem conflito** com princípio permanente. *(Constitution-check de identidade normalmente
  disparado pelo `ita-visionary`; nesta sessão feito diretamente — o agente custom não entra no registro sob
  o cwd `ita-lang/`, ver `design-notes.md`.)*

## 8. Artefatos auxiliares (gerados nesta fase de planejamento)

- [`design-notes.md`](./design-notes.md) — as 4 decisões do dono materializadas + modelagem (ASDL, `Error*`,
  dump, 8 cantos, recuperação N2, forward-compat Kernel), cada uma com capítulo citado.
- [`conformance-cases.md`](./conformance-cases.md) — os 23 CAs → `.tu`→`.ast` (goldens/erros), com o golden
  de CA9 **corrigido**.
- [`grammar-delta.md`](./grammar-delta.md) — a seção §Syntactic (W3C EBNF), os apertos vs `GRAMMAR.md`, os
  deltas tree-sitter registrados.

> **Nota — agent-context:** a skill prevê atualizar um bloco `<!-- SPECKIT -->` no `CLAUDE.md`. **Não existe
> esse marker** no workspace nem no `ita-next/` (a Fase 1/003 também não criou) — passo **pulado**, mesmo
> precedente. O contexto dos agentes do `ita-next` são os 3 subagentes-especialista + as skills speckit.
