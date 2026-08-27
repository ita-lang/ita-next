---
name: fase5-instanciacao-subtipagem
description: Fase 5 — desenho W1 (2026-07-15) dos 4 itens: `_isSubtype` com type-args, prefixo ∀ no FunctionType (mata `_freeParams`), ResolvedCall, ResolvedMember.origin/kind
metadata:
  type: project
---

# Instanciação (∀) e subtipagem com type-args — desenho W1 (2026-07-15)

Arquivos: `compiler/lib/frontend/semantic/{check,collect,type,type_table,unify}.dart`.
Segue [[fase5-guarda-ciclo]] (fecha a "lacuna remanescente" #1 dela) e [[fase5-spec-011-membros]].

## Item 1 — `_isSubtype` descarta type-args

- **Dois walks que COINCIDEM POR CONSTRUÇÃO, não um walk parametrizado.** Fig. 2.37 (`Env.get`) é
  UMA rotina porque há UMA pergunta; aqui há duas (membro-denotado × reachability), com álgebras de
  resultado diferentes (mais-interno+`ambiguous-member` × predicado puro). O ponto único é a
  **relação de arestas JÁ INSTANCIADA**: `_superTypesOf(NamedType) → List<NamedType>` (aplica
  `_substOf` + `substitute` e devolve os pais). `sources` deu as arestas; isto dá as arestas
  **substituídas**. `_lookup` e `_isSubtype` consomem a mesma.
- **`_reachesDecl` MORRE.** A recursão passa a ser `_isSubtype(s, sup)` sobre o pai instanciado —
  reentra na cabeça ⟹ args comparados **a cada hop**. É o subtyping algorítmico (TAPL Fig. 15-3;
  S-Trans admissível) — **lacuna do Dragon**, que não tem subsunção.
- **Ponto único da variância = `_argsConform(List<Type>, List<Type>)`**, chamado de
  `_sameApplication(a,b) = identical(decl) && _argsConform(args)` na cabeça do braço NamedType×NamedType.
  Hoje `==` par a par (invariante). Deliberadamente redundante com o `sub == sup` do topo — a
  redundância **é a costura**.
- **`substitute` (type.dart:387) já passa pelo smart ctor `optional`** (linha 391) e `Unifier.resolve`
  também (unify.dart:66). Regra: `_superTypesOf` **reusa `substitute`**, nunca mapeia à mão. Caso
  concreto que quebraria: `class D<T> : A<T?>` com `D<String?>` ⟹ ingênuo dá `A<String??>` ⟹
  `D<String?> ≤ A<String?>` FALSO, silencioso, irreparável pelo usuário.
- **TERMINAÇÃO (afinando a nota do [[fase5-guarda-ciclo]]):** o corte por decl (A3) prova a terminação
  **CONDICIONADO a `_argsConform` NÃO recursar**. Com invariância (`==` estrutural) a medida é a
  profundidade do DAG de decls e o crescimento do tipo (`List<List<…>>`) é irrelevante — nunca se
  recursa nos args. **No dia em que a variância entrar, a prova CAI**: `A<X> ≤ A<Y>` viraria consulta
  recursiva a `≤`, e aí vale Kennedy & Pierce 2007 (nominal + variância + herança expansiva =
  **indecidível**); o requisito passa a ser o teste de **herança expansiva** (Viroli 2000; é o que
  C#/.NET e Java fazem). `class C<T> : C<List<T>>` já morre na A3 (auto-aresta); o perigoso é
  `class C<T> : D<C<C<T>>>` — decl-grafo ACÍCLICO, hoje termina, sob variância não.
  **Escrever isto no doc do `_argsConform`.**

## Item 2 — `_freeParams` é o sintoma: falta o PREFIXO ∀ no modelo de tipos

- **Dragon 6.5.4 tem a técnica, e o prefixo é PARTE DO TIPO**: `∀α. list(α) → integer` (6.12);
  Alg. **6.16**: *"Para cada ocorrência de uma função polimórfica, substitua as **variáveis ligadas
  em seu tipo** por novas variáveis distintas e **remova os quantificadores ∀**"*. O `FunctionType`
  do Itá **não tem prefixo** ⟹ `_freeParams` o **reconstrói escaneando** = generalização
  (Alg. 6.16: *"Ligue quaisquer variáveis … sem restrições … por quantificadores ∀"*) na hora errada
  (no USO, não na definição) e sem saber quais são livres. §4.4 **recusa** let-generalization ⟹ o
  prefixo é **escrito pelo usuário** (`FnDecl.generics` / `TypeInfo.generics`), nunca inferido.
- **A over-coleta é UNSOUND, não só ruído:** `struct Box<T>{var v:T}` + `fn set(x:T)`; dentro do corpo
  `self.set(x: 5)` ⟹ `_freeParams` pega o `T` **rígido**, instancia `α`, `unify(α, Int)` **passa**.
  Deveria ser `type-mismatch`. Rígido virado buraco ⟹ qualquer valor tipa.
- **Rota "recuperar a lista pela decl no `_call`" REGRIDE CA73.** `Stack.nova()`: o quantificador a
  instanciar é o da **CLASSE**, não o do método (`nova.generics == []`). `_receiverAsTypeName` funda
  `Stack<T>` com `TypeParamType` e o `_substOf` vira identidade — é o mesmo **trocadilho de
  representação** que causa a over-coleta: `TypeParamType` serve hoje de "rígido" E de "buraco".
- **Decisão: `FunctionType.quantifiers: List<TypeParamType>`** (o prefixo ∀), preenchido **onde o
  binder é conhecido** — e **todo sítio já o tem em mãos e o joga fora**:
  `collect._methods` (`_withMethodGenerics`, m.generics) · `collect._initOf`/`extensionInits`
  (`info.generics`, owner = decl do tipo) · `check._topLevelType` (`_withGenerics`, n.generics).
  Regras por sítio de uso: **receptor VALOR** ⟹ ∀ = só o do método (a classe já foi fixada por
  `recv.args`); **receptor NOME-DE-TIPO** (`_staticMember`) ⟹ ∀ = `[∀ do tipo] ++ [∀ do método]`
  (ordem a confirmar com `dart-vm-expert`: em Dart `static` não vê o `T` da classe).
  `substitute`/`resolve` **carregam o prefixo intacto** (o domínio da subst nunca o intersecta —
  invariante a documentar; captura não ocorre porque `recv.args` vem de fora do método).
- **Q3 (rígido × quantificador) — o critério certo NÃO é um predicado, é uma ESTRUTURA DE DADOS**:
  não se instancia o que não está no prefixo. Nomenclatura: **rígido / skolem** × **flexível /
  unificação** — Peyton Jones, Vytiniotis, Weirich, Shields, *"Practical type inference for
  arbitrary-rank types"*, JFP 17(1) 2007, §4 (skolemisation); Vytiniotis et al., *OutsideIn(X)*,
  JFP 21 (2011). **Não está em `references/`.** **Lacuna do Dragon:** Alg. 6.16 é prenex/top-level
  (ML sem classes) ⟹ o livro nunca tem binder ANINHADO (classe genérica × método genérico).
- **Ordem declarada:** sai de graça (o prefixo vem de `n.generics`, lista ordenada da `GRAMMAR`
  §`genericParams`). Fundamento front-end: qualquer outra ordem seria **inventada** (P4). Dragon é
  **lacuna** aqui (o alvo dele é 3-endereços sem tipos; type-arg nunca é emitido).
- **Limite declarado (não regressão):** fn polimórfica usada como VALOR (não aplicada) não instancia
  ⟹ `type-mismatch`. Alg. 6.16 diz *"cada **ocorrência**"*, mas o store dele é **global** e o nosso
  `Unifier` é **local por `_call`** — mesma divergência já documentada no R0 (check.dart:1052-1055).
  `==` do prefixo é **sintático**, não α-equivalente (6.5.4: *"variáveis ligadas podem ser
  renomeadas"*): incompleto, **sound**.

## Item 3 — `ResolvedCall`

- **`instantiate` DEVOLVE as variáveis, na ordem do prefixo** — e o fundamento é que **S É a saída do
  algoritmo**: Alg. 6.16 *"SAÍDA: Tipos inferidos"*; 6.5.5/Ex. 6.20: *"Se o Algoritmo 6.19 retornar
  true, podemos construir uma substituição S … Para cada variável α, find(α) fornece o nó … A
  expressão representada por n é S(α)"*. `unify.dart:161` descartava o mapa ⟹ guardava só `S(t)` e
  jogava fora `S`. `typeArgs[i] = u.resolve(αᵢ)` **é** `S(αᵢ)`.
  Fica no `Unifier` (dono do `fresh()`/store) — o Checker cunhar var seria 2ª casa da instanciação.
- **`signature = u.resolve(inst)`** ✓ = `S(σ(sig))`: σ = subst do receptor (`_substOf`, aplicada no
  `_lookup` antes), S = do unificador. Com o prefixo modelado, `inst.quantifiers` é **vazio**
  (Alg. 6.16 *"remova os quantificadores"*) ⟹ invariante asserível.
- **`typeArgs` PODE ter var não-resolvida, e o guarda do `ret` NÃO cobre:** (a) quantificador fantasma
  (`fn f<T>() -> Int`); (b) `T` só num param **omitido por default**. Correção: a totalidade é sobre
  **S**, não sobre `S(ret)` — `vars.every((v) => !_hasTypeVar(u.resolve(v)))`. É **estritamente mais
  forte** e subsume o check do `ret`: no universo daquele `Unifier` os ÚNICOS `TypeVar` são os de
  `instantiate` (todo outro `_call` tem Unifier próprio e resolve ou erra).
  Opcional (ruling do dono): rejeitar o fantasma na **A3** (errar 1× na causa, não N× no uso — mesmo
  argumento do "kind mora na A2/A3" do [[fase5-guarda-ciclo]]).

## Item 4 — `ResolvedMember.origin` / `kind`

**Tudo derivável, zero informação faltando.** `kind`: os 2 sítios do `_lookup` já são disjuntos
(FieldInfo→field, MethodInfo→method). `origin` de método: `MethodInfo.origin` + o mesmo switch do
`type_table.dart::_originOf` (linhas 253-257) — nota: ele distingue `impl`×`impl-trait` e o contrato
F7 os colapsa. `origin` de **campo = `ownDecl` por CONSTRUÇÃO**, e é principiado, não sorte:
`extension` **não adiciona armazenamento** (`extension-field-unsupported`, collect.dart:357) e a razão
é **6.3.4** (largura/offset do registro fecham na decl). `inherited` fora ✓ — é derivável pelo
consumidor (`identical(r.ownerType.decl, recv.decl)`); não guardar o derivável.

## Ordem e dependências

**1 → 2 → 3 → 4.** (1) é autocontido, mata dano ativo e **endurece a relação que (2) vai passar a
exercer** (com o `T` rígido, mais args caem em `_isSubtype`). (2) é a mudança de modelo (type/collect/
check/unify) e mata `_freeParams`. (3) **depende de (2)** (ordem dos `typeArgs` = ordem do prefixo;
`instantiate` devolvendo as vars). (4) é independente e trivial — empacotar com (3) (mesmo contrato §7,
mesma superfície de teste).
