---
name: fase5-fatia-c-contextual
description: Fase 5 fatia C (spec 010, tipagem contextual) — fundamentação Dragon 5.2.4/5.2.5 para closures, ordem de args, e os 3 cortes de escopo (currying/**/member) com a evidência que os funda
metadata:
  type: project
---

# Fatia C — tipagem contextual (spec 010, levantamento W1 2026-07-15)

Sucede a 009 (fatias A/B/D implementadas, 499 testes verdes). Ver [[types]] para o levantamento-mãe da F5.

## Fundamentação central: L-atribuída é propriedade da ORDEM DOS ARGS, não da linguagem
- **Dragon 5.2.4(b)** (definição literal): um atributo herdado `Xi.a` pode usar *"os atributos herdados ou
  **sintetizados** associados às ocorrências dos símbolos X1…Xi-1 localizados **à esquerda** de Xi"*.
  ⟹ `dobra(xs, { $0*2 })`: `arg₂.expected` usa `callee.type` (X1) **e** `arg₁.type` (X2) — **ambos irmãos à
  esquerda, ambos sintetizados** = L-atribuída **verbatim**. 1 walk, sem ponto-fixo, sem circularidade.
  A dúvida "type-args vêm da unificação do arg1" se dissolve: arg1 TAMBÉM é irmão à esquerda.
- **Dragon Exemplo 5.9 é o contraexemplo exato**: `A→BC` com `B.i = f(C.c, A.s)` — *"a SDD não pode ser
  L-atribuída, pois o atributo C.c é usado para ajudar a definir B.i, e C está **à direita** de B"*.
  Mapeia 1:1 em `f((x) => x*2, xs)` (closure ANTES do que fixa seu tipo). ⟹ **L-atribuição não é teorema da
  linguagem; é consequência da ordem dos args.**
- **Dragon 5.1.1** — a citação que a 009 usa (*"permitimos que um atributo sintetizado no nó N seja definido
  em termos dos … herdados do próprio nó N"*) está CORRETA (`Closure.type` sintetiza de `Closure.expected`).
  Mas a **primeira metade da mesma frase é constraint**: *"não permitamos que um atributo herdado no nó N seja
  definido em termos dos valores dos atributos de seus **filhos**"* ⟹ **proíbe espiar o corpo da closure** para
  descobrir o tipo do param. Regra útil, fácil de violar por "esperteza".

## Q2 (ordem de checagem dos args) — a fundação é 5.2.5, NÃO 6.5.5/6.8
- O store da unificação (union-find) é **efeito colateral** ⟹ **Dragon 5.2.5**. O livro dá 2 disciplinas; a do
  Itá é a **segunda**: *"Restringir as ordens de avaliação permitidas … As restrições podem ser consideradas
  **adicionando arestas implícitas no grafo de dependência**"*. NÃO é a primeira (Ex. 5.10 `addType` é
  order-independent — *"as entradas podem ser atualizadas em qualquer ordem"*; unificar+descer no corpo NÃO é).
- ⟹ A spec 010 **deve declarar as arestas implícitas**, senão a SDD fica subdeterminada. Ordenar args = ordenação
  topológica (5.2.2), continua **1 walk** (cada nó visitado 1×, só não da esquerda p/ direita).
- **LACUNA declarada**: Dragon NÃO cobre ordem de args em checagem bidirecional — e **não pode**: 6.5.4 é HM, e
  **HM não tem esse problema** (param de lambda ganha var fresca α, corpo infere contra α, zero contexto). O
  problema é *criado* pelo modo `check`. Fonte real = Pierce & Turner TOPLAS 2000 §3; survey = Dunfield &
  Krishnaswami, *Bidirectional Typing* (ACM Comput. Surv. 2021). **Nenhum dos dois está em `../references/`.**
- Algoritmo mínimo recomendado: **2 rodadas** (R1 args que sintetizam → `_synth`+unify; R2 formas
  checking-only → `_check` contra param já substituído; sobrou `TypeVar` ⟹ `cannot-infer`). Determinístico,
  independente da ordem textual. **Custo real: diagnósticos saem fora da ordem textual** ⟹ ordenar por offset
  antes de reportar. Circularidade genuína existe (`f<T,U>(a:(U)->T, b:(T)->U)`) e 5.1.2 nota 1 diz que detectar
  é exponencial ⟹ **não detectar**: estratégia fixa + `cannot-infer` (ADR-0013).

## Evidência do repo (verificada 2026-07-15, não é opinião)
- **`{ $0 }` só parseia como trailing closure** → `primary` (GRAMMAR §4.1) não tem alternativa p/ `{` de closure;
  `mapLiteral` exige `:`. E `parser.dart:1234` faz `args.add(Arg(null, _trailingClosure()))` — **anexa como
  ÚLTIMO arg**. ⟹ `$0`-closure é **estruturalmente o irmão mais à direita** = L-atribuída **por construção**.
  `find(xs, { $0 > 2 })` NÃO parseia; `find(xs) { $0 > 2 }` sim.
- **Buraco real:** closure explícita com param sem tipo (`param = IDENT IDENT? (":" type)?` — tipo é OPCIONAL)
  pode ir em qualquer posição ⟹ `f((x) => x*2, xs)` = Exemplo 5.9. É o único caso que exige as 2 rodadas.
- **stdlib: 0 exceções** — todas as 18 HOF são `(list, …, closure)` com closure em ÚLTIMO (`find`, `flatMap`,
  `takeWhile`, `partition`, `scan(list, initial, f)`, `groupBy`, `sortBy`, `any`/`all`/`none`/`count`,
  `maxBy`/`minBy`). Grep por closure-param-seguido-de-vírgula: **zero matches**.
- `_trailingClosure` cria `Closure(…, false, const [], …)`; desugar (`desugar.dart:858-891`) sintetiza
  `Param(null, '$i', **null** /* sem tipo */, …)` ⟹ **é exatamente `params.type = herdado de expected`**.
  Corner: `{ 42 }` (sem `$k`) → params `const []` = **aridade 0**; se `expected=(T)->U` ⟹ mismatch. Precisa ruling.

## Os 3 cortes de escopo (com a prova)
1. **Currying: FORA — não é implementável.** `PartialAppExpr` = **AST órfã** (`ita/…/GRAMMAR.md:307`);
   design-notes 004:262 crava *"Não portar `PartialAppExpr`"*; **zero** ocorrências de `PartialApp`/`Curry` no
   `ita-next`. Sintaxe `add(5, _)` (LANGUAGE_SPEC:414) **não parseia**: `primary` não tem `_`; `_` só existe como
   `pattern` (GRAMMAR:255); `arg = (IDENT ":")? expression`. ⟹ é feature de **Fase 2+3+7** (gramática+desugar+
   Kernel), NÃO de tipos — o checker é a parte BARATA (constrói `→` do 6.3.1 com os slots vazios). Mispriced.
2. **`**`: FORA — já está PRONTO na fatia B.** `check.dart:71` tem `BinaryOp.pow: [(Int,Int,Int),(Float,Float,Float)]`,
   match exato. É `Tag.starStar`/`BinaryOp.pow` nativo (parser `_power`, precedência 11 direita), NÃO dispatch p/
   método. A 009 §5.4 listando `**` em C está **defasada**. Só volta com `OperatorDecl` (= overload → Ex 6.5.2
   dois percursos → mata o "1 walk"; é o blocker #6 do [[types]]).
3. **Member: separável, MAS `CopyWith` arrasta metade.** `_member` deferido em `check.dart:606`. `map`/`filter`/
   `reduce`/`fold` **NÃO EXISTEM na stdlib** (verificado) — combinadores são funções livres. A máquina contextual
   fecha e é testável **sem** member: `find(xs) { $0 > 2 }`. **Porém** `CopyWith` (na lista de C) precisa enumerar
   campos por tipo = `record(t)` (Dragon **6.3.6**) — **a mesma tabela** que `p.x` (leitura de campo) usa ⟹ se
   CopyWith está em C, **leitura de campo sai quase de graça**; o delta real é **dispatch de método** (walk de
   traits/superclass). Recomendo cortar aí: C = closures+`.variant`+`[]`/`{}`+CopyWith+campo; método → 011.
   Custo de não trazer member: o corpus `conformance/desugar/dollar_closure*.tu` usa `xs.map { … }` (member +
   `List.map` inexistente) ⟹ reescrever p/ fn-livre+trailing, ou aceitar pendente.

## `[]`/`{}` (Q4) — a regra do `nil` generalizada
`[]` **não sintetiza**: 6.5.1 diz que síntese *"constrói o tipo de uma expressão a partir dos tipos de suas
subexpressões"* — com **zero** subexpressões não há de que construir. Síntese é *definicionalmente* indefinida
aqui; não é escolha. (Dar `List<α>` seria 6.5.4/let-gen = HM, rejeitado.) ⟹ `let x = []` = `cannot-infer` está
**certo** (ADR-0013). Empírico: stdlib tem 25+ `[]`/`{}` e **100% sob anotação** (`var result: List<List<T>> = []`,
`self.inbox = []`). Enquadramento elegante: `nil`, `[]`, `{}`, `.variant` = **formas de introdução checking-only**
(sem regra de síntese) — **1 regra, 4 literais**; `nil` (§4.6) já a implementa. Em `chunk<T>`, o `T` de
`List<List<T>>` é `TypeParamType` **rígido** (não `TypeVar`) ⟹ puro check-mode, sem unificação. Corner: `{}` é
ambíguo `mapLiteral` vs `block` (GRAMMAR:214 vs 196) — confirmar desempate no parser.
