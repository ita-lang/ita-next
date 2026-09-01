---
name: collection-literal-check-vs-synth
description: Literal de coleção NÃO-VAZIO — a spec 009 §4.3 já crava "literais de coleção CHECAM, não sintetizam" com exemplo não-vazio; o caso COM esperado é bug (entailment), o caso SEM esperado é design e só o dono o reabre.
metadata:
  type: project
---

# Literal de coleção não-vazio — o que é design e o que é lacuna (W0 da LT-012b, 2026-08-31)

Pergunta trazida pelo team-lead: `let xs: List<Int> = [10, 20, 30]` dá `cannot-infer`; é design ou bug?
As `tasks.md`/`design-notes.md` da 012 registram como *"dependência da fatia C, não bug da 012"*.

## A âncora que decide — **spec 009 §4.3, `specs/009-semantic-types/spec.md:145`**, verbatim

> *"**Literais de coleção CHECAM, não sintetizam.** `[]` não tem tipo sozinho; `[Cachorro()]` contra
> esperado `List<Animal>` desce elemento a elemento (`Cachorro() ⇐ Animal` → sub → ok). Sem esperado
> ⟹ `cannot-infer`."*

O exemplo do texto é **não-vazio**. Logo a política do Itá não é sobre `[]` — é sobre literal de coleção
em geral, e ela tem **duas metades**:

| caso | política | estado medido (2026-08-31) |
| :-- | :-- | :-- |
| **COM** esperado (`let xs: List<Int> = [1,2,3]`) | **tem de tipar**, descendo elemento a elemento | ✗ `cannot-infer` ⟹ **BUG** |
| **SEM** esperado (`let xs = [1,2,3]`) | `cannot-infer` — **é design** | ✓ correto |

⚠️ **A leitura da 012 confunde as duas.** O W3-A (`design-notes.md:80`) fala de *"literal de coleção **nu**"*
— o caso sem esperado, e ali está certo. Os três casos medidos pelo team-lead (param tipado, `let`
anotado, retorno anotado) são **com** esperado ⟹ a leitura não os cobre, e eles violam a 009 §4.3.

**Consertar a 1ª metade é entailment** ([[doctrine-consenso-entre-candidatos]]): todas as opções em aberto
dizem que `let xs: List<Int> = [1,2,3]` tipa. **Consertar a 2ª seria mudar a linguagem sem ruling.**

## O que fica para o dono — a categoria PROPAGA existe e é o candidato natural

A 010 §4.1-b (`specs/010-contextual-typing/spec.md:215-235`, **ruling do dono de 2026-07-28**) criou uma
**terceira categoria** para `if`/`match`: tem síntese, mas havendo esperado ele **desce às subexpressões**.
Literal de coleção é o mesmo animal, e o dono **não o mencionou**. Estender a categoria a ele é derivação
de agente, não ruling ⟹ vai à mesa. Pergunta: (A) checking-only puro, como a 009 §4.3 · (B) PROPAGA —
sintetiza `List<join(elementos)>` com o join **achatado** (009 §4.3:147-151: identidade + `Never`; nunca
supertipo, nunca lub) e desce no check.

**Consequência ergonômica que decide a escolha** (levar junto): sob (A), literal **nunca liga type-var** ⟹
`f([1,2,3])` sobre `fn f<T>(xs: List<T>)` é `cannot-infer` naquele arg (010 §4.3, rodada 2 contra param
já substituído). Sob (B), liga.

## Rulings que não se reabrem aqui

- **`[1, "a"]`** → `type-mismatch` **no span do elemento culpado**, nome já existente (009 §11). Nunca lub,
  nunca `dynamic`/`Object?` (ADR-0013 §2/§3 + [[phase5-types-identity-rulings]] R2).
- **`[1, 2.0]`** → **não existe promoção** e criar uma é a tentação nº5. Zero coerção (009 §4.5:188) +
  *"literal tem tipo lexical"* (009 §4.5:195, verbatim: *"`let x: Double = 1` é **erro** (escreva `1.0`)"*).
- **`Map<K,V>[k] → V?`** — ruling do dono de 2026-07-20, assentado em `specs/012-builtin-members/spec.md:26`.
  `List[i]` panic × `Map[k]` `V?` **não são duas políticas**: sequência densa × mapa esparso (012 §4.3).
  Simetrizar (panic no Map) seria trocar ausência-legítima por erro-de-programa.

## Ordem: **o literal vem ANTES da emissão do chão** (identidade, não engenharia)

CA1/CA2/CA3/CA9/CA10 da 012 são **inexecutáveis** sem ele: nenhum programa Itá inteiro consegue construir
uma `List` com conteúdo hoje, e `fn m(xs: List<Int>)` não é chamável de `main`. Só a CA4 (`"olá".length`)
roda, porque literal de String sintetiza. Emitir primeiro ⟹ o único caminho para o verde é reescrever os
CAs para a forma que não os testa — o padrão que a R9 proíbe, e que as T001–T003 já começaram a registrar.
Ver [[doctrine-declaracao-sobrevive-ao-tick-verde]].

## Co-requisitos ao tocar o ramo do `_check`

- **W3-E** (`design-notes.md:84`): `xs[[]]` tipa em silêncio — o ramo de coleção vazia
  (`check.dart:2673-2678`) faz `exprTypes[e] = expected` **sem validar que `expected` é `List`/`Map`**.
  Quem mexe no ramo fecha o furo, senão a superfície cresce sobre a mentira.
- **`nil` é pattern legal** (`compiler/docs/spec/grammar.ebnf:383`) e, pelo ruling de 2026-07-12
  (`T?` = Option, `nil` = `.none`), denota a **mesma** variante que `.none`. A CA10 da 012 usa `nil`; o
  team-lead escreveu `.none`. A exaustividade da F6 tem de tratá-los como um só, ou o `match` do idioma
  `Map[k]` acusa falso.

**Relacionadas:** [[phase5-builtin-members-chao-vs-biblioteca]] (a auditoria W0 da 012, 2026-07-20),
[[phase5-types-identity-rulings]] (§3 zero coerção, R2 `Object?`), [[doctrine-consenso-entre-candidatos]].
