# Spec 010: Fase 5 — Tipagem contextual (fatia C)

> **Tipo:** feature-fase · **Marco:** `Fase 5 (Semântica) do ita-next` · **Escopo:** fatia **C** — o que a 009 deferiu
> **Status:** `clarified` — **5 rulings de dono fechados** (2026-07-15: §12-1/2/3 + §12-B1/B2); 3 levantamentos de agente + **review de identidade da spec escrita** incorporados (o review achou 1 bloqueante — CA53 — e 3 correções doutrinárias; todas aplicadas). Pendentes: §12-A (ergonomia da trailing constante), §12-B3 e §12-D/E — **nenhum bloqueia a implementação**
> **Autor / Data:** orquestração (Claude) · 2026-07-15 · **Fundamentação:** Dragon Book 5.1/5.2 (atributos herdados, L-atribuída, efeitos colaterais controlados) + 6.3.6 (`record(t)`) + 6.5.1 (síntese); levantamentos `compiler-craftsman`, `ita-visionary` e `dart-vm-expert` de 2026-07-15; oracle `ita/` (mapeado — **não serve de gabarito**, ADR-0013).

## §0 Metadados

- **Classe da mudança:** [x] **Nova regra** — completa a Fase 5 com o modo `check` **contextual**: o tipo esperado desce e dá tipo a formas que não sintetizam. Sucede a 009 (fatias A/B/D, implementadas e verdes).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [x] **Formal/Tipos (§4)** · [x] **SDD/atributos (§5)** · [ ] Fluxo · [x] **Codegen/IR (§7 — só o contrato)** · [x] **Runtime (§8 — só a dependência)**
- **Princípios afetados:** P4 (sem mágica — decide o §3), P6 (infere sem exigir), P3 (tudo é expressão), P1/P2. **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

A regra-mãe da 009 continua governando: *"a inferência do Itá não atravessa fronteira de declaração; nenhuma conversão acontece sem um glifo que o usuário escreveu."* E a doutrina que autoriza esta fatia inteira é a §4.9 da 009:

> **Resolução contextual é legítima quando o glifo a PEDE; ilegítima quando é silenciosa.**

Cada forma desta spec **pede**: o `.` do `.variant` é um caractere cuja única função é delegar ao contexto; `{ $0 }` sem tipos anuncia que os tipos vêm de fora; `[]` vazio não tem de que sintetizar. Nenhuma delas é `p + q` (que não anuncia nada). **Mesmo teste P4 dos dois lados.**

**Sem conflito de princípio.** Três rulings de dono fechados em **2026-07-15** (§12).

---

## §1 Motivação e resumo

A 009 entregou o bidirecional com o modo `check` (⇐) **existindo mas quase vazio**: só o `nil` vivia lá. Esta spec o preenche — é o que faz o tipo **descer**.

### 1.1 O que ENTRA (escopo, ruling §12-2)

| Item | Por quê |
| :-- | :-- |
| **Formas *checking-only*** — `nil`, `[]`, `{}`, `.variant` | **1 regra, 4 literais** (§4.1). Não são quatro casos especiais |
| **Closure contextual** — `{ $0*2 }`, `(x) => x*2` | Params herdam do esperado (§4.2). É o coração da fatia |
| **Ordem de argumentos** — 2 rodadas | §4.3. Sem isso, closure nunca recebe contexto |
| **`CopyWith`** — `s.{ campo: v }` | §4.4. Exige `record(t)` (6.3.6) |
| **Leitura de campo** — `p.x` | §4.5. **Vem quase de graça**: é a MESMA `record(t)` do CopyWith |
| **O chão** (~4) — `.length`, `.slice`, `[]`, `+` | §4.6. **Não é adiável** — sem ele a stdlib não tipa (§1.3) |

### 1.2 O que SAI, e por quê (correções à §5.4 da 009 — ela está defasada)

1. **Currying: fora, e já estava fora.** `specs/004-parser-ast/design-notes.md:262` cravou **"não portar `PartialAppExpr`"**; no oracle esse nó é **AST órfã** (`ita/compiler/docs/GRAMMAR.md:307`) e no `ita-next` há **zero** ocorrências. A sintaxe `add(5, _)` **não parseia**: `primary` não tem `_`, que só existe como `pattern` (GRAMMAR §255), e `arg = ( IDENT ":" )? expression`. O checker seria a parte barata (montar o `→` do 6.3.1 com slots vazios); o custo está em **gramática + F3 + F7**. **Currying está mispriced como feature de tipos.** Se voltar, é ADR + ruling de identidade, não item de spec de tipos.
2. **`**`: já está PRONTO** desde a fatia B — `check.dart:71` tem `BinaryOp.pow: [(Int,Int,Int),(Float,Float,Float)]`, match exato, operador nativo (`Tag.starStar`, precedência 11, direita). Não é dispatch para método. O que faltava não era a regra de tipo: era **decidir o `2 ** -1`** — fechado no ruling §12-3, e o que sobra é **contrato de F7** (§7.3).
3. **Dispatch de método** (`xs.map { … }`) → **spec 011** (§1.4). É consequência do ruling §12-1.

### 1.3 Por que o chão entra: **ruling 2** — e só

> ⚠️ **Esta seção foi REESCRITA em 2026-07-15.** A versão original dizia *"o chão não é adiável — sem ele a stdlib não tipa"*. **O argumento era falsificável e foi falsificado.** Fica o registro, porque o erro é instrutivo.

**O que a versão anterior afirmava:** sob ADR-0013, `list.length` vira `unknown-member` ⟹ a F5 rejeita a stdlib ⟹ o chão é urgente.

**Por que caiu — necessário ≠ suficiente.** É verdade que sem o chão a stdlib não tipa. Mas **com** o chão ela **continua não tipando**:

| Blocker | Estado | Evidência |
| :-- | :-- | :-- |
| `for item in list` — **17 funções** de `iter.tu` | **não-objetivo desta spec** (§1.4-2) | l.41, 50, 58, 66, 102, 112, 133, 146, 161, 171, 204, 211, 220, 227, 234, 242, 288 |
| `list[i]` — índice | **nenhuma regra existe** | grep `Index` em `check.dart`: **zero** |
| `result + [item]` — concat de `List` | **nenhuma regra existe** | `check.dart:49` — `_primitiveOps[add]` só tem `(Int,Int,Int)`, `(Float,Float,Float)`, `(String,String,String)` |
| **5 dos 12 módulos não PARSEIAM** | dialeto antigo do oracle | `validate` 18, `datetime` 11, `log` 9, `iter` 4, `async` 1 — usam `if c { a } else { b }` como expressão, e a forma real é `if c => a else b` (RD-1) |
| imports entre módulos | os 7 que parseiam falham | `unknown-type` / `unresolved-before-check` |

⟹ **"a stdlib tipa" não é gate desta spec; é gate da 011** (e nem lá, sem migrar o dialeto). Um princípio pendurado num fato falso é tão frágil quanto pendurado em custo — é a doutrina do §8.3 da 009 (*o dado reforça, não fundamenta*), e ela **vale contra nós mesmos**.

**O chão não precisa daquele argumento: ele tem o ruling 2** (§2). Autoridade do dono é fundamento suficiente, e é o fundamento honesto. O que o chão **é**: **pré-requisito** de a stdlib tipar um dia — não a peça que fecha o gate.

### 1.4 Não-objetivos

1. **Dispatch de método** (`xs.map`, `x.foo()`) → **011**. Delta real sobre esta spec: walk de traits/superclasse. A leitura de campo (§4.5) já fica aqui.
2. **Trait `Iterator` / `for`** (o deferido §12-4 da 009) → **011**. ⚠️ **Achado do `ita-visionary`, e é estrutural:** a spec do `Iterator` e a spec de "membros de built-in" são a **MESMA spec**. O `Iterator` **defere, não dissolve** — o `impl Iterator for List` cai no mesmo chão. As duas perguntam *"como um built-in ganha um contrato que o usuário também escreveria?"*. **Duas specs para uma pergunta é como se acaba com duas respostas.**
3. **Overload / `OperatorDecl`** → **011**. Reintroduz o Ex. 6.5.2 (dois percursos) e **ameaça o 1-walk** — precisa de spec que encare isso de frente.
4. **Migração dos 5 métodos de `Option`/`Result` para `.tu`** → **011** (§3.4). É a 1ª parcela do Norte do Art. II, e é barata.
5. **Exaustividade, definite-return, unreachable** → **F6** (path-sensitive), como na 009.

---

## §2 Rulings do dono — **FECHADOS 2026-07-15**

| # | Ruling | Consequência |
| :-: | :-- | :-- |
| **1** | **`.map` em container é o idioma** (Swift/Rust), **não** `|>` + função livre | Contraria a recomendação do `ita-visionary` — que cravou ser **decisão do dono** (constituição silente; P5 empurra para função livre **sem fechar a porta**). ⟹ **CA15 migra para a 011** e **não pode ser flagship da 010**; `iter.tu` ganha `map`/`filter`/`fold` como `extension` na 011. ⚠️ **Depende do §12-B1** — ver §2.1 |
| **2** | **Escopo = contextual + campo + o chão** | O chão entra como **débito declarado forma-M5** (§3.3) |
| **3** | **`Int ** Int -> Int`, com panic no expoente negativo** | Tipo **fechado sobre Int** (honra §4.5 da 009 — zero coerção). Exige **`intPow` nossa**; `dart:math::pow` é proibido (§7.3) |
| **4** | **Bloco de closure com UMA `ExprStmt` → `ExprBody` no desugar (F3)** | Resolve a colisão **RD-1 × ruling 1** (§2.2). **Preserva** RD-1 em vez de furá-lo: o `=>` passa a existir de fato, visível em `itac desugar --dump` (P4) |

> **Sobre o ruling 1 — registro honesto.** O `ita-visionary` recomendou `|>` + função livre com três argumentos: o `|>` já existe e desugara para `f(x, a)` em F3 (atestado em `pipe.tu`, `pipe_bare.tu`, `nested_pipe_compose.tu`); a stdlib inteira já é assim (25 funções livres, **18 HOF, zero exceções**); e `.map` em container exige a única máquina não-resolvida. O dono decidiu o contrário, no seu direito — **a constituição é silente e isto é taste, não princípio**. O custo foi aceito com a decisão: a **011 carrega member dispatch + `map`/`filter`/`fold`**.

### 2.1 O que o ruling 1 IMPLICA — e a condição de que ele depende

**`extension List<T>` deixou de ser pergunta de forma. É *entailment* do ruling 1**, e a cadeia é fechada dentro desta spec:

1. Ruling 1: `.map` é membro de container ⟹ `map` **tem** de ser membro de `List`.
2. §3.1: `map` é **biblioteca**, não chão.
3. §3.3-1: o chão é **FECHADO** ⟹ `map` **não pode** entrar na tabela.
4. ⟹ `map` só pode vir de **`extension List<T>` em `.tu`**. **Não há terceira porta.**

> ⚠️ **Condição de viabilidade (§12-B1):** se `extension List<T>` **não** for legal, o ruling 1 fica **sem caminho de implementação** que não seja hard-codar `map` no compilador — o que o §3.4 proíbe (engorda o vazamento que o ADR-0013 mandou fechar) e o que mata o Norte do Art. II (a stdlib nunca vira "só Itá"). **Nesse cenário o ruling 1 volta à mesa.** Não é a spec que o revoga — é governança.

**Destino do `|>` — escrito, para ninguém o deletar como resíduo.** "Parcialmente vestigial" é vago demais para sobreviver a uma faxina. O preciso: **`|>` perde os combinadores da stdlib e mantém o pipeline de função livre do usuário** — `data |> parse |> validate |> save` —, onde **método não é opção**, porque não se põe método no tipo dos outros. Divisão coerente e permanente: **`.map` para container; `|>` para pipeline de domínio.**

**A stdlib migra na 011.** Se `.map` é o idioma e `chunk(list, size)` é função livre, o usuário decora qual combinador tem qual forma — arbitrariedade não é mágica, mas é **incoerência**, e o ruling 1 alcança `chunk`/`zip`/`find`/`partition` pela mesma razão que alcança `map`. **A 010 não atrapalha** (nada nela fixa forma de chamada — §9-5), mas fica registrado para a 011 não descobrir.

### 2.2 A colisão **RD-1 × ruling 1** — e por que o ruling 4 a resolve preservando RD-1

**Descoberta na implementação (2026-07-15), e era um conflito entre dois rulings do dono.**

| | |
| :-- | :-- |
| **RD-1** (rodapé do `ast.asdl`) | *"`=>` é o ÚNICO token que rende valor em todo o Itá — fn-body, **closure**, match-arm, if-expr"*; *"blocos `{}` … **NÃO** rendem seu último valor"* |
| **Ruling §12-1** (hoje) | `.map` em container é o idioma ⟹ `xs.map { $0 * 2 }` |

**O choque:** a gramática só dá **uma** forma ao closure-shorthand — `trailingClosure ::= block` —, então `{ $0 * 2 }` nasce com corpo-BLOCO. Verificado no golden da F3: `(closure (params (param "$0")) (block (expr-stmt (* (id $0) (int 2)))))`. Por RD-1 esse bloco **não rende** ⟹ a closure devolve `Void`, o `$0 * 2` é **descartado**, e **o idioma que o ruling 1 escolheu não significa nada**.

**O ruling 4 não abre exceção — ele torna o `=>` VERDADEIRO.** As chaves de `{ $0 * 2 }` são delimitador **da closure**, não um bloco-nu. A F3 passa a emitir `ExprBody`, e é o que a **própria spec do desugar já escrevia** (`{ … $0 … } ⟿ ($0, …) => { … }`) e que a implementação não cumpria. Pós-F3 o `=>` **existe**, e o `itac desugar --dump` o mostra: **sem mágica escondida** (P4).

**Escopo deliberadamente estreito — só CLOSURE:**

| Forma | Resultado | Razão |
| :-- | :-- | :-- |
| `{ $0 * 2 }` (1 `ExprStmt`) | ⟶ `($0) => $0 * 2` | há uma expressão para render |
| `{ g()  h() }` (multi) | **continua bloco** ⟶ `Void` | não há **uma** expressão |
| `{ let z = 1 }` (1 não-expr) | **continua bloco** | idem |
| **`fn f() -> Int { 5 }`** | **continua bloco** — **não rende** | **RD-1 exatamente onde importa**. Corpo de `fn` não passa pela regra |

---

## §3 A doutrina: **chão vs biblioteca** — `[ita-visionary, 2026-07-15]`

Esta seção existe porque a pergunta *"de onde vêm os membros dos built-ins?"* é um **erro de categoria**. Ela conflata dois problemas e faz o chão parecer enorme.

### 3.1 A distinção

| | Natureza | Exemplos | Tamanho |
| :-- | :-- | :-- | :-- |
| **CHÃO** | irredutível — **tem** de tocar o Dart | `.length`, `[]`, `.slice`, `+` | **~4** |
| **BIBLIOTECA** | derivável do chão, em Itá puro, **zero mecanismo novo** | `map`, `filter`, `fold`, **e os 5 de `Option`/`Result`** | ilimitado |

**Prova 1 — a stdlib já faz.** `stdlib/iter.tu:56`:

```
pub fn flatMap<T, U>(list: List<T>, f: (T) -> List<U>) -> List<U> {
  var result: List<U> = []
  for item in list { result = result + f(item) }
  return result
}
```

Isso é `map` **+ concat**, em Itá puro sobre o chão, **hoje**. Se `flatMap` não precisou de corpo mágico, `map` não pode precisar. **"O corpo de `map` precisa tocar o Dart" é falso:** ele toca o **chão**, e o chão toca o Dart — uma vez, em ~4 lugares.

**Prova 2 — os 5 hard-coded são débito, não piso.** `iter.tu:64` (`compact`) já faz `match item { .some(v) => …, .none => {} }`. Logo:

```
extension Option<T> {
  fn map<U>(f: (T) -> U) -> Option<U> => match self { .some(v) => .some(f(v)), .none => .none }
}
```

**Zero chão.** Os 5 (`Option.map`/`unwrapOr`, `Result.map`/`mapErr`/`unwrapOr`, `codegen.dart:683`) são **todos** escrevíveis em `.tu` com `extension` + `match` — mecanismos que existem e que a stdlib usa **24×** (`extension Stack`, `extension Queue`…). Eles emitem `DynamicType()` em cada nó: são **literalmente a doença que o ADR-0013 nasceu para matar**.

> ⚠️ **Argumento circular a não repetir** (eu o fiz, e o `ita-visionary` o derrubou): *"o idioma real do `.map` é `Option`/`Result`, porque é lá que ele aparece nos exemplos"*. Os métodos que existem são **exatamente** os 5 hard-coded. Não há um sexto porque ninguém escreveu um sexto. **Isso não é evidência de doutrina — é a mágica descrevendo a si mesma como doutrina.**

### 3.2 O teste da mágica: **privilégio**, não tabela

> ⚠️ **Proveniência — não confundir ruling com reconstrução.** O que o **dono** disse no §12-4 da 009 é que a tabela hard-coded (`List<T>→T`) **é** *"a mágica que §4.5/§8.3 recusam"* — o texto dele recusa **a tabela**. A leitura abaixo (*o pecado real é o privilégio, e o chão passa no teste*) é **reconstrução do `ita-visionary`** da intenção dele, **não ratificada como exegese**. Fica marcada como tal. **O §4.6 não depende dela:** a tabela do chão está autorizada pelo **ruling 2**, que é do dono. Esta seção explica *por que ela é defensável*; não é ela que a autoriza.

O teste proposto:

> **O usuário obtém isto para o tipo DELE escrevendo Itá? E consegue escrever, em Itá, o que o compilador dá ao built-in?**

São **duas faces**, e as duas precisam passar:

| Face | Pergunta | Falha em |
| :-: | :-- | :-- |
| **1** | Poder que o **tipo do usuário** não alcança | `for` sobre `List` via tabela: o `MyType` dele **nunca** ganha `for`, e nenhuma linha de Itá conserta. **Privilégio ⟹ mágica.** A cura que o dono mandou (trait `Iterator`) é exatamente a que **abre** o poder |
| **2** | Poder sobre o **built-in** que só o compilador tem | o compilador dá `.map` a `List` e o usuário não pode dar. **É a face que o ruling §12-1 tornou load-bearing** — e é o que o `extension List<T>` (§2.1/§12-B1) decide |

> ⚠️ **Por que a face 2 é obrigatória:** sem ela o teste **absolve** `List.map` hard-coded — *"o usuário põe `.map` no `MyStack` dele, não há lacuna de poder"* — e absolveria **errado**. A face 1 sozinha não vê o privilégio que o ruling 1 criou.

- `.length` no chão → passa nas duas: o tipo do usuário tem campo e `extension` (face 1), e o chão tem **destino `.tu` escrito** (face 2 — §3.3-3).

Mesma forma do ruling R5 da 009: *"overload é o que torna built-in não-privilegiado; **recusar** overload é que seria a mágica."* **A tabela é detalhe de implementação; o privilégio é o pecado.** O que tornou a do oracle indefensável não foi ser tabela — foi ser **aberta e silenciosa**: `_inferMember` → `UnknownType` sem erro → dynamic get → **erro em runtime**.

### 3.3 As três condições do débito (forma-M5)

Uma tabela hard-coded é legítima **se e só se** as três valerem. O precedente é do dono (`Ops(sym)` → M5) e o destino é Art. II (`MANIFESTO:50`: *"built-ins hoje embutidos no codegen **migrados para `.tu`**"*).

1. **FECHADA** — conjunto enumerado na spec, não extensível por conveniência.
2. **ERRA no desconhecido** — `unknown-member`, **nunca** `UnknownType` silencioso (ADR-0013 §1/§4/§5 + P4).
3. **DESTINO `.tu` escrito** — a spec diz o que ela vira quando morrer.

### 3.4 Leis herdadas (não são escolha desta spec)

- **Não estender `_addBuiltinMethod`, nem criar tabela de método no codegen.** O ADR-0013 ordenou o inverso: *"`Option`/`Result` … devem migrar para a tabela de tipos da F5 — senão o vazamento sobrevive à reescrita e a F7 continua dona do conhecimento de tipo."* Crescer aquilo é engordar o vazamento que ele mandou fechar.
- **Membro desconhecido = ERRO.** Nunca `UnknownType`.
- **Um marcador de intrínseco JAMAIS pode ser `@intrinsic`/`@extern`.** **P6 é permanente:** *"`@decorators` nunca serão implementados"*. Se um dia entrar, é **keyword**, e é conversa do **M5** — não desta spec. (Metade das formas óbvias de "marcador" é inconstitucional de saída.)

---

## §4 Especificação formal — `[cap 5.1, 5.2, 6.3.6, 6.5.1]`

### 4.1 Formas *checking-only* — **1 regra, 4 literais**

> **Definição.** Uma forma é ***checking-only*** quando **não tem regra de síntese**: ela só existe no modo `⇐`.

**Uma regra, DOIS fundamentos** — e a distinção não é pedantismo, é o que mantém o `.variant` defensável:

| Forma | Regra | Falha | **Fundamento** |
| :-- | :-- | :-- | :-- |
| `[]` | `Γ ⊢ [] ⇐ List<T>` | `cannot-infer` | **6.5.1 — vacuidade** |
| `{}` | `Γ ⊢ {} ⇐ Map<K,V>` | `cannot-infer` | **6.5.1 — vacuidade** |
| `nil` | `Γ ⊢ nil ⇐ OptionalType(T)` | `nil-under-non-optional` (009 §4.6) | **§4.9 — o glifo pede** |
| `.v` | `Γ ⊢ .v ⇐ E`, `v ∈ Σ(E)` | `cannot-infer` (sem contexto) / `unknown-variant` | **§4.9 — o glifo pede** |

**Fundamento A — vacuidade (definicional, `[]`/`{}`).** Dragon **6.5.1**: a síntese *"constrói o tipo de uma expressão a partir dos tipos de suas **subexpressões**"*. `[]` tem **zero** subexpressões ⟹ **não há de que construir**. Síntese é **indefinida** ali; não é escolha. (Dar `List<α>` seria 6.5.4 + let-generalization = **HM**, recusado pela 009/ADR-0013.)

**Fundamento B — o glifo pede (política, `nil`/`.variant`).** ⚠️ **Aqui a vacuidade é FALSA como razão, e usá-la nos desarmaria.** `.v` também tem zero subexpressões, mas não é por isso que ele não sintetiza: é porque **o nome da variante não determina o enum**. Se apenas um enum no escopo tivesse `.none`, a síntese seria **possível** — linguagens fazem isso. **Não fazer é política**, e é a política certa: **§4.9 — o `.` é o glifo cuja única função é delegar ao contexto.** (`nil` é o mesmo caso, não o de `[]`: pelo ruling do dono de 2026-07-12, `T?` é `Option` e `nil` é `.none` — **a variante é conhecida; o tipo não**.)

> **Por que a distinção importa.** Escrito como "definicional", o `.variant` fica **indefensável** no dia em que alguém propuser *"só um enum tem `.none`, deixa sintetizar"* — o argumento da vacuidade **não barra isso**. O da §4.9 barra. Seria trocar o escudo forte pelo fraco justamente na forma que mais precisa dele.

Em modo `⇒` **as quatro produzem `cannot-infer`** (ADR-0013) — a regra é **uma**. O livro **não tem literal de coleção vazia** (lacuna declarada), mas o padrão já está implementado: o `nil` da 009 **é** esta regra.

**Empírico (`compiler-craftsman`):** **25+ `[]`/`{}` na stdlib, 100% sob anotação** (`var result: List<List<T>> = []`; `self.inbox = []` — campo com tipo declarado). **Zero contraexemplos.** `let x = []` → `cannot-infer` não custa nada real.

> **`[]` não precisa da fatia D.** Em `chunk<T>`, o `T` de `List<List<T>>` é `TypeParamType` **rígido**, não `TypeVar` ⟹ é **puro check-mode, sem unificação**.

**CA38 da 009 continua:** `var r: Option<Response> = .none` ⟶ ok. É o contraste deliberado com `p + q` (§0.5).

### 4.2 Closures — **metade SINTETIZA; só a outra metade é contextual**

> ⚠️ **Esta seção foi reescrita contra o parser e o checker REAIS** (2026-07-15). A versão anterior dizia "closure é contextual" por atacado, e estava errada nos dois eixos: no que **parseia** e no que **precisa** de contexto.

#### 4.2.1 A regra: o gatilho é a **anotação dos params**, não a forma

```
todos os params têm tipo (inclusive ZERO params)
──────────────────────────────────────────────────  SÍNTESE
Γ ⊢ (x: T₁, …) => e  ⇒  (T₁,…,Tₙ) → synth(e)

algum param SEM tipo
────────────────────────────────────────────────── CHECKING-ONLY
Γ ⊢ (x, …) => e ⇐ (T₁,…,Tₙ) → U     params.type := herdado
```

É a divisão bidirecional clássica (Pierce & Turner §3): **o que não tem buraco, sintetiza.** Só o param sem tipo é o buraco que o contexto preenche.

**O estado de HOJE (verificado, `itac check`):** `Closure` **não é tratado no `_synth`** — cai no default e **tudo** vira `cannot-infer`, inclusive o que não precisa de contexto nenhum:

| Código | Hoje | Correto |
| :-- | :-- | :-- |
| `let c = (x: Int) -> Int => x` | `cannot-infer` | **`(Int) → Int`** — totalmente anotado; um "não consigo" **falso** |
| `let c = () => 5` | `cannot-infer` | **`() → Int`** — zero params, corpo sintetiza |
| `let c = (x: Int) => x` | `cannot-infer` | **`(Int) → Int`** |
| `let c: (Int) -> Int = (x) => x` | `cannot-infer` | **ok** — a anotação é o contexto; `x : Int` |
| `let c = (x) => x` | `cannot-infer` | **`cannot-infer`** — certo, mas **por acidente** (default), não pela regra |

**Aridade** da forma-chaves vem do scan sintático da F3 (`$0..$n`, normalizado, teto `$255` no léxico). Divergência ⟶ `closure-arity-mismatch`.

#### 4.2.2 As duas formas têm ALCANCE SINTÁTICO diferente — e isso é normativo

Verificado no parser (`itac parse --dump`), **não** inferido da gramática:

| Forma | Onde parseia | Evidência |
| :-- | :-- | :-- |
| **chaves** `{ $0 }` | **só** trailing, **só** último arg, **só** depois de `f(…)` | `find(xs, { $0 > 2 })` ⟶ `(error-expr)` + `parse-error`; `find(xs) { $0 > 2 }` ⟶ ok |
| **arrow** `(x) => x`, `() => 5` | **qualquer** posição de expressão | `let c = (x) => x` ⟶ `(closure (params (param "x")) (id x))` |

⟹ **`{ $0 }` NUNCA aparece fora de trailing.** `let c = { 42 }` e até `let c: (Int) -> Int = { $0 }` **não parseiam** — a forma-chaves não existe em posição de inicializador. Consequência dupla:

1. **A forma-chaves é L-atribuída por construção** (§5.2) — sempre o último arg, contexto sempre à esquerda.
2. **A forma-arrow é o ÚNICO buraco** — `f((x) => x*2, xs)` **parseia** com o param sem tipo na 1ª posição. **É o Ex. 5.9 vivo, e é o único caso que justifica as 2 rodadas do §4.3.**

> ⚠️ **Hazard verificado — `f { $0 }` sem parênteses.** Parseia como `(id f)` **seguido de um bloco solto**: `(let (bind "r") (id f)) (block (expr-stmt (id $0)))`. **Dois statements, não uma chamada** — silenciosamente. Não é problema desta spec (é sintaxe), mas fica registrado: sob ADR-0013 o `let r = f` vai dar erro de tipo, o que ao menos é alto. **§12-E.**

**Params com tipo explícito** contra um esperado divergente ⟶ `param-type-mismatch`.

**Retorno:** no modo `⇐`, o corpo é checado contra `U` — é o que faz o corpo `nil`/`[]`/`.variant` funcionar.

**A restrição que o livro impõe, e que eu havia omitido** (5.1.1, primeira metade da frase — a segunda é a que a 009 §5.1 cita):

> *"Embora **não permitamos que um atributo herdado no nó N seja definido em termos dos valores dos atributos de seus filhos**, permitimos que um atributo sintetizado no nó N seja definido em termos dos valores dos atributos herdados do próprio nó N."*

⟹ **`Closure.expected` NÃO pode ser definido olhando o corpo da closure.** Proíbe o hack tentador de "espiar o corpo para descobrir o tipo do param". **Normativo.**

**Params com tipo explícito** (`(x: Int) => …`) não herdam: são verificados contra o esperado (`param-type-mismatch`). Params **sem** tipo herdam — `param = IDENT IDENT? ( ":" type )?`, o tipo é opcional.

**Retorno:** o corpo é checado contra `U` (`⇐`), não sintetizado-e-comparado — é o que faz `{ $0 }` com corpo `nil`/`[]`/`.variant` funcionar.

**Corner aberto — ruling pendente (§12-A):** `{ 42 }` (sem `$k`) sai da F3 com `params = const []` = **aridade 0**; contra `expected = (T)→U` dá mismatch. É `closure-arity-mismatch`, ou params implícitos são ignorados (Kotlin: `it`; Swift: erro)?

### 4.3 Ordem dos argumentos — **2 rodadas**

Tipar `$0` em `f(xs, { $0*2 })` com `f<T,U>(list: List<T>, g: (T)→U)` exige `T:=Int` **antes** de descer na closure.

| Rodada | Quem | Modo |
| :-: | :-- | :-- |
| **R1** | args com **regra de síntese** | `_synth` + `unify` contra o param |
| **R2** | formas ***checking-only*** (§4.1) + closure sem tipos | `_check` contra o param **já substituído** |

`TypeVar` não resolvida ao fim de R1 ⟹ `cannot-infer` **naquele arg** (não no call inteiro).

> O critério é **sintático** (a forma de introdução), não "closures por último". Fica explicável em uma frase e estável.

**Custo aceito:** os diagnósticos saem **fora da ordem textual** ⟹ **ordenar por offset antes de reportar** (a ordem-fonte é a que o usuário lê — já é o contrato da 009 §11).

**Alternativas recusadas:** *textual com adiamento* colapsa em (a) quando o adiamento é "tudo que não sintetiza" — e vira **worklist até ponto-fixo**, que **quebra o 1-walk** (§5.2); *constraint-solving global* (Swift antigo) é ponto-fixo sobre grafo — é de onde vem o `expression too complex`, e a doutrina L-atribuída o rejeita.

> ⚠️ **Bug a corrigir — `check.dart:405`:** `final argTs = [for (final a in n.args) _synth(a.value)]` sintetiza **todos** os args antes de unificar ⟹ **closure nunca recebe contexto**. **`_call` é reescrita obrigatória desta spec.**

### 4.4 `CopyWith` — `s.{ campo: v }`

Tipo do resultado = **tipo do receptor** (`s`). Cada override é checado (`⇐`) contra o tipo **declarado do campo**. Exige enumerar campos por tipo = **`record(t)`** (Dragon **6.3.6**: *"um tipo registro tem a forma record(t), onde t é um objeto de tabela de símbolos"*) — que a fatia A **já construiu** (`TypeInfo.fields`).

Erros: `unknown-field` (label não existe), `type-mismatch` (valor não casa), `copywith-on-non-aggregate`.

> Contraste com o oracle (`_inferCopyWith`, `type_checker.dart:204`): ele erra *"só quando o label claramente não existe — conservador"*, e nunca checa o **valor**. Aqui os dois são erro (ADR-0013).

### 4.5 Leitura de campo — `p.x`

```
Γ ⊢ p ⇒ NamedType(D, …)   x ∈ fields(D)
─────────────────────────────────────────
Γ ⊢ p.x ⇒ fields(D)[x]  (com type-args substituídos)
```

**É a MESMA `record(t)` do §4.4** — por isso entra aqui, não na 011: o custo já está pago. Campo inexistente ⟶ `unknown-member` (**não** `UnknownType`, §3.4).

**O que fica na 011:** dispatch de **método** (walk de traits/superclasse). Este é o delta real.

`member-on-optional` (009 §4.6) continua: `T?` tem **Σ_membros = ∅**, e o erro nasce no `.foo()`, ensinando `if let`.

### 4.6 O chão — **duas listas, dois critérios, dois destinos**

> ⚠️ **REESTRUTURADO em 2026-07-15.** A versão original era **uma** tabela de membros com `.length`/`.slice`/`String.length`/`Map.keys()`, e tinha **dois defeitos graves** — os dois apanhados pelo `ita-visionary`:
> 1. **O critério vazou.** `.slice` **não é chão**: é derivável de `[]` + `+` + `.length` — o laço é literalmente o de `chunk`/`take`/`window`, que estão em `.tu`. Pela **Prova 1 do §3.1**, `slice` é **biblioteca**. Ele estava lá porque `iter.tu` o chama **como membro** e a 010 não tem member dispatch: razão **pragmática**, não critério. Com ele dentro, o critério de adesão vira ***"a stdlib chama"*** — que é **ABERTO**, e a condição FECHADA (§3.3-1) perde os dentes. **É o erro de categoria do §3 renascendo dentro do §4.**
> 2. **A tabela perdeu `[]` e `+`** — os dois mais usados — porque a **forma** "tabela de membros" não comporta índice nem operador. O §1.1 lista o chão certo; a tabela encodava 2 dos 4 e completava com 2 impostores. **O chão tem TRÊS formas sintáticas (membro, índice, operador); enquadrá-lo como tabela de membros fez 50% dele sumir.**

#### 4.6.1 CHÃO — irredutível

**Critério:** não é derivável em Itá; **tem** de tocar o Dart. **Destino:** `dart:` explícito no **M5** — **nunca some**, muda de forma.

| Forma | Regra | Uso real |
| :-- | :-- | :-- |
| `List<T>.length` / `String.length` | `⇒ Int` | `iter.tu` (quase toda fn); `server.tu:428` (`queryString.length == 0`); `log.tu:70-71` |
| `xs[i]` — **índice** | `List<T> × Int ⇒ T` | `iter.tu`, difuso. ⚠️ **Nenhuma regra existe hoje** — grep `Index` em `check.dart`: **zero** |
| `+` — **concat** | `List<T> × List<T> ⇒ List<T>` | `iter.tu`, difuso. ⚠️ **Não existe** — `check.dart:49` só tem triplas **concretas** (`Int,Int,Int`…); `List<T>+List<T>` é **genérico** ⟹ **muda a FORMA do `_primitiveOps`**, não só o conteúdo |

#### 4.6.2 COMPAT-STDLIB — biblioteca com sintaxe de membro

**Critério:** é **biblioteca** (derivável), mas entra por **expediência**, porque a stdlib a chama como membro e a 010 não tem member dispatch. **Destino:** `extension` em `.tu` na **011** — **some**.

| Membro | Tipo | Uso real |
| :-- | :-- | :-- |
| `List<T>.slice(Int, Int)` | `List<T>` | `chunk`, `window` |
| `List<T>.set(Int, T)` | `List<T>` | `iter.tu:177` |
| `Map<K,V>.keys()` | `List<K>` | `config.tu:94` |

> **Destinos diferentes ⟹ seções diferentes.** É a **condição 3** (§3.3-3: destino escrito) cobrando. Uma lista só, com destinos distintos, é como o critério se dissolve.

**Fora das duas ⟶ `unknown-member`.** É o que separa isto da tabela do oracle (condição §3.3-2).

> ⚠️ **§4.6.1 já mistura duas grafias** — `.length` sem parênteses, `.keys()` com. **Decisão tomada por acidente**, e é o §12-B2. Não é cosmética: se `extension List<T>` só declara `fn`, então `.length` parenless é membro que o usuário **NÃO consegue escrever** ⟹ **face 2 do privilégio** (§3.2) outra vez.

---

## §5 SDD — `[cap 5.1, 5.2]`

### 5.1 A SDD é **L-atribuída** — 5.2.4(b), verbatim

> *"(b) Os atributos herdados **ou sintetizados** associados às ocorrências dos símbolos X1, X2, …, Xi-1 localizados **à esquerda** de Xi."*

Em `Call → callee arg₁ arg₂`, a regra `arg₂.expected = σ(params[2])` usa `callee.type` (X1) **e** `arg₁.type` (X2). **Ambos irmãos à esquerda, ambos sintetizados** — e 5.2.4(b) admite *sintetizados de irmãos à esquerda* explicitamente. Grafo acíclico ⟹ **1 walk, sem ponto-fixo** (5.2.2).

### 5.2 ⚠️ L-atribuição é propriedade da **ORDEM DOS ARGUMENTOS**, não da linguagem

O **Exemplo 5.9** é o contraexemplo exato:

> *"`A→BC`, `B.i = f(C.c, A.s)` — a SDD **não pode ser L-atribuída**, pois o atributo C.c é usado para ajudar a definir B.i, e **C está à direita de B**."*

Isso é `f((x) => x*2, xs)` letra por letra.

**O Itá é L-atribuído POR CONSTRUÇÃO DA GRAMÁTICA** — não por sorte:
- `{ $0 }` **só parseia como trailing closure** (`primary`, GRAMMAR §4.1:198-208 não tem alternativa de `{`; `mapLiteral` exige `:`). **`find(xs, { $0 > 2 })` não parseia.**
- `parser.dart:1234` — `args.add(Arg(null, _trailingClosure()))` — **anexa como último arg**.
- stdlib: **18 HOF, zero exceções**. Grep por closure-param-seguido-de-vírgula: **zero matches**.

**O único buraco:** `param = IDENT IDENT? ( ":" type )?` — o tipo é **opcional** ⟹ `(x) => x*2` precisa de contexto e **pode ir em qualquer posição**. É o Ex. 5.9 vivo, e é **o único caso que justifica o §4.3**.

**Circularidade real:** `f<T,U>(a: (U)→T, b: (T)→U)` é ciclo genuíno. **5.1.2 nota 1** avisa que detectar circularidade é **exponencial**. ⟹ **Não detectar.** Estratégia fixa (§4.3) + `cannot-infer`.

### 5.3 Efeitos colaterais controlados — **5.2.5** é a fundação, não 6.5.5

O store da unificação **é efeito colateral**. 6.5.5 é o Alg. 6.19 (unificação pura) e 6.8 é codegen de switch — **nenhum dos dois cobre ordem de checagem**. O livro dá duas disciplinas e a nossa é a **segunda**:

> *"Restringir as ordens de avaliação permitidas, de modo que a mesma tradução seja produzida por qualquer ordem permitida. As restrições podem ser consideradas **adicionando arestas implícitas no grafo de dependência**."*

**Não** é a primeira (Ex. 5.10, `addType`, é order-independent: *"as entradas podem ser atualizadas em qualquer ordem"*). Unificar-e-descer-no-corpo **não é**. ⟹ **Esta spec declara as arestas implícitas** (§4.3), senão a SDD fica **subdeterminada**. Ordenar args = ordenação topológica (5.2.2) e **continua 1 walk** (cada nó 1×, só não da esquerda para a direita).

> **Lacuna declarada:** o Dragon **não cobre** ordem de args em checagem bidirecional — e **não poderia**: 6.5.4 é HM, e **HM não tem esse problema** (o param do lambda ganha α fresca, o corpo infere contra α, contexto zero). **O problema é criado pelo modo `check`.** Fontes reais: Pierce & Turner, TOPLAS 2000 §3; Dunfield & Krishnaswami, *Bidirectional Typing* (ACM Comput. Surv. 2021). ⚠️ **Nenhum dos dois está em `references/`** — não citar normativamente sem obter.

---

## §7 Contrato F5 → F7 (codegen)

### 7.1 `interfaceTarget` é **obrigatório** — a pergunta não tem meio-termo

```dart
// pkg/kernel/lib/src/ast/expressions.dart:551-596
class InstanceGet extends Expression {
  DartType resultType;                  // "includes substituted type parameters from the static receiver type"
  Reference interfaceTargetReference;   // <- NON-nullable
  InstanceGet(kind, receiver, name, { required Member interfaceTarget, required DartType resultType })
```

E o verifier cobra (`verifier.dart:1604-1651`): `isInstanceMember`, `enclosingClass != null`, `node.name == interfaceTarget.name`, e recusa `RepresentationField` como alvo.

⟹ **"E se o `interfaceTarget` ficar nulo?" não é pergunta com resposta — o nó não se constrói.** A escolha real é **`InstanceGet` vs `DynamicGet`** (o nó de fuga, onde o oracle está hoje).

**Consequência direta para o chão (§4.6):** para emitir `InstanceGet` sobre `dart:core::List`, a semântica precisa do **`Member` real** — não do nome, do `Reference` para o `Procedure`. Isso significa **carregar o `.dill` da platform e resolver a superfície do `dart:core`**. Não há meio-termo: ou conhece o membro, ou emite `DynamicGet`. **A VM exige; se o Itá reusa `dart:core::List` é decisão nossa — mas se reusar, conhecer a superfície é obrigatório, não otimização.**

### 7.2 Closures no Kernel — **o Kernel nunca força honestidade, só preenchimento**

```dart
PositionalParameter({ required this.type, … })              // DartType non-nullable
LocalVariable({ required DartType? type, … }) : type = type ?? const DynamicType()
FunctionNode(this._body, { this.returnType = const DynamicType(), … })
```

Não existe "tipo ausente" — existe `const DynamicType()`, e é o **default** do `FunctionNode.returnType`. O verifier **não confere acurácia** de tipo de param (confere `interfaceTarget`, aridade de type-args). **Quem garante é o frontend.**

> **Calibração importante — o ganho da fatia C é o CORPO, não a chamada.** A unboxing info é **Member-only** (`type_flow/transformer.dart` chaveia por `Member`); não há registro para `FunctionExpression` — **closure é chamada por convenção genérica**. Com `$0 : dynamic`, `$0 * 2` é `DynamicInvocation('*')`; com `$0 : Int`, é `InstanceInvocation(interfaceTarget: dart:core::int::*, functionType: (num)→int)` ⟹ a VM reconhece `int::*` e compila **aritmética unboxed**.

⚠️ **Débito novo (D1 corrigido):** em 3.12.2 `VariableDeclaration` virou **`sealed`** (`variables.dart:75`) com `LocalVariable` / `VariableStatement` / `CatchVariable` / `PositionalParameter` / `NamedParameter` / `ThisVariable` / `SyntheticVariable`. O codegen tem de **dispatchar por subclasse** — param **não** é local.

### 7.3 `**` — `dart:math::pow` é **proibido** (ruling §12-3)

Fatos (`dart-vm-expert`, verificados no SDK):
- **`num` não tem `operator **`** — não há primitivo no Kernel.
- `dart:math`: `external num pow(num x, num exponent)`. Doc: *"If [x] is an [int] and [exponent] is a non-negative [int], the result is an [int], otherwise both arguments are converted to doubles first, and the result is a [double]."*
- `_intPow` tem **corpo Dart puro** (exponenciação por quadrados); `_doublePow` é external. Ambos em `recognized_methods_list.h`, mas **o `pow` público não é recognized**.

**Por que proibido:** o tipo estático de `pow(...)` é **`num`** ⟹ `_getUnboxingType` não concede `kInt`/`kDouble` ⟹ **`kBoxed`**. Para voltar a `Int`, o codegen emitiria `AsExpression` → `AssertAssignable`. **Zero coerção (009 §4.5) já nos tirou do `num`; reusar `pow` nos devolve para lá.**

**Contrato:** F7 emite **`intPow(Int, Int) -> Int` própria** — o mesmo laço, tipado, unboxed, sem passar por `num`. **Não se perde nada:** `_intPow` também é só Dart, não há mágica de VM a herdar. **Expoente negativo ⟶ panic** (erro de programador, P7).

### 7.4 `CopyWith` — P7 mantém o allocation sinking ligado

`s.{ campo: v }` é `ConstructorInvocation` → `AllocateObject` no heap (não há tipo-valor multi-campo no Kernel; `struct` é classe no heap).

**Não existe** reconhecimento do padrão "copiar e trocar um campo". Mas existe **`AllocationSinking`** (backend IL, **roda também em AOT**, intra-procedural, pós-inline) — e ele tem uma condição que vale ouro:

```cpp
// runtime/vm/compiler/compiler_pass.cc
COMPILER_PASS(AllocationSinking_Sink, {
  // TODO(vegorov): Support allocation sinking with try-catch.
  if (flow_graph->try_entries().is_empty()) {
```

**Sinking é desligado inteiro em qualquer função com try/catch.** O Itá, por **P7**, não emite `TryCatch` (`Throw` não cria try_entry — só *catch* cria) ⟹ `try_entries()` fica vazio e **o pass permanece ligado nas funções do Itá**.

> **Na ordem certa (§8.3 da 009):** **P7 é a razão**; o backend **reforça**. Não o inverso.

⚠️ **Não verificado:** se a transformação `async` da VM introduz `try_entries` — o que reintroduziria o problema justo onde não se vê. **Medir**, não estimar.

---

## §8 Runtime — o que a VM ENTREGA e EXIGE `[dart-vm-expert, 2026-07-15]`

> **Retrato** do vendor `ita/third_party/dart/3.12.2/pkg/kernel` (Kernel 130). **Datado, não lei.**

### 8.1 Correção ao modelo mental do projeto: `dynamic` **não** impede devirtualização em AOT

`pkg/vm/lib/transformations/devirtualization.dart` **visita os nós `Dynamic*`** (`visitDynamicInvocation`, `visitDynamicGet`, `visitDynamicSet`). A TFA devirtualiza por **dataflow**, não pela anotação estática — um `DynamicGet` monomórfico no mundo fechado vira chamada direta igual.

**O ganho do tipo está em outro lugar: precisão do conjunto de alvos** (`type_flow/analysis.dart::_collectTargetsForSelector`):

| Selector | Conjunto inicial de alvos |
| :-- | :-- |
| `InterfaceSelector` | `receiver.intersection(member.enclosingClass.coneType)` — **podado pelo cone do tipo estático** |
| `DynamicSelector` | `hierarchyCache.getDynamicTargetSet(selector)` = **todo membro com aquele `Name` no programa inteiro** |

⟹ `list.length` como `DynamicGet` não é "não devirtualiza" — é *"o conjunto parte de toda classe do mundo fechado que tem getter `length`"*, e a TFA tem de estreitar sozinha. **Tree shaking** é o custo mais subestimado: `DynamicSelector` **retém** todos os N homônimos (tamanho de binário, não só velocidade).

**Bloqueio que amarra nulidade a perf:** `_handleMethodInvocation` exige `!hasExtraTargetForNull(directCall)` — **receptor potencialmente nulo adiciona alvo e mata a devirtualização**. (Reforço do invariante de nulidade; não sua razão.)

### 8.2 Assimetria JIT × AOT — a que o ADR-0007 não pode ignorar

**JIT não tem TFA.** O dispatch é inline cache (`UntaggedICData`), que estoura para `MegamorphicCache`. ⟹ **boa parte da devirtualização que se espera só existe em AOT**; em JIT o tipo estático ajuda menos (o IC aprende sozinho) e o ganho vem do **corpo** e do unboxing dos Members. `DelayAllocations` idem: **AOT-only** (`INVOKE_PASS_AOT`).

### 8.3 Doutrina — a ordem dos argumentos nesta seção

> **O princípio é a razão; o dado da VM é o REFORÇO.** (§8.3 da 009, fechada com o dono.) Nenhuma regra desta spec está pendurada em custo de VM.

⚠️ **Citação retirada:** *"dynamic calls always use boxed values"* (`unboxing_info.dart`) **não foi reconfirmada** — o fetch devolveu paráfrase. A substância se sustenta pela lista `_cannotUnbox` (natives, entrypoints, `isDynamicallyOverriddenMember`, `hasDisableUnboxedParameters`), mas **não citar entre aspas** sem reverificar a linha. **Corrige a 009**, que a usa.

---

## §9 Checklist de completude

1. **A máquina contextual fecha sem member dispatch.** Teste de desacoplamento: `find(xs) { $0 > 2 }` — trailing closure anexa como último arg de um `Call` sobre **função livre** (`parser.dart:1234`), exercita `expected` herdado + as 2 rodadas + `.variant`, **sem tocar em member**.
2. **A leitura de campo (§4.5) e o CopyWith (§4.4) compartilham `record(t)`** — não há custo duplicado.
3. **O chão (§4.6) é ortogonal à máquina contextual** — entra por causa da stdlib (§1.3), não por dependência técnica.
4. **`.variant` já força a side-table de resolução** — a mesma que member preencheria na 011.
5. **A máquina contextual é INDIFERENTE à forma da chamada** — e é isto que faz a 010 sobreviver ao ruling §12-1. `xs.map { $0*2 }` e `map(xs, { $0*2 })` pedem **a mesma coisa**: o tipo esperado desce nos params da closure. O que muda é só **de onde vem a assinatura** — membro (011) ou função livre (010). ⟹ **A 010 não ensina um dialeto que a 011 desensina**; ela constrói a máquina sobre a única fonte de assinatura que existe hoje, e a 011 pluga outra fonte **na mesma máquina**. Closure passada a função livre continua legal para sempre — código de usuário faz isso.

---

## §11 Critérios de aceite (viram `conformance/check/*.tu`)

**Flagship** (ruling §12-1 tirou o `xs.map`): código **real** da stdlib — `iter.tu:198`

- **CA40** — `quickSort(list, (a, b) => keyFn(a) - keyFn(b))` ⟶ `a`/`b` herdam `T` da assinatura; tipa. **Closure real, função livre anotada, código que existe.**
- **CA41** — `dobra(xs) { $0 * 2 }` com `dobra(xs: List<Int>, f: (Int)→Int)` ⟶ `$0 : Int`. ⚠️ **Corrigido:** a versão original era `dobra(xs, { $0*2 })`, que **não parseia** (§4.2.2).
- **CA42** — `let c = (x) => x` (sem contexto, param sem tipo) ⟶ `cannot-infer`. ⚠️ **Corrigido:** a versão original era `let x = { $0*2 }`, **inalcançável** — a forma-chaves não parseia em inicializador (§4.2.2).
- **CA42b** — `let c: (Int) -> Int = (x) => x` ⟶ **ok**, `x : Int`. *(Hoje: `cannot-infer` — é o bug que a fatia C mata.)*
- **CA42c** — `let c = (x: Int) -> Int => x` ⟶ **`(Int) → Int` por SÍNTESE**, sem contexto. *(Hoje: `cannot-infer` falso.)*
- **CA42d** — `let c = () => 5` ⟶ **`() → Int` por síntese** (zero params).
- **CA43** — `var r: List<Int> = []` ⟶ ok; `let x = []` ⟶ `cannot-infer`.
- **CA44** — `var m: Map<String, Int> = {}` ⟶ ok. *(Verificado: `{}` parseia como `(map)` — map vazio, **não** bloco. Fecha o §12-C.)*
- **CA45** — `var r: Option<Response> = .none` ⟶ ok (CA38 da 009, agora executável).
- **CA46** — `.naoExiste` contra enum sem a variante ⟶ `unknown-variant`.
- **CA47** — `p.{ x: 1 }` com `p: Point` ⟶ `Point`; `p.{ z: 1 }` ⟶ `unknown-field`; `p.{ x: "s" }` ⟶ `type-mismatch`.
- **CA48** — `p.x` ⟶ tipo do campo; `p.zz` ⟶ `unknown-member`.
- **CA49** — `list.length` ⟶ `Int` (chão); `list.naoExiste` ⟶ `unknown-member`.
- **CA50** — `f(xs, { $0 })` onde `T` fica livre ⟶ `cannot-infer` **naquele arg**, com offset do arg.
- **CA51** — diagnósticos de call saem em **ordem-fonte** apesar das 2 rodadas (§4.3).
- **CA52** — `(x: String) => x` contra `(Int)→Int` ⟶ `param-type-mismatch`.
- **CA53** — ⚠️ **ENCOLHIDO 2026-07-15 — a versão original era INATINGÍVEL POR CONSTRUÇÃO.** Ela dizia *"`stdlib/iter.tu` tipa inteiro"*, mas `iter.tu` usa `for item in list` em **17 funções**, e tipar o binder do `for` é **não-objetivo desta spec** (§1.4-2). **A CA exigia o que a spec proíbe** — e ainda dependia de `[]`/`+`/`.set`, que não existem (§4.6.1). *Uma CA que não pode passar não é gate; é dívida disfarçada de checkbox.*
  **Fica:** as funções de `iter.tu` **sem `for`** (as de `while`) tipam — `chunk`, `window`, `zip`, `intersperse`, `interleave`, `take`, `skip`, `maxBy`, `minBy`, `sortBy` — **condicionado** a `[]` (§4.1) e `+` de `List` (§4.6.1) entrarem. **Pré-requisito:** `iter.tu` precisa migrar do dialeto antigo (4 erros de parse: usa `if c { a } else { b }` como expressão; a forma real é `if c => a else b` — RD-1). **Isso não é trabalho desta spec.**

> ⚠️ **Nota de validade — CA40 e CA53 serão REESCRITOS pela 011, e isso não é regressão.** Os dois vivem em `iter.tu`, que o **ruling §12-1 agendou para demolição**: `sortBy` (a linha do CA40) vira `extension List<T>`. Os CAs valem pela **máquina que exercitam**, não pela linha que citam. Quando a 011 os quebrar, é migração — não regressão.

---

## §12 Rulings

### Fechados (dono, 2026-07-15) — ver §2

1. **`.map` em container é o idioma** ⟹ CA15 → 011.
2. **Escopo = contextual + campo + chão.**
3. **`Int ** Int -> Int` com panic no negativo**; `intPow` própria.

### Pendentes

| # | Pergunta | Quem decide |
| :-: | :-- | :-- |
| ~~**A**~~ | ✅ **FECHADO 2026-07-15 — e quem o respondeu foi a própria F3, não eu.** A premissa da pergunta estava errada: eu disse *"a F3 emite `params = const []` (aridade 0); contra `(T)→U` dá mismatch"*. **A F3 emite params vazios de PROPÓSITO, e o comentário dela é normativo:** *"SEM `$k`: mantém implícita (aridade genuinamente contextual, ex.: `map { g() }` **exige 1 arg mas usa 0 — forçar arity-0 seria errado**)"* — e a spec do desugar concorda (*"aridade é contextual → Fase 5"*). ⟹ **Closure sem `$k` ADOTA a aridade esperada** (`hasExplicitParams: false`); tratá-la como aridade 0 na F5 desfaria a decisão da F3 no andar de cima. **Com `$k`, a aridade do scan vale** ⟹ `dobra(xs) { $0 + $1 }` é `closure-arity-mismatch`. *(Nota do `ita-visionary` verificada de todo modo: a grafia de closure constante existe — `(x) => 0` parseia; `(_) => 0` não, pois `_` só é `pattern`.)* | — |
| ~~**B1**~~ | ✅ **FECHADO 2026-07-15 — RATIFICADO.** `extension List<T>` sobre built-in genérico **é legal**. ⟹ O **ruling §12-1 é viável** e não volta à mesa; e a 011 tem caminho para `map`/`filter`/`fold` **e** para migrar os 5 métodos hard-coded de `Option`/`Result` (§3.1, Prova 2) | — |
| ~~**B2**~~ | ✅ **FECHADO 2026-07-15 — `.length` parenless**, e `extension` **pode declarar campo/getter**. Mantém a grafia que a stdlib já usa. **Verificado no parser:** `extension Foo { let length: Int }` ⟶ `(field "length" (type Int))` ⟹ **o usuário consegue escrever** o que o compilador dá ao built-in ⟹ **passa na face 2 do privilégio** (§3.2). O `Map.keys()` do §4.6.2 fica com parênteses **por ser fn**, não por acidente | — |
| **B3** | ⚠️ **Aberto pelo B2, e é da 011:** `extension Foo { let length: Int }` parseia como **campo**. Mas campo é **armazenamento**, e extension não adiciona armazenamento (Swift proíbe explicitamente *stored properties* em extension). É **campo** (impossível) ou **getter computado** (o que precisamos)? A gramática aceita; a **semântica de `extension` não está decidida** | dono / **011** |
| ~~**C**~~ | ~~Desempate do `{}`~~ — **FECHADO 2026-07-15, verificado no parser:** `{}` ⟶ `(map)` (map vazio) e `{ "a": 1 }` ⟶ `(map (entry …))`. A forma-chaves **não compete** em posição de expressão porque **não parseia** lá (§4.2.2). Sem ambiguidade | — |
| **D** | Fixtures `conformance/desugar/dollar_closure*.tu` usam `xs.map`/`xs.reduce` (membro inexistente). Hoje **não quebram** (o runner da F5 só varre `conformance/check/`), mas é hazard latente. O ruling §12-1 (`.map` é o idioma) os torna **válidos na 011** — talvez a ação certa seja só esperar | técnico |
| **E** | `f { $0 }` (sem parênteses) parseia como `f` + **bloco solto**, não chamada (§4.2.2). É sintaxe (F2), não tipos — mas é uma pegadinha silenciosa que o ruling §12-1 (`.map` em container ⟹ mais trailing closures) torna mais provável | dono / F2 |

---

## Definition of Done

- [x] `_call` reescrito com as 2 rodadas (§4.3) — **o bug do `check.dart:405` morto**
- [~] Formas checking-only (§4.1) — **3 de 4**. ⚠️ **Correção de registro (2026-07-15): este item esteve `[x]` por engano — é a SEGUNDA vez** (a 1ª foi o chão). `nil`/`[]`/`{}` foram entregues; **`.variant` NÃO** — ele estava no `_isCheckingOnly` mas o `_check` não o tratava, então **CA45/CA46 nunca passaram** e `let x: E = .a` dava `cannot-infer`. Descoberto ao implementar a 011 (o flagship dela bate em `.none`) e **entregue lá**
- [x] **Closure SINTETIZA** quando todos os params têm tipo (§4.2.1) — mata os `cannot-infer` **falsos** de `(x: Int) => x` e `() => 5`
- [x] Closure **checking-only** quando algum param não tem tipo (§4.2.1) + `closure-arity-mismatch` + `param-type-mismatch`
- [x] **Aridade contextual** (§12-A): closure sem `$k` adota a esperada
- [x] **Ruling 4** (§2.2): bloco de 1 `ExprStmt` → `ExprBody` na F3 — corpo de `fn` intocado
- [x] **Generics de `fn` em escopo** — gap descoberto na implementação: a A1 só planta cabeça para tipos NOMEADOS, então `fn f<T>(x: List<T>)` dava `unknown-type` no próprio `T` ⟹ **o `instantiate` da fatia D era inalcançável a partir de fonte real**
- [x] `List`/`Map` no chão (§4.6.1) — antes eram `unknown-type`
> ⚠️ **O que a 010 NÃO entregou — registro honesto (2026-07-15).** Os itens abaixo eram escopo declarado e **escaparam**. Verificado: `p.x` ⟶ `cannot-infer`; `p.{ x: 1 }` ⟶ `cannot-infer`; `s.f()` ⟶ `cannot-infer`; `xs.length` ⟶ `cannot-infer`; `xs[0]` ⟶ `cannot-infer`; `xs + xs` ⟶ `no-operator-for-types`. **O `_member` é `cannot-infer` INTEIRO.**
>
> Isso **define a 011** melhor do que a formulação que eu vinha usando ("extension/impl entram na F5"): a unidade indivisível é **`_member` inteiro** — campo, CopyWith, método próprio, extension/impl e herdado saem todos da MESMA `record(t)` (6.3.6). Ver **spec 011**.

- [ ] `CopyWith` (§4.4) + leitura de campo (§4.5) sobre a `record(t)` da fatia A → **migram para a 011**
- [ ] Chão (§4.6.1) — `.length`, **índice `xs[i]`** e **`+` de `List`** (este muda a FORMA do `_primitiveOps`: `List<T>+List<T>` é genérico, e a tabela só tem triplas concretas) → **migram para a 012**
- [ ] Compat-stdlib (§4.6.2) — `.slice`, `.set`, `Map.keys()` → **migram para a 012**
- [ ] `unknown-member` fora das duas listas → **011** (com a ressalva do `builtin-member-unsupported`: sob a 011, `.length` bate no `_member` sem resposta, e `unknown-member` seria **falso** — o membro existe, nós é que não o modelamos)
- [x] Diagnósticos em ordem-fonte (CA51) — e o `checkTypes` **já** ordenava tudo por offset ao juntar `collector.errors` + `c.errors`: a máquina local do `_call` era **redundante** e saiu no `e8a8e79`
- [ ] **As funções de `iter.tu` sem `for` tipam** (CA53 encolhido) — *não* "iter.tu inteiro": o `for` é não-objetivo (§1.4-2)
- [ ] Corpus `conformance/check/` para CA40–CA53
- [ ] §5.4 da 009 corrigida (currying/`**` fora da fatia C)
- [ ] Citação do `unboxing_info.dart` removida da 009 §8 (§8.3)
