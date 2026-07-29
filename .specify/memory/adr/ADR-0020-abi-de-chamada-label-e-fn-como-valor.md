# ADR-0020 — ABI de chamada, o opt-out de label, e `fn` como valor de primeira classe

- **Status:** **Decisão 1 ACEITA** (dono, 2026-07-29): **(E) `&dobro` — captura explícita no USO**. As decisões 2 (`_`) e 3 (label obrigatório) seguem **abertas**, e a (E) as desamarra — ver §11. O §4 (teorema) e o §7 (reversibilidade) permanecem como registro do que foi excluído e por quê.
- **Data:** 2026-07-29
- **Relacionados:** [[ADR-0016]] §A (meta-diretriz Swift; *não se auto-executa*), §C (*ordem obrigatória, defaults saltáveis; o label CONFIRMA, não reordena* — e explicitamente **não** decide a obrigatoriedade) · [[ADR-0017]] R2 (existencial **marcado**: `any Ord`; *"keyword, nunca `@` — P6"*) · [[ADR-0012]] (`@` proibido) · [[ADR-0013]] (inferência que falha é ERRO) · [[ADR-0019]] (o modelo deste ADR) · spec 013 §12-3 (params named required — **confirmado pelo dono 2026-07-16**) · spec 010 §12-1 (trailing closure) · `grammar.ebnf:213,230,320,353`

## Procedência

Preparado em 2026-07-29 por dois pareceres independentes, **assinados** (Art. IV-6b):
`ita-visionary` (leitura pelos 11 princípios e pelo Art. II) e `compiler-craftsman`
(sistema de tipos, com Dragon e TAPL). Auto-contido: o que os pareceres provaram está
transcrito com as fontes. **A recomendação é derivação da sessão; a decisão é do dono.**

Precedentes externos pesquisados nesta sessão e usados no §3: Swift **SE-0111**, Rust
(*function item* × *fn pointer*), F# (função × método .NET), Elixir/Erlang (`&f`, `fun f/1`).

---

## §1 O problema, medido

```
fn dobro(x: Int) -> Int => x * 2
fn aplica(f: (Int) -> Int, v: Int) -> Int => f(v)
fn main() { print("${aplica(f: dobro, v: 5)}") }
```

`itac check` → **PASSA**. `itac build` → **`ice-codegen-type-FunctionType`**. Programa
aceito pelo type-checker, morto no codegen com "erro interno" — o que a R6 proíbe.

**A causa é uma cisão de ABI que ninguém decidiu:**

- `collect.dart:643-646` dá `label: p.label ?? p.name` a **todo** param de `fn`. Sem opt-out;
- `check.dart:1079-1081`, verbatim: *"Closure é **posicional pura** — a superfície não tem label ali"*.

Duas convenções de chamada, escolhidas pelo **kind da declaração**, nenhuma assentada em
artefato. E a F5 aceita a travessia porque `ParamType.operator ==` **ignora `label`**
(`type.dart:256`), com a razão escrita no código: *"nenhuma função nomeada casava com um
tipo-função anotado, jamais — ordem superior só funcionava com closure"*.

### Dois fatos que reordenam o problema

**(i) A ABI dual SEM marcador já é o comportamento de hoje.** Verificado por execução:
`dobro(5)` **roda e imprime `10`**. `_matchArgs` (`check.dart:1804`) só consulta label
quando o call-site o escreve (`:1810`, `:1826`), e a F7 monta os `NamedExpression` pelo
**slot da nº5** (`emit.dart:1941-1960`), não pela posição textual.
⟹ **O marcador da opção (D) só significa alguma coisa se a decisão 3 for "sim".**

**(ii) Nada de ordem superior roda hoje.** Além do `_emitType` (`emit.dart:1682`), há dois
irmãos: `_ident` (`:1481`, `ident-nonlocal`) e `_call` (`:1917`, `call-<Res>`). São **três
buracos da F7, ortogonais às cinco opções** — nenhuma os fecha, e o ADR não pode vender
nenhuma como conserto deles. Consequência boa: toda opção aqui quebra exclusivamente
programas **check-verdes / build-mortos**. **É a janela mais barata que este ruling terá**,
e ela fecha quando a F7 emitir closure.

---

## §2 As cinco opções

**(A) Eta-expansão implícita.** O compilador gera `(v) => dobro(x: v)` quando um `fn` flui
para slot de tipo-função. Ergonomia de Swift/Rust.

**(B) Proibir**, com erro nomeado na F5 (`fn-not-a-value`). Ordem superior só com closure.

**(C) A ABI vem da DECLARAÇÃO — o `_` do Swift.** `fn dobro(x: Int)` = named, não é valor;
`fn dobro(_ x: Int)` = posicional, **é** valor.

**(D) Dupla ABI com marcador explícito** — a proposta do dono, análoga ao `any` do
TypeScript: *"não é implícito escondido, é marcado como podendo ser um ou outro"*.

**(E) Captura explícita no USO — `&dobro`.** A função nomeada não é valor; `&` a converte
no sítio onde isso acontece. É Elixir (`&dobro/1`) e Erlang (`fun f/1`).

---

## §3 Os precedentes, e o que cada um paga

| | mecanismo | por quê | consequência |
|---|---|---|---|
| **Swift** (SE-0111) | label sai do **sistema de tipos** | *"Removing this feature simplifies the type system"* | `(x: Int) -> Bool` e `(a: Int) -> Bool` viram o mesmo tipo; via valor, labels **proibidos**: *"If the invocation refers to a value … the argument labels do not need to be supplied"* |
| **Rust** | coerção *fn item* → *fn pointer* | não tem labels; o dilema é dispatch estático × indireto | automática, com "coerce-unify" em `if`/`match`/arrays. **O custo é invisível** |
| **F#** | função ≠ método | herança do .NET: *"Named arguments are allowed only for methods, not for let-bound functions"* | lambda explícita obrigatória. **É (B) por acidente histórico, não por design** |
| **Elixir/Erlang** | captura no uso (`&f`, `fun f/1`) | nome+aridade é uma entidade; valor-função é outra | marcador **no sítio do fenômeno** |

⚠️ **O Art. II posiciona o Itá como `Itá : Dart :: Elixir : Erlang`.** O precedente da
família que o próprio posicionamento invoca é o **(E)** — e ele não estava nas quatro
opções originais.

---

## §4 O TEOREMA que decide a opção (D)

A promessa da (D) é *"quem lê o código SABE"*. O precedente que o dono invoca, o `any Ord`
(ADR-0017 R2), cumpre isso porque o marcador está **no tipo** e portanto **viaja com o
valor**: todo slot que boxa diz que boxa. Um marcador de dupla ABI **na declaração NÃO
viaja** — em `f(5)` três arquivos adiante, ninguém sabe de nada.

Para o marcador viajar, ele tem de estar no tipo. E estar no tipo custa uma das três:

1. **Um tipo com terceiro estado "dual"** — se `dual == posicional` e `dual == named` mas
   `named ≠ posicional`, o `==` **deixa de ser transitivo**. Quebra o contrato de
   `Object.==` do Dart, quebra `Map<Type, k.DartType>` (a F7 faz `coreTypes[type]` em
   `emit.dart:1682`) e quebra o **union-find** (Dragon 6.5.5 / Alg. 6.19), que é uma
   estrutura de **classes de equivalência** — uma relação reflexiva+simétrica
   não-transitiva é uma *tolerância*, e union-find não a representa.
   ⚠️ **E é exatamente a propriedade que a analogia importa:** `any` do TypeScript e
   `dynamic` do Dart **são** relações de compatibilidade não-transitivas (`int → dynamic
   → String` é atribuível, `int → String` não). Daí vem a lavagem de tipos que o
   ADR-0013 tranca.
2. **Tipos interseção** (`((Int)->Int) ∧ ((x:Int)->Int)`) — Coppo–Dezani; Reynolds,
   *Forsythe*; **TAPL §15.7** (*lacuna declarada: o Dragon não tem interseção*).
   Interseção finita **é sobrecarga**: Dragon **6.5.3** e **Ex. 6.5.2** — sintetizar
   *conjunto* bottom-up e descer top-down. **Dois percursos**, contra o 1-walk da F5.
3. **Subtipagem** — `(Int)->Int` e `(x:Int)->Int` são **incomparáveis**: nenhum protocolo
   subsume o outro. Decretar `named <: posicional` **não é subtipagem, é coerção** — o
   valor tem de *mudar* na fronteira (Dragon 6.5.2: coerção é a que **materializa**, Fig.
   6.26). ⟹ **(D) como subtipagem é a (A) com passos a mais.**

> **Ou o marcador viaja e o sistema de tipos paga, ou o sistema fica são e o marcador não
> viaja. Não há terceira via.**

**Corolários, e são duros:**

- **(D) como DEFAULT é (A).** Se todo `fn` aceita as duas formas sem glifo, a superfície é
  a de (A) — e a diferença é só o lowering, que é técnica (Art. III), não identidade.
- **Logo (D) só existe como opt-in ⟹ pressupõe (B) ou (C)**, e adiciona um terceiro estado
  na declaração. E, pelo fato (i) do §1, ela **só ganha conteúdo se a decisão 3 fechar em
  "obrigatório"** — se a 3 ficar "opcional", o glifo nunca significa nada **e não se
  remove**, porque quebraria quem o escreveu. Glifo que só pode ser adicionado é a pior
  dívida de superfície.
- **Sob (D), a promessa se cumpre só no arquivo da declaração.** Isso tem de estar escrito.

**Glifo, se a (D) sobreviver:** `any` está tomado (ADR-0017 R2), `@` é proibido (P6). O
slot legítimo é o de modificadores de `fnDecl` (`grammar.ebnf:207`, que já toma
`static`/`override`), com **palavra, não sigilo** — é o precedente que o próprio R2 criou.
Anti-requisito registrado: **não pode ser parente de `any`**, porque `any` é marca que
viaja e essa não viaja.

---

## §5 O que o `ita-visionary` e o `compiler-craftsman` acharam contra cada uma

### (A) — não-itaiana por P4, mas **puramente aditiva**

Depois de `let g = dobro`, `g(x: 5)` é ilegal e `dobro(x: 5)` é legal: **o mesmo objeto
responde diferente conforme a via, sem marca no fonte**. É a forma já recusada duas vezes
no projeto (flow-narrowing; default sob `override`). E é resolução type-directed
**silenciosa** — a régua da casa licencia resolução por contexto *"quando o glifo a PEDE"*.

Dois defeitos técnicos próprios: **não é composicional sob `let`** (`aplica(f: dobro)` tem
sítio de subsunção, `let f = dobro` não tem — hoje isso é *mascarado* pela permissividade
do fato (i)); e **quebra identidade de valor-função** (duas travessias do mesmo `fn` são
dois closures distintos).

**Mas:** é a única **puramente aditiva** — cabe depois de (B), (C), (D) ou (E) sem quebrar
uma linha. Pela régua do ADR-0019 R4 (*"escolher o que só afrouxa depois"*), (A) é a
decisão que se **adia de graça**, não a que se recusa para sempre.

### (B) — cerca honesta, e **não fecha porta nenhuma**

Converte ICE sobre programa legal em erro nomeado da fase dona. O namespace unificado não
a proíbe: `struct`, `enum` e `trait` já são nomes que **não são valores**.

Custo real: **P5** — numa linguagem cujo 5º princípio é *"funcional é o caminho natural"*,
ter closure como único valor-função é ferida. Menor do que parece: `|>` e `>>` sobrevivem
(o desugar põe os operandos em posição de **callee**, `desugar.dart:809-826`); só morre
*passar como argumento*.

**Co-requisito:** a cerca tem de ser **posicional** (callee = ok, outra posição = erro). Se
for feita como "o nome não sintetiza tipo", mata `|>`/`>>` junto.

### (C) — itaiana na forma, com o rótulo errado

**Não sobrecarrega o ADR-0016 §C:** §C governa *o que um label presente faz*; (C) governa
*se o label existe*. E o glifo não é sobrecarregado — `_` no slot de label é o **mesmo
wildcard** de `pattern ::= "_"` (`grammar.ebnf:377`): *"não ligue este nome"*.

**Mas não é "P2 aplicado a funções".** P2 separa o que o valor **É** (identidade × cópia);
(C) separa **como se escreve a chamada**. A analogia promete semântica e entrega sintaxe.
**A justificativa correta é P4:** pelo §1, a cisão de ABI já existe e foi feita pelo
compilador — (C) não inventa, **revela**, e entrega o volante.

**Representação: é um QUOCIENTE, sem campo novo.** `ParamType.label == null` já é o bit
"posicional" (`type.dart:227-228`) e já circula em três sítios. A mudança inteira:

```dart
bool operator ==(Object other) => other is ParamType && other.type == type &&
    (other.label == null) == (label == null);
int get hashCode => Object.hash(type, label == null);   // vai JUNTO
```

Dragon **6.3.2**: o que entra no `==` é **estrutura**. "Tem label" é estrutura do protocolo
de chamada; "qual label" é texto da declaração. Swift fez o quociente **total**; (C) faz um
**mais fino** — mesma família, granularidade diferente.

⚠️ **Bloqueante:** há uma **terceira** noção de igualdade — `unify.dart:109-118`, cujo doc
diz *"Label/default são da declaração e não participam da equivalência estrutural"*. Sob
(C) esse arm muda junto, senão reincide o achado *"duas igualdades, uma negando a outra"*.

**Custo que precisa estar no ADR:** (C) torna ordem superior um **opt-in que o autor do
callee concede**. `map(f: dobro)` passa ou falha conforme alguém, noutro arquivo, ter
escrito `_` — invisível no call-site.

**E (C) tem emissão de custo ZERO**, por um motivo principiado: assinatura toda-posicional
⟹ o `Procedure` já tem tipo `int Function(int)` ⟹ **`StaticTearOff`** basta, sem
adaptador. *A ABI do tipo = a ABI do Kernel.* Toda outra opção paga wrapper ou forwarder.

### (E) — o precedente do Art. II, e o único com o glifo no sítio do fenômeno

`&dobro`. **P4 servido pela forma já ratificada duas vezes:** o `?` (no caractere da
propagação) e o `any Ord` (no slot que boxa) — o glifo fica onde o fenômeno ocorre.
Nenhuma das outras quatro tem essa propriedade.

**P5 resolvido sem pagar (C):** todo `fn` é capturável; nenhum autor precisa prever nada;
nenhum estado novo na declaração.

**Glifo livre, custo léxico zero:** `&` é lexado (`grammar.ebnf:129`) e **morto no parser**
(o bitwise foi para `Bits.*`, spec 001 / ADR-0012). É o glifo exato do Elixir; para quem
vem de C/Rust, `&dobro` lê como *"referência a `dobro`"* — **verdadeiro-amigo**.

**Sem aridade** (`&f`, não `&f/1`): o Itá não tem overload.

**Desamarra a fila:** (E) é ortogonal a `_` e a label obrigatório ⟹ a decisão 1 **sai** do
nó de três. É (A) com o glifo que o P4 pede — a eta-expansão continua sendo a técnica, muda
**quem a pede**.

*Handoff:* ambiguidade de `&` prefixo na escada de precedência (`unary`,
`grammar.ebnf:308-310`) é do `compiler-craftsman`.

---

## §6 A amarração das três decisões

1. `fn` em posição de valor: (A) (B) (C) (D) ou **(E)**?
2. O opt-out `_` entra? Com que semântica?
3. Label obrigatório no call-site?

### A decisão 3 não é sobre `div(den: 2, num: 10)` — é sobre `|>`, `>>` e trailing-closure

- `desugar.dart:815-816` (`>>`) e `:838`/`:845` (`|>`) constroem **`Arg(null, …)`** — sem
  label. E o desugar é **type-agnostic por design**: não tem como injetar label, não sabe
  quais são.
- `trailingClosure ::= block` (`grammar.ebnf:320`) **não tem slot de label**. É o
  idioma-bandeira, por ruling da spec 010 §12-1.
- **O memberwise não tem opt-out:** `field ::= ("var"|"let")? IDENT ":" type …`
  (`grammar.ebnf:230`) não aceita `_`, e `collect.dart:610` dá `label: f.name` a todo
  campo ⟹ sob label obrigatório, **`P(1, 2)` fica ilegal e sem saída**.

⟹ **Label obrigatório exige uma lista de isenções** — e lista de isenções é a forma exata
de *"o compilador escreve a forma que proíbe ao usuário"*. Se a 3 for "sim", o ADR tem de
dizer **no mesmo ato** o que acontece com `|>`, `>>`, trailing-closure e memberwise.

### Ordens possíveis sem quebrar código escrito

| ordem | veredito |
|---|---|
| **2 antes de 3** | **obrigatório** — *"cada `_` adicionado depois quebra os callers"* (`type.dart:301-304`) |
| 1 = (B) ou (E) agora | grátis: só quebra check-verde/build-morto (§1-ii) |
| 1 = (A) **depois** | seguro — puro afrouxamento |
| 1 = (C) **depois** de 3 | **fatal** — é o caso que a nota do dono descreve |
| 1 = (D) antes ou depois | seguro quanto a quebra; **fura a 3 nos dois casos** |

### ⛔ Combinação INCOERENTE, excluída por nome

> **(A) + label obrigatório.** O compilador fabrica `(v) => dobro(x: v)` e, dentro do
> thunk, executa a **chamada posicional que ele acabou de proibir ao usuário**. O
> compilador se isenta da regra que impõe — a violação mais pura de P4 neste espaço.

A mesma doença chega por outra porta em **(B)/(C)/(D)/(E) + 3 sem isenção declarada**.

---

## §7 Reversibilidade (régua do ADR-0019 R4)

| opção | quebra hoje | fecha porta |
|---|---|---|
| **(B)** | só check-verde/build-morto | **nenhuma** — todo o resto é aditivo sobre ela |
| **(E)** | idem | gasta o `&`; nada mais |
| **(C)** | idem | solda `_` a dois fatos ortogonais (legibilidade + ABI); **habilita** 3 |
| **(D)** | idem | gasta um glifo; **fura a 3 permanentemente**; única que adiciona superfície **e** restringe decisão futura |
| **(A)** | nada | **remover depois quebra todo call-site**; **foreclosa a 3**; institucionaliza custo invisível |

Ordem por reversibilidade: **(B) ≈ (E) > (C) > (D) > (A)**.

## §8 Custo por fase

| | F2 (gramática) | F4 | F5 | F7 |
|---|---|---|---|---|
| **(A)** | 0 | 0 | arm de `_isSubtype` + `kind` novo na nº7 (`coercions`) | wrapper **por sítio** |
| **(B)** | 0 | 0 | `==`/`hashCode` + `unify` + diagnóstico nomeado | baseline |
| **(C)** | 1 produção (`_` já é token — `token.dart:136`) | 0 | (B) + mapear `_`→`null` em 2 sítios | **ZERO** (`StaticTearOff`) |
| **(D)** decl | glifo novo | 0 | bit carregado-não-equiparado | ~0 (reescrita pelo slot da nº5) |
| **(D)** tipo | glifo novo | 0 | **dois percursos**, `Unifier` reescrito | — |
| **(E)** | `&` no `unary` | 0 | regra de captura | wrapper no sítio do `&` |

⚠️ **"(B) é a mais barata" é FALSO.** (B) ⊂ (C): mesma técnica de tipo, e (C) é (B) **mais
uma produção**. (B) não economiza no sistema de tipos — **perde a capacidade**.

⚠️ **As duas ABIs não são equipotentes.** O posicional só corta default do **FIM** — é a
razão inteira do §12-3. Default do **meio** é saltável **só** pelo named. Logo uma `fn` com
default no meio **não pode ser honestamente dual**: a "outra forma" perde call-sites.

---

## §9 Derivações da sessão (não são rulings)

**`ita-visionary`:** (B) agora + **(E) como destino**; `_` entra com a semântica do Swift
**desacoplado de "é valor"**; decisão 3 **não** obrigatória enquanto `|>`/`>>`/trailing não
tiverem resposta própria; (A) **adiada, nunca recusada**; (D) recusada como default (é (A)
com outro nome) e **dominada por (E)** como opt-in.

**`compiler-craftsman`:** **(C)**, com erro nomeado apontando o `_` como conserto, e a 3
adiada — porque (C) é a única com emissão zero, a única que não injeta não-determinismo na
inferência, e já tem 100% da representação pronta.

**Onde discordam:** (E) × (C) para a decisão 1. Os dois concordam em: (A) adiada não
recusada; (D) não como default; 3 adiada; 2 antes de 3.

## §10 O que fica FORA

Os **três buracos da F7** (`_emitType`, `_ident`, `_call`) — ortogonais, pagos de todo modo,
e nenhuma opção é evidência a favor de si por causa deles. Overload (o Itá não tem).
Aridade na captura (`&f/1` — desnecessária sem overload).

---

## Fontes

- [SE-0111 — Remove type system significance of function argument labels](https://github.com/apple/swift-evolution/blob/main/proposals/0111-remove-arg-label-type-significance.md)
- [Rust — fn item × fn pointer](https://users.rust-lang.org/t/puzzling-expected-fn-pointer-found-fn-item/46423) · [RFC 1558](https://rust-lang.github.io/rfcs/1558-closure-to-fn-coercion.html)
- [F# — Parameters and Arguments](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/parameters-and-arguments)
- Dragon **6.3.2** (equivalência estrutural) · **6.5.2** (coerção materializa) · **6.5.3** + Ex. 6.5.2 (sobrecarga: dois percursos) · **6.5.5** / Alg. 6.19 (union-find) · TAPL **§15.7** (interseção — lacuna do Dragon)
- `grammar.ebnf:129,207,213,230,308,320,353,377` · `type.dart:227,256,301` · `collect.dart:610,643` · `check.dart:1079,1804,1810,1826` · `desugar.dart:809-826,838,845` · `emit.dart:1481,1682,1917,1941-1960`

---

## §11 A decisão 1, e o que ela fecha

**O dono escolheu (E): `&dobro`.**

```
fn dobro(x: Int) -> Int => x * 2

dobro(x: 5)                  // chamada normal — o label continua
aplica(f: &dobro, v: 5)      // como valor — o `&` marca a conversão
```

**A razão, e ela é do Art. II.** Nenhuma das quatro opções originais tinha sido derivada
do posicionamento da linguagem; a (E) é. O Art. II diz `Itá : Dart :: Elixir : Erlang`, e
é exatamente assim que Elixir (`&f/1`) e Erlang (`fun f/1`) resolvem: nome+aridade é uma
entidade, valor-função é outra, e a conversão é **escrita**.

**É a forma que o P4 já ratificou duas vezes:** o glifo fica no **sítio do fenômeno** — o
`?` no caractere da propagação, o `any` no slot que boxa, o `&` no ponto em que a função
vira valor. Nenhuma das outras quatro tem essa propriedade.

### O que isto DESAMARRA

A fila do dono registrava três decisões como *"um ruling só"*. **Com (E), a decisão 1 sai
do nó:** o `&` é ortogonal a label. Sobram 2 e 3 amarradas entre si — que é a amarração
original e verdadeira do ADR-0016, sem a decisão de valor-função no meio.

Consequências diretas:

- **`_` (decisão 2) volta a decidir só legibilidade** — o sentido literal do Swift —, sem
  carregar ABI junto. Continua valendo *"o `_` antes do label obrigatório"*.
- **Todo `fn` é capturável.** Nenhum autor precisa prever, no arquivo dele, que alguém vai
  querer passar a função. Era o pior defeito de (C), e ele desaparece.
- **(A) segue adiada, não recusada.** Tornar o `&` opcional depois é puro afrouxamento —
  aceita mais programas, não quebra nenhum. A ordem inversa quebraria.
- **(D) fica recusada** pelo teorema do §4, e o registro dela permanece: um marcador de
  dupla ABI ou viaja com o valor (e o `==` perde a transitividade) ou não viaja (e a
  promessa *"quem lê SABE"* só vale no arquivo da declaração).

### O custo, declarado

Um símbolo novo a aprender, e o `&` passa a ocupar a posição de prefixo unário. Para quem
vem de C/Rust, `&dobro` lê como *"referência a `dobro`"* — verdadeiro-amigo, não falso.

### Escopo da implementação

`&` **é lexado hoje** (`grammar.ebnf:129`) e **morto no parser** (o bitwise foi para
`Bits.*`, spec 001 / ADR-0012), então o token existe e nada o usa.

1. **F2** — `&` como prefixo unário; ambiguidade na escada de precedência
   (`unary`, `grammar.ebnf:308-310`) é o único ponto de atenção.
2. **F5** — `&f` sintetiza o tipo **posicional** de `f` (mesmo tipo, labels descartados).
   Sem aridade no glifo (`&f`, não `&f/1`): o Itá não tem overload.
3. **F7** — a eta-expansão (`(v) => dobro(x: v)`) é a técnica, e ela é **exatamente a
   emissão de uma closure**. ⟹ **`&` depende de LT-F7c**: sem `FunctionExpression` e
   `FunctionType` emitidos, não há como baixar a captura.

**Ordem obrigatória: LT-F7c (closures) antes de `&`.** Não é preferência — é dependência.
