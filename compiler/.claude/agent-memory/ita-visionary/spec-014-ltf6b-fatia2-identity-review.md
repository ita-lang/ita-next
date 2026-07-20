---
name: spec-014-ltf6b-fatia2-identity-review
description: "Review W0 da LT-F6b Fatia 2 (Range/IntLit como intervalo, testemunha concreta) — liberado-com-ressalva; 3 flancos (detail stale nomeia range; witness overflow no maxInt64; empty-range usa código genérico)."
metadata:
  type: project
---

Review de identidade da **LT-F6b Fatia 2** (exaustividade de `match`: `Range`/`IntLit` sobre `Int`
modelados como INTERVALO — testemunha concreta `10`, redundância de ranges, range vazio como morto).
Implementação em `compiler/lib/frontend/analysis/match_analysis.dart`; design em
`specs/014-flow-check/blueprint-match-analysis.md` §F2.

**Veredito: liberado-com-ressalva.** Serve P4 (testemunha concreta > `_` — mais transparente) e o
§12-11 ("a PEDRA não mente"): as afirmações novas (`10 não coberto`, `unreachable @ 5`) são
verificadas, não chutadas. `_MatchUnsupported` estreitou honestamente (só List/produto).

**Por que a testemunha nunca vira valor não-digitável no caso comum:** o lexer trata `-` como
`Tag.minus` separado (`lexer.dart:240-242`) e o parser de pattern só aceita `Tag.intLiteral` direto
(`parser.dart:1854`) ⟹ **não existe pattern-Int negativo**. Logo todo intervalo tem `lo ≥ 0`, e
`_gapValue` (cursor sobe a partir do menor `lo`) devolve sempre `≥ 0`. ℤ-ilimitado e i64 CONCORDAM:
`Int` nunca exaure sem `_` (negativos não são expressáveis) — a escolha ℤ do blueprint é sound.

**3 flancos (⚠️, nenhum bloqueia):**
1. **`detail` stale nomeia `range`** — `match_analysis.dart:69` diz "cobertura de list/produto/**range**
   chega na Fatia 2/3", mas Fatia 2 JÁ promoveu range para fora do unsupported. Range nunca mais chega
   nesse erro. Sob "diagnóstico nunca mente", até string de hint não pode nomear forma já suportada.
   Corrigir para "list/produto".
2. **Witness overflow no maxInt64** — `match n: Int { 0..=9223372036854775807 => 1 }` → witness
   `maxHi+1 = 2^63`, que NÃO é `Int` válido (const-overflow §12-7) e não é digitável. Corner
   patológico (dev tem de escrever range até i64 max), mas é o único ponto onde a testemunha vira
   não-valor. Candidato a ruling do dono (fallback a `_` quando gap ≥ 2^63?) — não escrever na voz dele.
3. **Range vazio usa `unreachable-match-arm` genérico** — `9..=3` como 1º braço é morto por VACUIDADE
   (não por dominação), mas o código não distingue. "unreachable" sem braço anterior confunde. Honesto
   (o braço é dead de fato, §12-1), mas sub-informativo (P4). Um `detail` "range vazio (lo>hi)" ensinaria.
   Confirmado que `9..=3` sozinho também dá `match-not-exhaustive, 0 não coberto` — dupla verdade, sem mentira.

**I6 intacto:** guard filtrado em `analyzeMatch` (`:49` exaustividade, `:78` redundância) — acima e
ortogonal à lógica Int/Range; braço guarded com range vazio NUNCA é acusado de morto (o `continue`
precede o `_useful`). Ver [[diagnostico-nunca-mente]].
