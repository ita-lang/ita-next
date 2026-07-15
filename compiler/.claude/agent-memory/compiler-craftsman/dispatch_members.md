---
name: dispatch-members
description: Spec 011 — dispatch de método, membros de extension/impl, built-ins e Iterator. Fundamentação (Dragon 1.6.3/1.6.4/2.7/6.3.6/6.5.1), corte de escopo e a lacuna do livro.
metadata:
  type: project
---

# Spec 011 — dispatch de método + membros (fundamentação e corte)

**Fase (Dragon):** 6.3.6 (tabela como parte do tipo) + 6.5.1 (síntese exige declaração antes do uso)
+ 1.6.4/2.7.1 (escopo de membro, aninhamento mais interno na hierarquia).

## Decisões cravadas (2026-07-15)

- **Extension/impl NÃO cria tabela nova — contribui entradas para a tabela do ALVO.** 6.3.6:
  `record(t)`, `t` = objeto de tabela de símbolos, *"a tabela é parte do tipo"*. 2.7 §1: *"uma classe
  teria sua própria tabela, com uma entrada para cada campo e método"*. Extension só redefine o
  critério de *pertence* (1.6.3) de aninhamento léxico → nomeação explícita do alvo.
- **NÃO é passe novo (A1.5). É A2 estendida + A3 estendida.** A1 = só cabeças (extension não é tipo).
  Inserção é ordem-independente por 5.2.5 / Ex 5.10 (*"as entradas podem ser atualizadas em qualquer
  ordem"*); duplicata é A3 (6.3.6: *"um nome pode aparecer no máximo uma vez"*).
- **Dispatch NÃO ameaça o 1-walk; overload de operador AMEAÇA.** São problemas distintos:
  `x.foo()` → receptor sintetiza primeiro ⟹ tabela FIXA ⟹ lookup `Env.get` (Fig 2.37), zero nós
  revisitados; é 6.5.1 regra (6.8), síntese pura. `E1 + E2` → sem receptor, candidatos dependem dos
  dois operandos (6.5.1 nota 6) ⟹ Ex. 6.5.2 (Ada) exige 2 percursos. Manter `OperatorDecl` fora.
- **Sem ponto-fixo.** É o mesmo two-pass do 6.5.1. Não há ciclo (5.2.1) porque a aresta é
  `assinatura → corpo`, nunca o inverso — e isso só vale porque **§4.4 "borda anota"** torna o
  retorno conhecido sem olhar o corpo. Registrar: *borda anota é o que COMPRA o 1-walk*.
- **Dispatch dinâmico é Grupo B.** 1.6.5 Ex 1.8: *"Somente no momento da execução é que pode ser
  decidida qual definição de m é a correta"*. F5 resolve a ASSINATURA pelo tipo estático; a VM
  seleciona a implementação (vtable). Não tentar resolver `override` estaticamente.

## Lacuna do livro (declarada, não chutada)
O Dragon (2006) **não cobre extension methods** — C# 3.0 é 2007. O mais próximo é 1.6.4 (C++: método
*definido* fora da classe), mas lá a *declaração* está dentro. Onde extension/trait entram na cadeia
de lookup **não tem fonte no livro** — é ruling de identidade (`ita-visionary`), não de técnica.
Bidirecional moderno (contexto propagado para o retorno) também não: fonte é Pierce & Turner
TOPLAS 2000 §3.

## Fatos verificados no repo (2026-07-15)
- **A stdlib não declara UM trait sequer** (`grep "trait \w+" stdlib/` = 0). **Não existe `trait
  Iterator`.** Todos os 30+ `for x in …` iteram `List` (ou `Map.keys()` → List).
  ⟹ **`for` NÃO precisa de `Iterator`** — precisa de `List`/`Map` iteráveis (tabela de built-in).
  A "corrente" for→Iterator→dispatch→extension **tem um elo falso**.
- `resolver.dart` passa `n.target` (um **TypeNode**, não a decl) como `selfType` de extension/impl.
- `check.dart:143 _decl` usa `default: break` — **`Decl` é `sealed`**, e `resolver.dart:186 _topDecl`
  faz o switch EXAUSTIVO. Mesma base, duas políticas. O `default` engoliu Extension/Impl/Operator/Init.

## Corte (corrigido pelos rulings do dono/visionary, 2026-07-15)
- **011 = (i) coletar extension/impl + escopo genérico do alvo + (iii) dispatch.** Unidade indivisível.
- **(ii) membros de built-in + (iv) `for`/`Iterator` = M5** (não "012"): ADR-0012 §C-9 já roteou —
  `List`/`Map`/`Result` ganham decl `.tu` na des-Dartificação; `for` fica `ForInStatement` até lá.
  Meu grep (*"`for` não precisa de `Iterator` tecnicamente"*) é verdadeiro **e irrelevante**: a
  dependência do dono é NORMATIVA (face 1: `for` é sintaxe que só o built-in alcança).
- **Linha a escrever na spec:** **variantes** de built-in (Σ fechado: `Option{some,none}`,
  `Result{ok,err}`) = 011 (é exaustividade, mesma pergunta do enum); **membros** (`.length`, `.map`) = M5.
- **`Stack.new()` — retirei o "risco nº1"; o visionary tem razão** (não é HM: a assinatura `-> Stack<T>`
  está ANOTADA, não se infere através de fronteira; simétrico a `[]`). **Mas o mecanismo NÃO é
  `_isCheckingOnly`** (critério sintático; `Call` marcado assim destrói a fatia C) — é `_call(n,
  [expected])` unificando `inst.ret` com o esperado antes do `_hasTypeVar`. 1 aresta implícita a mais
  (5.2.5). Continua 1 walk.
- **Memberwise é da 011, não dívida de F3.** A spec 005 §3.6 diz "Fase 3" com o sentido de
  **semântica** (numeração pré-ADR-0011): título = *"O que sobra para a SEMÂNTICA"*, subtítulo =
  *"deferidas ao binder/type-checker"*, §1 = *"antes da semântica (Fase 3)"*. **Eu errei antes** (li o
  número, não a frase); o `ita-visionary` carrega o mesmo erro e conta CA63/CA73 como bloqueados por
  F3. Argumento independente que fecha: sintetizar `init(items: List<T>)` exige os TIPOS dos campos ⟹
  não é type-agnostic ⟹ não é desugar (mesma correção já registrada p/ copy-with e currying).

## Review da fatia 1 (commits 7ada8d1 / 2dd4069) — 3 bugs + padrão
- **B1 — `info.traits` ordem-DEPENDENTE:** `_collectBody:110` faz **assign**, `_contribute:171` faz
  append. `impl T for S` ACIMA de `struct S: U` ⟹ o assign apaga o trait do impl. Viola o 5.2.5/Ex 5.10
  que o doc do `TypeInfo.methods` cita 3 linhas ao lado. **Invariante:** A2 só faz `top.put` (Fig 2.38)
  — insere, nunca substitui; `traits` nunca reatribuída.
- **B2 — campo/`init` em extension engolidos:** `_methods` faz `if (m is! FnDecl) continue`. A spec 005
  §10 roteia `InitDecl` para corpo de extension/impl. Catch-all com forma nova (`continue` num `if`).
- **B3 — anotação de assinatura resolvida 2× ⟹ erro DUPLICADO** (A2 via `_methods`, checker via
  `_annotated` → mesma lista, sem dedup). E `_resolve` faz `annotations[node] = t` sempre ⟹ o 2º passe
  **corrompia a side-table nº4**. Fix: memoizar (`annotations[n] ?? resolveTypeNode(n)`) = o `get`/`put`
  separados da Fig 2.38 / 2.7.2. **Checar antes:** se o desugar COMPARTILHA `TypeNode` (DAG), memoizar
  é bug. `_withGenerics` continua necessário p/ anotações de CORPO (A2 não as visita).
- **5º catch-all, não contado:** `_contribute` → `types.declNamed` só conhece user-type ⟹
  **`extension Int: Ord {}` (CA5 da 005) dá `unknown-type: Int`** — mentira; `Int` existe. Precisa
  `extension-on-builtin` (M5).
- **Antídoto do livro para a doença do catch-all (6.5.2, `widen`/`max`):** *"else **error**"* / *"Ela
  **declara um erro** se t1 ou t2 não estiver na hierarquia"*. ⟹ **um default pode ser `error`; não
  pode ser um VALOR.** Formulação: `ErrorType` **após** diagnóstico = anti-cascata (correto);
  `ErrorType` **sem** diagnóstico = a doença. `_topLevelType` tem catch-all porque `TopLevelRes.decl` é
  `AstNode` (tipo largo demais) — apertar o tipo devolve a exaustividade de graça.
- **Achado 2 (match) NÃO foi invasão de escopo:** `_bindFieldPatterns` faz o MESMO lookup que `_member`
  (`NamedType → types.of → fields → substitute`) — é a mesma `record(t)`, logo a mesma spec.
- **Débito D4 (sub-nós sem identidade) é F2/`ast.asdl`, não F4** — F4 não pode inventar identidade p/
  quem não é nó. `FieldPattern` + `EnumCase` + `GenericParam` + `Param` = **um** débito, 4 pagamentos.

## W1 dos 5 itens que fecham a 011 (Rationale, 2026-07-15)

- **Item 0 (NOVO, pré-condição do 4) — labels/defaults não existem no `Type`.** `FunctionType.params` é
  `List<Type>`; `Param` tem `label`+`defaultValue`, `Arg` tem `label`, e nada sobrevive ⟹ `_call` casa
  POSICIONAL. Bugs vivos: `fn f(x: Int = 1)` + `f()` = `arity-mismatch` falso; `f(b:2, a:1)` liga
  TROCADO em silêncio. Memberwise é chamado SEMPRE por label ⟹ sem isto o item 4 mente. **Livro não
  cobre** (6.3.1: param = produto cartesiano, posição pura; Alg. 6.16: *"apenas funções unárias"*).
  Ruling: label PARTICIPA do `==` de assinatura; default NÃO.
- **Item 1 `missing-trait-member`** — o livro **não tem trait/interface**; a formulação exata é **1.6.4,
  box "Declarações e definições"** (*"um método é **declarado** … a assinatura. O método é então
  **definido** … em outro local"*): trait declara, impl define. Em C++ isso é erro de LINK ⟹ não há
  capítulo porque o livro empurra p/ fase que não temos. Estrutura: 6.3.6 (record(t) dos dois lados).
  Comparação: **6.3.2 equivalência de NOME** ⟹ `==` estrutural basta, **sem Alg. 6.19**. Requisito =
  `FnDecl.body == null` (com corpo = default). **DOIS códigos** (`missing-trait-member` ≠
  `trait-member-signature-mismatch`): nome-só é UNSOUND (trait pede `-> Int`, tipo dá `-> String`, `≤`
  passa). Generics: **UM degrau** (trait não herda trait — `traitDecl` não tem `:`). Roda em A3.
  Arestas: trait é TypeInfo (não pode disparar sobre si); `impl Ord for Comparable` parseia.
- **Item 2 `override`** — **o livro NÃO fala de `override` explícito**: 2.7.1 dá o fenômeno, 1.6.4 a
  regra de shadowing, 1.6.5 o dispatch. Keyword = política pura (ruling do dono). **Correção ao
  coordenador:** "override sobre extension não faz sentido" é FALSO no geral — `extension Dog {
  override fn speak() }` com `class Dog : Animal` shadowa o HERDADO (não há colisão ⟹ não é
  duplicate). **Uma regra, sem exceção:** `override` exige que o walk ACIMA do nível do próprio tipo
  (super + defaults de trait) ache o nome; `origin` é irrelevante.
- **Item 3 CopyWith** — 6.3.6 e nada além. `class` **não muda a regra de tipo** (6.3.6 fecha: *"também
  serve para classes"*); valor×referência é 1.6.2/1.6.6 = runtime/F7. Mutabilidade NÃO impede (campo
  `let` é o CASO DE USO). Type-args do receptor, nunca re-inferidos (invariância).
- **Item 4 memberwise** — sintetizar decl que ninguém escreveu **é legítimo e tem mecanismo no livro:
  6.3.5, não-terminais MARCADORES** (`M → ε {ação}` — não corresponde a texto do fonte e executa ação
  semântica) ⟹ nem toda entrada da tabela vem de lexema. Derive a **assinatura** (`TypeInfo.init`), NÃO
  crie `InitDecl` fantasma (seria F3 + fere P4). **Refino do meu "else error":** `widen`/`max` (6.5.2) é
  erro do **USUÁRIO** → `CheckError`; `_topLevelType` default é violação do **contrato F4×F5** → falha
  ALTA (`throw`), não diagnóstico. Apertar o tipo (`TopLevelDeclRes`/`TopLevelLetRes`) é o certo mas é
  do **D4**, não da 011.
- **Item 5 `Stack.new()`** — **retiro "o livro não cobre"**. Alg. 6.16 não tem `expected` porque o store
  é **GLOBAL**; o Itá cria `Unifier()` novo por `_call` (store LOCAL) ⟹ unificar `expected` com
  `inst.ret` **devolve uma restrição que o livro teria de graça** — é uma restrição a MENOS, não a
  mais. **Cite 6.5.4/Alg. 6.16 + Alg. 6.19; nada de P&T.** Ordem: **R1 → R0(expected) → R2**.
  `R0→R2` é NECESSIDADE (R2 lê o store via `u.resolve`); `R1→R0` é DIAGNÓSTICO (erro no call, não no
  arg). A unificação é **confluente** (Alg. 6.19, union-find) — o que torna a ordem observável é a
  LEITURA do store. Duas arestas do 5.2.5, dois estatutos.
- **Regra de citação:** normativo só o que está em `references/`; o resto = descrever o mecanismo +
  atribuir origem sem força.
- **Ordem:** 0 → 4 → 5 → (1, 2) → 3.
- **Padrão a extrair do `_self`:** todo `ResolvedName` que a F4 produz precisa de leitor na F5, e o
  conjunto é `sealed` ⟹ teste que percorre as variantes e afirma "tem leitor" mata a classe inteira
  (4ª ocorrência: `_decl`, `_stmt`, `_bindPattern`, `SelfExpr`).

## O que falta para a fatia 2 (`_member`)
1. **Substituição COMPOSTA ao subir** (`class Sub<T> : Base<T>` + receptor `Sub<Int>`): compor
   `subst ∘ _substOf(baseInfo, superclass.args)` a cada degrau. 3º bug da série "generic não substituído".
2. `_member` devolve **`ResolvedMember(info, sigSubstituída, ownerType)`** (side-table nº3), não
   `MethodInfo`: `origin` = de onde baixar o Procedure (F7); `ownerType` = sob que substituição.
3. **`override` nunca é checado** e a keyword existe (`FnDecl.isOverride`) ⟹ `missing-override` /
   `override-nothing`. Só o walk responde. É da 011.
4. **`missing-trait-member`** — `_contribute` faz `impl Trait for T` produzir `T ≤ Trait` **sem
   verificar que os métodos existem**. Promessa não-verificada ⟹ `_isSubtype` mente.
5. A3 reporta `duplicate-member` no **2º inserido** = ordem textual das decls ⟹ com o extension acima,
   o erro cai no struct (o inocente), contra o doc. Ordenar `info.methods` por offset antes de A3.
