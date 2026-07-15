# Spec 009: Fase 5 — Semântica / Tipos

> **Tipo:** feature-fase · **Marco:** `Fase 5 (Semântica) do ita-next` · **Escopo:** fatias **A + B + D** (C → spec 010)
> **Status:** `clarified` — 7 rulings de dono fechados (2026-07-15); ADR-0013 Accepted; 3 reviews de agente aplicados
> **Autor / Data:** orquestração (Claude) · 2026-07-15 · **Fundamentação:** Dragon Book 6.3 (tipos e declarações) + 6.5 (verificação de tipo) + 5.1/5.2 (atributos herdados/sintetizados, L-atribuída); levantamentos `compiler-craftsman`, `ita-visionary` e `dart-vm-expert` de 2026-07-14/15; oracle `ita/compiler/lib/semantic/` (mapeado — **não serve de gabarito nesta fase**, ADR-0013).

## §0 Metadados

- **Classe da mudança:** [x] **Nova regra/fase** — a Fase 5 (Semântica) do ADR-0011: atribui tipo a cada nó, resolve o que é type-directed e impõe o invariante de nulidade. Entre o Binding (Fase 4) e o Fluxo (Fase 6).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [x] **Formal/Tipos (§4)** · [x] **SDD/atributos (§5)** · [ ] Fluxo · [x] **Codegen/IR (§7 — só o contrato)** · [x] **Runtime (§8 — só a dependência)**
- **Princípios afetados:** P4 (sem mágica — é o princípio que decide quase tudo aqui), P6 (infere sem exigir), P7 (`Result`+`?`+panic), P1 (imutável), P2 (valor vs referência), P3 (tudo é expressão). **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

Veredito do `ita-visionary` (2026-07-14), **regra-mãe**: *"a inferência do Itá não atravessa fronteira de declaração; nenhuma conversão acontece sem um glifo que o usuário escreveu."* Reconcilia P6 com P4 — eles não competem: P6 governa **dentro** do corpo (o checker não *exige* anotação para trabalhar), P4 governa a **fronteira** (contrato se escreve). Vereditos:

1. **Inferência: DENTRO infere, BORDA anota** — itaiano. HM global recusada.
2. **Narrowing por binding (`guard let`) é desestruturação, não narrowing** — itaiano. Flow-narrowing (`if x != nil`) é **não-itaiano**.
3. **Coerção: ZERO, nem widening** — P4. (Ver §4.5: o template manda o contrário; é trap.)
4. **Subtipagem nominal declarada; `struct` é final** — P2 (subtipagem de valor = slicing).
5. **Exaustividade é ERRO, não warning** — P3 (`match` é expressão; braço faltando = expressão sem valor).
6. **`?` só sob `Result`; must-use é ERRO** — P7 é P4 aplicado a erro: todo caminho de erro tem um glifo.
7. **Overload de operador: só pelos OPERANDOS** (§4.9) — já decidido em ADR-0012 B8; `+` é enum (A5), não nome, então o F4 #1 não se aplica. E **recusar overload é que seria a mágica**: sem ele, `Int + Int` seria privilégio permanente do codegen, contra o MANIFESTO §Norte.

**Sem conflito de princípio.** Os 7 rulings de dono foram decididos em **2026-07-15** (§12) — **6 fechados** e incorporados; o **§12-7** (`let` sem init) segue **reaberto** (a premissa que o sustentava caiu — ver lá).

## §1 Motivação e resumo

Após o Binding, cada nome sabe a que declaração se refere, mas **nada sabe seu tipo**. A Fase 5 atribui tipo a cada nó, resolve o que é type-directed (`.field`, `.método`, `.variant`, aridade) e é quem finalmente **impõe o invariante de nulidade** (`compiler/docs/spec/nullity-invariant.md`, decisão de dono 2026-07-11) — cujos 4 checkboxes não-marcados são literalmente o mandato desta spec.

É o **P0 do ADR-0007**: *"gerar Kernel tipado é a única alavanca de performance (recupera ~7,7×)"*, e os ~7,7× são *"o custo do dinamismo no AOT"*. Medição do projeto (ROADMAP, PR #6): tipar só os locais deu **~16× no AOT** (2,14s→0,13s) — o TFA da VM devirtualiza quando o receptor tem tipo concreto.

**Antes → Depois** (observável via `itac check`):

```tu
let x: String = nil        // antes: parse+bind limpos, ninguém reclama
xs.map { $0 * 2 }          // antes: o tipo de `$0` não existe
```
```
// depois:
//   nil-under-non-optional @… — `nil` exige um tipo opcional (`String?`)
//   e `$0` tem tipo, então `*` resolve, e o Kernel sai tipado
```

**Escopo (ruling do dono, §12-2): fatias A + B + D** — fecha a nulidade **e P7** (`Result<T,E>` real).

**Não-objetivos:**
1. **Fatia C — contextual** (closures `{ $0*2 }`, `.variant`/`EnumShorthand`, `CopyWith`, currying, `**`): vira a **spec 010**. São os deferidos do ADR-0011. Consequência: **CA15/CA16 migram**.
2. **`for x in xs`** (ruling §12-4): a F5 vê o `ForStmt` mas **não tipa o binder** nesta spec — tipar exigiria tabela hard-coded (`List<T>→T`…), a mágica que §4.5/§8.3 recusam. O trait `Iterator` (`next() -> Option<T>`) entra na spec que fecha D, como decisão de **linguagem**. **Honesto: até lá, `itac check` é incompleto para `for`.**
3. **Exaustividade de `match`** — a *política* é desta spec (é **erro**), a *checagem* é F6 (§4.7 dá o contrato).
4. **Definite-assignment / use-before-assign / unreachable** — path-sensitive → F6.
5. **Narrowing sem binding** (`if x != nil`) → não existe (§4.6).
6. **Emissão de Kernel** → F7 (§7 é só o contrato).
7. **Layout de memória** (Dragon 6.3.4/6.3.5) → **Grupo B**, a VM faz (§5.3).

---

## §4 Especificação formal (tipos e regras) ⭐ — `[cap 6.3, 6.5]`

### 4.1 Expressões de tipo — `[cap 6.3.1]`

`sealed class Type` espelhando o livro (*"um tipo básico ou é formada pela aplicação de um operador chamado construtor de tipo"*):

| Forma | Construtor | Nota |
| :-- | :-- | :-- |
| básico | `IntType`, `FloatType`, `BoolType`, `StringType`, `VoidType` | 6.3.1 (*`void` = "ausência de um valor"*) |
| nome de tipo | `NamedType(decl: AstNode, args: List<Type>, kind: {struct,class,enum,trait,actor})` | **por nó-decl, não por string** — lição da F4 (o Kernel referencia por objeto). O `kind` carrega **valor vs referência** (P2): `struct` = valor, `class`/`actor` = referência — daí `struct` ser final (§4.2b) e habilitar `deeply-immutable` (§8.4) |
| nome **builtin** | `BuiltinType(kind: {option}, args)` | nome **genérico sem nó-decl**. Hoje o `kind` tem **um** habitante: `Option` (aridade 1) — a stdlib o usa 33× e **nunca o declara**, então ele não cabe em `NamedType(decl:)`. (Os básicos acima já têm construtor próprio; `Option<X>` é reescrito para `OptionalType(X)` em A2 — §4.6, e por isso `BuiltinType` **não sobrevive à fatia A**.) |
| opcional | `OptionalType(inner)` | `T?` — **construtor próprio**, não ADT (§4.6) |
| função | `FunctionType(params, ret, isAsync)` | 6.3.1 (`s → t`) |
| produto | `TupleType(elements)` | 6.3.1 (`s × t`); espelha o ASDL (≥2 elementos). Lowering: `RecordType` do Kernel (§8.4) — **posicional só**; não há record literal nomeado na superfície |
| bottom | `NeverType` | **lacuna no Dragon** (só tem `void`); fonte: TAPL §15.4 + `NeverType` nativo do Kernel |
| variável | `TypeVar(id)` | 6.5.4/6.5.5 — "ainda não sei"; **deve** sumir até o fim, senão `cannot-infer` |
| erro | `ErrorType` | absorvente pós-erro-já-reportado (anti-cascata) |

**`ErrorType` ≠ `TypeVar` — a distinção que o oracle não fez.** O oracle funde os dois em `UnknownType`, que é curinga nos dois sentidos (`resolved_type.dart:46`) e por isso **nunca gera erro** — 4 regras checadas em 1355 linhas. Aqui: `ErrorType` silencia cascata (a AST é total, com `Error*` — CI 11.5); `TypeVar` não resolvido é **erro**.

**Struct/class/enum são UM construtor** (`NamedType` + o `kind` acima), não três classes — o oracle fez três (`StructType`/`ClassType`/`EnumType`) com estrutura idêntica. Identidade **nominal** (§4.2).

**`mut` NÃO é tipo.** O `MutType` da AST não tem imagem em `DartType` (§8): a F5 normaliza `mut T` → `T` + **flag de mutabilidade no binding/campo** na side-table. `mut` é propriedade do local de armazenamento, como no Kernel (`VariableDeclaration.isFinal`, `Field.mutable/immutable`).

### 4.2 Equivalência de tipos — `[cap 6.3.2]`

**Por NOME** para user-types (`struct`/`class`/`enum`/`trait`), **estrutural** para construtores (`OptionalType`, `FunctionType`, `TupleType`). O livro dá as duas e deixa a escolha: *"A questão-chave é se um nome em uma expressão de tipo tem significado próprio ou é uma abreviação para outra expressão de tipo."*

Nominal é forçado por §0.5-4 (conformance é declarada, não por acidente de forma) e resolve os **tipos recursivos** que o livro destaca (box *"Nomes de tipo e tipos recursivos"*, `class Cell { int info; Cell next; }` — o grafo tem ciclos).

### 4.2b Subtipagem (`≤`) — nominal e DECLARADA

O `≤` usado no §4.3 (subsunção) e no §4.4 (razão 2 da recusa do HM). Reflexivo e transitivo; **só existe onde foi declarado**:

| Regra | Nota |
| :-- | :-- |
| `class D : Animal` ⟹ `D ≤ Animal` | é o que `class` + herança significa; a metade OO de P5; o Kernel entrega |
| `T : Trait` (inline ou `impl Trait for T`) ⟹ `T ≤ Trait` | conformance é **declaração de intenção** (ADR-0012 A2) |
| `Never ≤ T` | bottom (§4.1) — **só nesta direção** |
| `T ≤ T?` | o modificador admite o valor (§4.6) |
| `ErrorType ≤ T` **e** `T ≤ ErrorType` | absorvente **bidirecional** (anti-cascata) |
| **estrutural: NÃO existe** | conformance por acidente de forma tornaria as duas sintaxes de declaração decorativas |
| **`struct` é FINAL** | conforma trait, **nunca herda** (P2) |
| **variância: INVARIANTE** | v1 |

**`struct` final é P2 duro:** subtipagem de valor é **slicing** — atribuir um `Derivado` num slot do tamanho do `Base` e a parte derivada sumir em silêncio. É o exemplo perfeito de "código faz menos do que diz". Precedente: Swift.

**Invariante (não herdar a variância do Kernel por acidente):** covariância em container mutável é insound (o array store do Java). Ser mais restrito que o alvo é sempre seguro; variância declarada é débito futuro.

**`ErrorType` vs `Never` — a diferença que o oracle não fez.** `Never` é bottom: **só** `Never ≤ T`. `ErrorType` é curinga nos **dois** sentidos — que é **exatamente a propriedade do `UnknownType` do oracle** (`resolved_type.dart:46`, curinga bidirecional ⟹ o checker nunca erra). O bug do oracle **não é ter um curinga**: é dar semântica de `ErrorType` a um "ainda não sei". Por isso o invariante §7-3: `ErrorType` **só nasce depois de um erro já reportado**; "não sei" é `TypeVar`, e `TypeVar` que sobrevive é `cannot-infer`.

### 4.3 Regras de tipo — `[cap 6.5.1]`

Notação premissa/conclusão. `Γ ⊢ e ⇒ T` = **sintetiza** (bottom-up); `Γ ⊢ e ⇐ T` = **checa contra** (top-down).

```
      Γ ⊢ e₁ ⇒ Int      Γ ⊢ e₂ ⇒ Int      (Int,Int)→Int ∈ Ops(+)
      ────────────────────────────────────────────────────────────
                        Γ ⊢ e₁ + e₂ ⇒ Int
```

> **`Ops(+)` — de onde vem** (clarify 2026-07-15; ruling do dono). O símbolo é enum fechado (ADR-0012 A5) e a resolução é **match exato pelos operandos** (§4.9). `Ops(sym)` = as assinaturas declaradas por `OperatorDecl` **∪ a tabela de PRIMITIVOS** (`Int+Int→Int`, `Float+Float→Float`, `String+String→String`, comparações → `Bool`, …).
>
> ⚠️ **A tabela de primitivos é DÉBITO declarado, não design.** Ela é a mágica que o §4.9 acusa: o compilador sabendo de assinaturas que nenhum código Itá escreveu. Hoje é inevitável — a stdlib **não declara** `operator +` (verificado: zero ocorrências) e no oracle `Int+Int` é `k.Name('+')` cru no codegen (`codegen.dart:3006`). **Destino: migrar para `.tu` no M5** (des-Dartificação), cumprindo o MANIFESTO §Norte (*"built-ins hoje embutidos no codegen migrados para `.tu`"*). É pequena e fechada — o conjunto de símbolos é fixo (ADR-0012 B8) —, e a migração é localizada: `Ops(sym)` deixa de ter o ∪.
```
      (nil não sintetiza — só checa)
      ─────────────────────────────────
            Γ ⊢ nil ⇐ OptionalType(T)
```
```
      Γ ⊢ e ⇒ OptionalType(T)   Γ, x:T ⊢ corpo ⇒ U
      ───────────────────────────────────────────── (guard let / if let: o binder é NOVO)
            Γ ⊢ match e { .some(x) => corpo } ⇒ U
```

**Subsunção — o ÚNICO ponto onde `≤` (§4.2b) é consultado.** É a troca de modo (Pierce & Turner, *Local Type Inference*, TOPLAS 2000 §3; Dunfield & Krishnaswami 2013 §3):

```
      Γ ⊢ e ⇒ S       S ≤ T
      ───────────────────────  (sub)
            Γ ⊢ e ⇐ T
```

> Consultar `≤` em qualquer outro lugar é como se produz checker inconsistente: `isSubtype` espalhado pelo código. **Um ponto, e só um.**

Regra do livro para chamada (6.8), com a nota do rodapé 6 (*"usaremos o termo 'síntese' mesmo que alguma informação de contexto seja usada"*): `if f tem tipo s → t and x tem tipo s, then f(x) tem tipo t`.

**Literais de coleção CHECAM, não sintetizam.** `[]` não tem tipo sozinho; `[Cachorro()]` contra esperado `List<Animal>` desce elemento a elemento (`Cachorro() ⇐ Animal` → sub → ok). Sem esperado ⟹ `cannot-infer`. (É por isso que o oracle dá `Unknown` em `let xs = [1,2,3]`: ele não tem modo `check`.)

**Join = identidade + bottom.** Tipo de `match`/`if`-expr = braços **iguais**, senão `branch-type-mismatch`; mais `join(Never, T) = T`.

- **`join` NÃO é o LUB do reticulado** — é o `max` do 6.5.2 sobre uma **hierarquia ACHATADA**: só `Never` embaixo, nenhuma outra relação, **apesar de `≤` existir** (§4.2b). Isso reconcilia com o §4.5 (`max(t,t) = t`; qualquer outro par é erro): as duas seções falam do mesmo `max`.
- **Por que `join(Cachorro, Gato) ≠ Animal`, se `Cachorro ≤ Animal`?** Porque **síntese nunca inventa supertipo**. O supertipo só entra por **subsunção contra um esperado que o usuário declarou** (`let a: Animal = match {…}` — o modo `check` empurra para baixo). É o que evita o `lub(Integer, String)` do Java.
- **Boa-formação:** com `join(a,b) = a se a=b; b se a=Never; a se b=Never; senão erro`, o fold sobre N braços é **associativo e comutativo** — é o join de um reticulado plano com bottom.
- **A razão de `join(Never,T)=T` é P3 + o significado de bottom** (TAPL §15.4): um braço que **diverge** não impõe restrição alguma sobre o tipo do resultado. O Kernel (§8.4) é **reforço**, não a razão — a doutrina do §8.3 vale aqui também.

### 4.4 Inferência vs síntese: **BIDIRECIONAL** — `[cap 6.5.1, 6.5.4, Ex. 6.5.2]`

**O livro já parte o mundo nos dois modos** (6.5.1): *"A verificação de tipo pode assumir duas formas: síntese e inferência. A síntese de tipo constrói o tipo de uma expressão a partir dos tipos de suas subexpressões. **Ela exige que os nomes sejam declarados antes de serem usados.** … A inferência de tipo determina o tipo de uma construção a partir do modo como ela é usada."* Isso é `synth`/`check`.

**O Exercício 6.5.2 descreve o algoritmo literalmente:** *"usando um atributo type para sintetizar um conjunto de tipos possíveis de baixo para cima e, quando o tipo único da expressão geral for determinado, prossiga de cima para baixo para determinar o atributo unique para o tipo de cada subexpressão."*

**HM completo é RECUSADO**, com quatro razões independentes:
1. **6.5.4 diz para quem serve**: *"útil para uma linguagem como ML, que é fortemente tipada, mas **não exige que os nomes sejam declarados**"* — não é o Itá (borda anotada, §0.5-1). ("Zero annotations" é sobre `@decorators`, não sobre type annotations.)
2. **Subtipagem** (§4.2b — `class D : Animal`): unificação decide `=`, subtipagem exige `≤`.
3. **Contextualidade genuína**: closures (`{ $0*2 }` — o tipo de `$0` vem do esperado), `nil` (§4.6), `.variant`, coleções vazias (`[]`). Nenhum deles sintetiza; todos **checam**. É o modo `check` se sustentando sozinho.
   > **Nota — o 6.5.3 NÃO é razão aqui.** Ele descreve a sobrecarga que *"nem sempre é possível resolver examinando apenas os argumentos… o contexto precisa fornecer informações suficientes"*. **O Itá recusou ser essa linguagem** (§4.9): a sobrecarga dele é resolvível **só pelos operandos**, por construção. Citar 6.5.3 como razão descreveria uma linguagem que não somos.
4. **P4/diagnóstico**: HM reporta longe da causa e infere tipos que ninguém escreveu.

Bidirecional **é** o "HM modesto" que o ADR-0004 já nomeava.

**Onde infere, onde anota** (§0.5-1):

| Posição | Regra |
| :-- | :-- |
| `let`/`var` local | **inferido** (anotação opcional) |
| closure — params e retorno | **inferido do contexto** (`xs.map { $0 * 2 }`) |
| type-args de generic | **inferidos da chamada** |
| `fn` nomeada — params **e retorno** | **anotado** (retorno inferido faria o corpo mudar a API pública em silêncio) |
| campo de `struct`/`class` | **anotado** |
| `let`/`var` **global** | **anotado** (forçado pelo letrec de módulo — F4 §0.5-3) |

**Unificação fica, restrita:** Algoritmo 6.19 (union-find) só para **type-args em aplicação**, sem let-generalization.

### 4.5 Conversões / coerção — **ZERO** — `[cap 6.5.2]`

> ⚠️ **O template (§4.5) manda documentar** *"widening (implícita, preserva) vs narrowing (cast explícito, perde); `max(t₁,t₂)`, `widen(a,t,w)`"*. **Isto é a técnica do Dragon Book, não a lei do Itá** — implementar a maquinaria de um capítulo não é adotar a política dele. Esta spec **recusa** explicitamente, senão o template escreve a coerção sozinho.

O próprio livro é descritivo, não normativo: *"As regras de conversão de tipo **variam de uma linguagem para outra**"* — e a Figura 6.25 é do **Java**.

**Regra do Itá: `max(t,t) = t`; qualquer outro par é erro.** `Int + Double` → `type-mismatch` (escreva `.toDouble()`).

Três razões:
1. **P4** — precedente unânime: ADR-0012 #6 (*"conversões são métodos explícitos"*), spec 001 §4.5, nullity-invariant (*"o Itá não tem coerção truthy/falsy"*).
2. **"Widening preserva" é FALSO nos tipos do Itá** — `Int` é 64-bit (spec 001) e `Double` tem 53 bits de mantissa: `Int → Double` **perde** acima de 2^53. O default do livro nem é sound aqui.
3. **`widen(a,t,w)` GERA instrução** (Fig. 6.26) — coerção não é grátis nem invisível; seria trabalho de codegen para materializar o que o usuário não pediu.

**Corolário — literal tem tipo lexical.** `let x: Double = 1` é **erro** (escreva `1.0`). O lexer já decidiu int×float (conformance `int_bases`/`floats`/`float_dot`); a F5 reinterpretar o glifo contradiz uma fase anterior.

**Reforço de backend** (a razão é P4, acima — isto **paga**): em Dart, `int + double` devolve **`num`**, e `num` é veneno para o AOT — o `unboxing_info.dart` só reconhece `_intTFClass` e `_doubleTFClass`, então `num` cai em `kBoxed` e vira cone de 2 classes para a TFA. **Zero coerção mantém o Itá inteiramente fora do `num`** — exatamente onde o unboxing morre.

### 4.6 Nulidade — fecha INTEIRA aqui, sem flow-typing

O mandato: os 4 checkboxes de `nullity-invariant.md` (que dizem "Fase 3" — numeração **antiga**; sob o ADR-0011 é a **Fase 5**).

**O modo `check` É a implementação do invariante.** `nil` **não sintetiza** — só se checa contra `T?`:
- `let x: String = nil` → `nil-under-non-optional`.
- `let x = nil` → `cannot-infer` (nunca `Nil`, nunca `dynamic`). O `NilType` do oracle é o sintoma de não haver modo `check`.
- `let x: String = ""` → **ok, e sem warning jamais** (valor vazio é valor real).

**Desembrulho é regra de PATTERN, não narrowing** — e a F3 já pagou o preço: `??`/`?.`/if-let viraram `match` sobre `.some`/`.none` (commitado), e `guard let` foi retido com `target: pattern`. `guard let v = opt` **não estreita `opt`**: cria um binder **novo** `v` do payload. O nome novo É a honestidade (P4).

**`if x != nil { x.foo() }` → `member-on-optional`**, com hint ensinando o idioma (`if let x = x { … }`). Três razões convergentes:
1. **Normativa:** o `nullity-invariant.md` **lista** as portas de desembrulho — *"`?`, `guard let`, `if let`, `??` operam sobre opcionais"* — e `!= nil` **não está na lista**.
2. **Técnica:** narrowing sem binding é path-sensitive → seria F6 (Dragon 9.2: grafo de fluxo, *"não distinguimos entre os caminhos"*), e aí a nulidade não fecharia aqui.
3. **Identidade:** flow-narrowing é a cura de uma doença que o Itá não tem — ele tem `.some`/`.none` + match exaustivo.

O `!= nil` segue **legal e sem warning** (é uma pergunta booleana honesta); o erro nasce no `.foo()`. E o caminho certo já é o mais curto: `if let x = x { x.foo() }` < `if x != nil { x!.foo() }`. `!` permanece como válvula explícita (falha = `panic`, alto — P7).

**`Option<T>` ≡ `T?` — alias canônico BUILT-IN** (Swift-style, onde `Optional<T>` ≡ `T?`). Não são dois tipos: são **dois nomes do mesmo tipo**. Ruling de dono 2026-07-12: *"O Itá TEM `Option<T>` BUILT-IN (Swift-style). `T?` = `Option<T>`, `nil` = `.none`, `.some(x)` = presença"* — ancorado em `codegen.dart:684` (`Option<T> { some(value:T), none }`) e na stdlib, que usa `Option<T>` **33×** (`collections.tu` 20, `iter.tu` 5, `async.tu` 3, `server.tu` 3…) **sem nunca declará-lo**. `Option` não é ADT de usuário — se fosse, não existiria e a stdlib não compilaria.

**`?` é MODIFICADOR, não construtor** — e daí sai tudo o mais. O `nullity-invariant.md` (palavras do dono) já dá a doutrina: *"A única **porta** para `nil` é um tipo opcional `T?`"*. Porta é propriedade do **slot**, não embrulho que empilha. É a mesma forma do argumento do `mut` (§4.1): ninguém espera que `mut mut T ≠ mut T`. Consequências:

- **`T?? = T?` é idempotência de modificador**, não "achatamento com perda". Invariante do §4.1: `OptionalType(inner)` onde `inner` **nunca** é `OptionalType` (forma canônica).
- **`T??` escrito à mão = `redundant-optional`** (§4.8). Idempotência é a semântica; **silêncio seria a mágica** — se o usuário escreveu dois glifos e o compilador engoliu um, o código faz menos do que diz (P4). Diagnosticar, não engolir.

**Três condições para o invariante ser sound** (sem elas ele quebra em silêncio ou rejeita programa legal):

1. **Toda construção passa pelo smart constructor — inclusive `subst`.** `subst(OptionalType(TypeVar T), T := OptionalType(String))` por map estrutural ingênuo produz `OptionalType(OptionalType(String))` e o invariante quebra **calado** — e aí a F7 não tem imagem para o tipo (§8.1 tem **um** byte de `Nullability`, não dois).
2. **`redundant-optional` NÃO mora no construtor — mora em A2, sobre o `TypeNode` da AST.** A distinção é **o usuário escreveu dois glifos** vs. **a substituição produziu dois**. Se morar no construtor, dispara em `compact<String?>` — **programa legal** — e quebra a stdlib. É checagem de forma **sintática**, nunca sobre `Type`.
3. **A incompletude é REAL e declarada** (não é bug — é a escolha certa): o Alg. 6.19 (Fig. 6.32) é **unificação sintática sobre construtores livres** (`unify(s1,t1) and unify(s2,t2)`). Com `?` idempotente, **`?` não é construtor livre**: casar `List<T?>` contra `List<String?>` tem **duas** soluções — `T := String` (sintática) e `T := String?` (módulo a teoria = E-unificação). O Alg. 6.19 devolve a primeira e **nunca considera a segunda**. Consequência concreta: **`compact` com `T = String?` é inalcançável por inferência**, e não há turbofish para forçar (GRAMMAR §6: *"não há turbofish — `Foo<Int>()` numa expressão vira `((Foo < Int) > ())`"*). A solução preferida é a útil, e é determinística. **Precedente:** Swift viveu isto — `try?`/`as?` produziam `T??` até o **SE-0230** achatar.
- **Ausência tem UMA via.** Quem precisar de aninhamento genuíno (`some(none) ≠ none`) declara um ADT **com nome próprio** (`enum Maybe<T> { just(T), nothing }`) — aí a escolha tem um glifo: o nome que a pessoa escreveu. Duas vias para expressar ausência feriria P4 e o "um nome, um significado" (ruling F4 #1).

**`Option<T>` na superfície é ALIAS resolvido em A2** — uma reescrita de uma linha: `NamedType("Option", [X]) → OptionalType(X)`. **Não é instanciação genérica** (é `BuiltinType`, §4.1, sem nó-decl). Por isso **CA29 cabe em A+B**, e a **nulidade não depende de genéricos**: `OptionalType` é construtor próprio do modelo, ainda que o *nome* pareça genérico.

**Lowering: nullability nativa do Kernel** — ver §8.1 (o dado do backend **reforça**; a razão é a doutrina acima). **Não há "campo de rota" na side-table:** o lowering é **derivado** do tipo do subject, que a side-table nº1 já contém (`type(subject) is OptionalType` → nativa; senão → is-chain para ADT genuíno, ex. `enum Maybe<T>`). Guardar rota seria informação derivada armazenada duas vezes — pode divergir da primeira (P4).

**`T?` tem Σ_membros = ∅** — nenhuma API de instância nesta spec, e `member-on-optional` (§4.8) vale **sem exceção**. Isto fecha um buraco entre `Option<T> ≡ T?` e o ruling do dono: se `Option` tivesse API, `opt.unwrapOr(0)` seria membro num optional e cairia no próprio erro. (Swift resolve distinguindo membros **de `T`** — erro — de membros **do próprio `T?`** — `map`/`flatMap`, legais.) **Custo hoje: zero** — a stdlib **nunca chama** `.unwrapOr`/`.map`/`.unwrap`/`.isSome` (0 ocorrências em 12 módulos); usa `Option<T>` só como tipo e `.some`/`.none` como construtores. A API de `T?`, se entrar, é spec futura **com a exceção declarada**.

### 4.7 Contrato F5 → F6 (exaustividade e fluxo)

A *política* é desta spec (§0.5-5: exaustividade é **ERRO**); a *checagem* é **F6** (ADR-0011). Razão de fronteira: é análise de **cobertura sobre matriz**, não regra de tipo — não atribui tipo a nó, não usa `synth`/`check`. E o mesmo algoritmo (Maranget 2007, `U(P,q)`) dá **braço redundante** de graça, que é irmão de unreachable-code (F6 declarado). Um algoritmo, dois diagnósticos, ambos F6. (Dragon 6.8 é só codegen de n-way branch; CI não tem pattern matching → **lacuna declarada**.)

**A F5 entrega para a F6:** (a) tipo do scrutinee; (b) **Σ** — conjunto completo de construtores + aridade por tipo; (c) tipo de cada subpadrão; (d) `.variant` já resolvido. Tipos infinitos (`Int`/`String`) → Σ nunca completo, só `_` fecha. Braço com guard **não** conta para cobertura.

### 4.8 Erros de tipo detectados (EN kebab-case + span)

| Erro | Nota |
| :-- | :-- |
| `nil-under-non-optional` | `let x: String = nil` — o mandato do invariante |
| `cannot-infer` | falta informação do usuário (`let x = nil`) — **nunca `dynamic`** (§10) |
| `type-mismatch` | anotação × valor; argumento × param; `return` × `-> T`; sem coerção (§4.5) |
| `member-on-optional` | `x.foo()` com `x: T?` — hint: `if let` (§4.6) |
| `unknown-member` | `.field`/`.método` inexistente no tipo do receptor |
| `unknown-type` | anotação cita tipo inexistente (§4.1 — a F4 não resolve namespace de tipo) |
| `arity-mismatch` | nº de args ≠ nº de params (o oracle **não checa** — `type_checker.dart:156`) |
| `branch-type-mismatch` | braços de `match`/`if`-expr com tipos distintos (join = identidade, §4.3) |
| `not-bool` | condição de `if`/`while`/`guard` e operandos de `&&`/`\|\|`/`!` exigem **exatamente** `Bool` |
| `comparison-type-mismatch` | `==`/`!=`/`<`/`>`/`<=`/`>=` com operandos de tipo **distinto** → `Bool`. Coerente com join=identidade + zero coerção: `1 == "a"` é erro. (`<` sobre tipos ordenáveis exige bound `Ord` — **fatia D**.) |
| `no-operator-for-types` | nenhum `operator` declarado casa os tipos dos operandos — **match exato**, sem ranking (§4.9) |
| `overlapping-operator-impl` | dois `operator` do mesmo símbolo com operandos sobrepostos por subtipagem — erro **na declaração**, não no uso (§4.9) |
| `operator-precedence-conflict` | `precedence`/`associativity` declarados divergem da tabela fixa do símbolo — o parser já decidiu (§4.9); aceitar em silêncio um glifo ignorado é P4 |
| `try-outside-result-fn` | `?` em fn que não retorna `Result` (§0.5-6) — o lado da **fn envolvente** |
| `try-on-non-result` | `e?` onde o **operando** não é `Result` — o outro lado do §0.5-6 |
| `error-type-mismatch` | `?` com `E` divergente do `E` da fn — **sem `From` automático** (§5.4); hint `.mapErr()` |
| `unused-result` | `Result` descartado (must-use = **erro**, §0.5-6; escape explícito: `let _ = f()`) |
| `assign-to-immutable` | `let x = 1; x = 2` — **P1**; consome a flag de mutabilidade do §4.1 (o alvo `obj.field` é type-directed ⟹ F5, contrato 008 §5.5) |
| `redundant-optional` | `T??` escrito à mão — `?` é modificador idempotente (§4.6); engolir em silêncio seria a mágica |
| `missing-param-annotation` | `fn f(x) => x` — a **borda anota** (§4.4). A gramática NÃO fecha (`Param.type` é `TypeNode?`), então é a F5 quem fecha. **Escopado a declaração NOMEADA** (`FnDecl`/`InitDecl`): `Closure.params` usa o mesmo `Param` com `type` opcional e **DEVE inferir do contexto** — `{ x => x }` é legal (§4.4) |
| `duplicate-field` | 6.3.6 literal: *"os nomes dos campos de um registro devem ser distintos"* |
| `pattern-type-mismatch` | pattern × tipo do scrutinee |
| `bare-field-access` | **ruling do dono §12-5**: dentro de método, campo exige `self.x`; `x` nu resolve só a local/param. Sem a regra, o significado de `x` dependeria da lista de campos do tipo — e **adicionar um campo `x` mudaria em silêncio um `x` já existente** (ação à distância, P4) |
| ⚠️ `wildcard-covers-known-variants` | **WARNING** (o único sobre código legal — ruling do dono §12-6): `_` cobrindo variantes de **enum fechado**, listando as engolidas; suprimível ao nomeá-las. **Domínio infinito (`Int`/`String`) NUNCA avisa** — lá o `_` é obrigatório para exaustir. Razão: ao **adicionar** uma variante, o `_` a engole em silêncio e a exaustividade — que é promessa da linguagem (§4.7) — deixa de proteger |

**Sobre `-> T` ausente:** não é erro — significa **`Void`** ("não rende valor"), nunca "infira pra mim" (§4.4). `fn f() => 5` cai em `type-mismatch` de graça.

### 4.9 Overload de operador — resolução **só pelos operandos** — `[cap 6.5.3]`

**Já decidido:** ADR-0012 **B8** (Accepted) — *"Só **overloading** infix do conjunto fixo de símbolos por ora."* A 009 decide a **disciplina de resolução**, não o "se".

**Por que não fere o ruling F4 #1 ("um nome = um significado") — é *category error*:** `+` **não é um nome**. Pelo ADR-0012 **A5**, operadores são **enums fechados** (`BinaryOp.add`), com o símbolo servindo *"só como tag de dump"*. A F4 nunca resolve operador: não há entrada no namespace, não há binder. O F4 #1 governa nomes que o **binder** resolve lexicamente. *Reductio:* se `+` em `Int` e `+` em `Vec` fossem "um nome, dois significados", `.map` em `List` e em `Option` também seriam — e todo método de trait. **Despacho por tipo do operando é despacho, não ambiguidade** (a metade OO de P5).

**A razão que torna obrigatório (P4 invertido):** o MANIFESTO §Norte manda *"built-ins hoje embutidos no codegen **migrados para `.tu`**"*, rumo a "só código Itá". **Se o usuário não pode declarar `+`, a stdlib também não pode** — e `Int + Int` fica sendo mágica do codegen **para sempre**, um privilégio que nenhum código Itá reproduz. **Recusar overload é que seria a mágica:** P4 não é só "o código não esconde"; é **"o compilador não faz o que o usuário não pode fazer"**. O `OperatorDecl` existe para que `+` não seja propriedade exclusiva do compilador.

**A disciplina — só operandos; nunca contexto, nunca retorno:**

| Regra | Razão |
| :-- | :-- |
| **Match EXATO pelos tipos dos operandos** em `Ops(sym)` (§4.3) | sem coerção (§4.5) ⟹ **não há ranking, nem "melhor match", nem promoção**. É *lookup*: ou o tipo bate, ou é erro. **Overload no Itá é resolução, não escolha.** |
| `Ops(sym)` = `OperatorDecl`s **∪ tabela de primitivos** | a tabela é **débito** (§4.3) — morre no M5, quando os built-ins migrarem para `.tu` (§Norte). Um `operator +` do usuário para `Int` colide com o primitivo ⟹ `overlapping-operator-impl` |
| **Contexto NÃO escolhe** | senão `let x: A = p + q` e `let y: B = p + q` seriam a mesma expressão com significados diferentes, decididos em outro lugar — ação à distância (P4). O modo `check` **verifica**, não **escolhe**. |
| **Overload por RETORNO: recusado** | duas decls diferindo só no retorno é "um nome, dois significados" sem desambiguação local — **aqui o F4 #1 se aplica corretamente**. |
| **Sobreposição por subtipagem = erro na DECLARAÇÃO** (`overlapping-operator-impl`) | `+` para `Animal` **e** para `D : Animal` reintroduziria ranking ("o mais específico") pela porta dos fundos. Diagnóstico **na causa**, não longe no uso. Precedente: regras de coerência/overlap do Rust. |

> **O "1 walk" (§5.2) sobrevive — mas por CONSEQUÊNCIA do princípio, não como razão dele.** Se o argumento fosse "só-operandos porque preserva 1 walk", o princípio ficaria pendurado em custo (a doutrina do §8.3, de novo). A razão é P4; o 1 walk é o troco.

**A linha que reconcilia com `.variant`** (`var r: Option<Response> = .none` **é** resolução por contexto — e é legítima):

> **Resolução contextual é legítima quando o glifo a PEDE; ilegítima quando é silenciosa.**

O `.` do `EnumShorthand` **é** o pedido explícito — um caractere cuja única função é delegar ao contexto. Já `p + q` não anuncia nada. Mesmo teste P4 dos dois lados.

**`precedence`/`associativity` são do SÍMBOLO, não do tipo.** Verificado no parser (`parser.dart:459-472`): são consumidas na **Fase 2**, antes de existir qualquer tipo — logo **não podem variar por tipo** (`+` não pode ser left para `Vec` e right para `Matrix`; quem associa é o parser, que não sabe tipos). E o conjunto de símbolos é **fixo** (A5/B8) ⟹ a precedência de `+` **já é da linguagem**. Portanto `operator + precedence 6 left` declarado é **redundante ou mentira** ⟹ `operator-precedence-conflict` quando diverge da tabela fixa. (Mesmo argumento do `T??`: aceitar em silêncio um glifo que o compilador ignora é P4. Os campos ficam na AST — forward-compat da B8 para símbolos custom.)

---

## §5 SDD / Tradução dirigida por sintaxe — `[cap 5.1, 5.2]`

### 5.1 Atributos

O bidirecional **é** a dupla do livro (5.1.1): **sintetizado** (filhos→pai) = `⇒ T`; **herdado** (pai/irmãos→filho) = `⇐ T` (o "esperado").

| Produção | Regras semânticas |
| :-- | :-- |
| `E → E₁ + E₂` | `E.type = synth(E₁) ⊓ synth(E₂)` (§4.3; sem `max`, §4.5) |
| `E → nil` | `check(E, E.expected)`; falha se `E.expected` não é `OptionalType` |
| `E → { $0 … }` | `E.params.type = herdado de E.expected` (closure é contextual) |

O livro **autoriza explicitamente** o que o bidirecional faz: *"permitimos que um atributo sintetizado no nó N seja definido em termos dos valores dos atributos **herdados** do próprio nó N"* (5.1.1).

### 5.2 Classe da SDD: **L-atribuída** — `[cap 5.1.2, 5.2]`

É o modelo já declarado do projeto (template §5.2: *"L-atribuída (modelo do Itá, casa com descendente)"*). 5.1.2 avisa que SDDs com atributos herdados **podem ser circulares e sem ordem de avaliação**; L-atribuída é a subclasse segura. **É por isso que o bidirecional roda em 1 walk, sem ponto-fixo.**

### 5.3 Ações e efeitos colaterais

Inserção na tabela de tipos (6.3.6: *"um tipo registro tem a forma record(t), onde t é um objeto de tabela de símbolos"*).

> ⚠️ **O template (§5.3) manda documentar `offset += width`** citando 6.3.4–6.3.5. **NÃO se aplica:** layout de armazenamento, endereço relativo e alinhamento são **Grupo B** — a Dart VM faz (ADR-0007). Metade do 6.3 é herdada; implementar `offset += T.width` seria código sem consumidor.

### 5.4 Arquitetura do passe: **A → B**, two-pass

O corte é do livro: 6.3 popula a tabela a partir das **declarações**; 6.5 checa as **expressões**. Duas seções, dois passes.

**Two-pass é obrigatório, não estilo:** 6.5.1 — *"A síntese de tipo… exige que os nomes sejam declarados antes de serem usados"*. O módulo do Itá é **letrec** (F4 §0.5-3), então sem coletar assinaturas antes, `fn a() { b() }` com `b` declarado depois não sintetiza. E os **tipos são mutuamente recursivos** (6.3.1, box + nota 3: o grafo tem ciclos) → o Collect é ele mesmo two-pass interno.

| Fatia | Conteúdo | Observável |
| :-- | :-- | :-- |
| **A — Collect** | A1 cabeças de tipo; A2 resolve as expressões de tipo das assinaturas (campos, params, ret, variantes) **incluindo os `genericParam` da decl** + alias `Option<X> → OptionalType(X)` (§4.6) + `redundant-optional` (sintático, §4.6-cond.2); A3 boa-formação (`duplicate-field`, aridade de generic, ciclo de herança) | dump da tabela de tipos + `unknown-type` |
| **B — Check** | literais, binários/unários, if/match, call, `let` com/sem anotação, `Try`. **Sem `for`** (ruling §12-4: não-objetivo — o binder exigiria tabela hard-coded; o trait `Iterator` é spec própria) | `itac check` + `--dump-types`; **fecha a nulidade (§4.6)** |
| **D — Unificação de type-args** | Alg. 6.19 (union-find) nas **aplicações**, sem let-generalization | `Result<T,E>` real ⟹ **fecha P7** |
| ~~**C — Contextual**~~ | closures, `.variant`, `[]`/`{}`, `CopyWith`, **leitura de campo** | **→ spec 010** (ruling §12-2) |

> ⚠️ **Esta linha foi CORRIGIDA em 2026-07-15** (levantamentos para a spec 010). A versão original listava também **currying** e **`**`**, e as duas estavam erradas: **currying nunca foi da fatia C** — `specs/004-parser-ast/design-notes.md:262` já cravou *"não portar `PartialAppExpr`"*, o nó é AST órfã no oracle, e `add(5, _)` **não parseia** (`_` só existe como `pattern`); e **`**` já está PRONTO** desde a fatia B (`check.dart:71`, `BinaryOp.pow`, operador nativo — não é dispatch para método). Em compensação, **leitura de campo** entrou: o `record(t)` (6.3.6) que o `CopyWith` exige é o mesmo que `p.x` usa, então vem quase de graça. O que fica para a **011** é **dispatch de método**.

> **Esta spec entrega A + B + D** (ruling do dono §12-2). A fatia **C** vira a **010** — ela adiciona ergonomia/expressividade, não corretude; já **D fica**, porque `Result<T,E>` é **P7**, princípio permanente, e deixá-lo em promessa seria dívida de identidade.

**Ordem: A → B → D → C** (não `A → B → {C,D}`). Três razões:
1. **Generic PARAMS já são A2, não D.** Resolver `struct Box<T> { v: T }` exige `T` em escopo, e a stdlib usa `Option<T>` 33× e `List<T>`/`Map<K,V>` em tudo — **A2 não resolve as anotações da stdlib sem parâmetros genéricos**. O que é deferível **não é "genéricos"**: é só a **unificação de type-args em aplicação** (6.5.5/Alg. 6.19). Daí o nome de D.
2. **6.3.1 lista variável de tipo no modelo BASE**, não como extensão: *"Expressões de tipo podem conter variáveis cujos valores são expressões de tipo."* O `args` do §4.1 sem D seria um campo que ninguém sabe popular.
3. **C depende de D; D não depende de C.** O flagship de C (CA15, `xs.map { $0*2 }`) precisa instanciar `T:=Int` na assinatura de `map` **antes** de tipar `$0` — isso é D. Já D funciona inteiro com bindings anotados. E **P7 (princípio permanente) fica em nota promissória até D** (§12-2).

`Try` (`?`) é **regra não-local**: operando `Result<T,E>` → `T`, **e** exige que a fn envolvente retorne `Result<_,E>` com **`E` IDÊNTICO** ⟹ o passe carrega "tipo de retorno da fn corrente" no contexto.

**Sem `From` automático** (§0.5-6): divergência de `E` é `error-type-mismatch`, hint `.mapErr()`. O `From` implícito do Rust é o único ponto onde ele fura o próprio "sem conversão implícita" — maquinaria invisível rodando em **todo** `?`. "Compatível" seria a palavra que reabre essa porta; é `E` idêntico, ponto. Custa ergonomia; P4 ganha.

---

## §7 Contrato F5 → F7 (codegen) — `[cap 6.2]`

A F5 **não emite** Kernel; produz o que o codegen exige. São **quatro** side-tables (`Map.identity` — a AST é imutável, ADR-0004; e a F3 roda 2× para testar idempotência), empacotadas num `CheckResult`:

1. `<Expr, Type>` — consumidores: **F7** (Kernel tipado = a alavanca do ADR-0007) e F6.
2. **Tabela de tipos** (`decl` → campos/variantes/assinaturas) — consumidores: F6 (Σ, §4.7) e F7 (copy-with enumera campos; hoje isso é `_typeFields` **dentro do codegen** do oracle = vazamento a corrigir).
3. `<Member|EnumShorthand|Call, ResolvedMember>` — **a resolução type-directed** do contrato 008 §5.4. **A F5 não produz só tipos: produz resolução** — qual `Procedure`/`Field` do Kernel aquele `.foo` é, **por objeto** (lição da F4). **`ResolvedMember` precisa de um caso `builtin`/intrínseco**: para `.some`/`.none` sobre `T?` **não há membro no Kernel** (não há classe `Option`) — sem esse caso, ou `.none` não tipa (CA29 quebra) ou a F5 inventa uma decl fantasma. Precedente: o oracle já resolve `unwrapOr`/`map` como **intrínsecos expandidos inline** (`codegen.dart:829-837`), não como `Procedure`.
   > **Débito a corrigir (vazamento do oracle):** hoje `Option`/`Result` moram no `codegen.dart:683` (`_registerBuiltinTypes`), invisíveis à semântica e com type-args apagados para `const DynamicType()`. Eles têm de **migrar para a tabela de tipos da F5** — mesma correção que o §7-2 faz para o `_typeFields` do copy-with. Sem isso o vazamento sobrevive à reescrita e a F7 continua dona do conhecimento de tipo.
4. `<TypeNode, Type>` — dump e assinaturas.

**Não anotar a AST.** (CI 2.1.3 lista as 3 opções — atributo no nó / lookup table / nova IR; o Itá já escolheu lookup-table na F4.)

**Invariantes da side-table (a F7 depende deles):**

1. **Nulidade DECIDIDA — derivada de ESTRUTURA, nunca de ignorância.** Para todo tipo, a F5 sabe **qual dos três casos vale e por quê**:
   - `OptionalType` → `nullable`;
   - **type-param nu → função do BOUND** (`T extends Object?` ⟹ `undetermined`; bound non-nullable ⟹ `nonNullable`);
   - demais → `nonNullable`;
   - `void`/`dynamic`/`invalid`/`bottom` têm nulidade **fixa** (`types.dart:559-563`) — a F5 não escolhe.

   > ⚠️ **`undetermined` NÃO é o `UnknownType` disfarçado — é o oposto.** Doc do Kernel (`types.dart:12-25`): *"Non-legacy types **not known to be nullable or non-nullable statically**"*, com o exemplo `class A<T extends Object?>` onde `x = null` **e** `Object y = x` são **ambos** erro de compilação. As duas proibições são conhecidas: é informação **precisa** sobre um tipo aberto. O `UnknownType` do oracle é curinga nos dois sentidos (aceita tudo, vai para tudo) — são **contrários**. Provas de que é estado legítimo: predicados dedicados (`isPotentiallyNullable`/`isPotentiallyNonNullable`, `:577-589`) e proibição cirúrgica onde não cabe (`NeverType.internal` tem `assert(declaredNullability != undetermined)`, `:852-853`).
   >
   > Logo: `undetermined` é **legal e OBRIGATÓRIO** em `TypeParameterType` com bound nullable (`List<E>` precisa aceitar `List<Int?>` ⟹ bound `Object?` ⟹ `E` nu é `undetermined`; emitir `nonNullable` ali é **mentira de tipo**, e a TFA é closed-world — ela **acredita** e deriva unboxing disso); **bug** em qualquer tipo concreto; **proibido** em `Never`.
   >
   > **O teste é:** *a F5 nunca escolhe `undetermined` por não saber; só o deriva de um bound.* É isso que mata o `UnknownType` sem proibir um estado que o Kernel exige. (Sem genéricos este invariante seria verdadeiro **por acidente** — e viraria bug latente na fatia D.)
2. **Nenhum `TypeVar` sobrevive** — se sobrou, é `cannot-infer` (§4.1), não `dynamic`.
3. **`ErrorType` só onde já houve erro reportado** (anti-cascata) — nunca como "não sei" (§4.2b).
4. **Totalidade da `<Expr, Type>`** — todo nó de expressão da AST canônica tem entrada, e **`typeOf` FALHA se não tiver**. O oracle faz `_types[node] ?? const UnknownType()` (`type_table.dart:46`) — um **default que esconde buraco**: se a F7 pede tipo e recebe default silencioso, o `dynamic` volta pela porta dos fundos.
5. **Totalidade da tabela de resolução** — um `Member` sem entrada = `DynamicInvocation` = contamina a convenção de chamada (§8.3).
6. **`OptionalType` normalizado** (§4.6) — a F7 depende para emitir **um** byte de `Nullability`.
7. **Nenhum `MutType` sobrevive** — não tem imagem em `DartType` (§8.2); CA19 testa.

---

## §8 Runtime — o que a VM ENTREGA e EXIGE `[dart-vm-expert, 2026-07-15]`

Verificado no vendor local `ita/third_party/dart/3.12.2/pkg/kernel/` (`BinaryFormatVersion = 130`, bate com ADR-0003).

> **Esta seção é RETRATO de `3.12.2`/Kernel 130, não lei** — e é por isso que a doutrina do §8.3 existe. Prova de que muda: `dart-lang/sdk#40004` diz *"We start with unboxed `double` fields, but might extend this to `int`"*, e o `numRecordFieldsForReturnValueUnboxing = 2` de hoje não existia antes. **Ancorar um princípio nela seria ancorar em areia.**

### 8.1 `T?` nativo vs `Option<T>` boxed — **decide o §4.6**

**Herdado:** `Nullability` é campo de **todo** `DartType` (`types.dart:518-590`; `enum Nullability {undetermined, nullable, nonNullable}`), serializado como byte em cada tag (`binary.md:1554-1588`). Há `toNonNull()`, `withDeclaredNullability()`.

**O custo do Option boxed é estrutural, não cosmético:**
- Unboxing em AOT só aceita `int`/`double` **non-nullable** (`unboxing_info.dart`) — `Option<int>` é classe de usuário ⟹ param/retorno **sempre boxed**.
- `.some(x)` é `AllocateObject` — não há "enum de stack" no Kernel.
- **A TFA não elimina a alocação**: ela faz devirtualização, tree-shaking, unboxing-info, direct-call (`type_flow/transformer.dart`) — **escape analysis não está na lista**. Quem afunda é o `AllocationSinking` (`compiler_pass.cc`), que é **intra-procedural** e **desligado em função com try/catch**.
- `int?` nativo **não** aloca — Smi é *"an immediate object"* (`glossary.md`). O custo não "já existe": o Option o cria do zero. Em `double?` é o dobro do dano (perde unboxing **e** aloca wrapper).
- **Paridade (ADR-0005):** no `dart2js` não há TFA nem AllocationSinking ⟹ o Option boxed sobrevive como alocação por elemento. O lowering nativo é o único que ganha nos **três** alvos.

**A ergonomia do Option mapeia direto** — o desugar da F3 (já commitado) funciona sem inventar nó:

| forma F3 | Kernel |
| :-- | :-- |
| `.none` (teste) | `EqualsNull` (`expressions.dart:2419`) |
| `.some($x)` (bind) | `Let($x = subject)` com `T.toNonNull()` (`types.dart:571`) |
| `a ?? b` | `Let(t=a, ConditionalExpression(EqualsNull(t), b, t))` |
| `x!` | `NullCheck` (`expressions.dart:4072`) |

Troca *1 alocação + 1 is-test + 1 unwrap* por *1 compare-with-null*.

**O preço — vira ruling (§12-1):** nullability nativa **achata** (`T?? = T?`), perdendo `some(none) ≠ none`. Dart/Swift/Kotlin aceitam.

### 8.2 O contrato que a F5 assina

O Kernel **não aceita** chamada sem tipo:
- `InstanceInvocation` exige `interfaceTarget` **e** `functionType` — *"This includes substituted type parameters from the static receiver type and generic type arguments"* (`expressions.dart:1850-1883`).
- `InstanceGet` exige `interfaceTarget` **e** `resultType` substituído (`:551-571`).
- Sem tipo estático ⟹ só `DynamicInvocation`/`DynamicGet` (`:455-486`).

| Exigência | Falha se ausente |
| :-- | :-- |
| `Nullability` explícita em **todo** tipo emitido | não existe tipo sem ela (byte obrigatório) |
| tipo **substituído** em cada acesso/chamada | `DynamicGet`/`DynamicInvocation` |
| aridade exata de type-args | verifier rejeita (`verifier.dart:1308`, `:1521`) |
| `join(Never, T) = T` | `ConditionalExpression.staticType` vira `dynamic` |
| `mut` como flag de storage, não `DartType` | `MutType` não tem imagem em `DartType` (§4.1) |
| named fields de record ordenados **lexicograficamente** | assert no construtor (`types.dart:2316-2328`) |
| ordem/tipos completos dos campos de `struct` | sem copy-with; todo campo `double` vira box |

### 8.3 `dynamic` é VIRAL — o dado que REFORÇA a recusa

> **Doutrina (vale para toda §8, e sobretudo na F7): o princípio é a razão; o dado da VM é o reforço.** `dynamic` na superfície já está proibido por **P4** e pelo §4.8 (`cannot-infer`) — a identidade decide. O que segue **reforça** e informa a F7. Escrito ao contrário, a recusa ficaria contingente à convenção de chamada da VM: se um backend futuro baratear o dinamismo, o argumento evaporaria — **e P4 não evapora junto**. Custo baixo nunca é licença.

> ⚠️ **CORRIGIDO em 2026-07-15** (`dart-vm-expert`, revisão para a spec 010). A redação anterior desta seção afirmava *"`DynamicInvocation` → sem `interfaceTarget` → **TFA não devirtualiza**"* e citava `unboxing_info.dart` entre aspas (*"dynamic calls always use boxed values"*). **As duas coisas estavam erradas** e não devem ser propagadas: (1) `pkg/vm/lib/transformations/devirtualization.dart` **visita os nós `Dynamic*`** (`visitDynamicInvocation`, `visitDynamicGet`, `visitDynamicSet`) — a TFA devirtualiza por **dataflow**, não pela anotação estática, e um `DynamicGet` monomórfico no mundo fechado vira chamada direta igual; (2) a citação **não foi reconfirmada** na fonte (o fetch devolveu paráfrase) — a substância se sustenta pela lista `_cannotUnbox`, mas **não citar entre aspas**. A conclusão (recusar `dynamic`) **não muda** — ela é P4, e nunca dependeu deste dado.

**O mecanismo real** (`type_flow/analysis.dart::_collectTargetsForSelector`) é **precisão do conjunto de alvos**: `InterfaceSelector` entra intersectado com o cone do tipo estático (`receiver.intersection(member.enclosingClass.coneType)`), enquanto `DynamicSelector` parte de **todo membro com aquele `Name` no programa inteiro** (`getDynamicTargetSet`) — e a TFA tem de estreitar sozinha. Custos: **tree shaking** retém os N homônimos (tamanho de binário); receptor potencialmente nulo **adiciona alvo e mata a devirtualização** (`!hasExtraTargetForNull`); e o unboxing só concede `kInt`/`kDouble` a tipos non-nullable (`_cannotUnbox` inclui `isDynamicallyOverriddenMember`). **Assimetria a registrar: JIT não tem TFA** — lá o dispatch é inline cache (`unlinked → monomorphic → single-target → linear → megamorphic`) e o tipo estático ajuda menos.

**Não há "orçamento de `dynamic`".** O fallback do checker é `cannot-infer`, **sempre** (§4.8/CA5) — `dynamic` não é tipo de superfície do Itá e não é alcançável da sintaxe.

**`Object?` NÃO é fallback de inferência** (isso seria a tentação nº1 com outro nome: o programa compilaria e a falha migraria para um downcast adiante). `Object?` é topo, não curinga — dele não se chama nada sem prova (`match`/check); é o oposto de `dynamic`, que desliga a checagem. Ele tem exatamente dois lugares legítimos:
1. **Fato de emissão (F7):** quando o codegen precisar emitir um tipo que não sabe nomear, `Object?` > `dynamic` (dá `InstanceAccessKind.Object`, não `DynamicInvocation`). É regra de F7, não política de F5.
2. **Tipo que o usuário ESCREVE na borda `dart:`** (decodificar JSON) — decodifica-se na borda, devolvendo `Result`; dynamic externo nunca flui para dentro.

**A doc não quantifica** — o mecanismo está documentado; a magnitude (~7,7×) é medição do projeto.

### 8.4 Demais vereditos

- **`Never`**: nativo (`types.dart:844-918`, tag 98); a TFA o vê como `EmptyType` (alimenta tree-shaking). `ConditionalExpression` tem `staticType` **obrigatório no construtor** (`expressions.dart:3293-3306`) ⟹ `join(Never,T)=T` (§4.3, CA14) é **exigência dura**, não preferência. **Ressalva:** `Never` resolve o **tipo**, não a **forma** — `panic`→`Throw` é `Expression` ✅, mas `return`/`break`/`continue` são **Statements** no Kernel: `let x = if c => 1 else => return` exige lowering via `BlockExpression`/temp+`IfStatement` (débito de F7, não da F5).
- **`Result<T,E>` aloca SEMPRE** (para constar; medir): não tem equivalente nativo (payload nos dois lados) ⟹ classe no heap. E com o desugar da F3 o `Result` **escapa via `return`** ⟹ `AllocationSinking` não afunda. Logo **toda fn `-> Result` aloca 1 objeto por chamada, inclusive no caminho feliz**. `Option` era o único ADT eliminável — e a 009 o elimina (§8.1).
- **Invariância da superfície NÃO remove o covariance check do `dart:core List`** (medir): `isCovariantByClass` — *"the method implementation needs to contain a runtime type check to deal with generic covariance"* (`statements.dart:1501-1507`). O callee não sabe que o caller é invariante; a TFA **pode** remover, não é garantido. O ganho do §4.2b é de identidade/soundness; o de performance só se materializa com coleções próprias.
- **Genéricos: reified, erasure não é opção** — o verifier exige aridade; a TFA **não monomorfiza**. Custo controlável: type-args **top** → `is` por cid-range (rápido); instanciados → checagem por Ti (`type_testing_stubs.md`). Regra de codegen (F7), depende da F5 garantir soundness estaticamente.
- **`struct` = classe no heap** — não há tipo-valor multi-campo (`ExtensionType` embrulha **um** valor). Prêmio: `final` + `@pragma('vm:deeply-immutable')` ⟹ **zero-copy entre isolates** (`deeply_immutable.md`), e um `struct` do Itá satisfaz por construção (P1). All-or-nothing e viral pela hierarquia.
- **Tuplas**: `RecordType` serve; retorno de record com **exatamente 2 campos** é unboxed em AOT.
- **`match` sobre sum grande é `is`-chain O(n)** — o Kernel **não tem `SwitchExpression`**. Custo que a VM não desfaz; medir se sums grandes entrarem em hot path.
- ⚠️ **Armadilha de serialização (F7, nasce aqui):** `ast_to_binary.dart` escreve `nullability.index` (`undetermined=0, nullable=1, nonNullable=2`), mas `binary.md:1548` documenta `nullable=0, nonNullable=1, neither=2` — **o markdown está desatualizado**. Alinhar com o enum Dart, não com a doc.

---

## §9 Checklist de completude
- [ ] `semantic/` — `type.dart` (modelo §4.1), `type_table.dart`, `collect.dart` (**A**), `check.dart` (**B**), `unify.dart` (**D** — Alg. 6.19, union-find), `check_result.dart` (§7)
- [ ] **A**: cabeças + assinaturas **com generic params**; alias `Option<X> → OptionalType(X)`; `redundant-optional` (sintático); `duplicate-field`; ciclo de herança
- [ ] **B**: bidirecional `synth`/`check` em **1 walk** (L-atribuída, §5.2); `Ops(sym)` com a tabela de primitivos (**débito M5**, §4.3)
- [ ] **D**: unificação de type-args nas aplicações, **sem** let-generalization ⟹ `Result<T,E>` real (**fecha P7**)
- [ ] 4 side-tables `Map.identity` + os **7 invariantes** (§7); **AST não anotada**; `typeOf` **falha** (não defaulta)
- [ ] `itac check` + `--dump-types` (parse→desugar→bind→check) + função pura testável
- [ ] Erros §4.8 (kebab-case + span) — incluindo o **warning** `wildcard-covers-known-variants` (§12-6)
- [ ] Corpus `conformance/check/*.tu` → `.types` + `.errors`
- [ ] `dart analyze` limpo; `make test` verde

## §10 Compatibilidade e alternativas

- **Breaking change?** Não — fase nova; `resolve --dump` inalterado. `check` é output novo. **Mas:** programas que hoje passam no `parse`/`resolve` podem falhar no `check` (é o objetivo).
- **Rulings cravados:** bidirecional (não HM); zero coerção; `T?` nativo ≡ ergonomia Option; nulidade fecha na F5 sem flow-typing; `mut` = flag; join = identidade; exaustividade = política F5 / checagem F6; equivalência nominal para user-types.
- **Alternativas descartadas:** HM completo (6.5.4 é para ML sem declaração; + subtipagem/overload/diagnóstico); coerção widening (§4.5 — o "preserva" é falso no Itá); `Option<T>` boxed como `T?` (§8.1 — caro nos 3 alvos); flow-narrowing (§4.6 — path-sensitive ⟹ F6, e a nulidade não fecharia aqui); anotar a AST (ADR-0004).
- ✅ **Divergência de ADR — RESOLVIDA pelo [ADR-0013](../../.specify/memory/adr/ADR-0013-inferencia-falha-e-erro.md)** (Accepted, 2026-07-15; ruling do dono §12-3). Ele **supersede PARCIALMENTE o ADR-0004**: revoga só a *regra de ouro* `UnknownType → dynamic` (que colidia com o ADR-0007 — *"Kernel tipado é a única alavanca; ~7,7× = o custo do dinamismo"* — e produziu, no oracle, um `Unknown` curinga-bidirecional que nunca erra: 4 regras em 1355 linhas). **O resto do ADR-0004 segue em vigor e é reafirmado** (side-table `Map.identity`, rota rustc, AST imutável). Consequência para esta spec: `cannot-infer` (§4.8/CA5) é a política; `dynamic` não é alcançável da sintaxe; `Object?` só em F7/borda (§8.3); `ErrorType` ≠ `TypeVar` (§4.1); `typeOf` **falha** em vez de defaultar (§7-4). **A "zero falsos-positivos" do ADR-0004 é preservada** — `cannot-infer` não é falso-positivo, é a borda pedindo a anotação que o contrato §0.5-1 já exige.

## §11 Critérios de aceite (viram corpus `conformance/check/*.tu` → `.types`/`.errors`)

- **CA1** — `let x = 5` ⟶ `x : Int` (síntese, sem anotação).
- **CA2** — `let x: String = nil` ⟶ `nil-under-non-optional`. **(mandato do invariante)**
- **CA3** — `let x: String? = nil` ⟶ ok, `x : String?`.
- **CA4** — `let x: String = ""` ⟶ ok, **zero warning** (valor vazio é valor real).
- **CA5** — `let x = nil` ⟶ `cannot-infer` (nunca `Nil`, nunca `dynamic`).
- **CA6** — `let x: Double = 1` ⟶ `type-mismatch` (literal tem tipo lexical, §4.5).
- **CA7** — `1 + 1.0` ⟶ `type-mismatch` (zero coerção).
- **CA8** — `guard let v = opt else { return }` … `v` ⟶ `v : T` (não `T?`) e `opt : T?` **inalterado** (desestruturação, não narrowing).
- **CA9** — `if x != nil { x.foo() }` com `x: T?` ⟶ `member-on-optional` no `.foo()`; o `!= nil` **sem** erro nem warning.
- **CA10** — `fn f() -> Int => "s"` ⟶ `type-mismatch` (return × `-> T`; o oracle **não checa**).
- **CA11** — `f(1, 2)` com `fn f(a: Int)` ⟶ `arity-mismatch` (o oracle **não checa**).
- **CA12** — `match e { .a => 1, .b => "s" }` ⟶ `branch-type-mismatch` (join = identidade).
- **CA13** — `if 1 { … }` ⟶ `not-bool` (sem truthy).
- **CA14** — `let x = if c => 1 else => panic("x")` ⟶ `x : Int` (`join(Never, Int) = Int`).
- **CA15** — `xs.map { $0 * 2 }` com `xs: List<Int>` ⟶ `$0 : Int` (closure contextual, modo `check`).
- **CA16** — `enum E { A(v: Int) }` … `.A(1)` ⟶ resolve à variante + `Σ(E) = {A}` na tabela (contrato F6).
- **CA17** — `struct P { x: Int, x: Int }` ⟶ `duplicate-field` (6.3.6).
- **CA18** — tipo inexistente em anotação ⟶ `unknown-type`.
- **CA19** — `mut T` ⟶ tipo `T` + flag de mutabilidade (não `MutType` na side-table, §8.2).
- **CA20** — idempotência do dump: `check` 2× → `.types` idêntico (AST não anotada).
- **CA21** — **P1**: `let x = 1` … `x = 2` ⟶ `assign-to-immutable`. (`var x = 1; x = 2` ⟶ ok.)
- **CA22** — **P7**: `?` em fn `-> Int` ⟶ `try-outside-result-fn`.
- **CA23** — **P7**: `?` com `E` divergente do `E` da fn ⟶ `error-type-mismatch` (sem `From` automático).
- **CA24** — **P7**: chamada a fn `-> Result<…>` com valor descartado ⟶ `unused-result`; `let _ = f()` ⟶ ok.
- **CA25** — **P2**: `struct S : Outra` (herança) ⟶ erro; `struct S : Trait` (conformance) ⟶ ok (§4.2b).
- **CA26** — subsunção: `let a: Animal = Cachorro()` com `class Cachorro : Animal` ⟶ ok.
- **CA27** — invariância (**morde na VARIÁVEL, não no literal**): `let ds: List<Cachorro> = [Cachorro()]` … `let as: List<Animal> = ds` ⟶ `type-mismatch`. **Contraste (o literal PASSA):** `let xs: List<Animal> = [Cachorro()]` ⟶ **ok** — literal de coleção **checa**, o esperado desce elemento a elemento e `Cachorro() ⇐ Animal` resolve por subsunção (§4.3).
- **CA28a** — **de ANOTAÇÃO**: dois níveis de opcionalidade escritos à mão ⟶ `redundant-optional`. Formas: `Option<Option<Int>>`, `Option<Int>?`, `Option<Int?>` — se `Option<T> ≡ T?`, todas são o mesmo tipo (`Int?`) e **todas disparam**. As legítimas (`Int?`, `Option<Int>`) passam limpas.
  > ⚠️ **`T??` é INEXPRIMÍVEL** (achado da implementação, 2026-07-15): o lexer casa `??` como **um** token (`questionQuestion` — o coalesce; maximal munch), então `let x: String??` morre no **parser** (`expected-token`), não aqui. A redação anterior deste CA (*"`let x: String?? = nil` ⟶ `redundant-optional`"*) descrevia um programa impossível. O diagnóstico existe e vale — só não pela grafia `??`.
- **CA28b** — **substituição é SILENCIOSA**: `compact<T>(list: List<T?>)` instanciado com `T = String?` ⟶ tipo `String?`, **sem diagnóstico** (ninguém escreveu dois glifos). É o CA que trava a checagem no lugar certo (A2/sintático) — se ela morar no construtor, rejeita programa legal e a stdlib quebra.
- **CA29** — `Option<T>` e `T?` são o MESMO tipo: `let a: Option<Int> = nil` e `let b: Int? = nil` ⟶ ambos ok, mesmo tipo na side-table (§4.6, ruling 2026-07-12).
- **CA30** — borda: `fn f(x) => x` ⟶ `missing-param-annotation`; `fn f(x: Int) => x` ⟶ ok. **Contraste:** `xs.map { x => x }` (closure) ⟶ **ok**, infere do contexto.
- **CA31** — `-> T` ausente = `Void`: `fn f() => 5` ⟶ `type-mismatch` (não infere retorno).
- **CA32** — `1 == "a"` ⟶ `comparison-type-mismatch` (zero coerção alcança `==`).
- **CA33** — `opt?` com operando não-`Result` ⟶ `try-on-non-result` (o outro lado de CA22).
- **CA34** — `T?` não tem API: `opt.unwrapOr(0)` ⟶ `member-on-optional` (Σ_membros = ∅, §4.6).
- **CA35** — overload resolve pelos **operandos**: com `operator +` para `Vec` e para `Int`, `v1 + v2` ⟶ o de `Vec`; `1 + 2` ⟶ o de `Int` (§4.9).
- **CA36** — **anti-Ada** (o CA que prova que contexto NÃO escolhe): `let x: A = p + q` e `let y: B = p + q` ⟶ **a mesma resolução** nos dois (decidida por `p`/`q`); se nenhum `operator` casa ⟶ `no-operator-for-types` nos dois — **nunca** um resolvendo diferente do outro por causa do tipo esperado.
- **CA37** — `operator +` para `Animal` **e** para `D : Animal` ⟶ `overlapping-operator-impl` **na 2ª declaração** (não no call-site).
- **CA38** — `.variant` contextual segue legítimo (o glifo pede): `var r: Option<Response> = .none` ⟶ ok — contraste deliberado com CA36 (§4.9).

- **CA39** — **`self.x`** (§12-5): em método com campo `x`, `self.x` ⟶ ok; `x` nu ⟶ `bare-field-access`. Com `let x = 1` local, `x` ⟶ o **local** (nunca o campo).
- **CA40** — **wildcard** (§12-6): `enum E { a, b }` + `match e { .a => 1, _ => 2 }` ⟶ **warning** `wildcard-covers-known-variants` listando `.b`; nomear `.b` suprime. **Contraste:** `match n { 1 => "um", _ => "outro" }` com `n: Int` ⟶ **sem aviso** (domínio infinito).

> **CAs que migram para a 010** (fatia **C**, ruling §12-2): **CA15** (closure contextual) e **CA16** (`.variant` contextual). Os de P7 (**CA22/23/24**) e **CA28b** **ficam** — a 009 inclui a fatia **D**.

## §12 Rulings de dono — **FECHADOS 2026-07-15** (exceto o 7, reaberto)

| # | Decisão do dono | Onde entra |
| :-- | :-- | :-- |
| 1 | **`?` é MODIFICADOR** (idempotente): `T?? = T?`; `T??` à mão = `redundant-optional`; nesting genuíno = ADT com nome próprio | §4.6, CA28a/b |
| 2 | **Escopo = A + B + D** — fecha a nulidade **e P7** (`Result<T,E>`); **C** vira a **010** | §5.4, §1 |
| 3 | **ADR-0013** escrito e Accepted (supersede parcial do ADR-0004) ✅ | §10 |
| 4 | **`for` fora do escopo** (não-objetivo); trait `Iterator` na spec de D | §1 |
| 5 | **Exigir `self.x`** | §4.8, CA39 |
| 6 | **Warning `wildcard-covers-known-variants`** — só enum fechado | §4.7, CA40 |
| 7 | **REABERTO** — ver abaixo | §12-7 |

### §12-7 — `let` sem init: **PROIBIDO** (ruling do dono, 2026-07-15 — revisado)

> **Nota de governança:** o dono ratificou "permitir" em 2026-07-15 **sobre uma premissa falsa** que a orquestração forneceu. Corrigida a premissa, ele **reverteu para proibir** no mesmo dia. O registro fica: a decisão é dele; o erro de fato era nosso.

**A premissa que caiu:** *"RD-1 (blocos não rendem valor) torna o uninit-let a **válvula** que evita cair em `var`"*. **Erro de categoria:** RD-1 é sobre **blocos**; `if`/`match` **são EXPRESSÕES** (P3).

**A linguagem não tem uma válvula — tem TRÊS** (todas verificadas ao vivo):

| Caso | Caminho itaiano existente |
| :-- | :-- |
| inicialização **condicional** | `let x = if c => a else b` / `match` — **P3** (`conformance/valid/expr_if.tu`) |
| inicialização em **vários passos** | **`where { }`** — value-first, bindings intermediários (**ADR-0012 A4**) |
| inicialização que **pode falhar** | `let x = f()?` / `guard let x = f() else { … }` — **P7** |

Uninit-let não seria uma quarta válvula: seria um **quarto caminho que duplica os três, sendo menos honesto que todos**.

**O argumento decisivo — coerência com o próprio ruling 2** (recusa do flow-narrowing): lá o veredito foi *"um nome com dois tipos em duas linhas do mesmo escopo, **sem marca sintática**; o leitor tem de simular o flow-analysis de cabeça"*. Em `let x: T` … `x = "a"`, o glifo significa **inicializar** ou **mutar** conforme o histórico de fluxo, **sem marca sintática** — o leitor tem de simular a F6 de cabeça. **É a mesma doença.** (E **não** é o caso do `guard let`: lá a honestidade vem do **nome novo**; aqui não há marca, há glifo reusado.)

**Domínio útil VAZIO:** onde a F6 **conseguiria provar** exatamente-uma-atribuição (if/else), `if`-expr já resolve — mais curto. Onde seria realmente preciso (acumulador em loop, 0..n iterações), a F6 **não consegue provar** — e várias atribuições em caminhos diferentes **é** mutação: `var` é a palavra honesta. **Legal só onde é desnecessário; necessário só onde é ilegal.**

**Doença alheia:** o Swift precisa de uninit-let porque **não tinha `if`-expressão** (até 5.9). Nós temos. Importar a cura é importar a doença (Art. II) — mesmo padrão do flow-narrowing.

#### A regra

- **`let` exige `= EXPR`** — na **GRAMÁTICA** (parser), não na F5. `let z` e `let z: T` morrem os dois.
- **`var` mantém init opcional**, exigindo anotação quando sem init (`var x: Int`; `var z` nu = `cannot-infer`). Use-before-assign já é **F6** declarada (ADR-0011) — nada novo.
- **A assimetria é o princípio visível na gramática:** `let` **liga um valor** ⟹ exige o valor; `var` é **slot mutável** ⟹ pode encher depois. **P1 deixa de ser só semântica e vira FORMA.**

**Por que no parser (e não "representar e deferir"):** aquele ruling governa **VALIDAÇÃO** (tipo, escopo, pureza) — **não FORMA**. `pub init` foi representado porque é forma legal cuja *política* se decidia depois; `let` sem init **não é forma legal em fase nenhuma** — nenhuma fase posterior pode torná-la válida, então a AST estaria representando **lixo**. O **D5 não é contra-argumento — é a favor**: ele segurou a forma aberta *enquanto a decisão pendia* (`nullity-invariant.md` §Aberto). Decidida, a gramática fecha. Mesma mecânica do `~` (ADR-0012 §C-9: resolvido o ruling, o token desceu a morto-no-parser).

**Erro que ENSINA** (padrão do `member-on-optional`):

> **`let-requires-value`** — *"`let` liga um valor. Para inicialização condicional use `if`/`match` como expressão (`let x = if c => a else b`); para passos intermediários, `where { }`; se o valor realmente muda, use `var`."*

**Sem keyword nova:** `late` é do Dart, que o tem **porque tem null + late-init**. Importá-lo seria importar a cura de doença alheia (Art. II) — e para um domínio vazio.

> **Δ de fase:** esta regra é do **parser** ⟹ vira **delta à `grammar.ebnf`** (`letStmt`) e ao `ast.asdl`, mais fixture `conformance/invalid/let_requires_value.tu`. Não é código da F5 — mas nasce deste ruling.

**Herdado menor:** existencial de `struct`-em-trait (recomendação: generics com bound — zero boxing, casa com o TFA; existencial, se entrar, exige marca explícita `any Drawable`, nunca implícita).

## Definition of Done
- [ ] CAs cobertos por corpus `.types`/`.errors` + unit, verdes via `itac check`. (Os que migram p/ a 010 estão marcados no §11.)
- [ ] Checker + side-tables à mão (P11); AST imutável (ADR-0004 — a parte **não** revogada pelo ADR-0013).
- [ ] Contrato F4→F5 honrado (não reconstrói escopo) e F5→F6/F7 entregue (§4.7, §7).
- [x] **§12 fechado — 7 rulings** (dono, 2026-07-15); o §12-7 reaberto e re-decidido no mesmo dia.
- [x] **ADR-0013** escrito e Accepted (supersede parcial do ADR-0004) — pré-requisito do §10.
- [x] **Clarify** (2026-07-15): `Ops(sym)` e a tabela de primitivos (§4.3, **débito M5**); `NamedType.kind` (valor/ref); `BuiltinType.kind`; `TupleType` × `RecordType` reconciliados.
- [x] Constitution check (§0.5) sem conflito + **3 reviews aplicados**: identidade (`ita-visionary` — 6 bloqueadores), técnica (`compiler-craftsman` — 10), backend (`dart-vm-expert` — 4).
- [ ] `make test` + `dart analyze` verdes.

> **Delta de fase já ENTREGUE** (nasceu do §12-7, mas é parser): `let-requires-value` — commit `a5251ca`, 397 testes verdes. Fecha o §Aberto do `nullity-invariant.md`.
