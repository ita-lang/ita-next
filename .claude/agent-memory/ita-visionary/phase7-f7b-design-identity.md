---
name: phase7-f7b-design-identity
description: Rulings de identidade do DESIGN da LT-F7b (promover `resolution` a contrato) — catálogo numerado é a revelação P4; descartabilidade se preserva (não se constrói); "co-equal à IR" = status, não mutabilidade.
metadata:
  type: project
---

# Design da LT-F7b: promover `resolution` sem trair o Itá

Rodada 2 do debate F7 (2026-07-26). O dono trouxe Dragon §1.2 (symbol table passada JUNTO com a IR,
usada por todas as fases) + Crafting Interpreters §11.4 (Nystrom: side-table por identidade, "easy to
DISCARD — clear the map"). Não é re-votar (Opção 1 já DECIDIDA, [[phase7-order-f7b-before-offset]]) —
é gerar design e vigiar identidade.

## Fato de grounding que reenquadra o "God-object"
`CheckResult` (`type_table.dart:453`) NÃO é blob: 7 tabelas NUMERADAS (nº1–nº7), cada uma com
docstring que nomeia CONSUMIDOR (F6/F7) + prova de NÃO-DERIVABILIDADE. nº8 (`completesNormally`) no
`FlowResult`. `resolution` (F4, `Map.identity`, `resolver.dart:56`) é a única peça do contrato SEM
número, viajando solta.

## Ruling 1 — empacotar ≠ fundir; o catálogo numerado É a revelação P4
O medo do God-object é falso: o container ser um objeto é OK **se cada membro é nomeado e justifica-se
sozinho**. O anti-padrão seria `Map<Node, Tudo>` fundido (ninguém propôs). Param solto é PIOR que
God-object por ser ANÔNIMO. Promover = dar slot numerado + docstring (consumidor DA-F6/emissão-F7;
`Ident→LocalRes`; proveniência F4). **Guarda ao `compiler-craftsman`:** exigir da docstring o mesmo que
as nº1–nº7 (consumidor + não-derivabilidade + proveniência), senão a promoção vira cerimônia (marca
sem informação) — o oposto do que cura.

## Ruling 2 — fonte única > cópia; proveniência não se borra
`tasks.md` GREEN diz "campo de `CheckResult` E `FlowResult`" = 2 donos de 1 fato (cheiro P4). Mais
honesto: 1 portador seguido adiante (`ResolveResult` de `resolver.dart:47` já é a casa: program+
resolution+errors), resultados posteriores REFERENCIAM. Aninhar saída-da-F4 dentro do resultado-da-F5
(que só CONSOME) borra "de onde veio" (P4). Ideia de desenho, técnica é do `compiler-craftsman`.

## Ruling 3 — descartabilidade se PRESERVA, não se constrói (YAGNI + futuro)
O "clear the map" do Nystrom já vem de graça do ADR-0004 (side-table por identidade vs. campo no nó):
descartar/re-resolver é `map.clear()` por construção. **NÃO** perseguir IDE/incremental como feature
agora (fere "não construir o que não precisa"); **MAS** o desenho não pode DESTRUIR a propriedade —
manter `Map.identity`, jamais folding no nó. Propriedade a preservar, não feature a construir.

## Ruling 4 — "co-equal à IR" (Dragon) = STATUS, não MUTABILIDADE
Leitura perigosa: symbol table global MUTÁVEL cutucada in-place por toda fase (tradição imperativa) =
estado-escondido anti-P4 + fere P1. Leitura itaiana: F4 produz CONGELADA; a jusante todos LEEM,
ninguém escreve. Co-equal em status (1ª classe, passada explícita), não em mutabilidade. **P1
("imutável por default") vale para os dados do PRÓPRIO compilador**, não só p/ código do usuário —
fases puras encadeando valores imutáveis (P5). Invariante a defender.

**Relacionadas:** [[phase3-prep-side-table]] (ADR-0004), [[phase7-order-f7b-before-offset]] (a ordem),
[[phase5-011-w3-review]] (a doença do repasse solto que a 011 já matou).
