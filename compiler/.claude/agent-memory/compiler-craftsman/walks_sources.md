---
name: walks-sources
description: Os walks sobre TypeInfo.sources — por que NÃO fundir (Dragon 6.5.2 max/widen), o que fatorar (a aresta instanciada), a casa certa do _substOf, e o achado do requisito-como-hit no _lookup.
metadata:
  type: project
---

# Walks sobre `TypeInfo.sources` — fundir? (W1 reavaliado com contexto fresco, 2026-07-15)

## Contagem correta: são **5**, não 3 (enunciado) nem 6 (pesquisa de campo)
1. `check.dart:1604 _lookup` — recursivo; nível 0 CORTA; dedup por `decl`; **único que PODE FALHAR**.
2. `check.dart:1855 _isSubtype` + `1953 _superTypesOf` — ∃ (bool ∨). Um walk, não dois.
3. `collect.dart:887 _implementationAbove` — DFS, PULA nível 0, filtra `body != null`, 1º hit.
4. `collect.dart:977 _offeredBy` (driver `956 _checkInheritedConflict`) — `Map` nome→sig, união
   left-biased (= o `+~` do Scala). **Não existia no W1** — é o que desatualizou o enunciado.
5. `collect.dart:1131 _reaches` — DFS iterativo sobre **decls**, com `visited`, **sem substituição**.
Mais `_checkTraitConformance:1001` = varredura de UM nível sobre `traits` (não é walk).
`type_table.dart:260` ("Os quatro walks") também está desatualizado.

## Veredito: NÃO fundir — e **o meu argumento do W1 estava certo mas mal fundado**
"Parametrizar o monoide" é 1 de **4** eixos independentes: (i) alcance (nível 0 conta? corta?),
(ii) filtro (`body != null`? campos?), (iii) monoide, (iv) **totalidade**.

**O eixo que mata é a totalidade, e o Dragon dá o precedente exato — 6.5.2:** `max` e `widen` andam
o **MESMO grafo** (Fig. 6.25(a)); `max` *"declara um erro se t1 ou t2 não estiver na hierarquia"*,
`widen` devolve `a`/gera código/`else error`. **Fig. 6.27 roda `max` 1× e `widen` 2× sobre o mesmo
grafo na MESMA ação semântica, e o livro não os funde.** O que o livro fatora é a **ARESTA**
(Fig. 6.25(a) é uma figura; o `prev` da Fig. 2.37 é um campo) — nunca o walk. Regra: **fatore a
aresta, não o percurso.** (Campo: Dart roda mixin application (não falha) × combined member
signature (falha); rustc separa `probe`/`confirm` — pluralidade é prática corrente.)

Argumento novo, que eu não tinha: **`_lookup` é o único com canal de falha, e falha exige nó de
culpa (`ast.Member at`)** — que `_reaches` não tem e não pode inventar. E `_reaches` é
**infundível sob qualquer parametrização**: roda **antes** da aciclicidade da qual a terminação dos
outros 4 depende (`check.dart:1896`, `collect.dart:869`) ⟹ fundir reimportaria o `visited` que o
two-pass do `_checkWellFormed` acabou de pagar para remover.

## O que PAGA: promover a **aresta instanciada** (2 artefatos, `type_table.dart`)
O bug já aconteceu **duas vezes, no mesmo eixo**: `type_table.dart:258` (*"cada um tinha a sua cópia
desta lista… Uma lista, um alcance"*) e `collect.dart:879` (*"a **lista** foi unificada, a
**substituição** não"* — 4º da série "generic não substituído"). ⟹ o compartilhado não é `sources`,
é `substitute(sources, subst)`. `_superTypesOf` **já É isso** e o doc dele diz (*"é onde o
`_isSubtype` e o `_lookup` coincidem por construção"*) — mas é privado do `check.dart` e só 1 walk usa.
1. `TypeInfo.substFor(List<Type> args)` — mata o `_substOf` duplicado.
2. `TypeTable.sourcesOf(NamedType t)` — a aresta substituída; consumida por 1–4.
Recolhe **4** cópias da aresta (`_lookup:1636`, `_implementationAbove:897`, `_offeredBy:983`,
`_superTypesOf:1958`) e **6** cópias do `if (s is! NamedType) continue` (893/959/986/1002/1144/1959).
`_reaches` fica na aresta CRUA e isso é **justificado** (decls; args não podem importar) — merece 1
linha de doc, senão o próximo leitor "conserta".

## `_substOf` duplicado: **NENHUMA das duas casas** — é do `TypeInfo` (6.3.6)
`check.dart:585` ≡ `collect.dart:1032` byte-a-byte (só muda `info`/`ti`). Teste mecânico: nenhuma
das duas toca `_types`/`types`/`_err` ⟹ função pura de `(TypeInfo.decl, TypeInfo.generics, args)`.
6.3.6: `record(t)`, *"t é um objeto de tabela de símbolos"* — a substituição que **instancia** a
tabela é propriedade do TIPO, não do passe.

**O guard é o tell:** `if (… args.length != info.generics.length) return const {}` — devolve um
**VALOR** (subst vazia ⟹ todo `T` fica livre) para uma violação de invariante. É a doença que eu
mesmo registrei (`dispatch_members.md` item 4: violação de contrato = `throw`, não diagnóstico).
A aridade é cobrada em `collect.dart:738` (`generic-arity-mismatch` + `ErrorType`) ⟹ o guard é
inalcançável **exceto** por `collect.dart:369` — `annotations[target] = NamedType(targetDecl,
info.kind)` **sem args**: para `extension Box { }` com `struct Box<T>`, isso põe um `NamedType`
aridade-inválido na **side-table nº4** que a F7 vai ler. Latente hoje (não flui p/ `_substOf`), vivo na F7.

## Achado: `_lookup` conta **REQUISITO** como hit no nível 1+
`_implementationAbove:899` já tem a cerca (`x.decl.body != null`) e o doc a funda (`:867` — *"requisito
sem corpo não tem o que sobrepor"*). **A mesma frase vale para o `_lookup`: requisito não tem o que
DENOTAR** — 1.6.4, box *"Declarações e definições"* (declarado ≠ definido); não há Procedure p/ F7.
Nível 0 **não** pode filtrar (`fn g(x: X) { x.f() }` com receptor-trait é legal — dispatch é Grupo B);
só o **degrau de subida** filtra. Consequência em CA70 (`check_test.dart:968`): o programa É ilegal, mas
por `missing-trait-member` **×2** (`S` não declara `f`) — o `ambiguous-member` é 3º erro na mesma causa
e culpa o **uso** em vez da **decl**. Com a cerca, sobra só o caso (b): **dois defaults** com a mesma
assinatura ⟹ aí `ambiguous-member` está certo e o campo concorda 3/3 (Scala/Swift/Dart recusam
concreto×concreto não relacionado).

**Por que `_lookup` e `_implementationAbove` NÃO se contradizem** (a pesquisa sugere que sim):
`_checkOverride` pergunta *"que TIPO meu override deve ter?"* → assinatura → iguais → escolha
inobservável (o doc `:947` está certo). `_lookup` pergunta *"que DECL este nome denota?"* → dois
corpos → indeterminado. **A mesma igualdade que torna a escolha inobservável para um deixa o outro
genuinamente indeterminado.** É a prova mais limpa de que os walks não são fundíveis.

Não medi: não rodei os testes. Tudo acima é leitura de código + livro.
