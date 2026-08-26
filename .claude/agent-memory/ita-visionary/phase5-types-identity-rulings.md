---
name: phase5-types-identity-rulings
description: Rulings de identidade da Semântica/Tipos (Fase 5, spec 009) — fronteira da inferência, NÃO-narrowing por fluxo, zero coerção, subtipagem nominal, exaustividade, must-use, e a lista de trair-o-Itá.
metadata:
  type: project
---

# Rulings de identidade da Semântica/Tipos (Fase 5 / spec 009)

Emitidos 2026-07-14 a pedido da orquestração (fundamentar §0.5 da spec 009). F5 = onde a
linguagem ganha SIGNIFICADO — é a fase que impõe (ou dissolve) o caráter do Itá.

## Regra-mãe que unifica os 7 pontos
**"A inferência do Itá não atravessa fronteira de declaração; nenhuma conversão acontece
sem um glifo que o usuário escreveu."** Tudo abaixo é corolário. P4 + P6 reconciliados:
P6 = o checker não *precisa* de anotação para trabalhar (dentro do corpo); P4 = a *fronteira*
é contrato e se escreve.

## 1. Inferência — DENTRO infere, BORDA anota. Resolvi (P6 + P4).
Local (`let`/`var` em corpo), closure (params + retorno), type-args de generic (sem turbofish)
→ **inferido**. Assinatura de `fn` nomeada (params **e** retorno), campo de struct/class,
global top-level → **anotado obrigatório**. HM global/unificação cross-function = RECUSADA
(é "inferência que esconde intenção": corpo decide API pública; erro longe da causa).
Modelo = **bidirecional** (síntese + checagem contra esperado) = o "HM modesto" do ADR-0004.
**Global anotado é forçado** pelo letrec de módulo ([[phase4-binding-identity-rulings]] #3):
grupo mutuamente recursivo sem anotação exigiria unificação global.

## 2. Narrowing — `guard let`/`if let` NÃO é narrowing; `if x != nil` NÃO estreita. Resolvi.
Chave: `guard let v = opt` é **desestruturação de `Option` via pattern** (`.some(v)`), não
flow-narrowing. `v` é binding NOVO; `opt` continua `T?`. Zero análise de fluxo, e o nome novo
É a honestidade (P4). Já cai da regra de tipo de `match` que F5 tem de ter de qualquer jeito.
**`if x != nil { x.foo() }` → ERRO** `member-on-optional` com hint ensinando `if let`. Why:
smart-cast = um nome com 2 tipos em 2 linhas do mesmo escopo, sem marca sintática (P4); regra
assimétrica `let` vs `var` (P1); e é a *cura da doença que o Itá não tem* — TS/Kotlin/Dart
inventaram narrowing porque têm null sem Option; o Itá tem `.some`/`.none` + match exaustivo.
`x != nil` segue LEGAL sem warning (pergunta booleana honesta). `!` (force-unwrap) é a válvula
explícita (glifo anuncia risco → `panic`, P7). Ergonomia decide sem sermão: `if let x = x { }`
é MAIS CURTO que `if x != nil { x!. }`.

## 3. Coerção — ZERO, nem widening. Resolvi (P4 + precedente unânime).
`Int + Double` = erro (`.toDouble()` explícito). Sem `Int8→Int64` implícito. **Armadilha
nomeada:** `.specify/templates/spec-template.md` §4.5 manda "widening (implícita) vs narrowing
(cast)" + `max(t₁,t₂)`/`widen()` [Dragon 6.5.2] — **é a técnica do livro, não a lei do Itá**
(Art. III: implementar a maquinaria ≠ adotar a política). No Itá `max(t,t)=t`, resto = erro.
Bônus técnico: "widening preserva" é FALSO aqui (Int 64-bit → Double = 53-bit mantissa; spec
001 Q3 fez Int64 wrap normativo). Precedentes: ADR-0012 #6, spec 001 §4.5, BYTES_BUFFER_PLAN,
nullity-invariant. **Corolário:** literal tem tipo LEXICAL (`let x: Double = 1` = erro, escreva
`1.0`) — o lexer já decidiu int×float (conformance `int_bases`/`floats`); F5 reinterpretar
contradiz fase anterior. **Corolário 2:** tipo de `match`/`if`-expr = braços IGUAIS (join =
identidade); supertipo comum só por subsunção contra tipo ESPERADO declarado, nunca por lub
sintetizado (senão widening entra pela porta dos fundos).

## 4. Subtipagem — nominal declarada; `struct` não herda. Resolvi (P2 + P4 + ADR-0012 A2).
Estrutural = conformance por acidente → RECUSADA (ADR-0012 A2 já escolheu declaração-de-intenção:
inline `struct P: Trait` ou `impl Trait for T`). `class D: Animal` É subtipo (P5 "OO quando faz
sentido"). `struct` = **final, só conforma trait, NUNCA herda** (P2: subtipagem de valor = slicing
= código faz MENOS do que diz). Variância: **invariante** por ora (covariância em container mutável
é insound — array store do Java); não herdar a variância do Kernel por acidente (ser mais restrito
que o alvo é sempre seguro). **ABERTO (dono):** `struct` conformando trait vira existencial/trait-
object implícito (boxing → tensão com P2)? Recomendo: **generics com bound** `fn f<T: Drawable>(x: T)`
é a via natural (zero boxing, casa com TFA/ADR-0004); existencial, se entrar, exige marca (`any Drawable`).

## 5. Exaustividade — ERRO, não warning. Resolvi (P3 + ADR-0011).
"Promessa que só avisa não é promessa" (ADR-0011: "match exaustivo é promessa da linguagem";
ADR-0004: era 1 dos 5 bugs). P3 decide: `match` é EXPRESSÃO — braço faltando = expressão sem
valor; warning obrigaria fallback runtime (throw → fere P7; nil → fere nullity). Maranget 2007
dá a testemunha → erro lista as variantes faltantes. **Fronteira:** a CHECAGEM é F6 (ADR-0011);
F5 só provê o conjunto de variantes + tipa pattern×scrutinee. **`_`:** distinguir `_` de BRAÇO
(catch-all — o hazard) de `_` de PATTERN/binding (`let _ =`, `.some(_)`, param — nunca avisar).
Domínio infinito (Int/String): `_` é obrigatório, zero warning. Enum fechado: recomendo warning
`wildcard-covers-known-variants` LISTANDO as variantes engolidas — **ruling de dono aberto** (é o
único lugar onde o Itá amolaria código legal; nullity-invariant firmou "não amole o dev").
Braço com guard não conta para cobertura (Maranget).

## 6. `?` / Result — `?` só em fn que retorna Result; must-use é ERRO. Resolvi (P7 = P4 aplicado a erro).
`?` fora de fn `-> Result` = `try-outside-result-fn` (F5: precisa do retorno da fn envolvente —
que é DECLARADO pelo ruling 1 → checagem local e barata; composição bonita). **Tipo do erro tem de
ser o MESMO** — sem `From` auto do Rust (é o único lugar onde o Rust fura o próprio "sem conversão
implícita"; não importar). Converta com `.mapErr()` e depois `?`. Propagação automática NÃO é mágica:
o glifo `?` está no caractere exato onde acontece (+ dump do desugar); a mágica é o try/catch, onde
a AUSÊNCIA de marca significa "pode lançar". **Must-use = ERRO** `unused-result` (não warning — é o
arrependimento nº1 do Rust; Result descartado = exceção não-checada com passos extras, e P7 é
princípio PERMANENTE, não convenção de lib). Escape explícito: `let _ = f()`. NÃO estender must-use
a `Option` (ausência ≠ erro; é dead-code = F6). `panic` deve ter tipo `Never` (bottom).

## 7. Trair o Itá — catálogo F5 (ver também [[identity-yield-and-nao-fazer]])
1. **`dynamic` como escape.** ⚠️ **CONFLITO COM ADR-0004** ("regra de ouro `UnknownType`→`dynamic`
   onde a inferência não é confiável") — era bootstrap do ORACLE (M1), e é exatamente o mecanismo da
   família "compila mas roda errado" que o ADR-0004 nasceu para matar. F5 do ita-next: falha de
   inferência = **erro** (`cannot-infer`), nunca dynamic. `dynamic` só como fallback INTERNO do
   codegen (Kernel exige tipo), jamais tipo de superfície/escape semântico. **Divergência precisa ser
   DECLARADA na spec 009 (ADR novo/ruling de dono)** — não reinterpretar ADR em silêncio.
2. Dynamic vindo do `dart:` (ex.: `req.json()`) deve ser **decodificado no border** (`Result`), nunca
   fluir pra dentro — senão o Norte de independência apodrece por dentro.
3. Truthy: condição de `if`/`while`/`guard` e `&&`/`||`/`!` exigem **exatamente `Bool`**.
4. Null implícito / default-init (`var x: Int` = 0). nullity-invariant: default NUNCA vira nil.
5. Inferência global (Q1), lub/widening implícito (Q3), `as` cast (ADR-0012 #6 já recusou).
6. Nullable-by-default do interop: tipo `dart:` chega como `T?` explícito.
7. **Panic recuperável** (`Result::catch`/`recover`) = try/catch de sobretudo. A recuperação itaiana
   é **supervisão** (o `actor` já está na AST; herança Erlang), não catch.
8. Interpolação `"${opt}"` imprimindo "nil"/"none" = doença do JS. Recomendo exigir conformance
   `Show`/`Display`; `Option` não conforma (desembrulhe). Recomendação, não ruling.

## Review da spec 009 escrita (2026-07-15) — 3 rulings NOVOS

### R1. `T?` nativo SIM; achatamento é **idempotência de modificador**, não perda. Resolvi.
Aceito o dado do `dart-vm-expert` (box estrutural nos 3 alvos; TFA não faz escape analysis).
**Mas a justificativa tem de ser doutrinária, não de custo** ([[doctrine-vm-data-reinforces]]).
Doutrina a cravar: **`?` é MODIFICADOR** (propriedade do slot — "a porta para `nil`", palavras do
`nullity-invariant`; mesma forma do `mut` = flag do §4.1), **`Option<T>` é o nome canônico do mesmo
tipo**. Logo `T?? = T?` é idempotência (`mut mut T = mut T`), não achatamento. **`T??` escrito à mão
= erro `redundant-optional`** — aceitar em silêncio é engolir um glifo (P4). Nesting genuíno = o
usuário declara ADT próprio com nome próprio (`enum Maybe<T>`). RECUSAR o "Option boxed volta para
esses casos" do §12-1: duas vias para ausência fere P4 + "um nome, um significado" (F4 #1).
**Argumento "Dart/Swift/Kotlin aceitam" é INCOERENTE** — é a mesma tríade que o §4.6 acusa de ter
inventado narrowing para curar doença que o Itá não tem. Não citar como precedente.

### R2. `Object?` NÃO é `any` — mas só como tipo ESCRITO, jamais como fallback. Resolvi.
`dynamic` = "não cheque nada, permita tudo"; `Object?` = **topo** = "cheque tudo, permita nada até
provar". Habilita a checagem em vez de desligá-la ⟹ não é a tentação nº1. **PORÉM:** "onde a
inferência falhar, use `Object?`" (§8.3) É a porta dos fundos e contradiz o próprio §4.8/CA5.
Fallback do checker é **sempre `cannot-infer`**. `Object?` é (a) fato de EMISSÃO da F7, ou (b) tipo
que o usuário escreve na borda `dart:` enumerada. Nunca política da F5. `Object` nem está no §4.1 —
se entrar na superfície, é pela borda e com ruling próprio.

### R3. `Option<T>` é BUILT-IN e NOMEÁVEL — a spec quase reverteu ruling de dono. Fato verificado.
§4.6 diz *"`Option<T>` segue como ADT comum do usuário, **sem privilégio sintático**"* — **falso nos
dois sentidos**, e colide com o ruling do dono de 2026-07-12 ("O Itá TEM `Option<T>` BUILT-IN").
Evidência: `Option` **não é declarado em lugar nenhum** da stdlib (grep: zero `enum Option`) e é
usado como tipo NOMEADO e GENÉRICO em toda ela — `iter.tu:64` `compact<T>(list: List<Option<T>>)`,
`iter.tu:203` `find<T>(…) -> Option<T>`, `collections.tu` (12×), `server.tu:337` `var result:
Option<Response> = .none`. Como "ADT de usuário" ele não existiria. **Recomendação: `Option<T>` ≡
`T?` (alias canônico, à la Swift `Optional<T>`)** — honra o dono, mantém a stdlib válida, mata a
ambiguidade. **Caso concreto de custo do achatamento (não-hipotético):** `compact` com `T=String?`
recebe `List<Option<String?>>` = `List<String??>` → achatado, ele não distingue "ausente" de
"presente e nil" e descarta nils presentes em silêncio. Vive na stdlib canônica; depende de
genéricos (fatia D) ⟹ **§12-1 pede decisão antes de a evidência entrar em escopo.**

### R4. `undetermined` do Kernel é LEGÍTIMO — eu errei; ruling corrigido. (2026-07-15)
Eu afirmei que `Nullability.undetermined` seria "o `UnknownType` do oracle disfarçado de byte" e
pedi o invariante "undetermined = bug da F5". **ERRADO — derrubado pelo `dart-vm-expert`, verificado
por mim na fonte.** `undetermined` é informação **precisa sobre tipo aberto**: um `T` undetermined
**rejeita `null`** E **rejeita atribuição a `Object`** — duas proibições CONHECIDAS. O `UnknownType`
é curinga nos dois sentidos (aceita tudo, vai para tudo). **São duais, não parentes.** Evidência que
achei sozinho (mais forte que a doc): `pkg/kernel/lib/src/types.dart:460-660` tem regras de
subtipagem **dedicadas** — *"The two nullabilities are undetermined, but are connected via"* — e o
predicado `isPotentiallyNullable` (`:93`). Ninguém escreve regra de subtipagem para estado de erro.
**E o pior:** meu invariante seria **verdadeiro por acidente** em A+B e **falso** na fatia D —
`List<E>` aceitando `List<Int?>` exige bound `Object?` ⟹ `E` nu **é** `undetermined`; emitir
`nonNullable` ali é **mentira de tipo**, e a TFA é closed-world (acredita e deriva unboxing).
**Formulação correta (preserva a intenção — matar o `UnknownType`):** a F5 nunca **ESCOLHE**
`undetermined` por não saber; só o **DERIVA** de um bound. Legal/obrigatório em type-param com bound
nullable; bug em tipo concreto; proibido em `Never`. Lição de método → [[doctrine-vm-data-reinforces]].

### R5. Overload de OPERADOR — permitido, mas resolvido SÓ pelos operandos. Resolvi. (2026-07-15)
**Não é decisão nova:** o **ADR-0012 B8 já a tomou** — *"Só **overloading** infix do conjunto fixo de
símbolos por ora"*. A 009 decide a **disciplina**, não o "se".
- **Não fere o F4 #1 (namespace unificado) — é category error.** `+` **não é nome**: é
  `BinaryOp.add`, enum fechado (ADR-0012 A5); a F4 não resolve operador. Despacho por tipo do
  operando é o MESMO mecanismo de `.map` em `List` e em `Option` — se overload de operador fosse
  "um nome, dois significados", **todo método de trait seria também**. Teste decisivo, reductio.
- **É EXIGIDO pelo Norte de independência do Dart:** se o usuário não pode declarar `+`, a stdlib
  também não pode, e `Int + Int` fica mágica do codegen **para sempre** — o oposto de "built-ins
  migrados para `.tu`" (MANIFESTO §Norte). **Overload é o que torna built-in não-privilegiado;
  RECUSAR overload é que seria a mágica.**
- **Resolução: SÓ pelos operandos, match EXATO, sem ranking.** Nunca por retorno/contexto (Ada /
  Dragon Ex. 6.5.2). Why: contexto decidindo faz `let x: A = p+q` e `let y: B = p+q` serem a mesma
  expressão com significados diferentes = ação à distância (P4); e o modo `check` deve **verificar**,
  não **escolher**. Zero coerção (§4.5) faz o lookup ser exato — é *resolução*, não *escolha*
  (tentação nº9 pagando dividendo). O "1 walk" sobrevive **por consequência do princípio**, não por
  escolha de perf ([[doctrine-vm-data-reinforces]]).
- **Sobreposição por subtipagem** (`+` para `Animal` e para `D : Animal`) reintroduziria ranking →
  **erro na DECLARAÇÃO** (`overlapping-operator-impl`), não ranking no call-site. Diagnóstico na
  causa, não no uso. Precedente: regras de coerência/overlap do Rust (vizinho do "zero coerção").
- **Linha que salva o `.none` contextual:** resolução por contexto é legítima **quando o glifo a
  PEDE** (`.` de `EnumShorthand` = "olhe o tipo esperado"); ilegítima quando é **silenciosa**
  (overload por retorno). O `.` é o pedido explícito; `p + q` não anuncia nada.
- **Achado estrutural (parser.dart:218, 459-495):** `OperatorDecl` é **top-level livre** com
  `precedence`/`associativity`. Mas essas são propriedades **do símbolo**, decididas pelo **parser**,
  antes de existir tipo — **não podem variar por tipo**. E o conjunto de símbolos é FIXO (A5/B8) ⟹
  precedência declarada é **redundante ou mentira**. Mesmo argumento do `T??`: **engolir em silêncio
  um glifo declarado é P4**. Recomendo `operator-precedence-conflict` na divergência.

### R6. `let` sem init — **PROIBIR** (opção A). Reverti minha recomendação. (2026-07-15)
**Minha recomendação anterior ("permitir + definite-assignment") apoiava-se em premissa FALSA** e
o dono ratificou o ruling 7 **com base nela** ⟹ **tem de voltar para ele** (Governança: decisão dele,
premissa minha, premissa caiu). Ver [[doctrine-argumento-de-ausencia]].
- **A premissa que caiu:** eu disse que RD-1 (blocos não rendem) tornava o uninit-let a válvula
  contra `var`. Category error — `if`/`match` **não são blocos, são expressões** (P3).
  `conformance/valid/expr_if.tu:1` `let m = if a > b => a else b`; `:3` cobre até `if let` dentro.
- **A linguagem cobre init imutável por TRÊS caminhos:** (1) `if`/`match`-expr → condicional;
  (2) **`where { }`** → multi-passo com bindings intermediários (é literalmente o construto
  value-first da ADR-0012 A4 — ele EXISTE para isto); (3) `?`/`guard let` → early-exit. Uninit-let
  não é 4ª válvula: é 4º caminho que duplica os três sendo menos honesto que todos.
- **Argumento decisivo (consistência com o MEU ruling 2):** eu recusei flow-narrowing porque
  *"um nome com dois significados em duas linhas do mesmo escopo, sem marca sintática"*. Em `let x: T`
  + `x = v`, o glifo `x = v` significa **inicializar OU mutar** conforme o histórico de fluxo, sem
  marca. **Mesma doença.** Recusar lá e aceitar aqui é incoerência. E o que fez `guard let` ser
  honesto foi o **NOME NOVO**; aqui não há marca nenhuma.
- **"Cura de doença que o Itá não tem"** (mesma forma do ruling 2): o Swift precisa de uninit-let
  porque não tinha if-expr (até 5.9). O Itá tem.
- **Domínio útil é VAZIO:** onde a F6 conseguiria provar exatamente-uma-atribuição, if/match/where já
  resolvem; onde seria preciso (loop, 0..n iterações), a F6 **não consegue provar**. Legal só onde é
  desnecessário; necessário só onde é ilegal.
- **Forma:** `let` passa a exigir `= EXPR` **na GRAMÁTICA** (parser) — reverte a opcionalidade do D5
  **para `let`**; `var` mantém init opcional (mas exige anotação sem init; F6 faz use-before-assign,
  já declarado no ADR-0011). **A assimetria É o princípio visível na gramática:** `let` liga um valor
  (precisa do valor); `var` é slot mutável (pode encher depois). Mata o `let z` nu do dono na raiz.
- **Fronteira parser×F5 (refina [[doctrine-ast-representa]]):** "representar e deferir" governa
  **VALIDAÇÃO** (tipo, escopo, pureza — `pub init` é forma legal com política diferida), **não FORMA**.
  Se a forma não está na linguagem, não está na gramática. Precedente do dono: `where { let y }` sem
  valor morreu no PARSER (2026-07-14). O D5 segurou a forma aberta **enquanto a decisão pendia**;
  decidida, a gramática fecha.
- **Recusar `late let` (opção B):** keyword nova para domínio vazio; e `late` é do Dart, que a tem
  porque tem null+late-init — importar cura de doença alheia (Art. II). Se o dono insistir em escape,
  B > C (B tem a marca; C não tem).
- **Entrega:** erro do parser deve ENSINAR os três caminhos (padrão `member-on-optional`).

### R7. `class-after-trait` ("superclasse primeiro ou em lugar nenhum") — **ITAIANO**. Resolvi. (2026-07-15)
Surgiu do ruling do dono *"o papel vem do KIND, não da posição"* (2026-07-15), que deixou aberto o
`class` em posição não-primeira (`class Dog : Barker, Animal`). O `compiler-craftsman` implementou a
cerca e veio perguntar se eu vetava. **Confirmo — e NÃO precisa do dono: não contradiz o ruling (b),
o COMPLETA.**
- **A tensão é aparente — dissolve-se em DERIVAÇÃO × APRESENTAÇÃO** → [[doctrine-derivacao-vs-apresentacao]].
  (b) proíbe o **compilador** de INFERIR papel da posição; a cerca proíbe a **fonte** de CONTRADIZER,
  na posição, o papel que o kind dá. A cerca só é **enunciável** porque (b) é verdadeiro.
- **Mesma forma do próprio (b):** (b) consertou o **compilador** atribuindo mal por posição; a cerca
  conserta o **leitor** atribuindo mal por posição. Os dois dizem: *kind e posição têm de concordar*.
- **Teste decisivo (P4):** sem a cerca, `class Dog : Barker, Animal` convida a **leitura errada mais
  natural** — toda linguagem da família `:` põe a superclasse primeiro. Forma que deixa a leitura
  natural CORRETA é P4-positiva; forma que deixa a leitura natural errada e sem correção é P4-negativa.
- **Família (o `:` do Itá já é o de Swift):** Java = **keyword** marca (`extends`/`implements`);
  Kotlin = a **chamada** marca (`A()`); Swift = a **posição** marca, imposta; Itá = **kind** marca +
  posição imposta. Ordem livre faria do Itá a **única** da família com superclasse posicionalmente
  livre — novidade sem razão, em sintaxe emprestada do Swift (que é o precedente que o DONO citou p/ (b)).
- **Monotonia (vale mesmo se eu errasse):** a cerca RESTRINGE. Relaxar depois preserva todo programa
  válido; apertar depois quebra. Restringir-agora-relaxar-depois é o default seguro sob ruling pendente.
- **Cerimônia não se aplica direto — é category error:** a doutrina do `override` fala de **marca**;
  a cerca não acrescenta glifo nenhum. O que se aplica é o P4 por trás dela.
- **A justificativa no comentário estava SUPERESTIMADA** (`collect.dart:172-174`): a 1ª posição **não**
  dá "herda de alguém" de graça — dá *"B e C certamente NÃO são a superclasse"*; o kind de A ainda é
  preciso. O ganho real: a busca do leitor cai de **N arquivos para 1**. Mesma forma do `override` (que
  também não diz QUAL superclasse tem o método — aponta, não responde). Corrigir: justificativa
  superestimada em comentário é semente de decisão errada futura.
- **Opção (iii) nomeada e recusada:** marcar a superclasse com glifo (o `A()` do Kotlin) — inventa
  superfície nova para comprar o que a ordem já compra de graça; e o Itá não tem chamada-de-construtor
  na lista de conformances.

### R8. `_isSubtype` ignora type-args — **ENTAILMENT**, e o fix NÃO espera o ruling de variância. (2026-07-15)
`check.dart:1772-1778` (`_reachesDecl`) compara só `identical(s.decl, sup)` e **descarta `s.args`** ⟹
`class D : A<Int>` satisfaz `A<String>`. **É o código contradizendo a spec, não pergunta de design.**
- **Fundamento correto — NÃO é a cláusula do ADR-0013.** A *decisão* do 0013 é sobre `dynamic`/
  `cannot-infer`; isto não é vazamento de dynamic. Quem governa: **ADR-0007** (linhas 30-31 — Kernel
  tipado *"conserta os bugs 'compila mas roda errado'"*) + **spec 009 §4.2b** (`≤` *"só existe onde foi
  declarado"*) + P4. O 0013 entra como **precedente de método** (Contexto item 3: *"o checker nunca erra
  onde a inferência não alcança"*). Não esticar ADR para além do próprio texto.
- **3ª ocorrência do mesmo defeito** (após `override-signature-mismatch` e `missing-trait-member`,
  [[phase5-011-w3-review]]): **promessa declarada e não verificada** ⟹ `D ≤ A` mente.
- **Invariância É ruling, não doc acidental:** spec 009 §4.2b (linha da tabela *"variância: INVARIANTE
  | v1"* + o parágrafo *"não herdar a variância do Kernel por acidente"*) + **CA27**. Origem: meu ruling
  #4 de 2026-07-14, ratificado na spec escrita.
- **Achado: CA27 não tem teste** (grep em `test/`: zero) — Art. IV-4 manda todo CA virar conformância.
  **E ele passa assim mesmo, por sorte estrutural:** `List<Cachorro>` é `BuiltinType`, e `BuiltinType.==`
  compara args (`type.dart:166-167`) ⟹ nunca chega ao walk. **A regra vale onde foi testada por acaso e
  falha onde não foi:** o furo é exclusivo do walk de HERANÇA.
- **Não é questão de variância — e isto DESBLOQUEIA o fix.** Covariância licenciaria `A<Cachorro> ≤
  A<Animal>` (args *relacionados* por ≤). `Int` e `String` são **não-relacionados**: nenhuma disciplina
  do espaço de design (co, contra, `in`/`out`, bi) licencia `A<Int> ≤ A<String>`. O bug não é
  "invariância não imposta" — é **args ignorados**, insound sob TODA regra candidata →
  [[doctrine-consenso-entre-candidatos]].
- **Forma do fix (a parte de identidade; mecanismo é do `compiler-craftsman`):** o walk tem de
  **INSTANCIAR** a fonte, não só comparar decls — `class D<T> : A<T>` ⟹ `D<Int> ≤ A<Int>` exige subst.
  Logo "comparar args por `==`" só está certo **depois** da substituição. E a subst passa pelo smart
  constructor (spec 009 §4.6 cond. 1; ver R1) ou a forma canônica de `T?` quebra calada.
  **Isolar a comparação de args em UM ponto** — é o ponto que uma regra de variância futura substitui.
- **LACUNA DECLARADA — variância declarável (`in`/`out`) é decisão de DONO, em aberto.** O corpus só
  diz *"variância declarada é débito futuro"* (§4.2b); Art. I/II e ADRs não se pronunciam. Dois insumos
  para quando vencer: (1) **P6 não a proíbe** — `in`/`out` não são `@decorators`, são keyword de decl
  como `mut`, e passam no teste do `mut`/`override`; (2) **o ângulo itaiano:** a justificativa da
  invariância no §4.2b é *covariância em container **MUTÁVEL*** — está **condicionada à mutabilidade**,
  e o Itá é a linguagem onde mutabilidade é modificador explícito (P1, `mut`). O Itá poderia amarrar
  variância ao `mut` (covariante quando imutável, invariante sob `mut`) — a história de coleção
  read-only feita por modificador em vez de duas hierarquias. **Recomendação a considerar, não doutrina**
  (custo: `≤` passa a depender do `mut`; exige spec própria).

### R9. `class` construível SÓ por `init` de `extension` — **ITAIANO**; o `no-init` é bug. (2026-07-15)
`class C { x: Int }` + `extension C { init(x: Int) {} }` + `C(x: 1)` ⟹ `no-init`. Causa: `check.dart:983`
consulta os candidatos só com `cands.length > 1`, e `class` **nunca** tem memberwise ⟹ `cands.length == 1`
⟹ `info.init == null` ⟹ `no-init`. `struct` não sofre (o memberwise garante ≥2).
- **O ruling do dono não alcança `class` — por VACUIDADE, não por silêncio.** As duas cláusulas ("init no
  CORPO mata o memberwise" / "init em extension o PRESERVA") têm predicado *"o tipo tem memberwise"*.
  `class` não tem ⟹ nenhuma decide. Se parasse aqui, seria lacuna.
- **Quem decide é fonte ANTERIOR — ADR-0012 A1**, literal: *"`class` usa `init` **explícito** … O parser
  aceita `InitDecl` nos corpos roteados por `_typeBody` (struct/class/trait/**extension**/actor/impl) … a
  política por-kind é imposta na Fase 3 [=F5]"*. Dois fatos: (i) o critério é **explícito × sintetizado**,
  não *onde se escreve* — e um `init` de extension é explícito (o usuário escreveu param, label, corpo);
  (ii) o ADR **nomeia `extension`** entre os corpos que admitem `InitDecl`. A forma é ato de dono, datado.
  "Sem construtor" não é política — é o `_call` não olhar.
- **Mérito por [[doctrine-porta-fechada]]:** nada é sintetizado; a única porta foi aberta pelo usuário,
  com glifo. O comentário do `check.dart:891-896` (*"abriria a pergunta feia de memberwise + herança"*)
  defende contra **SINTETIZAR** e continua correto — não alcança init escrito à mão.
- **A leitura restritiva se condena sozinha** ⟹ [[doctrine-consenso-entre-candidatos]]: se `class` fosse
  inconstruível-ponto-final, `extension C { init }` seria forma que parseia, coleta em `extensionInits` e
  é inalcançável, e o erro (`no-init`) seria **mentira** (há init). A forma honesta dela seria erro
  **nomeado na decl**. As duas leituras rejeitam o comportamento de hoje; só uma tem respaldo textual.
- **4ª instância de "feature meio-ligada"**, e a regra de método ganha refino: o co-requisito duro que
  eu impus (o escape tem de ABRIR) foi pago **só para `struct`** — testes `check_test.dart:713`/`:1144`
  testam extension-init só sobre `struct`. ⟹ **ao aceitar um glifo, testar a chamada em TODOS os kinds
  que o glifo admite.**
- **LACUNA DECLARADA (dono) — herança:** `class D : A` com campo em `A` — como `A` é inicializada? **Não
  há `super` na gramática** (grep `grammar.ebnf`: zero; zero `super.init` fora do vendor Dart). É
  **ortogonal ao R9** (morde igual com o init no corpo) ⟹ **não bloqueia o fix** (`cands.isNotEmpty`).

### R10. O `label` é da DECLARAÇÃO, não do TIPO — e a GRAMÁTICA já respondeu. (2026-07-15)
`fn dobro(x: Int)` não casava com `(Int) -> Int` (sem arm de `FunctionType` no `_isSubtype` + `label` no
`ParamType.==`) ⟹ **ordem superior só funcionava com closure**. **Não é pergunta de design em aberto.**
- **Fundamento nº1 — `grammar.ebnf:353`:** tipo-função é `"(" (type…)? ")" ("->" type)?`. **`(x: Int) ->
  Int` não parseia.** Logo `(Int) -> Int` e `(x: Int) -> Int` não são "o mesmo tipo": o 2º **não existe**.
  Doutrina completa → [[doctrine-declaracao-vs-tipo]].
- **Superfície verificada** (não intuída — [[doctrine-argumento-de-ausencia]]): stdlib escreve tipo-função
  100% posicional (`event.tu:6`, `async.tu:9`, `iter.tu` ×16, `server.tu:91`) e chama valor-função sem
  label (`iter.tu:205` `predicate(item)`). `desugar.dart:815-816`: `f >> g` → `Call(f, [Arg(null, …)])`
  — **posicional**; label no tipo quebraria `>>`/`|>` sobre fn nomeada.
- **O label já é OMISSÍVEL hoje em todo call-site** (`arg ::= (IDENT ":")? expr`; `_matchArgs` aceita
  `label == null`, `check.dart:1216-1241`): a regra do dono é *"ordem obrigatória, defaults saltáveis; o
  label CONFIRMA, não reordena"*. **Confirmador opcional não é discriminador de tipo.**
- **Diretriz Swift = desempate, não fundamento** (SE-0111 tirou o label do sistema de tipos). Os pontos
  acima decidem sem ela.
- **Sem tensão com o item 0** (`div(den:2, num:10)`): aquilo é **call-site de nome**, e o conserto exige
  o label **no dado** (`_matchArgs`), não no `==`. **Carregar ≠ equiparar.**
- **CORREÇÃO — o "ruling prévio" citado NÃO é do dono.** *"Label participa do `==`; default não"* está em
  `compiler-craftsman/dispatch_members.md:101`, e ele mesmo a chama de *"o meu ruling"*
  (`f5_quantifiers_subtyping.md:73`). Grep: `label` na spec 011 = 2 linhas (`:129`, `:365`), na 009 =
  **zero**. Do dono são: (i) *"ordem obrigatória, defaults saltáveis"* (`check.dart:1200-1207`); (ii) *"o
  memberwise é sempre chamado por label"* (`type.dart:256`).
- **Fronteiras que o fix NÃO pode decidir de lado:** (a) o arm de `FunctionType` no `_isSubtype` — sob
  monotonia comece por `==` (invariante, §4.2b) e **isole o ponto** (padrão do `_argsConform`, R8);
  (b) `fn dobro<T>(x: T)` como valor exige instanciar polimórfico (§4.4 recusa let-generalization;
  `FunctionType.positional` nasce sem ∀) — **pergunta própria**, não a responda com `instantiate` escondido.
- **Adicionar label ao tipo-função é superfície NOVA ⟹ dono.** Recuso preventivamente: dois tipos onde há
  um, e importa o erro que o Swift reverteu.

### R11. `hasDefault` — fora do `==` de tipo, DENTRO do override. O erro do A6 está certo; a razão, não. (2026-07-15)
`class A { fn f(x: Int = 1) }` + `override fn f(x: Int)` ⟹ `override-signature-mismatch`.
- **Não confirmo o enunciado geral** *"default não participa"* — ele funde as duas noções
  ([[doctrine-declaracao-vs-tipo]]). Certo: `hasDefault` fora do `==` de TIPO (entailment, mesmo do R10).
  Errado: **override não é `==` de tipo — é a promessa `D ≤ A`.**
- **Correção de direção:** quem chama **via `A`** não quebra (a assinatura de `A` tem o default). **Quebra
  via `D`**: `d.f()` = `missing-argument`. `f()` é aceito pela API de `A` e recusado pela de `D` ⟹ `D` não
  faz tudo que um `A` faz = a mentira que acusei em [[phase5-011-w3-review]] (conflito 1).
- **Espaço enumerado** ([[doctrine-consenso-entre-candidatos]]): (a) assinatura idêntica ⟹ **erro**;
  (b) default livre ⟹ legal; (c) contravariância no default (pode ADICIONAR, não remover) ⟹ **erro**.
  **(b) cai por princípio:** defaults diferentes (`=1` em A, `=2` em D) = o mesmo objeto responde diferente
  conforme o tipo **estático** da referência, sem marca — forma exata do que recusei no flow-narrowing
  (ruling 2) e do slicing (P2). Sobram (a) e (c), as duas dizem **erro** ⟹ **entailment, não vai ao dono.**
- **Aberto e pequeno: override pode ADICIONAR default?** (a) não, (c) sim (D aceitaria *mais*, não fere ≤).
  **Monotonia ⟹ hoje é (a)**; isolar o predicado num ponto. Só vai ao dono se alguém pedir (c).
- **Diretriz Swift NÃO se aplica:** é desempate para **indecisão**, e `D ≤ A` não pode mentir é linha
  ratificada (009 §4.2b). E o fato do Swift teria de ser **verificado** antes de virar argumento.
- **Reforço a pedir ao `dart-vm-expert` (nunca fundamento — [[doctrine-vm-data-reinforces]]):** no Kernel o
  default vive no **callee** (`VariableDeclaration.initializer`)? Se sim, `a.f()` emite chamada sem arg
  contra alvo dinâmico `D.f` sem default ⟹ "compila mas roda errado" (ADR-0007/0013). Reforça; não funda.

## Achados de processo para a spec 009
- **RENUMERAÇÃO:** `nullity-invariant.md` §"A garantir na **Fase 3** (semântica — type-checker)" e
  ADR-0012 A4 (pureza do `where` "na Fase 3") usam a numeração ANTIGA. Sob ADR-0011, semântica = **F5**.
  Os **4 checkboxes do nullity-invariant são o mandato de F5** → viram CAs da 009. Idem pureza do `where`.
- `let x: T` sem init (aberto no nullity-invariant): F5 dá o tipo; definite-assignment é **F6**
  (ADR-0011 lista use-before-assign em F6). Recomendo **permitir** — RD-1 (blocos não rendem) torna
  uninit-let + definite-assignment a válvula que evita cair em `var`, logo SERVE a P1. `let x` nu (sem
  init e sem anotação) = `cannot-infer`.
- `self` explícito vs. bare-field ([[phase4-binding-identity-rulings]] #4) **aterrissa em F5** —
  é type-directed. Recomendação mantida: **A** (exigir `self.x`). Dono decide na 009.
