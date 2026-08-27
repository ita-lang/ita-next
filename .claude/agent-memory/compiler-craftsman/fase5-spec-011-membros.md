---
name: fase5-spec-011-membros
description: Fase 5 / spec 011 (resolução de membro) — review W3 do diff 2dd4069..e61c15a; achados de correção, contratos F4×F5 e o que ficou fiel
metadata:
  type: project
---

# Spec 011 — resolução de membro (review W3, 2026-07-15)

Arquivos: `compiler/lib/frontend/semantic/{check,collect,type,type_table,unify}.dart`.
Fonte-mãe: Dragon **1.6.3/1.6.4** (escopo de membro = aninhamento na cadeia de herança), **2.7 §1**
(uma tabela por classe, campo E método), **6.3.6** (`record(t)`), **6.5.1** (síntese/two-pass),
**5.2.5/Ex. 5.10** (ordem irrelevante entre decls).

## O que está FIEL (confirmado — não reabrir)
- **Substituição composta ao subir** (`_lookup`): `substitute(sup, subst)` ANTES de recursar. Correto
  para `class D<T> : A<T>` com `D<Int>` **e** para `class D : A<Int>` (`_substOf` devolve `{}` quando
  `generics.isEmpty`). 1.6.4 respeitado.
- **Memo do `_resolve` por identidade de `TypeNode`** — SOUND. Todo sítio que toca anotação empurra o
  MESMO owner de escopo genérico antes (`_fnDecl`/`_topLevelType`/`_withGenerics`/`_contributionBody`
  ↔ `_contribute`/`_withMethodGenerics`). Um `TypeNode`, um escopo, um tipo. É o `put`/`get` da Fig. 2.38.
- **1-walk sobrevive.** `_implementationAbove` (A3) percorre a **TABELA** (`TypeInfo`→superclass/traits),
  não a árvore. `_lookup` é `Env.get` (Fig. 2.37) O(profundidade). Só overload traria o Ex. 6.5.2
  (2 percursos) — e o ruling §12-4 o barrou.
- **Ordem A2/A3.** `info.methods` é `final List` só com `.add`; `info.fields` só o dono atribui;
  `_addTraits` acumula. Inserções disjuntas ⟹ Ex. 5.10 vale. A3 roda depois de todo A2.
- `_matchArgs`: correto p/ label fora de ordem, default no meio, aridade excedente, label inexistente.

## Achados (BLOQUEANTES)
1. **`_self` em `extension`/`impl` = `ErrorType` SILENCIOSO.** A F4 põe **`n.target` (um `TypeNode`)**
   em `SelfRes` (`resolver.dart:203-204`); `_self` faz `_types.of(res.receiver)` → tabela é keyed por
   **decl** → `null` → `ErrorType` absorvente. A própria spec §3.2 escreveu a instrução
   (`resolveTypeNode(target)` → `NamedType(decl)` → `types.of(decl)`) e o código não a seguiu.
   O teste *"`self` em `extension` vê o `T` do ALVO"* é **FALSO-VERDE** (passa porque ErrorType absorve).
2. **`_topLevelType` → `throw StateError` em QUALQUER referência a `let`/`var` global.** A F4 põe o
   **`BindPattern`** em `TopLevelRes` (não o `LetStmt` — `_declarePattern`/`scope.dart` §TopLevelRes).
   O arm `ast.LetStmt n =>` é **CÓDIGO MORTO** e estaria errado p/ destructuring. `let x=5\nlet y=x` crasha.
3. **`_lookup` e `_isSubtype` sem guarda de ciclo** (`_implementationAbove` TEM — assimetria).
   `_checkInheritanceCycle` **reporta e não neutraliza** (não corta a aresta), e **só olha `superclass`**
   — ciclo por TRAIT (`struct S : S`, `impl A for A`) nem é detectado. `_lookup` → StackOverflow;
   `_isSubtype` → **loop infinito** (hang). Dragon 6.3.1 nota 3: o grafo TEM ciclos.
4. **CA73 (`let s: Stack<Int> = Stack.new()`) não entregue** — `_check` não tem caso p/ `Call`, o
   `expected` nunca desce ao **retorno**; `_hasTypeVar(ret)` dispara `cannot-infer`. Sem teste pinando.
   (Trabalho declarado no DoD: Pierce & Turner TOPLAS 2000 §3 — **não está em `references/`**.)

## Achados (correção)
5. **Conformance não verifica que o alvo É trait** (`_checkTraitConformance` faz `continue` mudo;
   `_isSubtype` compara `identical(t.decl, sup.decl)` sem checar `kind`) ⟹ `struct A : B` (B struct)
   dá **`A ≤ B` falso**, e `struct S : S` é a porta do ciclo do #3. Regra declarada na **spec 005 §3.6**
   (*"traits devem existir e ser traits"*) — vizinha do memberwise na mesma lista.
6. **`≤` não é transitivo por trait de superclasse:** `_isSubtype` sobe `superclass` sem consultar
   `cur.traits`. `class A : Base, Voa` + `class D : A` ⟹ `d.voa()` resolve (`_lookup` é transitivo em
   `superclass ∪ traits`) mas `D ≤ Voa` é FALSO. Mesma hierarquia, dois alcances.
7. **Forward-ref a global `let` → `ErrorType` mudo** (mesmo após consertar o #2): o checker roda em
   ordem-fonte e `_binderTypes` ainda está vazio. F4 dá letrec de módulo; a F5 não. É o 6.5.1
   (*"exige que os nomes sejam declarados antes de serem usados"*) sem o two-pass p/ globais.

## Menores
- `_substOf` (check.dart) ≡ `_substOfTrait` (collect.dart) — mesma função, duas casas (risco de drift).
- `_checkDuplicateMembers`: qual dos dois colidentes leva o span depende da ORDEM de contribuição
  (extension antes do struct ⟹ erro no struct "inocente"). Conteúdo da tabela é ordem-independente; o
  diagnóstico não.
- Doc do `_matchArgs` diz *"a maneira do Swift é a diretriz"*, mas Swift **exige** o label; aqui
  posicional é sempre legal (`div(2,10)` passa, `div(den:2,num:10)` erra). O comportamento é ruling
  deliberado (teste *"posicional continua legal — a stdlib faz"*); a **justificativa escrita** é que
  não bate.
