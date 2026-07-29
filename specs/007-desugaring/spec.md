# Spec 007: Fase 3 — Desugaring / lowering (AST → AST canônica)

> **Tipo:** decisão-de-linguagem + feature-fase · **Marco:** `Fase 3 (Desugaring) do ita-next`
> **Status:** `draft`
> **Autor / Data:** orquestração (Claude) · 2026-07-12 · **Fundamentação:** Dragon Book 5.3 + Crafting Interpreters 9.5.1 + oracle `ita/`; levantamento `compiler-craftsman` 2026-07-12

## §0 Metadados

- **Classe da mudança:**
  - [x] **Nova regra/fase** — a Fase 3 (Desugaring) do faseamento ADR-0011, um passe AST→AST entre o parser (Fase 2) e o binding (Fase 4).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [ ] Formal · [x] **SDD/desugaring (§5)** · [ ] Fluxo · [ ] Codegen · [ ] Runtime
- **Princípios afetados:** P3 (tudo é expressão), P4 (sem mágica — o açúcar vira forma explícita e **inspecionável**, não some), P11 (zero codegen — o passe é escrito à mão). **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

O `ita-visionary` (rulings 2026-07-12) e o dono cravaram: `?` = só Result (P7); ausência (`Option`/`T?`) via `guard let`/`if let`/`??`/`?.`/`!`, desaçucarados sobre `.some`/`.none` (modelo Swift — `Option<T>` é built-in, `nil` = `.none`); `Try` permanece nó core (block-expr-with-return **rejeitado**, feriria RD-1); gensym lexicamente reservado (`$`+tag). Tensão P4 (o `match` gerado embute teste de variante) **resolvida**: aceitável PORQUE o `itac desugar --dump` expõe a expansão — sem mágica escondida. **Sem conflito aberto.**

## §1 Motivação e resumo

A Fase 2 entrega uma AST **rica em açúcar** (`?`, `|>`, `>>`, `??`, `?.`, `!`, `where`, `if-let`, `for`, `$0`). A Fase 3 produz a **AST canônica**: reescreve o açúcar em um **subconjunto núcleo** de nós, para que as fases seguintes (Binding, Semântica, Análises, Codegen) trabalhem sobre poucas formas ortogonais — não sobre toda a superfície da linguagem. É o modelo **rustc AST→HIR** (ADR-0011), mas sobre a **mesma hierarquia `sealed`** (Dragon 5.3: "um segundo walk SDD não exige um segundo tipo de nó").

**Antes → Depois** (o desugaring é observável via `itac desugar --dump`):

```tu
// antes (AST bruta, Fase 2):
let city = user?.address?.city ?? "unknown"
let f = parse >> validate
```

```tu
// depois (AST canônica, Fase 3) — conceitual:
//   a?.b        →  match a { .some($x) => $x.b, .none => .none }
//   a ?? b      →  match a { .some($x) => $x, .none => b }
//   f >> g      →  ($c) => g(f($c))
// nenhuma construção-açúcar sobrevive; só match/call/closure/while + nós core.
```

**Não-objetivos:** (1) **resolução de nomes** (a qual `fn` o `|>` liga) — é Fase 4. (2) **Tipos** — desugaring é type-agnostic; copy-with, currying, `**` e **`>>`** (que precisam de tipo) **ficam de fora**. (3) Lowering final do `Try`/copy-with para Kernel — é Fase 7. (4) Exaustividade dos `match` gerados — é Fase 6.

---

## §5 A fase de Desugaring — `[Dragon 5.3; CI 9.5.1]`

### 5.1 Modelo arquitetural
- **Tradução AST→AST canônica** sobre a hierarquia `sealed` de `ast.dart` (Dragon 5.3 — SDD *para a árvore de sintaxe*). **Não** um HIR paralelo (dobraria a manutenção à mão, P11); **não** in-place (AST imutável — cada passe produz uma árvore nova).
- **Transformer visitor** (espelho do `AstDumper`, CI 5.3 — `switch` exaustivo, mas retorna `AstNode` em vez de `String`), **post-order** (Dragon 5.2): filhos canônicos antes do pai, resolvendo o aninhamento (`a |> b where {…}`).
- **Passe único, idempotente:** nenhum desugar produz nó-açúcar (as saídas são só nós core) → um walk basta; `desugar ∘ desugar = desugar` é invariante testável.
- **Localização:** `compiler/lib/frontend/desugar/`.

### 5.2 Catálogo de reescritas (regras)

Cada regra preserva o **span** do açúcar-fonte em todo nó sintetizado (M1 → `fileOffset` do Kernel; DWARF/source-map). `$k` = gensym reservado (§5.3).

| Açúcar (fonte) | Forma canônica (alvo) | Fundamentação |
| :-- | :-- | :-- |
| `a ?? b` | `match a { .some($x) => $x, .none => b }` | Swift Option; oracle `_compileNilCoalesce` |
| `a?.b` | `match a { .some($x) => $x.b, .none => .none }` (chain achata, short-circuita 1×) | Dragon 5.3; Swift optional-chaining |
| `a!` | `match a { .some($x) => $x, .none => panic("force-unwrap on none") }` | usa nó `Panic` existente |
| `if let P = e => t else f` | `match e { .some(P) => t, .none => f }` | CI 9.2; rustc if-let→match |
| `guard let P = e else { blk }` | `match e { .some(P) => «continua», .none => blk }` (P entra no escopo seguinte) | oracle `_compileGuardLet` |
| `V where { let x = e; … }` | `match e { $x => V[x:=$x] }` aninhado (bind irrefutável = let-in) | Dragon 5.3; ADR-0012 A.4 |
| ~~`f >> g` (compose)~~ | **RETIDO como núcleo** — ver §12-C abaixo | ruling do dono, 2026-07-29 |
| `x \|> f(a)` (pipe) | `f(x, a)` — insere `x` como 1º posicional | CI 9.5.1; oracle `_compilePipe` |
| `{ $0 * 2 }` (shorthand) | `Closure(params=[$0..$n])`, aridade = maxIndex do corpo + 1 (scan sintático) | corrige o hardcode de 3 do oracle |

**Retidos como nós CORE (não são açúcar; NÃO desaçucaram na Fase 3):**
- `e?` (**`Try`**) → early-return de `Result`; baixa no codegen (Fase 7). `return` é `Stmt`, não cabe em `=> expr`; block-expr-with-return foi rejeitado (RD-1).
- **`for x in it` / `for await` (`ForStmt`)** → o codegen emite `ForInStatement` do Kernel; a Dart VM itera `Iterable`/`Stream` de graça (**Grupo B**). NÃO desaçucara para `while` — **Dragon 6.1** manda não lowerar além do backend, e o Kernel já tem `ForInStatement` (o CI 9.5.1 só lowera por falta de primitivo no tree-walker). Só o INTERIOR (`iterable`/`body`) é desaçucarado. **Ruling de dono (2026-07-12):** reter agora; o protocolo iterador **Itá-próprio** (trait `Iterator`, `next() -> Option<T>`, modelo Elixir `Enumerable`) é débito de roadmap (M5 — des-Dartificação). Convergência unânime dos 3 agentes.
- `nil` literal → `.none` é conceitual; o nó `NilLit`/`LiteralPattern(nil)` pode permanecer (o codegen mapeia para `Option.none`).

**Fora da Fase 3 (type-directed → Fases 4/5/7):** `p.{…}` copy-with (enumerar campos precisa do tipo), currying/sub-aplicação (precisa da aridade do callee), `a ** b` (alvo `pow` Int/Float é type-directed).

### 5.3 Higiene — gensym reservado
Binders sintetizados (`$c` no compose, `$it` no for, `$x` nos unwraps) usam o prefixo **`$` + tag alfabética** (`$c0`, `$it0`, `$x0`). São **lexicamente inatingíveis** pelo usuário: o léxico só produz `$`+dígitos (`CLOSURE_PARAM = $[0-9]+`) ou `IDENT` (letra/`_`); `$c0` não casa nenhum → zero-captura garantida por construção (Kohlbecker et al. 1986, higiene). São **visíveis no dump** (`(bind "$c0")`) — honestidade P4.

### 5.4 Validação (observável)
- **`itac desugar --dump`** reusa o `AstDumper` (S-expr, CI 5.4) — mesmo padrão de `tokenize`/`parse --dump`. Função pura chamada direto pelo teste (espelho de `parseDump`).
- **Diff vs `parse --dump`:** somem `(?? …)`, `(opt-chain …)`, `(force-unwrap …)`, `(if-let-expr …)`, `(where …)`, `(|> …)`, `(for …)`; aparecem `(match …)`, `(call …)`, `(closure …)`, `(while …)` com gensyms `$…`. **Permanecem** `(try …)`, `(copy-with …)`, **`(>> …)`**.
- **Assertion pass** de boa-formação do core: após a Fase 3, nenhum nó-açúcar sobrevive (análogo ao blocker de boa-formação da Fase 2). É o preço de não duplicar a hierarquia.
- **Corpus `.desugar`** (`.tu` → `.desugar` golden), padrão ADR-0011.

---

## §9 Checklist de completude

- [ ] `desugar/` — transformer visitor post-order, passe único, idempotente
- [ ] Gensym reservado (`$`+tag), zero-captura, visível no dump
- [ ] `itac desugar --dump` no driver + função pura testável
- [ ] Spans preservados em todo nó sintetizado (teste: span dentro do range do fonte)
- [ ] Assertion pass de boa-formação do core
- [ ] Corpus `.desugar` cobre cada regra §5.2 + idempotência
- [ ] `dart analyze` limpo; `make test` verde

## §10 Compatibilidade e alternativas

- **Breaking change?** Não — é fase nova; `parse --dump` inalterado. `desugar --dump` é output novo.
- **Rulings de dono cravados:** modelo Swift (`T?`=`Option<T>`, `nil`=`.none`); `?`=só Result; ausência via guards/`??`/`?.`/`!` sobre `.some`/`.none`; `Try` core; gensym `$`+tag; copy-with/currying/`**`/**`>>`** fora da Fase 3.
- **Correção ao ADR-0011:** o ADR listava copy-with e currying como type-agnostic — o oracle prova que **não são** (leem `_typeFields`/aridade). Migram para pós-binding. A spec 007 registra a correção.
- **Alternativas descartadas:** HIR paralelo (custo P11 sem os consumidores do rustc); desugar dentro do parser (modelo CI — mas o Itá quer o passe separado, ADR-0011); `?` polimórfico Result+Option (mistura erro e ausência — decisão de dono: não).

## §11 Critérios de aceite (viram corpus `.desugar`)

- **CA1** — `a ?? b` ⟶ `(match (id a) (arm (pat-enum "some" (bind "$x0")) (id "$x0")) (arm (pat-enum "none") (id b)))` (nomes exatos conferidos ao vivo).
- **CA2** — `a?.b` ⟶ `match` sobre `.some`/`.none`, `.some` faz `.b`, `.none` propaga `.none`.
- **CA3** — `a!` ⟶ `match` com braço `.none => (panic …)`.
- **CA4** — `f >> g` ⟶ **`(>> …)` RETIDO**, intacto. Ver §12-C.
- **CA5** — `x |> f(a)` ⟶ `(call (id f) (id x) (id a))` (x é 1º posicional).
- **CA6** — `if let x = o => t else e` ⟶ `(match (id o) (arm (pat-enum "some" (bind "x")) (id t)) (arm (pat-enum "none") (id e)))`.
- **CA7** — `for x in xs { … }` ⟶ **`(for …)` RETIDO** (não vira `while`); só o interior é desaçucarado (ex.: `??` no corpo vira `match`). `for await` idem (`(for-await …)`).
- **CA8** — `V where { let x = e }` ⟶ `match`/let-in (sem `(where …)`).
- **CA9** (retenção) — `e?` ⟶ **`(try …)` permanece**; `p.{x:1}` ⟶ **`(copy-with …)` permanece** (não expandem).
- **CA10** (idempotência) — `desugar(desugar(P)) == desugar(P)` para todo caso acima.
- **CA11** (span) — todo nó sintetizado tem `offset/length` dentro do range do açúcar-fonte (via `--spans`).

## Definition of Done

- [ ] CAs cobertos por corpus `.desugar` + unit, verdes via `itac desugar --dump`.
- [ ] Transformer + gensym + assertion pass implementados à mão (P11).
- [ ] Fronteiras respeitadas (copy-with/currying/`**`/`Try`/**`>>`** NÃO expandem).
- [ ] Constitution check sem conflito + code review de identidade (`ita-visionary`) aplicado.
- [ ] `make test` + `dart analyze` verdes.

---

## §12-C — `>>` é NÚCLEO (ruling do dono, 2026-07-29)

**Decisão:** a F3 **não reescreve** `f >> g`. O nó `Binary(compose)` sobrevive ao
desugar, a **F5 ganha regra de síntese própria** e a **F7 emite** a closure já tipada.

### Por que a reescrita estava errada

Ela produzia uma closure com parâmetro **sem anotação**:

```dart
final param = Param(null, c, null, null, n.offset, 0);
//                          ↑ o tipo, e ele é null
```

E a F5 tem regra firme: closure com parâmetro sem tipo **não sintetiza** — precisa de
contexto que faça o tipo descer. Resultado medido:

```
let comp = dobra >> mais1                  ⟹ check-error: cannot-infer
let comp: (Int) -> Int = dobra >> mais1    ⟹ compila
```

**`f >> g` é inteiramente sintetizável.** Se `f : (A)→B` e `g : (B)→C`, então
`f >> g : (A)→C` — não há nada a inferir, é composição de tipos conhecidos. A informação
existe toda **antes** de qualquer contexto.

Quem a destruiu foi a própria reescrita: ela é *type-agnostic na forma* mas **não preserva
o MODO** — leva uma expressão que **sintetiza** (⇒) a uma que só **verifica** (⇐).

**Fundamento:** preservação de modo bidirecional sob lowering **não está no Dragon**
(Fig. 1.7 ordena semântica **antes** da geração de IR; o Itá inverte e compra isso com
"type-agnostic", ADR-0011). A referência é Dunfield & Krishnaswami, *Bidirectional
Typing*, ACM CSUR 54(5), 2021, §3 (*mode-correctness*). **Lacuna declarada**, não herdada.

### A companhia que ele passa a ter

`>>` entra na lista que a §"Não-objetivos" já mantinha — **copy-with, currying, `**`** —
e pelo motivo idêntico: *"precisam de tipo, ficam de fora"*. O que a lista não tinha, e
esta decisão corrige, é o próprio `>>`: o cabeçalho do `desugar.dart` afirmava que só
aquelas três precisavam de tipo, e isso era falso desde que o `_compose` foi escrito.

### O que muda por fase

| fase | antes | agora |
|---|---|---|
| **F3** | `_compose` → closure com param `null` | passa através (`Binary(compose)` intacto) |
| **F4** | resolve dentro da closure gerada | resolve os dois operandos |
| **F5** | herdava `cannot-infer` da closure | **regra própria**: `(A)→B` `>>` `(B)→C` ⟹ `(A)→C`; incompatibilidade é `compose-type-mismatch` |
| **F6** | walk da closure gerada | walk dos dois operandos |
| **F7** | — (nunca chegou) | emite `FunctionExpression` com os tipos que a F5 provou |

### O que este ruling NÃO decide

`|>` (pipe) continua sendo reescrito. Ele **não tem o mesmo defeito**: o desugar o
transforma em chamada direta (`x |> f` ⟶ `f(x)`), não em closure — não há parâmetro
sintético sem anotação, e o modo é preservado.
