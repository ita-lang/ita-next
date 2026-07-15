# Spec 011: Fase 5 — Resolução de membro

> **Tipo:** feature-fase · **Marco:** `Fase 5 (Semântica) do ita-next` · **Escopo:** **`_member` inteiro** — campo, CopyWith, método próprio, `extension`/`impl`, herdado, `static`
> **Status:** `clarified` — **5 rulings de dono fechados** (2026-07-15: §12-1/2/3/4 + §12-D); 3 levantamentos de agente + **review de identidade da spec escrita** incorporados. O review achou **1 bloqueante** (§1.4 — eu usei o ruling do chão para autorizar o que o §12-4 recusou), **2 correções doutrinárias** (§1.5 argumento falsificável; §2.2 generalização que matava a R5) e **3 achados menores** (§2.1 escudo fraco; §3.3 o `impl` sem regra; CA63 = CA53 outra vez). **Todas aplicadas.** Pendentes: §12-B (campo vs getter em `extension`) e §12-C (precedência trait × superclasse, se surgir) — **nenhum bloqueia**
> **Autor / Data:** orquestração (Claude) · 2026-07-15 · **Fundamentação:** Dragon **2.7** (tabelas de símbolos), **1.6.3/1.6.4/1.6.5** (escopo, membros de classe, dispatch dinâmico), **6.3.6** (`record(t)`), **6.5.1** (síntese e two-pass), **5.2.5/Ex. 5.10** (efeitos colaterais controlados); levantamentos `ita-visionary`, `compiler-craftsman` e `dart-vm-expert` de 2026-07-15.

## §0 Metadados

- **Classe da mudança:** [x] **Nova regra + REPARO** — fecha o `_member`, que é `cannot-infer` **inteiro** hoje. Parte é escopo novo (dispatch, `extension`/`impl`); parte é **dívida declarada** da 010 (§1.2).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [x] **Formal/Tipos (§4)** · [x] **SDD/atributos (§5)** · [ ] Fluxo · [x] **Codegen/IR (§7 — só o contrato)** · [x] **Runtime (§8 — só a dependência)**
- **Princípios afetados:** P4 (sem mágica), P2 (valor vs referência — `struct` é final), P6. **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

Sem conflito de princípio. Ao contrário: a 011 **repara** duas violações de P4 que estão no `main` hoje (§1.2). Quatro rulings de dono fechados em 2026-07-15 (§2).

---

## §1 Motivação

### 1.1 A frase

> **Membros entram na F5.**

Hoje o `_member` devolve `cannot-infer` para **tudo**. Verificado:

| Código | Hoje |
| :-- | :-- |
| `p.x` (campo) | `cannot-infer` |
| `p.{ x: 1 }` (CopyWith) | `cannot-infer` |
| `s.f()` (método próprio) | `cannot-infer` |
| `stack.push(1)` (método de `extension`) | `cannot-infer` |

**É unidade indivisível** — campo, CopyWith, método próprio, `extension`/`impl` e herdado saem todos da **MESMA** `record(t)` (6.3.6). Fazer metade é construir a tabela e não consultá-la, ou consultá-la pela metade.

### 1.2 Isto é metade REPARO — e a spec não cobra crédito de feature por reparo

**(a) Dívida declarada da 010.** `CopyWith` (§4.4) e leitura de campo (§4.5) eram escopo declarado e **escaparam**. Estão `[ ]` no DoD dela, e migram para cá.

**(b) `extension`/`impl` são INVISÍVEIS à F5 — bug, não não-objetivo.** Verificado: `extension Foo { fn f() -> Int => "sou String" }` ⟶ **sem erro**; `extension Naoexiste { … }` ⟶ **sem erro**. A **F4 os resolve** (`resolver.dart:201-204`) e a F3 os visita — **o buraco era só da F5**, e vinha de um `default: break` sobre um `sealed` que engoliu **quatro** decls (`ExtensionDecl`, `ImplDecl`, `OperatorDecl`, `InitDecl`). Corrigido para switch exaustivo em **`e8a8e79`**, com os buracos **pinados como teste**.

> **Não-objetivo DECLARADO vira escopo; não-declarado vira buraco.** A 010 declarou o não-objetivo do `for` (com ruling) e **não declarou** o de `extension`/`impl`. Essa é a falha real.

**(c) ⚠️ A regra da própria 009 §4 está INERTE.** A tabela dela diz: *"`T : Trait` (inline **ou `impl Trait for T`**) ⟹ `T ≤ Trait`"*. Mas `collect.dart` só lê `n.traits` (a forma **inline**); **`ImplDecl` não é lido por NINGUÉM na F5**. ⟹ o **retrofit externo é no-op silencioso**, e o **ADR-0012 #2** (*"as duas formas coexistem — declaração-de-intenção vs. retrofit externo"*) está **meio-cumprido**. Pinado em `check_test.dart`.

### 1.3 Não-objetivos

| # | Fora | Destino | Por quê |
| :-: | :-- | :-- | :-- |
| 1 | **Membros de built-in** — `.length`, `xs[i]`, `+` de `List`, `.slice`, `Map.keys()` | **012** | Corte do `compiler-craftsman`: (i)+(iii) [esta spec] produzem e consomem a tabela de tipos do **usuário**; built-in é **outro produtor**, independente. Ver §4.7 (`builtin-member-unsupported`) |
| 2 | **Binder do `for`** | **M5** | **Ruling §12-D:** `for-binder-unsupported` até lá — o **§12-4 fica intacto** (nada de tabela `List<T>→T`, que é o exemplo canônico do privilégio). ⚠️ Não é 012, e **não depende de `Iterator` tecnicamente** — ver §1.4 |
| 3 | **Trait `Iterator` / protocolo de iteração** | **M5** | **Já roteado pelo dono**: ADR-0012 §C-9 item 3 (2026-07-12) — *"o contrato de iteração passa a ser um trait Itá na des-Dartificação (M5)"*. ⚠️ Ver §1.5 |
| 4 | **`extension List` / `.map` em container** | **M5** | Ruling §12-2 (§2). Exige que `List` tenha **declaração**, e isso é o Norte do Art. II |
| 5 | **Overload / `OperatorDecl`** | **012+** | Ruling §12-4: **o Itá não tem overload de método**. `OperatorDecl` traz o Ex. 6.5.2 (dois percursos) ⟹ ameaça o 1-walk |
| 6 | **`init` memberwise sintetizado** | **F3** | Spec 005 §3.1a: *"a política por-kind (`struct` = memberwise sintetizado; `class` = `init` explícito) é validação da **Fase 3**, não do parser"*. ⚠️ Ver §4.6 — a 011 **herda a dívida** |
| 7 | **Seleção da implementação em runtime** | **Grupo B** | 1.6.5 Ex. 1.8 — ver §4.4 |

### 1.4 ⚠️ A corrente que eu desenhei tinha um elo INVENTADO

Eu propus *"011 = dispatch + Iterator + membros de built-in, porque é uma corrente: `for` precisa de `Iterator`, `Iterator` precisa de dispatch"*. **Falso**, e o `compiler-craftsman` o matou com um grep:

```
grep "trait \w+" stdlib/   →   ZERO matches
```

**A stdlib não declara UM trait sequer.** `trait Iterator` não existe. E os 30+ `for x in …` dela iteram **`List`** (`for item in list`, `for l in self.listeners`, `for key in other.data.keys()`).

⟹ **`for` NÃO precisa de `Iterator` TECNICAMENTE.** Mas — e aqui estava um **erro grave meu**:

> ⚠️ **CORRIGIDO (review de identidade, 2026-07-15). A versão anterior desta seção dizia: *"`for` sobre o chão não é mágica; é o chão"*, e usava o ruling §12-2 para autorizar o que o §12-4 do dono NOMEADAMENTE recusou.**
>
> **São DUAS tabelas diferentes:**
>
> | Tabela | O quê | Status |
> | :-- | :-- | :-- |
> | **CHÃO** (010 §4.6.1, ruling §12-2) | `.length`, `xs[i]`, `+` — **membros/operadores** | **autorizada**, sob as 3 condições |
> | **`List<T>→T` do `for`** | **contrato de iteração** | **§12-4 da 009: *"a mágica que §4.5/§8.3 recusam"*** |
>
> **O §12-2 não revoga o §12-4** — e a prova está na própria 010: a §1.4-2 dele o chama de ***"o deferido §12-4 da 009"***. **Deferido é vivo, roteado.** E o §4.6.1 lista o chão inteiro: **`for` não está lá.**
>
> **Por que `.length` por tabela PASSA e `for` por tabela REPROVA** — é a **face 1**, e o exemplo canônico da doutrina **é literalmente o `for`** (010 §3.2): *"`for` sobre `List` via tabela: o `MyType` dele **nunca** ganha `for`, e nenhuma linha de Itá conserta. **Privilégio ⟹ mágica.**"* Já `.length` **não nega poder nenhum** ao tipo do usuário — ele escreve `let length: Int` (e **foi por isso que o ruling §12-B2 importava**). `for` é **sintaxe que só o built-in alcança**.
>
> **O pecado não é de onde vem a informação; é o que o usuário não alcança.** A frase antiga apagava essa distinção — que é a **única coisa que segura a tabela do chão de pé**.

**O que SOBREVIVE:** o grep é verdadeiro e o elo era mesmo inventado — **não há dependência TÉCNICA `for → Iterator`**. Mas de *"não depende tecnicamente"* **não segue** *"logo vai por tabela na 012"*. **A dependência que o dono criou é NORMATIVA.**

E o ADR-0012 §C-9 já escreveu o **interino**: *"o `for` **HOJE** é **retido como `ForInStatement`** (a VM Dart itera de graça, Grupo B)"*.

⟹ **"como a F5 tipa o binder do `for` entre agora e o M5" é RULING DO DONO** (§12-D), não dedução da 012.

O grafo é um **Y**, não uma corrente:

```
(i)  coletar extension/impl ──┐
                              ├──> (iii) dispatch   [011]
(ii) membros de built-in ─────┘                     [012]
(iv) for                                            [M5 — ruling §12-D: erro declarado até lá]
(v)  Iterator                                       [M5 — não depende de nada disto]
```

### 1.5 ⚠️ Alerta para quem escrever o M5: a linha do ADR-0012 §C-9 nomeia DOIS protocolos incompatíveis

> *"trait `Iterator`/`Iterable`, **`next() -> Option<T>`**, **modelo Elixir `Enumerable`**"*

**Essas duas metades não são o mesmo protocolo** (`ita-visionary`):

- `next() -> Option<T>` é **cursor com estado** (Rust/Swift) — pede `mut self`.
- O `Enumerable` do Elixir **não tem `next`**: é `reduce(enum, acc, fun)` com suspensão (`:cont`/`:halt`/`:suspend`) — **fold**, precisamente porque Elixir é imutável.

> ⚠️ **CORRIGIDO (review, 2026-07-15) — o argumento anterior era FALSIFICÁVEL, e é a lição da 010 §1.3 valendo contra nós.** Eu tinha escrito que `next()` *"põe o laço por um caminho de mutação, **contra P1**"*. **Falso: `mut self` NÃO viola P1.** P1 é *"mutação é **explícita e localizada**"* — e `mut self` é explícito. A stdlib tem `MutStack`, `MutQueue`, `MutDeque`, `MutPriorityQueue`. **Alguém aponta isso e o alerta inteiro morre.**
>
> **A forma que aguenta:** `next()` não **viola** P1; ele põe **o laço mais usado da linguagem** pelo caminho da mutação, tornando-a o **default de fato** da iteração — contra o **"por padrão"** de P1 e contra **P5** (*funcional é o caminho natural*).
>
> **E "é o quadrante que o Art. II nomeia" estava esticado:** a analogia Itá:Dart::Elixir:Erlang é sobre **runtime**, ortogonal ao domínio. O Elixir é **precedente/reforço**; quem fundamenta o fold é **P1+P5**. É a doutrina §8.3 (*o dado reforça, não fundamenta*) — de novo contra nós mesmos.

`impl Iterator for List` com `next()` exige cursor mutável. Saídas honestas: (1) fold à Elixir — puro, mas `break`/`continue` exigem a máquina de suspensão; (2) `fn iter() -> Cursor<T>` (o `IntoIterator` do Rust); (3) `mut self`. **Aquela linha NÃO está fechada — não a leia como se estivesse.** `for` sobre `Map` é da mesma decisão. Tudo M5, tudo ruling do dono.

> ⚠️ **Um alerta na 011 NÃO sobrevive até o M5**, e o ADR não se edita (é decisão datada). **Mínimo exigível: a spec do M5 nasce citando este §1.5.** A memória do `ita-visionary` já o carrega.

---

## §2 Rulings do dono — **FECHADOS 2026-07-15**

| # | Ruling | Consequência |
| :-: | :-- | :-- |
| **1** | **Os 5 métodos hard-coded de `Option`/`Result` MORREM.** O idioma é `match` / `if let` | Resolve a colisão `Option.map` × `member-on-optional` (§2.1). `T?` mantém **Σ_membros = ∅** e o erro segue nascendo no `.foo()`, *"o melhor momento pedagógico da língua"* |
| **2** | **`.map` em container chega no M5**, não aqui | `extension List` exige que `List` tenha **declaração**. Hard-codar está proibido (ADR-0013 + 010 §3.4). ⟹ **a 010 §2.1 ("a stdlib migra na 011") fica VOID** |
| **3** | **Colisão `struct` × `extension` ⟶ `duplicate-member`** (erro, em A3) | Extension está no **MESMO nível** dos membros próprios. Sem precedência inventada, sem código morto silencioso, e o erro nasce **na declaração** — na causa, não longe no uso |
| **4** | **O Itá não tem overload de MÉTODO** | Colisão de método é sempre duplicata (A3). O caso de uso já tem saída: **default params + labels**. Overload **de método** arrastaria o Ex. 6.5.2 ⟹ dois percursos ⟹ mata o 1-walk. ⚠️ **NÃO se estende a operador** — §2.2 |

> ⚠️ **Registro de um erro meu no ruling 3.** Ofereci a alternativa rotulada **"(Swift)"** para *shadowing silencioso*. **Swift não faz isso** — dá **`Invalid redeclaration`** ([SR-8123](https://bugs.swift.org/browse/SR-8123)); o único caso em que ele permite redeclarar via extension é sobre **tipos importados**, e está registrado como **bug** ([SR-12953](https://bugs.swift.org/browse/SR-12953)). O comportamento que rotulei "(Swift)" era o da **outra** opção. O dono decidiu sob o rótulo errado e **corrigiu para `duplicate-member`** quando eu apontei. Fica escrito: um ruling de identidade quase fechou sobre premissa falsa minha.

### 2.2 ⚠️ O ruling 4 é sobre MÉTODO — não sobre a linguagem

> **CORRIGIDO (review, 2026-07-15).** A versão anterior escrevia *"o 6.5.3 nunca é invocado nesta linguagem"*. **Falso HOJE, e a evidência está no `main`** (`check.dart:49`):
>
> ```dart
> final Map<ast.BinaryOp, List<(Type, Type, Type)>> _primitiveOps = {
>   ast.BinaryOp.add: const [
>     (IntType(), IntType(), IntType()),
>     (FloatType(), FloatType(), FloatType()),
>     (StringType(), StringType(), StringType()), // concatenação
>   ],
> ```
>
> **Isso É resolução de sobrecarga por argumentos = 6.5.3 literal, rodando.** E o **ADR-0012 #8** mantém `operator` infix (*"Só overloading **infix** do conjunto fixo de símbolos por ora"*).

**Por que a generalização era perigosa** — ela mataria a peça que evita o privilégio. **009 R5**, que a 010 §3.2 cita:

> *"overload é o que torna built-in não-privilegiado; **recusar** overload é que seria a mágica."*

Sem sobrecarga de operador, `Int + Int` seria **privilégio permanente do codegen** — contra o Norte do Art. II.

**O escopo correto do ruling 4:** *sem overload de **método***; **sobrecarga de OPERADOR existe** (conjunto fixo de símbolos, `_primitiveOps`) e **é o que mantém o built-in não-privilegiado** (R5). O destino dela já está escrito no próprio `_primitiveOps` (`check.dart:41-44`): *"migrar para `.tu` no M5 … `Ops(sym)` perde o ∪"* — que é o **precedente do dono** que a 010 §3.3 cita como forma-M5.

⟹ **O 6.5.3 é invocado por operador, não por método.** O que o dispatch de método (§3.5) não faz é *reintroduzi-lo* onde não estava.

### 2.1 A colisão `Option.map` × `member-on-optional` — e o erro era do `ita-visionary`

A **Prova 2 do §3.1 da 010** — que ele assinou — dizia que os 5 hard-coded são escrevíveis em `.tu` *"com zero chão"*, via `extension Option<T> { fn map<U>(f) => match self { … } }`.

> ⚠️ **CORRIGIDO (review, 2026-07-15).** Eu tinha escrito *"a declaração é escrevível; a CHAMADA não"*. **A declaração também não é.** A Prova 2 falha em **TRÊS eixos independentes**, e qualquer um a mata:

| # | Eixo | Por quê |
| :-: | :-- | :-- |
| **1** | **Grafia** | `extension Option<T>` é **error production** pela §3.3 **desta** spec |
| **2** | **Alvo sem declaração** | `collect.dart:227` — `Option` é `BuiltinKind.option`, **sem nó-decl**; e é **alias** resolvido para `OptionalType` em A2 (`:245-248`). `extension Option` nu daria `generic-arity-mismatch` |
| **3** | **Call-site** | `T?` tem **Σ_membros = ∅** (009 §4.6, implementado, testado no CA9) ⟹ `opt.map(f)` é `member-on-optional` |

> **Por que a precisão importa — e é o mesmo erro que a 010 §4.1 alerta.** Com **um** eixo, sobra a leitura *"então basta destravar o call-site e a Prova 2 volta"*. Com os **três**, o ruling 1 do dono fica **SOBREDETERMINADO**. Era o §2.1 pegando **o escudo fraco no lugar do forte** — exatamente o que a 010 §4.1 diz sobre trocar a §4.9 pela vacuidade no `.variant`.

Os dois ramos, e o dono escolheu o primeiro:
1. **Os 5 morrem** — idioma é `match`/`if let`. É o que a 009 **já** decidira por identidade; a 010 §1.4-4 (*"é barata"*) era **falsa**.
2. O ban vira fallback — e **a pedagogia do `if let` erode**: o erro deixa de ensinar o idioma, e `T?` deixa de ter superfície vazia (que **era** o invariante).

---

## §3 Especificação formal — `[cap 1.6, 2.7, 6.3.6, 6.5.1]`

### 3.1 Onde os membros MORAM: **na tabela do ALVO**

**Extension não cria tabela; contribui entradas para a de `Stack`.** Três citações encaixam:

- **6.3.6**: *"um tipo registro tem a forma `record(t)`, onde `t` é um objeto de tabela de símbolos"* — a tabela é **parte do tipo**; a fatia A já a construiu (`TypeInfo.fields`).
- **2.7, §1** (literal): *"Essa técnica também funciona para outras construções que usam escopos, por exemplo, **uma classe teria sua própria tabela, com uma entrada para cada campo e método**."* — **método mora na mesma tabela do campo**. Não há tabela de métodos separada no livro.
- **2.7.2**: *"o papel de uma tabela de símbolos é passar informações de **declarações** para **usos**."*

O que `extension` muda é o critério de **pertencimento**. **1.6.3**: *"Dizemos que uma declaração D 'pertence' a um bloco B se B for o bloco aninhado mais próximo contendo D"*. **Extension troca aninhamento léxico por nomeação explícita do alvo.** O destino da entrada não muda; o critério de roteamento muda.

> **Lacuna declarada:** o Dragon (2006) **não cobre extension methods** — C# 3.0 é 2007; Swift/Kotlin depois. O mais próximo é **1.6.4**: *"Em C++, uma definição de uma classe pode estar separada das definições de alguns ou de todos os seus métodos…"* — mas **ali a declaração está dentro da classe; só a definição está fora** (o box *"Declarações e definições"* do 1.6.4 faz a distinção). Extension é **declaração nova, de fora**. **O livro dá a estrutura de dados; a regra de contribuição é nossa.**

### 3.2 Arquitetura: **A2 estendida + A3 estendida** — NÃO um passe novo

1. **A1 planta cabeças de TIPO.** `extension Stack` **não é um tipo** — não há cabeça a plantar. Um "A1.5" inventaria etapa para entidade que não entra em `_byName`.
2. **A ordem A2(`struct Stack`) vs A2(`extension Stack`) é IRRELEVANTE, e isso é do livro.** **5.2.5**: *"permitir efeitos colaterais de menor importância… quando a avaliação do atributo baseado em **qualquer** tipo de ordenação topológica do grafo de dependência produzir uma tradução correta"*. E o **Ex. 5.10** dá o caso exato: *"Assumimos que esta inserção do tipo não afeta a entrada da tabela de símbolos para nenhum outro identificador. **Assim, as entradas podem ser atualizadas em qualquer ordem.**"* Campos e métodos são inserções **disjuntas**.
3. **A duplicata é A3**, e o próprio Ex. 5.10 o autoriza: *"Essa SDD não verifica se um identificador é declarado mais de uma vez, **mas ela pode ser modificada para fazer isso**"* — exatamente onde o `_checkDuplicateFields` já vive, citando 6.3.6 (*"um nome pode aparecer no máximo uma vez"*).

**Modelo:**

```dart
TypeInfo.methods: List<MethodInfo>
MethodInfo(name, FunctionType sig, bool isStatic, ast.Decl decl, ast.Decl origin)
```

O **`origin`** (qual decl contribuiu) **não é luxo**: é o que faz o diagnóstico de duplicata apontar o `extension` ofensor, e o que a F7 vai precisar.

> **Contrato F4 × F5 — aresta a registrar:** `resolver.dart:203-204` passa **`n.target`**, que é um **`TypeNode`**, não a decl, como `selfType`. A F5 tem de fazer `resolveTypeNode(target)` → `NamedType(decl, …)` → `types.of(decl)` para achar a tabela.

### 3.3 Generics de `extension`: **o alvo empresta, por nome**

O design **real** da stdlib (`collections.tu:29-38`) — e o `ita-visionary` crava que é **deliberado**, não acidente:

```
pub struct Stack<T> { items: List<T> }
extension Stack {                            // ← SEM <T>
  static fn new() -> Stack<T> => Stack(items: [])
  pub fn push(value: T) -> Stack<T> { return Stack(items: self.items + [value]) }
}
```

> **A regra em uma frase: `extension` é o corpo do tipo, escrito noutro lugar — vê o que o corpo vê.**

**Não há binder escondido** — o binder é `struct Stack<T>`, e o leitor **pode ler**. Passa em **P4**. É a linhagem Swift que a superfície inteira já é.

**A regra completa — e ela cobre `impl` também** (lacuna apanhada no review; a versão anterior só falava de `extension`, mas `implDecl ::= "impl" type ("for" type)? typeBody` tem alvo `type` e admite type-args do mesmo jeito):

> ### **Posição de ALVO = NOME NU** — é sítio de **binder**, não há o que aplicar.
> ### **Demais posições = tipos normais**, com o `T` do alvo em escopo.

| Forma | Veredito | Por quê |
| :-- | :-- | :-- |
| `extension Stack { … }` | ✅ | alvo nu; o `T` de `struct Stack<T>` entra em escopo |
| `impl Voa for Ave { … }` | ✅ | idem |
| `extension List<T> { … }` | ❌ `target-has-type-args` | alvo é sítio de binder |
| `impl Voa for Ave<T> { … }` | ❌ `target-has-type-args` | idem — **o `impl` não escapava da regra** |
| `impl Comparable<T> for Stack { … }` | ✅ | **o trait é *use site***, não alvo — type-args são normais ali |
| `extension Stack: Ord<T> { … }` | ✅ | idem (conformance inline) |

A regra **libera o que deve ser liberado**, e o código do erro (`target-has-type-args`) cobre os dois — o nome antigo (`extension-target-has-type-args`) era estreito demais.

**Razão verificada de `extension List<T>` ser error production:** o oracle escrevia `extensionDecl = "extension" IDENT …` (`GRAMMAR.md:112`) — lá `extension List<T>` **nem parseia**. O `ita-next` alargou para `type` (`grammar.ebnf:223`); parsear hoje é **artefato do alargamento**, não forma projetada. E o `<T>` **não é engolido — é representado como outra coisa** (referência a um tipo `T` que não existe), o que fere P4 tanto quanto engolir.

**Por que `extension<T> List<T>` (à la Rust) é RECUSADO** — e o argumento decisivo não é "muda a F2":

> **Ele institucionaliza o privilégio que veio remover:** `extension<T> List<T>` para built-in e `extension Stack` para o tipo do usuário = **duas formas, e a especial é a do built-in**. É a **face 2 do teste do privilégio** (010 §3.2), escrita na gramática.

### 3.4 O walk do dispatch — **1.6.4 é a fundação**

> *"Classes e estruturas introduzem um novo escopo para seus membros… **Em analogia com a estrutura de blocos, o escopo de uma declaração do membro x em uma classe C se estende a qualquer subclasse C', exceto se C' tiver uma declaração local com o mesmo nome x.**"* — **1.6.4**

E **2.7.1**: *"as subclasses podem redeclarar um nome de método que redefine um método de uma superclasse."*

⟹ o walk é a **regra de aninhamento mais interno (1.6.3)** aplicada à cadeia de herança em vez da pilha de blocos. Implementação: o **`Env.get` da Fig. 2.37**, com `prev` = superclasse em vez de bloco envolvente. **Isso É o `override`. Zero invenção.**

| Nível | Quem | Colisão dentro do nível |
| :-: | :-- | :-- |
| **0** | membros próprios de `T` **+ `extension`/`impl` sobre `T`** | **`duplicate-member`** (ruling §12-3) — extension está no MESMO nível |
| **1** | herdados: superclasse + defaults de trait | dois herdados distintos com o mesmo nome (diamante) ⟶ **`ambiguous-member`** |

**Não inventar precedência entre trait e superclasse** — o livro não dá, e qualquer escolha seria mágica (P4).

> **Correção incorporada:** ambiguidade **NÃO é 6.5.3.** 6.5.3 é *sobrecarga* (*"restringimos nossa atenção à sobrecarga que pode ser resolvida examinando-se apenas os argumentos"*). Dois membros com o mesmo nome no mesmo nível é **declaração duplicada (6.3.6)**. Só viraria 6.5.3 se o Itá tivesse overload — e o **ruling §12-4 diz que não tem**. ⟹ **o 6.5.3 nunca é invocado nesta linguagem.**

### 3.5 O 1-walk **sobrevive** — e a razão é precisa

| | `E1 + E2` (overload) | `x.foo()` (dispatch) |
| :-- | :-- | :-- |
| Receptor sintetiza antes? | **Não** — não há receptor | **Sim** (`_synth(n.receiver)`) |
| Conjunto de candidatos | depende dos **dois** operandos | **fixo** assim que `T` é conhecido |
| Fonte | 6.5.1 nota 6 → **Ex. 6.5.2**: *"sintetize um conjunto de tipos possíveis de baixo para cima e, quando o tipo único … for determinado, **prossiga de cima para baixo**"* = **2 percursos** | 6.5.1 regra **(6.8)**: *"if f tem tipo s→t and x tem tipo s, then f(x) tem tipo t"* — **síntese pura** |
| Custo | percurso extra da árvore | `Env.get` — O(profundidade), **zero nós de sintaxe revisitados** |

**Lookup em tabela não é percurso de árvore.** ⟹ **dispatch não ameaça o 1-walk; overload ameaçaria** — e o ruling §12-4 o barrou.

### 3.6 Two-pass: **sem ponto-fixo**, e "borda anota" é quem COMPRA isso

É exatamente o two-pass do **6.5.1**: *"A síntese de tipo constrói o tipo de uma expressão a partir dos tipos de suas subexpressões. **Ela exige que os nomes sejam declarados antes de serem usados.**"* Assinaturas de extension antes dos corpos = A1→A2 estendido = letrec de módulo.

**Circularidade nova (extension A usa método de extension B que usa A)? NÃO.** Isso é recursão mútua de **função**, não de **tipo** — e o grafo de dependência (5.2.1) **não tem ciclo**, porque a aresta é `assinatura → corpo`, **nunca `corpo → assinatura`**.

> **Por quê: o retorno é ANOTADO.** `-> Stack<T>` é obrigatório, e `fn` sem `->` é `Void` por decisão (§4.4/§4.8), não *"infira pra mim"*.
>
> **"Borda anota" é o que COMPRA o 1-walk.** Sem anotação de retorno, o tipo do método só sai do corpo, o corpo depende de outros métodos, e cai-se em **6.5.4** — que é onde ML precisa de unificação global e ponto-fixo (*"A inferência de tipo é necessária para linguagens como ML, que verificam tipos, mas **não exigem que nomes sejam declarados**"*). **O 1-walk foi comprado na Fase 5; a 011 só coleta o dividendo.**

---

## §4 Regras

### 4.1 Leitura de campo (dívida da 010 §4.5)

```
Γ ⊢ p ⇒ NamedType(D, args)     x ∈ fields(D)
────────────────────────────────────────────
Γ ⊢ p.x ⇒ subst(fields(D)[x], generics(D) := args)
```

`member-on-optional` (009 §4.6) **continua**: `T?` tem **Σ_membros = ∅**, e o erro nasce no `.foo()`, ensinando `if let`. **Ruling §12-1 o mantém.**

### 4.2 `CopyWith` (dívida da 010 §4.4)

Tipo do resultado = tipo do receptor. Cada override checa (`⇐`) contra o tipo **declarado** do campo. Erros: `unknown-field`, `type-mismatch`, `copywith-on-non-aggregate`.

### 4.3 Método — instância

```
Γ ⊢ r ⇒ NamedType(D, args)     m ∈ Σ_membros(D)     ¬m.isStatic
──────────────────────────────────────────────────────────────
Γ ⊢ r.m ⇒ subst(m.sig, generics(D) := args)
```

`Σ_membros(D)` = o walk do §3.4. Fora dele ⟶ **`unknown-member`** (ADR-0013 — nunca `UnknownType`).

### 4.4 O que a F5 resolve, e o que ela NÃO resolve

> **1.6.5, Ex. 1.8:** *"Normalmente, é impossível saber durante a compilação se x será da classe C ou da subclasse D… **Somente no momento da execução é que pode ser decidida qual definição de m é a correta.**"*

⟹ a F5 resolve a **ASSINATURA** pelo tipo **ESTÁTICO** — é tudo que tipar exige. A **seleção da implementação** é vtable da Dart VM = **Grupo B**. `ResolvedMember` aponta para a decl do tipo **estático**, e está **certo**. Escrever isto na spec, senão alguém tenta.

### 4.5 `static` — qualificador, não tabela

> **1.6.1, Ex. 1.3:** *"**static refere-se não ao escopo da variável**, mas sim à capacidade de o compilador determinar a localização na memória… torna x uma **variável de classe**"*

⟹ **não é tabela separada** (1.6.4: o escopo dos membros é **um só**). O que muda é o **qualificador do receptor**: `Stack.new()` tem receptor = **nome de tipo**; `s.push()` tem receptor = **valor**. `MethodInfo.isStatic` + `_member` bifurca. Erros novos: `static-via-instance`, `instance-via-type`.

### 4.6 `static fn new() -> Stack<T>` — **é o `[]` com outro nome**

> ⚠️ **REENQUADRADO (review, 2026-07-15).** Eu tinha escrito isto como *"RISCO Nº 1"* e cogitado *"se não couber, declarar como não-objetivo"*. **O enquadramento estava errado, e a correção é boa notícia.**

**Não é caso novo.** Zero args ⟹ o `T` não é determinável por síntese ⟹ é o **Fundamento A da 010 §4.1: vacuidade (6.5.1)**. `[]` é `List<T>` com `T` livre; `Stack.new()` é `Stack<T>` com `T` livre. **Mesmo fenômeno, mesma regra — *checking-only*:**

| | 010 §4.1 (já decidido) | §4.6 (por SIMETRIA) |
| :-- | :-- | :-- |
| **com** contexto | `var r: List<Int> = []` ⟶ ok | `let s: Stack<Int> = Stack.new()` ⟶ ok |
| **sem** contexto | `let x = []` ⟶ `cannot-infer` | `let s = Stack.new()` ⟶ `cannot-infer` |

**Atravessa fronteira de declaração? NÃO.** A assinatura de `new` está **anotada** — `-> Stack<T>`, o usuário a escreveu. **Não inferimos a assinatura a partir do uso; instanciamos uma assinatura DECLARADA** — que é o que a fatia D já faz em todo call. **E não é HM:** a 010 §4.1 é explícita que dar `List<α>` **seria** 6.5.4 + let-generalization, e foi recusado.

> ⚠️ **E o INVERSO é que seria anti-itaiano.** Se `[]` (built-in) ganha contexto e `Stack.new()` (tipo do usuário) não ganha, **o built-in tem um poder que o tipo do usuário não tem** — é a **face 1** do teste do privilégio (010 §3.2), no teste do próprio projeto.
>
> ⟹ ***"Se não couber, declarar como não-objetivo" NÃO é neutro: declarar não-objetivo aqui é declarar um PRIVILÉGIO DE BUILT-IN.*** Se for para declarar, tem de ser declarado **como isso**, e vira **ruling do dono** — não decisão de escopo. A alternativa simétrica seria tirar o contexto do `[]` também, que ninguém quer. **Logo: ENTRA.**

**O trabalho técnico é real e continua sendo o mais caro da spec:** exige **propagar o tipo ESPERADO para o retorno** (modo `check` no call) — a 010 só desceu em **args**. **O livro NÃO cobre**: 6.5.4 é HM e resolve por unificação global, não por propagação de contexto. Fonte real: **Pierce & Turner, TOPLAS 2000 §3** (*Local Type Inference*), que a 010 já cita no `_check`. ⚠️ **Não está em `references/`** — não citar normativamente sem obter.

**Hoje, sem isso:** o `_call` faz `instantiate` + unify; com zero args `α_T` fica livre, `_hasTypeVar(ret)` dispara e emite `cannot-infer`.

> ### ⚠️ O memberwise init é **DESTA SPEC** — não é dívida de outra fase
>
> **CORRIGIDO 2026-07-15, ao executar o item "verificar o memberwise ANTES" do DoD.** Eu vinha dizendo (e o review confiou na minha leitura) que *"o trabalho é da **F3**"*, citando a spec 005. **Errado — e o erro era de NUMERAÇÃO.**
>
> A spec 005 (2026-07-11) diz *"a política por-kind … é da **Fase 3**"*. Mas o **ADR-0011 (2026-07-10)** já numerava **Fase 3 = Desugaring** e **Fase 5 = Semântica**. A 005 usa a numeração **velha**, e as palavras dela são inequívocas:
>
> - o título da §3.6 é *"O que sobra para a **SEMÂNTICA** (Fase 3)"*;
> - o subtítulo é *"deferidas ao **binder/type-checker**"*;
> - **e os vizinhos na mesma lista são decisivos:** *"`condition` do `guard let` deve ser **`Bool`**"* e *"traits devem existir e **ser traits**"* — **type-checking puro**, que o desugar (type-agnostic por spec) não faz;
> - **a spec 007 (desugaring) tem ZERO menções a memberwise/`init`** — ela nunca o reivindicou.
>
> ⟹ **"Fase 3" na spec 005 = a fase SEMÂNTICA = a Fase 5 de hoje.** O memberwise **é desta spec**. Não há dependência entre fases; o `e8a8e79` deixou um comentário no `_decl` dizendo "F3" — **também errado, corrigido**.
>
> **Estado verificado (2026-07-15):** o memberwise **não existe em lugar nenhum**. Pior — **os construtores são aceitos em SILÊNCIO TOTAL**, porque `_topLevelType` tem `_ => const ErrorType()` e o `ErrorType` é absorvente por anti-cascata:
>
> | Código | Hoje |
> | :-- | :-- |
> | `P(x: 1, y: 2)` | **sem erro** |
> | `P()` (faltando args) | **sem erro** |
> | `P(zz: 9)` (label inexistente) | **sem erro** |
> | **`let n: Int = P(x: 1, y: 2)`** | **sem erro** — um `P` num `Int` |
>
> **É a mesma doença do `default: break`**: um catch-all que engole. Aqui o `_` do `_topLevelType` transforma buraco em silêncio.
>
> **Continua verdade o que o review disse:** é **pré-requisito de DUAS CAs, incluindo o flagship** — o **CA73** (`Stack.new()`) depende dele **por construção**, porque `new` **tem de construir**.

### 4.7 Membro de built-in: **`builtin-member-unsupported`**, não `unknown-member`

Sob a 011, `xs.length` bate no `_member` sem resposta. **`unknown-member` seria FALSO** — o membro **existe**; nós é que não o modelamos. Código próprio: **`builtin-member-unsupported`**. Ainda é **erro** (ADR-0013 satisfeito), mas **não mente**.

---

## §7 Contrato F5 → F7

- **`extension` do Itá → `Procedure` estático com `self` como 1º param.** É o que a CFE faz (vendor `declarations.dart:605-608`: *"The members are converted into top-level procedures and only accessible by reference in the `[Extension]` node"*; `ExtensionMemberDescriptor:747-790` documenta o mangling `B|get#bar(A #this)`). **A VM nunca despacha através do nó `Extension`** — emiti-lo é opcional (serve a tooling). `StaticInvocation` é **alvo único por construção** — o resultado que a devirtualização persegue. *(Reforço, não razão: `.map` em container é ruling do dono.)*
- **`trait` → `Class` abstrata**; `impl` entra em `implementedTypes`. O `interfaceTarget` de chamada via trait é o `Procedure` **abstrato da classe do trait** — `isInstanceMember` ✅, `enclosingClass != null` ✅.
- ⚠️ **`ForInStatement` é PROIBIDO no `.dill`** (verificado na tag **3.12.2**, `kernel_binary_flowgraph.cc`): é nó **interno da CFE**, e quem a bypassa bate em `ReportUnexpectedTag`/`UNREACHABLE`. Ele nem carrega `interfaceTarget` para `iterator`/`moveNext`/`current` — é declarativo demais para ser executável. **Consequência para o M5: não há prêmio de VM no `for` do Dart a que estejamos renunciando** ⟹ **o protocolo de iteração pode ser desenhado por PRINCÍPIO** (§1.5).

---

## §8 Runtime — dependência `[dart-vm-expert, 2026-07-15]`

> **Retrato** do vendor `3.12.2`. **Datado, não lei.** *(Lição do próprio levantamento: uma busca trouxe um commit onde o `case kForInStatement` existia; `main` e `3.12.2` dizem o oposto. **Comportamento da VM é versionado** — conferir na tag vendorizada.)*

- **Grupo B (herdado):** dispatch (switchable calls no JIT; devirtualização por TFA + GDT no AOT), inline caches, tree-shaking de procedures top-level (inclusive membros de extension), GC.
- **A VM NÃO distingue interface de classe concreta no dispatch.** Dispatch é por **selector × cid do receptor**; a GDT **não** é mecanismo de interface. ⟹ **trait não custa por ser trait.** O que custa é o **nº de alvos no call-site**. *(Isto **remove** um falso custo do debate — não adiciona um.)*
- **Doutrina (§8.3 da 009):** o princípio é a razão; o dado da VM é o reforço. Nenhuma regra desta spec está pendurada em custo de VM.

---

## §11 Critérios de aceite (viram `conformance/check/*.tu`)

- **CA60** — `p.x` ⟶ tipo do campo; `p.zz` ⟶ `unknown-member`.
- **CA61** — `p.{ x: 1 }` ⟶ `P`; `p.{ z: 1 }` ⟶ `unknown-field`; `p.{ x: "s" }` ⟶ `type-mismatch`.
- **CA62** — `s.f()` (método próprio) tipa; aridade e args checam.
- **CA63** — **`extension Stack { fn peek() -> T? => .none }` sobre `struct Stack<T>`: o `T` do ALVO resolve** (§3.3). *É o flagship.*
  > ⚠️ **CORRIGIDO (review, 2026-07-15) — era o CA53 outra vez.** O corpo original era o da stdlib: `fn push(v: T) -> Stack<T> { return Stack(items: self.items + [value]) }`. Ele depende de **duas coisas que não existem**: **memberwise init** (F3 — ver abaixo) e **`+` de `List`** (não-objetivo **012**). *Um flagship que não pode passar não é gate.* O corpo fixado (`peek() -> T? => .none`) exercita o **`T` do alvo** — que é o que a CA testa — **sem construir nada**.
- **CA64** — corpo de `extension` mal-tipado ⟶ `type-mismatch` *(hoje: silêncio — §1.2b)*.
- **CA65** — `extension Naoexiste` ⟶ `unknown-type` *(hoje: silêncio)*.
- **CA66** — **`impl Voa for Ave` ⟹ `Ave ≤ Voa`** *(hoje: no-op — §1.2c, a regra da 009 §4 é inerte)*.
- **CA67** — `struct S { fn f() }` + `extension S { fn f() }` ⟶ **`duplicate-member`** (ruling §12-3).
- **CA68** — `fn achar(x: Int)` + `fn achar(x: String)` no mesmo tipo ⟶ **`duplicate-member`** (ruling §12-4: sem overload).
- **CA69** — herdado: `class D : A` acha membro de `A`; `D` redeclara ⟶ o de `D` vence (1.6.4).
- **CA70** — diamante (dois traits com default de mesmo nome) ⟶ `ambiguous-member`.
- **CA71** — `extension List<T>` ⟶ `extension-target-has-type-args` (§3.3).
- **CA72** — `s.novo()` onde `novo` é `static` ⟶ `static-via-instance`; `Stack.push(x)` ⟶ `instance-via-type`.
- **CA73** — `let s: Stack<Int> = Stack.new()` tipa (§4.6 — **o risco nº1**).
- **CA74** — `xs.length` ⟶ `builtin-member-unsupported` (§4.7), **não** `unknown-member`.
- **CA75** — `for x in xs { }` ⟶ **`for-binder-unsupported`** (ruling §12-D). ⚠️ **Isto SUBSTITUI o teste que hoje afirma `errors.isEmpty`** (`check_test.dart`, grupo *"não-objetivos (§1)"*): o `for` deixa de ser aceito em silêncio e passa a **dizer** que é incompleto — que é o que a §12-4 da 009 já declarava em texto (*"até lá, `itac check` é incompleto para `for`"*), mas o código não dizia.

> ⚠️ **A stdlib NÃO é gate desta spec.** Os corpos dela misturam as duas camadas — `pop()` usa `self.items` (campo, **011**) **e** `self.items.length` (built-in, **012**). Ela já não compila hoje (5 de 12 módulos nem parseiam — dialeto antigo); que continue não compilando por 012 é **honesto**. **Os testes da 011 usam tipos do usuário.**

---

## §12 Rulings

### Fechados (dono, 2026-07-15) — ver §2
1. Os 5 hard-coded de `Option`/`Result` **morrem**; idioma é `match`/`if let`.
2. **`.map` em container → M5.** A 010 §2.1 fica void.
3. Colisão `struct` × `extension` ⟶ **`duplicate-member`**.
4. **Sem overload de método.**

### Pendentes

| # | Pergunta | Quem |
| :-: | :-- | :-- |
| **A** | **§12-B1 da 010 precisa ser RE-RATIFICADO.** O dono ratificou a **capacidade** (`extension` sobre built-in genérico) sob a **grafia errada** (`extension List<T>`, que é error production — §3.3). A capacidade sobrevive; a **alcançabilidade é M5** (falta a declaração de `List`). ⟹ dispara o escape-hatch do §12-B1 **por motivo diferente do escrito**: não "ilegal", **inalcançável** | dono |
| **B** | **B3 da 010** (herdado): `extension Foo { let length: Int }` parseia como **campo**, mas campo é armazenamento e extension não o adiciona (Swift proíbe *stored properties* em extension). É campo ou **getter computado**? | dono |
| **C** | **A precedência trait × superclasse** — recusei inventar (§3.4). Se um dia der `ambiguous-member` demais na prática, é ruling | dono (se surgir) |
| ~~**D**~~ | ✅ **FECHADO 2026-07-15 — `for-binder-unsupported`, erro declarado até o M5.** O **§12-4 da 009 fica INTACTO**: nada de tabela `List<T>→T`, nada de privilégio novo. `for x in xs` erra até o protocolo de iteração existir (M5, ADR-0012 §C-9). **Honesto, não novo:** o `itac check` **já** é incompleto para `for` hoje — a diferença é que passa a **dizer** isso em vez de aceitar em silêncio (a §12-4 já declarava: *"até lá, `itac check` é incompleto para `for`"*). A stdlib não é afetada — ela já não tipa por outras razões (§11) | — |

---

## Definition of Done

- [x] **PRIMEIRO: verificar o estado do memberwise init** — ✅ **feito 2026-07-15, e mudou a spec:** não é dívida da F3 (erro de numeração meu, §4.6); **é desta spec**. Não existe, e os construtores são aceitos em **silêncio total** (`_topLevelType` tem `_ => ErrorType` e o ErrorType é absorvente)
- [ ] **`init` memberwise sintetizado para `struct`** (ruling da 005 §10) + `class` exige `init` explícito
- [ ] **`P(...)` como construtor**: `_topLevelType` para de devolver `ErrorType` mudo para decl de TIPO — mata o silêncio da tabela acima
- [ ] ⚠️ **Auditar os outros catch-all `_ =>`/`default:`** que possam estar engolindo do mesmo jeito — é a 3ª vez que a mesma doença aparece (spec 006 `op:string`, `_decl`, `_topLevelType`)
- [ ] `TypeInfo.methods` + `MethodInfo` com **`origin`** (§3.2)
- [ ] A2 estendida: `extension`/`impl` contribuem membros para a tabela do alvo (§3.1/§3.2)
- [ ] Generics do alvo em escopo no corpo do `extension` **e do `impl`** (§3.3) + **`target-has-type-args`** (cobre os dois; libera `impl Comparable<T> for Stack`, que é *use site*)
- [ ] A3 estendida: `duplicate-member` (rulings §12-3 e §12-4)
- [ ] **`impl Trait for T` ⟹ `T ≤ Trait`** — mata o no-op silencioso (§1.2c) e cumpre o ADR-0012 #2
- [ ] `_member`: campo (§4.1) + método (§4.3) + walk herdado (§3.4) + `static` (§4.5)
- [ ] `CopyWith` (§4.2)
- [ ] `builtin-member-unsupported` (§4.7) + **`for-binder-unsupported`** (ruling §12-D) — os dois dizem *"lacuna do compilador"*, não *"erro do usuário"*
- [ ] **§4.6 — `Stack.new()` com `T` do contexto: ENTRA.** É o `[]` com outro nome (vacuidade, 6.5.1), e adiá-lo **declararia um privilégio de built-in** (face 1). Trabalho real: propagar o `expected` para o **retorno** — a 010 só desceu em args; o livro não cobre (Pierce & Turner §3)
- [ ] Corpus `conformance/check/` para CA60–CA74
- [ ] Os testes pinados em `check_test.dart` (grupo *"spec 011"*) **CAEM** — é o sinal de que funcionou
