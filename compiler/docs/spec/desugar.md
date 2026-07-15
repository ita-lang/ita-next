# desugar.md — Regras de reescrita da Fase 3 (Desugaring / lowering)

> Artefato formal da **Fase 3** (ADR-0010: *"tabela de reescrita — açúcar → núcleo canônico"*).
> Fonte-da-verdade **citável** das reescritas; par do [`ast.asdl`](./ast.asdl) (nós) e do
> [`grammar.ebnf`](./grammar.ebnf) (sintaxe). O código (`lib/frontend/desugar/desugar.dart`) é a
> materialização à mão destas regras (P11); mantenha os dois em sincronia.
>
> **Fundamentação:** Dragon Book 5.3 (SDD *para a árvore de sintaxe* — um 2º walk não exige 2º tipo de
> nó) · Crafting Interpreters 9.5.1 (desugaring). **Spec de processo:** `specs/007-desugaring/`.
> **Rulings de dono/identidade:** ADR-0012; modelo **Swift** (`T?` = `Option<T>`, `nil` = `.none`).

## Modelo

- Transformação **AST → AST canônica** sobre a mesma hierarquia `sealed` (não um HIR paralelo).
- **Transformer visitor post-order** (filhos canônicos antes do pai); **passe único**, **idempotente**
  (`desugar ∘ desugar = desugar` — as saídas são só nós núcleo).
- **Type-agnostic:** roda ANTES do Binding (Fase 4) / Semântica (Fase 5). O que precisa de tipo fica fora.
- **Spans:** todo nó sintetizado herda `offset`/`length` (e `opOffset` nos pós-fixos) do açúcar-fonte
  (→ `fileOffset` do Kernel; DWARF/source-map).
- **Gensym:** binders sintéticos usam `$` + tag alfabética (`$x`, `$c`, `$it`), contador por passe.
  Lexicamente inatingíveis (o léxico só produz `$`+dígitos ou `IDENT`) → zero-captura por construção
  (higiene, Kohlbecker 1986). Visíveis no dump (P4 — honestidade).

Notação: `S ⟿ C` = o açúcar `S` reescreve para a forma canônica `C`. `$x` = gensym fresco.

## 1. Nulabilidade (`Option`/`T?` — desembrulho, Swift)

```
a ?? b      ⟿   match a { .some($x) => $x,  .none => b }
a?.b        ⟿   match a { .some($x) => $x.b, .none => .none }        (cadeia achata; short-circuita 1×)
a!          ⟿   match a { .some($x) => $x,  .none => panic("force-unwrap on none") }
if let P = e => t else f
            ⟿   match e { .some(P) => t, .none => f }
```

`guard let P = e else { blk }` **é RETIDO** (ver §4): o `else` diverge com `return`/statements que não
cabem em braço `=> expr` (RD-1). O `?` (try) é de **`Result`**, não de `Option` — ver §4.

## 2. Funcional (composição, pipe, closure-shorthand)

```
f >> g          ⟿   ($c) => g(f($c))                                 ($c gensym)
x |> f(a…)      ⟿   f(x, a…)                                         (x = 1º posicional)
x |> f          ⟿   f(x)
{ … $0 … $n … } ⟿   ($0, …, $n) => { … }                            (aridade = maior $k no corpo + 1;
                                                                      scan sintático, para em closures aninhadas)
```

O `{ … }` **sem** `$k` permanece closure implícita (aridade é contextual → Fase 5).

O índice do `$k` tem **teto 255**, garantido pelo léxico (`lex-dollar-index-range`, `grammar.ebnf` §1) —
sem ele, `{ $3000000 }` faria esta fase alocar 3M de `Param`s. A Fase 3 confia na invariante: não
revalida (segue pura e infalível).

## 3. Bindings-antes-do-valor (`where`, letrec)

```
V where { let x₁ = e₁; … let xₙ = eₙ }
            ⟿   match e_{σ(1)} { x_{σ(1)} => match e_{σ(2)} { x_{σ(2)} => … => V } }
```

onde `σ` é a **ordenação topológica por dependência** (Kahn) — não a ordem-fonte. Dependência = análise
**sintática** de variáveis-livres: `xᵢ` depende de `xⱼ` sse `eᵢ` referencia o nome `xⱼ` livremente
(desce em closures = captura; respeita shadowing léxico de params/patterns/lets). Empate → ordem-fonte
(determinístico). Bindings puros → reordenar é referencialmente transparente (P4). Ciclo entre bindings =
inválido pela spec 006 §3.6; **deferido** ao pós-binding (o Desugarer não tem canal de erro) — o passe
permanece total (fallback em ordem-fonte, não crasha).

## 4. Retidos como núcleo (NÃO são açúcar — não reescrevem)

| Nó | Por quê retém | Baixa em (Fase 7) |
| :-- | :-- | :-- |
| `e?` — **`Try`** (`Result`) | early-return é `Stmt`, não cabe em `=> expr` (RD-1) | `if is-Err return; unwrap` |
| `for` / `for await` — **`ForStmt`** | Kernel tem `ForInStatement`; Dragon 6.1: não lowerar além do backend (a VM itera `Iterable`/`Stream` de graça — Grupo B). Só o **interior** desaçucara | `ForInStatement(isAsync?)` |
| `guard let` — **`GuardLetStmt`** | `else` diverge com statements (RD-1) | `if-not-let` no codegen |
| `p.{…}` — **`CopyWith`** | enumerar campos precisa do **tipo** (type-directed) | Fase 5/7 |
| `if c => a else b` (booleano) | mapeia 1:1 a `ConditionalExpression`; reduzir a `match {true/false}` seria net-negativo | `ConditionalExpression` |
| `a ** b` — **`Binary.pow`** | alvo (`pow` Int vs Float) é type-directed | Fase 5/7 |

> **Roadmap (ADR-0012 §C):** o `for` reter `ForInStatement` acopla a iteração ao `Iterable` do Dart; o
> **protocolo iterador Itá-próprio** (trait `Iterator`, `next() -> Option<T>`, modelo Elixir `Enumerable`)
> entra na des-Dartificação (M5) — migração localizada no codegen, não fecha a porta.

## 5. Fora do escopo type-agnostic (deferido — precisam de tipo/aridade)

- **copy-with:** enumeração de campos (`_typeFields`) → Fase 5/7. (Correção ao ADR-0011, que o listava como type-agnostic.)
- **currying / sub-aplicação:** aridade do callee → Fase 4/5. (Idem.)
- **`**` (pow):** alvo por tipo → Fase 5/7.

## 6. Débitos de codegen (Fase 7)

- **compose `>>`** reavalia `f`/`g` por-chamada; a forma fiel (hoist 1×) exige `Let`-hoist no Kernel (mesmo padrão do compound-assign). Divergência só com operandos efeituosos.
- **nulabilidade → `match`** baixa como cadeia `is`/`ConditionalExpression`+`Let` sobre a hierarquia `Option`/`Option_some`/`Option_none` (a VM devirtualiza o `is` de hierarquia fechada — Grupo B).

## Validação (observável)

`itac desugar <f.tu> --dump [--spans]` (S-expr determinística; reusa o `AstDumper`). Corpus:
`conformance/desugar/*.tu` → `.desugar` (golden). Invariantes por fixture: **idempotência**
(`desugar∘desugar == desugar`), **span-no-range**, e **boa-formação do núcleo** (`core_check.dart`:
nenhuma variante-açúcar sobrevive). Gate único `make test`.
