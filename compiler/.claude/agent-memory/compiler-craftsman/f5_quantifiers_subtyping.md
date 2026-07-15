---
name: f5-quantifiers-subtyping
description: F5 — prefixo ∀ (FunctionType.quantifiers), ≤ algorítmica, ordem R0/R1/R2 e as duas noções de igualdade de FunctionType. O que a implementação ensinou no W3 (2026-07-15).
metadata:
  type: project
---

# F5 — prefixo ∀, `≤` e igualdade de assinatura (W3, 2026-07-15)

Revisão adversarial dos commits `46ae592`/`deba83d`/`1d0711f`/`921353a` (branch
`feat/fase3-4-desugar-binding`). O que o código ensinou **contra** o meu W1.

## O que a implementação PROVOU certo (não re-litigar)
- **Terminação do `_isSubtype`**: `_argsConform` não recursa (`==` estrutural) ⟹ medida = profundidade
  do DAG de decls (Kennedy & Pierce 2007 é a lacuna certa, e só morde com variância). `_superTypesOf`
  tem 1 chamador (`_isSubtype`), que só roda no `Checker`, que nasce **depois** do `runCollector` ⟹
  **nunca vê grafo cíclico**. A3 corta a **SCC inteira** (culprits antes do corte) ⟹ ordem-independente.
- **Trait é folha, verificado nas duas metades**: `info.traits` só escrita em `_conform` (guarda
  `kind == trait_`); `info.superclass` só sob `inheritable`, só `case ClassDecl`. ⟹ só `superclass` cicla.
- **`instantiate` não perde nada** e a ordem `vars[i] ↔ quantifiers[i]` é por construção. **Captura não
  ocorre por construção**: `_resolveInner` usa `FunctionType.positional` ⟹ nenhuma anotação de
  superfície carrega ∀ (sem rank-2).
- **A prova do guarda `freshVars` sobrevive**: `fresh()` tem **1 chamador** (`instantiate`);
  `_closureAgainst` não cunha (só `unify`→`_bind`); todo `expected` que chega ao `_call` é var-free
  (auditei os 7 sítios de `_check`).

## Achados (dano ativo)
1. ✅ **PAGO em `191a1f9` (`_occursIn`).** `_staticMember` × guarda-`freshVars` = regressão:
   `Box.zero()` (static sem `T`) dava `cannot-infer` **inexprimível** (sem turbofish, GRAMMAR §6).
   **A assimetria que eu não vi no W1:** `_selfTypeOf` GARANTE que o ∀ da classe ocorre no ret do
   `init` ⟹ R0 sempre o determina ⟹ escape pela anotação. **Static não tem essa garantia.**
   **O argumento ESTRUTURAL de que o filtro não reabre o `_freeParams`** (melhor que "prefixo
   conhecido ≠ descoberta"): o caminho rígido (`self.set(x:5)`) **não passa por lá** —
   `_receiverAsTypeName` exige `Ident`, e `self` é `SelfExpr` ⟹ os dois caminhos estão separados por
   **discriminação sintática**, não por julgamento. Era isso que o `_freeParams` não tinha.
2. **DUAS noções de igualdade de `FunctionType`, e o doc de uma nega a outra.** `unify.dart:109` diz
   *"label/default não participam da equivalência estrutural"*; `ParamType.==` compara os dois.
   ⟹ `_isSubtype` **não tem arm de FunctionType** + label no `==` ⟹ **nenhuma fn nomeada casa com
   `(Int) -> Int` anotado**. Régua: **6.3.2** — nome × estrutural. `label` é texto da declaração, não
   estrutura. `==` de tipo ≠ `sameSignature` de membro (o ruling "label PARTICIPA" é do 2º).
3. ✅/🔴 **METADE paga em `191a1f9` (`sameSignature`, α-equivalência posicional).** O `==` sintático
   fazia override/trait de método GENÉRICO ser falso-positivo TOTAL (dois `FnDecl` distintos nunca
   têm assinatura genérica igual). **A soundness do `sameSignature` depende de AUSÊNCIA DE CAPTURA**,
   e ela vale por construção (os `TypeParamType` de `b` têm dono `ADecl`/`A.f`, os de `a.quantifiers`
   têm dono `D.f` — domínios disjuntos). Isso **não está no doc dele** e devia estar.
   `hashCode` OK: `sameSignature` não é `==`, logo não deve o contrato.
   **🔴 A METADE QUE FICOU — `_implementationAbove` (`collect.dart:800`) devolve o `MethodInfo` CRU**,
   sem `_substOf(si, s.args)` ⟹ `class D<T> : A<T>` + `override fn eco(x: T)` = falso-positivo, e o
   `sameSignature` não alcança (o `T` é da CLASSE, não está em prefixo). **4ª instância da série
   "generic não substituído"**: `_lookup` substitui, `_superTypesOf` passou a substituir (1d0711f),
   `_checkTraitConformance` substitui (`_substOfTrait`) — **só o `_implementationAbove` não**. O doc
   do `TypeInfo.sources` diz que unificou os 4 walks: unificou a LISTA, não a SUBSTITUIÇÃO.
4. **`exprTypes[closure]` retém `TypeVar`** — `_closureAgainst` grava `expected` ANTES de o corpo
   resolver o ret. Sem anotação (`let ys = mapa(xs) { $0+1 }`) o R0 não roda e `α` sobrevive na
   side-table nº1. Teste que mata a classe: *"nenhum valor de `exprTypes` contém TypeVar"*.
5. **`_call` só consulta candidatos com `cands.length > 1`** ⟹ `class` + init só em `extension` dá
   `no-init` (class nunca tem memberwise). Fix: `cands.isNotEmpty`.

## ⚠️ Meu W1 FALSIFICADO — a ordem R0/R1/R2
Eu escrevi *"R1 → R0 → R2; `R1→R0` é **DIAGNÓSTICO** (erro no call, não no arg)"*. **Errado: é
SEMÂNTICO.** O código faz **R0 → R1 → R2**, e está certo:
`fn dois<T>(a:T,b:T)->T` + `let x: A = dois(a: d, b: a2)` (d:D≤A) — R0-primeiro **aceita** (α:=A, os
dois args vão por subsunção); R1-primeiro **rejeita** (α:=D, `_isSubtype(A,D)` falso). O `expected`
antes dos args troca o **corte de cada arg** (unificação → subsunção) ⟹ aceita mais.
**Preço a documentar:** a culpa pode cair num arg CORRETO (`let x: Float = primeiro(xs: numeros)`
culpa `numeros`, mas o errado é a anotação).

## Correções ao meu próprio W1 (dívidas ainda abertas)
- **"`_superTypesOf` é o ponto único"** — FALSO no código: `_lookup` inlina o mesmo cálculo. Duas
  cópias; hoje coincidem, e o `1d0711f` existe porque uma vez não coincidiram.
- **`duplicate-member` no 2º inserido** — item 5 da lista "o que falta"; `_checkDuplicateMembers`
  percorre em ordem de contribuição, `dump()` ordena por offset. **Ainda aberto.**
- **`hasDefault` no `ParamType.==`** viola o meu ruling do item 0 (*"label participa; default não"*).

## Padrão a extrair
`sub == sup` no topo do `_isSubtype` é doc errada: **é redundante só no ramo `NamedType`**; para
Builtin/Tuple/Function/básicos é a **ÚNICA reflexividade** que existe (não há arm para eles).
Ver [[dispatch-members]].
