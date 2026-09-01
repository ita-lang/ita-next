---
name: fase5-literal-colecao
description: Fase 5 — síntese de literal de coleção NÃO-VAZIO ([1,2,3], {"a":1}): regra = aplicação de construtor ∀ (6.5.1+6.5.4+Alg 6.19), não join; ordem síntese-antes-de-emissão; 3 achados de código
metadata:
  type: project
---

# Literal de coleção não-vazio — a regra e a ordem (W1, 2026-08-31)

Pergunta do W1 da LT-012b (team-lead). Sucede [[fase5-spec-012-chao]] (o CHÃO tipa mas não emite).
Ver [[types]] (bidirecional≠HM), [[fase5-fatia-c-contextual]] (checking-only = vacuidade), [[fase5-instanciacao-subtipagem]].

## O fundamento: a vacuidade NÃO se estende ao não-vazio
A spec 010 §4.1 funda `[]`/`{}` em **6.5.1 — vacuidade** (*"constrói o tipo … a partir dos tipos de
suas **subexpressões**"*; zero subexpressões ⟹ nada de que construir). Com **n ≥ 1 há de que
construir** ⟹ a §4.1 não decide o não-vazio, e por contraposição **autoriza** a síntese. Não há
conflito normativo a resolver: a 010 §4.1 nunca falou do não-vazio (verificado, linha 241:
*"O livro **não tem literal de coleção vazia** (lacuna declarada)"*).

## ⚠️ A NORMA JÁ DECIDIU O MODO (achado do `ita-visionary`, conferido 2026-08-31)
**spec 009 §4.3 (`spec.md:145`), verbatim:** *"**Literais de coleção CHECAM, não sintetizam.** `[]` não
tem tipo sozinho; `[Cachorro()]` contra esperado `List<Animal>` desce elemento a elemento … Sem
esperado ⟹ `cannot-infer`."* O exemplo é **NÃO-VAZIO** ⟹ a política cobre n ≥ 1. Logo:
- COM esperado ⟹ **é BUG** contra a 009 §4.3 (conserto no `_check`, não no `_synthInner`).
- SEM esperado ⟹ `cannot-infer` é **design**; mudar exige ruling do dono.
- **Emenda de 1 linha que a 009 precisa:** §4.4-3 lista *"coleções **vazias** (`[]`)"* enquanto §4.3
  usa exemplo não-vazio — alinhar para "literais de coleção (n ≥ 0)".
- **O fundamento importa (R8):** para n ≥ 1 a vacuidade do 6.5.1 **não** se aplica ⟹ o `cannot-infer`
  sem esperado é **política** (família §4.9), não definicional. Citar vacuidade ali é o erro que a
  010 §4.1 já alertou no `.variant` (trocar o escudo forte pelo fraco).
- **Trade-off a escalar:** sob check-only, `f<T>(xs: List<T>)` chamada com `[1,2,3]` dá `cannot-infer`
  (`check.dart:1805` exige o param inteiro determinado na R2) ⟹ **todo HOF genérico da stdlib fica
  inacessível com literal no call-site**. Com síntese funcionaria (R1 + unify).

## Se um dia houver síntese: aplicação de construtor polimórfico (NÃO join, NÃO first-element-fixes)
Três âncoras abertas em 2026-08-31 (`references/livro-compiladores/06-…/05-verificacao-de-tipo.md`):
1. **6.5.1** autoriza ver construtor n-ário como aplicação: *"A regra (6.8) pode ser adaptada para
   E1 + E2 visualizando-a como uma **aplicação da função add(E1, E2)**"*.
2. **6.5.4** dá a homogeneidade verbatim: *"**Todos os elementos da lista precisam ter o mesmo
   tipo**, mas length pode ser aplicada a listas cujos elementos são de qualquer tipo"*; e o
   Alg. 6.16: *"Uma expressão f(a, b) pode ser verificada **casando-se** o tipo de a com s1 e o de
   b com s2"* + *"Unifique s e t. Se a unificação falhar, a expressão tem um erro de tipo"*.
3. **6.5.5 Alg 6.19** = o `Unifier` já existente (`unify.dart`).
⟹ `[e₁…eₙ]` ≡ aplicação de `mkList : ∀α. α×…×α → List<α>`. Com s₁=…=sₙ=α, "casar cada arg com o
param" **É** a homogeneidade. Zero maquinaria nova: é o que `_call` já faz (R1/R2 + `Unifier`).
**Não é HM**: HM é o Alg. 6.16 INTEIRO (com *"Ligue quaisquer variáveis … por quantificadores ∀"*
= let-generalization). Instanciar+unificar numa aplicação já é a fatia D em produção.

**First-element-fixes REJEITADA**: é disciplina POSICIONAL, e a 010 §4.3 já a rejeitou com o
**Ex. 5.9** (*"a SDD não pode ser L-atribuída, pois o atributo C.c … e C está **à direita** de B"*)
— o critério é **sintático** (forma de introdução), não posição. Observável: `[nil, 1]` culparia o
`nil` (informação está no elemento 2); com R1/R2 dá `List<Int>` + `nil-under-non-optional` no nil.

**`_join` NÃO serve** (`check.dart:2277`): (a) é fold sobre tipos **já sintetizados** ⟹ quebra em
elemento checking-only — o MESMO defeito que a 010 §4.1-b pagou em `match`/`?.`; (b) o span é o nó
pai; (c) `_join(Never,T)=T` codifica *"só UM braço executa"*, e num literal **todos avaliam** — hoje
coincidem por reticulado plano, e confundi-las esconde a divergência futura.

## Cantos que a regra tem de tratar (senão quebram)
- **`Never` não restringe α**: `unify(α, Never)` ligaria α:=Never e o próximo elemento falharia.
  Pular elemento `NeverType` na R1 (bottom, TAPL 15.4 + subsunção) — mesma razão do `_join`.
- **`ErrorType` num elemento** ⟹ devolver `ErrorType` **sem** `cannot-infer` (anticascata, `_join:2278`).
- **Totalidade da nº1**: visitar TODOS os elementos em TODOS os ramos (buraco Str-parts).
- Códigos: síntese sem esperado ⟹ **`element-type-mismatch`** / `key-type-mismatch` (irmãos do
  `branch-type-mismatch`: "divergem entre si, sem contrato"); com esperado ⟹ `type-mismatch` no
  elemento (sai de graça do `_check`).

## 3 achados de código (leitura, não execução — 2026-08-31)
1. 🔴 **`let x: Int = []` NÃO ERRA**: `check.dart:2673-2678` grava `exprTypes[e] = expected` **sem
   checar que o esperado é List/Map**. Bug vivo; vira `ListLiteral` com `typeArgument` de `Int`
   assim que a F7 emitir.
2. 🔴 **A cláusula de contraste do CA27 (spec 009:512) — *"o literal PASSA: `let xs: List<Animal> =
   [Cachorro()]`"* — nunca foi verificada**: o teste (`check_test.dart:244`) usa PARÂMETRO, não
   literal; hoje o literal dá `cannot-infer`. Meia-CA verde (R9).
3. ⚠️ **Descer com `_check`, nunca `_isSubtype`** — só o `_check` chama `_recordCoercion`
   (`:2690`/`:2717` = side-table nº7, ADR-0017): `let xs: List<Voa> = [Passaro()]` perderia o box.

## Ordem: SÍNTESE antes de EMISSÃO (dependência de invariante, não payoff)
1. **Gate I3** (`driver.dart:376` `if (check.hasErrors) return (…, flow: null)`) ⟹ nenhum programa
   com literal não-vazio alcança F6/F7 hoje. Emitir primeiro = ramo com **0 aplicações** (R12).
2. `ListLiteral` do Kernel exige `typeArgument`; a única fonte legítima é `exprTypes[literal]`, que
   **não existe** hoje (o `_cannotInfer` não desce). Emitir primeiro ⟹ recomputar dos elementos = **R1**.
3. (3º, não 1º) corpus degenerado: só lista vazia ⟹ `.length` sempre 0 e um emitter constante-0 passa.
