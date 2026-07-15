---
name: walks-refactor-identity-review
description: Gate do H1 da dec. 4 (2026-07-15) — unificar a aresta instanciada dos walks. Veredito "vai, com 3 cercas". São CINCO walks, não 4; a divergência inobservável é o ponto cego do refactor
metadata:
  type: project
---

# W0 — refactor da aresta dos walks (2026-07-15). **Vai, com 3 cercas nomeadas.**

## A doutrina nova (é o mirror da [[doctrine-citacao-ou-nome]])

**Política deliberadamente divergente cuja divergência é INOBSERVÁVEL é o ponto cego do refactor.**
A cerca do `_checkInheritedConflict` foi comprada justamente para tornar a precedência inventada
*"inobservável"* (f5 ITEM 3, e o código a cita em `check.dart:1662` + `collect.dart:997-1003`).
**Preço:** um walk cuja diferença não se observa é um walk que se "harmoniza" com **todos os testes
verdes**. Mesma cegueira estrutural do ruling fabricado (*"o código se comporta igual com ou sem"*),
invertida: lá a doutrina era invisível por não ter efeito; aqui é invisível **porque a cerca a montante
a neutralizou**. ⟹ **doutrina cuja evidência foi comprada por outra cerca tem de nomear a cerca no
sítio, não no header.**

## As 2 correções de medição (a cerca vale para o auditor)

1. **São CINCO walks sobre `sources`, não 4** — `_lookup` (`check.dart:1611`), `_superTypesOf`
   (`:2002`), `_implementationAbove` (`collect.dart:937`), `_offeredBy` (`:1027`), **`_reaches`
   (`:1222`)**. E `type_table.dart:260` — **o doc que carrega a doutrina** (*"Uma lista, um alcance"*)
   — lista **outros** quatro (`_lookup`, `_isSubtype`, `_implementationAbove`, detector de ciclo):
   **omite o `_offeredBy`**. O índice doutrinal já mente. Corrigir é parte do H1.
2. **"`_implementationAbove` não filtra" é FALSO** — `collect.dart:948-949`:
   `si.methods.where((x) => x.name == name && x.decl.body != null)`. É a **"Cerca 1"** do doc dele
   (`:917`). Ele e o `_lookup` (`_denota`, `check.dart:1700`) **concordam** no filtro de corpo,
   por razões declaradas diferentes.

## Q4 — os walks NÃO discordam. As 3 perguntas são 3, e o alcance coincide

`_lookup` = *"que membro este nome DENOTA?"* (corpo, senão não determina procedure) ·
`_implementationAbove` = *"há IMPLEMENTAÇÃO a sobrepor?"* (corpo) · `_offeredBy` = *"que OBRIGAÇÕES
esta aresta impõe?"* (**corpo é irrelevante — requisito É obrigação**).
`sources ⊆ NamedType` sempre (`_conform` só admite fonte que resolve a decl com `TypeInfo`) ⟹ filtrar
`NamedType` antes (`_implementationAbove`/`_offeredBy`) ou depois (`_superTypesOf`) do `substitute` é
**equivalente**. Não há #6.

## As 3 cercas (o que proteger de quem vier "consertar")

1. **`_offeredBy` NÃO filtra corpo, e isso é LOAD-BEARING** — não é descuido a harmonizar. Se filtrar,
   `inherited-signature-conflict` para de ver requisito × implementação, e caem **DOIS** rulings de uma
   vez: o `hits.first` do `_lookup` (`check.dart:1677` cita a cerca nominalmente) e o *"pega o primeiro"*
   do `_implementationAbove` (`collect.dart:997`). Backstop parcial (viraria
   `trait-member-signature-mismatch` pelo `_checkTraitConformance`) ⟹ **golden muda, não quebra** — e
   golden que muda é golden que se re-abençoa. O diagnóstico regride de *"a classe é insatisfazível"*
   para culpar o membro (regressão da f5 ITEM 3).
2. **`_reaches` fica FORA da unificação** — é o **único** walk que encara o grafo **antes** da
   aciclicidade (`:1221`), e não substituir é **certo** (ciclo é sobre decls; args irrelevantes).
   Unificar os 5 ⟹ ou pendura, ou o `seen` volta para a função compartilhada e **re-arma a guarda nos
   outros 4** — desfazendo *"duas passadas, e a ordem é o ponto"* (`collect.dart:806-814`), doutrina
   comprada exatamente ao preço de *"uma guarda em cada walker"*.
3. **O caveat *"só é são como post-filter porque trait é FOLHA"*** (`check.dart:1669`) é sobre a
   **recursão do `_lookup`**, não sobre a aresta. Mover a aresta **não** pode arrastá-lo para longe do
   `_lookup`. (E ele pende de `collect.dart:198`, *"trait é FOLHA"* — **inauditável**, item do ADR-0014.)

## Vereditos

- **Q1: predominantemente técnica** ⟹ `compiler-craftsman`. H1 **executa conclusão que eu já escrevi**
  (`check.dart:1936`: *"O ponto único correto é a aresta já instanciada"*) ⟹ **entailment, não gasta
  ruling do dono**. Não é pura só por causa das 3 cercas + o índice mentiroso (Art. IV).
- **Q2: nada se perde.** As 4 políticas ficam; só o *"quais são os pais, instanciados"* ganha dono.
  **Não** há razão de identidade para a cópia do `_lookup` (`check.dart:1643`) — é a dívida que o
  próprio commit prometeu.
- **Q3: `TypeInfo` (`type_table.dart`), vizinho de `sources`.** Critério **é** de identidade, mas é
  **Art. IV, não Art. I**: a doutrina mora no doc de `TypeInfo.sources` (`:258-266`); separar doutrina
  de enforcement é como ela apodrece. Reforço técnico (do `compiler-craftsman` confirmar): nem
  `_substOf` nem a aresta precisam da `TypeTable` — só de `info.generics`/`info.sources`; e pô-los no
  Checker **inverteria a ordem de fase** (Collector roda primeiro).
- **Ordem:** o *"5 antes de 4"* de [[crivo-5-decisoes-identity-review]] **não bloqueia o H1** — foi
  cravado por causa do H2(b)/(c), que pendem de rulings inauditáveis. H1 **não consome** nenhum.
- **Atribuição:** doc novo na aresta leva **nome** ou citação. O `Ruling ita-visionary (2026-07-15) —
  contestável, não é do dono` (`check.dart:1674`) está **certo hoje**; o refactor não pode lavá-lo
  num *"a aresta faz X"* sem dono.

Ver [[f5-consolidacao-identity-review]] (ITEM 3, a cerca que tornou tudo inobservável),
[[crivo-5-decisoes-identity-review]] (a dec. 4 e a ordem), [[doctrine-citacao-ou-nome]] (a cegueira gêmea).
