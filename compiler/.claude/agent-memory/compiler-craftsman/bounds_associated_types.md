---
name: bounds-associated-types
description: Bounds em generic param (F<: é a técnica, NÃO type classes) + o ADR-0012 §B-7 sob premissa falsa. Inclui o achado do §C-9 contradizer o §B-7 e o furo do `distinct by decl` no `_lookup`.
metadata:
  type: project
---

# Bounds + associated types — W1 de fundamento (2026-07-15)

## LACUNA do Dragon — CONFIRMADA na fonte (não é presunção)
6.5 é HM/ML **irrestrito**. `06/05-verificacao-de-tipo.md:246-253` (`∀α. list(α) → integer`),
`:248` (*"o quantificador universal … variável ligada"*). **Alg. 6.16** (`:324-325`): *"substitua as
variáveis ligadas … e **remova os quantificadores ∀**"* — remove o ∀ e nada mais; **não há sítio onde
uma obrigação sobreviva à instanciação**. É exatamente o buraco.
`11-referencias-do-capitulo-6.md:26` só cita **Milner** [7] e **Pierce** [8]. **Zero Wadler-Blott, zero
Cardelli-Wegner.** 6.5.2 (`:194-217`) é sobrecarga — resolve por assinatura do call-site, não por
constraint sobre variável. Parente, não substituto.

## A técnica canônica BIFURCA — e o Itá já escolheu, sem saber
- **F<: / bounded quantification** — Cardelli & Wegner 1985; TAPL cap 26 (`∀α≤B. τ`). Nominal.
- **Qualified types / type classes** — Wadler & Blott 1989; Jones 1994. Dictionary passing.

**Dictionary passing está PROIBIDO no Itá por Art. III (Grupo B): o dicionário É a vtable.**
E a conformance do Itá é nominal+global (`_conform` escreve `info.traits`; `impl Trait for T` escreve
na mesma tabela — ADR-0012 §A-2) ⟹ "T conforma Ord" é fato da type-table, não evidência que viaje.
**⟹ F<: é a técnica. Haskell não é modelo aqui, e a razão é estrutural, não estética.**

## As DUAS obrigações (quem só faz a 1ª tem compilador unsound)
- **(a) uso, no corpo** — `Σ_membros(T) := Σ_membros(bound(T))`. TAPL 26.3.
- **(b) instanciação, no call-site** — `α := Int` ⟹ checar `Int ≤ Ord`. Sem (b), (a) é unsound.

## O que muda no código — o arm é a ÚLTIMA linha, não a primeira
`check.dart:1605` (`if (recv is! NamedType) return null`) ⟹ `unknown-member` (`:1503`). Mas o bloqueio
está 3 camadas abaixo: **o bound não existe na type-table**.
- `TypeInfo.generics` é `List<String>` (`type_table.dart:213`) — só o nome.
- `TypeParamType(owner,name)` (`type.dart:406-409`), `TypeVar(id)` (`type.dart:425-427`) — sem bound.
- `_checkGenericBounds` (`collect.dart:95-132`) é walk **sintático**; nunca resolve `TypeNode`→`Type`.

Cadeia mínima: `generics` → `List<GenericInfo{name, List<Type> bounds}>` resolvido na **A2**
(recursivo por 6.3.1 box "nomes de tipo e tipos recursivos"). Aí o arm do `_lookup` reusa **o mesmo
monoide do nível 1+** (`hits`/`distinct`/`ambiguous-member`, `check.dart:1637-1652`).
**`T: A + B` não pede regra nova — é a `sources` com outro nome; o diamante já responde.**
`_isSubtype` não muda (arm novo lendo `boundsOf`; `_superTypesOf` segue a aresta instanciada).

**A (b) é a cara:** `instantiate` (`unify.dart:176-179`) não carrega bound. Obrigações **diferidas até
depois da R2** (não dentro do `_bind`) — senão a aceitação depende da ordem de unificação, contra o que
o W3 já provou em [[f5-quantifiers-subtyping]] (R0→R1→R2 troca o corte de cada arg).
**Armadilha nova:** bound **F-bounded** (`T: Comparable<T>`, o jeito nominal de escrever `Ord`) ⟹
`_occursIn` NÃO é occurs-check válido ali (a ocorrência é legítima). Canning et al. 1989 — outra lacuna
do Dragon. E **F<: cheio é INDECIDÍVEL** (Pierce 1994); a saída industrial é Kernel F<:.
**⟹ `T: A + B` não é feature barata de front-end. A conjunção é barata; o bound check é que custa.**

## §B-7 — a justificativa é falsa por DUAS razões independentes
Texto (`.specify/memory/adr/ADR-0012-rulings-superficie-fase2.md:24`): *"Associated types: **adiar**.
Bounds inline (`T: A + B`, já em `genericParam.bounds`) **cobrem a maioria dos casos**"*.
1. **Contingente** (achado do `ita-visionary`): bounds estão inertes (`collect.dart:95`).
2. **Categórica, e é a que importa — prova INTERNA, sem RFC 195:** bound é entrada no **Γ** (predicado,
   consumido por `_isSubtype`); associated type é entrada na **Σ_membros** (consumido por `_lookup`,
   precisa de `substitute` ao subir). **Duas tabelas, dois consumidores.** Nenhuma cardinalidade de
   bounds produz um `Type` de saída — não há campo em `TypeInfo` onde o resultado de um bound se leia
   como tipo. **Implementar `T: A + B` NÃO conserta o §B-7.**
⟹ Invalida a **justificativa**, não a **decisão**. Adiar segue defensável por **custo** (Rust: RFC 195
2015 → GATs 2022, 6,5 anos, 4 limitações no release). Pedido: **re-ratificar com razão nova**.

## ⭐ O ACHADO — o §C-9 do MESMO ADR contradiz o §B-7
`ADR-0012:33` §C-9 item 3 planeja *"trait `Iterator`/`Iterable`, **`next() -> Option<T>`**"* na M5.
Esse `T` é **output** (uma `List<Int>` itera `Int`, determinado por Self). Sem associated type só resta
`trait Iterator<T>` — que a `grammar.ebnf:220` (`traitDecl ::= "trait" IDENT genericParams? typeBody`)
**já aceita**. É **literalmente o `Iterator<A>` que a RFC 195 reverteu às vésperas do 1.0**.
**O ADR adia no §B-7 o que o §C-9 encomenda.**

## ⭐ Dano ativo verificado — `distinct by decl` colapsa instanciações
`_conform` (`collect.dart:216-261`) **não tem dedup de trait**: `traits.add(t)` (`:221`) +
`info.traits = [...info.traits, ...traits]` (`:261`). Não há `duplicate-conformance` em lugar nenhum
(grep em `collect.dart`). ⟹ `impl Iterator<Int> for Foo` **e** `impl Iterator<String> for Foo`
coexistem. No `_lookup:1643-1652` os dois hits têm **o MESMO `h.decl`** (o `next` do trait) ⟹
`distinct.length == 1` ⟹ **sem `ambiguous-member`**: devolve `hits.first`, isto é, **o primeiro por
ordem de declaração**. É a violação do **Ex. 5.10** que o autor já pagou uma vez (`collect.dart:181-185`).
O `distinct by decl` está certo para o **diamante** (mesmo membro por dois caminhos) e errado para
**duas instanciações do mesmo trait genérico**. Chave certa: `(decl, type)` — ou cortar em `_conform`.
**Consequência de design:** o Itá está HOJE na forma pré-RFC-195 do Rust — param de trait como input,
sem associated type, **sem checagem de coerência** — e sem turbofish (GRAMMAR §6) para desambiguar
`x.next()`. **A pergunta do §B-7 está forçada pelo código, não é acadêmica.**

## Correção à pesquisa de campo
Ela alegou *"divergência de sintaxe latente entre o §B-7 (`+`, forma do Rust) e a meta-diretriz Swift
(`&`)"*. **FALSO.** `grammar.ebnf:211` é normativo: `genericParam ::= IDENT ( ":" type ( "+" type )* )?`
— o `+` **é a norma do projeto** (Classe B), casado com `parser.dart:616-619`. A meta-diretriz Swift
resolve **empate**, e aqui não há empate a resolver.
