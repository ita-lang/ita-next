---
name: fase5-guarda-ciclo
description: Fase 5 / guarda de ciclo no grafo de tipos — IMPLEMENTADO 2026-07-15: dois grafos (Fig 2.37 vs Fig 6.32), A3 corta a aresta, sources() único, papel por KIND, trait é folha
metadata:
  type: project
---

# Guarda de ciclo no grafo de tipos (desenho W1, 2026-07-15)

> **STATUS: IMPLEMENTADO** (2026-07-15). Os 2 rulings que bloqueavam vieram do dono e
> estão na seção final. 652 testes verdes, analyzer limpo, verificado por `itac check`.
> O desenho abaixo sobreviveu inteiro à implementação — só a CASA do kind mudou
> (A2, não A3: é onde o span existe). Ver [[fase5-spec-011-membros]].

Origem: achados #3/#5/#6 do review da spec 011 ([[fase5-spec-011-membros]]).
Arquivos: `compiler/lib/frontend/semantic/{collect,check}.dart`.

## A tese: SÃO DOIS GRAFOS, com disciplinas opostas — e o livro dá as duas

| Grafo | Fonte | Ciclo | Walker canônico |
| :-- | :-- | :-- | :-- |
| **Expressões de tipo** (campo, type-arg) | 6.3.1 + nota 3 | **LEGÍTIMO** | Fig. **6.32**: `union(s,t)` **antes** de recursar — *"ao combinar em primeiro lugar … o algoritmo termina"* |
| **Escopos aninhados** (`prev` = superclasse/trait) | 2.7.1 + 1.6.4 | **CORRUPÇÃO** | Fig. **2.37**: `for(e=this; e!=null; e=e.prev)` — **sem** `visited` |

**O critério de legitimidade (Q1) é o PAPEL DA ARESTA, não ad-hoc:**
- 6.3.1: o grafo de tipos é um **DAG** com *"**folhas** para os tipos básicos, **nomes de tipo** e variáveis"*.
  Nota 3: o ciclo só existe *"**se as arestas para os nomes de tipo são redirecionadas**"*. Itá usa
  equivalência de **NOME** (6.3.2) ⟹ nunca redireciona ⟹ `struct A{b:B}`+`struct B{a:A}` é legal
  **e nenhum walker cicla** (`FieldInfo.type = NamedType(B)` é folha).
- `superclass`/`traits` **não é campo**: é o `prev` do `Env` (2.7 §1 *"uma classe teria sua própria tabela"*
  + 1.6.4 *"o escopo do membro de C se estende a qualquer subclasse"*). 2.7.1: o encadeamento *"forma uma
  **pilha**"* / *"resulta em uma estrutura de **árvore**"*. **Árvore não tem ciclo.**
- **Por que o livro não precisa de guarda:** `new Env(top)` só aponta para tabela que **já existe** ⟹
  aciclicidade **por construção**. `class A : B` resolve o pai **por nome, depois** ⟹ o Itá perde a
  garantia estrutural e tem de **restaurá-la explicitamente**.

## Rulings técnicos cravados

- **Q1 = (b) A3 corta a aresta**; (a) guarda-em-cada-walker **restrita ao DETECTOR** (é o único que encara
  o grafo antes de a garantia valer — é literalmente a Fig. 6.32). (c) rejeição-na-inserção **rejeitada por
  5.2.5/Ex. 5.10** (ordem de contribuição é irrelevante — o `_addTraits` acumula; detectar no `put` amarra o
  diagnóstico à ordem).
- **`visited` de TIPOS é insuficiente; o corte por DECL é o que prova terminação.** `_lookup` recursa sobre
  `Type` **substituído** ⟹ `class C<T> : C<List<T>>` gera infinitos TIPOS sobre finitas DECLS (recursão
  expansiva — Kennedy & Pierce 2007, **lacuna do Dragon**). Grafo de decls acíclico ⟹ todo walk sobre tipos
  desce um nível do DAG ⟹ termina. É a medida estrutural no lugar da contagem de classes da Fig. 6.32.
- **`sources(info) = superclass ∪ traits` é UM método só** (hoje: 4 cópias em `_lookup`, `_isSubtype`,
  `_implementationAbove`, `_checkInheritanceCycle` — a assimetria é o sintoma).
- **Q3: os dois alcances têm de COINCIDIR.** Não há razão no livro para divergirem: a única diferença
  superclasse×trait no Dragon é **6.3.4 (largura/leiaute — prefixo)** e **1.6.5/Ex. 1.8 (despacho)** — as duas
  **Grupo B** (Dart VM). Do lado do escopo (1.6.4) e da tabela (2.7), zero diferença. `≤` ⊋ lookup = unsound;
  lookup ⊋ `≤` = o achado #6. **Lacuna declarada:** o Dragon não tem trait/interface nem regra de subsunção —
  o "têm de coincidir" formal é Pierce TAPL 15.2.
- **Q2: a porta do ciclo-por-trait NÃO é o `traitDecl`** — `traitDecl = "trait" IDENT genericParams? "{" fnDecl* "}"`
  (GRAMMAR) **não tem cláusula `:`** ⟹ `trait X : Y` é inexprimível. As portas são **`extension X : Y`** e
  **`impl Y for X`** com X trait. ⟹ **ruling ao `ita-visionary`: trait tem supertrait?** Se não, A3 rejeita
  aresta em info de kind trait e o grafo de traits tem profundidade 1 (só `superclass` cicla). Hoje
  `_checkTraitConformance` faz `if (kind == trait_) return` (pula) **mas a aresta FICA** — incoerência.
- **Q4: kind mora em A3** (mesma casa do `duplicate-field`, 6.3.6), **não** no `_isSubtype` (reportaria no
  **uso**, N vezes, longe da causa). spec 005 §3.6 tem **DUAS** regras: *"Superclasse de `class` deve ser uma
  `class` (não trait)"* → `superclass-not-a-class`; *"traits devem existir e ser traits"* → `trait-expected`.
- **Ordem de A3 (importa): kind → ciclo → resto.** O kind-check já mata `struct S : S` e `struct A : B`+
  `struct B : A` (arestas inválidas somem ⟹ ciclo nem se forma). Sobra só `class A : B`+`class B : A`.
- **`_checkWellFormed` tem de virar 2 passadas.** Hoje é um loop único por `info` ⟹ `_checkOverride(A)` roda
  **antes** de `_checkInheritanceCycle(B)`. **É por isso que o `_implementationAbove` precisa do `seen` hoje** —
  não é virtude dele, é a ordem errada. Com fase-de-ciclo completa antes, o `seen` vira redundante.
- **Detecção ordem-independente:** aresta `u→v` está em ciclo sse `reaches(v,u)`. Computar sobre o grafo
  ORIGINAL (fase 1, com `visited` — Fig. 6.32), depois reportar+cortar **todas** (fase 2). Cortar "uma só"
  dependeria da ordem (viola 5.2.5).

## Os 2 rulings do dono (2026-07-15) — FECHADOS

- **(a) Trait é FOLHA — não tem supertrait.** Nenhuma aresta sai de um trait. A porta da frente já
  não exprimia (`traitDecl` sem cláusula `:`); as laterais (`extension X : Y` / `impl Y for X` com X
  trait) foram **fechadas** → `trait-supertype`. ⟹ grafo de traits com profundidade 1; **só
  `superclass` pode ciclar**, e é a única aresta que o detector corta.
- **(b) O papel vem do KIND, não da posição.** O 1º type após `:` só é superclasse **se for `class`**;
  sendo trait, é trait e a classe fica **sem** superclasse. `class Pato : Voa` deixa de ser
  inexprimível. É o que o Swift faz. Sub-regra derivada (minha, não do dono — ele pode vetar):
  **superclasse primeiro ou em lugar nenhum** → `class-after-trait`, senão saber se `class D : A,B,C`
  herda exigiria olhar o kind dos três.

## O que a implementação corrigiu no desenho

- **O kind mora em A2, não em A3** — e o motivo é o **SPAN**: o diagnóstico tem de cair no type
  ofensor, e `TypeInfo.traits` é lista **mesclada** (inline + contribuída por `extension`/`impl`) ⟹
  não é recasável 1:1 com a AST depois. Não há tensão com o "Q4: kind mora em A3": aquele era contra
  reportar no **USO** (`_isSubtype`, N×, longe da causa) — A2 é a **DECL**. E é ordem-independente
  (Ex. 5.10): depende só da AST da própria decl + a tabela de kinds, que a A1 já fechou.
- **`_conform` precisa de estado LOCAL.** Ler `info.traits` para decidir `class-after-trait` faria a
  ordem das declarações mudar o diagnóstico (`impl Voa for Ave` **antes** da decl já contribuiu) — o
  mesmo Ex. 5.10 que o assign do `_addTraits` já custou uma vez.
- **`inheritable` só para o corpo de `class`.** Sem o flag, `extension Dog : Animal` **plantaria
  superclasse por retrofit**. Superclasse vem da decl da própria classe e de mais lugar nenhum.
- **Nada de AST/parser mudou** (F2 intacta, goldens verdes): o split do parser é puramente posicional
  ⟹ **reversível**, e `[superclass, ...traits]` reconstrói a ordem-fonte sem perda.
- 4 códigos: `trait-supertype`, `class-after-trait`, `multiple-superclasses` (novos) + os 2 da 005
  §3.6 (`superclass-not-a-class`, `trait-expected`) agora **realmente disparam**.
- `_checkTraitConformance` perdeu os **dois** pulos (`if kind == trait_ return` e
  `if ti.kind != trait_ continue`): eram guarda tapando o buraco do lado errado. O `_conform` garante
  o invariante **na fonte** ⟹ ficaram provadamente mortos.

## Lacunas remanescentes
- **`_isSubtype` ignora type-args**: `identical(s.decl, sup.decl)` ⟹ `class D : A<Int>` satisfaz
  `A<String>`. Pré-existente (a cadeia de `superclass` já fazia isso, e os traits a 1 nível também) —
  **não** introduzido pelo `sources`. A doc diz "variância **invariante**" e o código não a checa.
  → **Desenho W1 feito em [[fase5-instanciacao-subtipagem]]** (item 1): `_reachesDecl` morre,
  `_superTypesOf` (aresta instanciada) é o ponto único, `_argsConform` é a costura da variância.
  ⚠️ **Afinação da nota de terminação abaixo:** o corte por decl prova a terminação **só enquanto
  `_argsConform` não recursar** — sob variância cai, e vale Kennedy & Pierce 2007 + o teste de herança
  expansiva (Viroli 2000).
- `struct A { a: A }` (recursivo por VALOR) **não é ciclo do grafo de tipos** — é **largura infinita**
  (6.3.4), e 6.3.4/6.3.5 são **Grupo B**. Não confundir com o assunto desta nota.
