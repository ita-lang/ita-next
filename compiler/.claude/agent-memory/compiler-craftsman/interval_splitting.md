---
name: interval-splitting-range-f6
description: W1 da Fatia 2 (LT-F6b) — interval-splitting de Range para exaustividade/redundância de match sobre Int; Maranget §3.1/§3.2 + rustc IntRange::split; a correção-chave "não splita o domínio na exaustividade".
metadata:
  type: project
---

# Fatia 2 (LT-F6b) — interval-splitting de Range sobre Int (W1, 2026-07-18)

Estende `match_analysis.dart` (Fatia 1). Fonte: **Maranget 2007 §3.1 (Fig 1, U/S/D)** + **§3.2
"Extensions"** (tipo de Σ infinita ⟹ nunca completa ⟹ default + testemunha fora de Σ) e o precedente
executável **rustc `rustc_pattern_analysis`** (`Constructor::IntRange`, `IntRange::split`,
`ConstructorSet::split → SplitConstructorSet{present,missing}`, sentinela `Missing`/`NonExhaustive`).

## A correção-chave que provei (o insight que corrige o esboço do coordenador)
- **Exaustividade NÃO precisa splitar o domínio.** Cobertura é MONÓTONA: um valor de col0 coberto casa
  ⊇ as linhas que um valor-gap casa (gap só casa ω-rows; coberto casa ω-rows + intervalo-rows). Logo o
  ponto "mais difícil de cobrir" é sempre um valor-gap. ⟹ para exaustividade basta **`maxHi+1`** (ou o
  primeiro furo interior via `_firstGap`; `0` se não há intervalo) + o ramo `D` INALTERADO. O split só é
  necessário na **REDUNDÂNCIA** (query = intervalo limitado, sobreposição parcial).
- **Por que Itá diverge do rustc aqui:** rustc splita o domínio na exaustividade porque tipos são
  LIMITADOS (`u8`: `0..=255` exaure). Itá trata `Int` como ℤ **ilimitado** (fato do dono: sem range
  aberto, nenhum conjunto de ranges exaure Int — só `_`/ω). ⟹ gap SEMPRE existe ⟹ pulo o split.

## Desenho cravado (o eixo isolado, como `_Sig` fez para selados)
- Bifurca por **novo `_RangeSig extends _Sig`** devolvido por `_sigOf(IntType)` (NÃO por `is IntType`
  espalhado) — `_sigOf` continua o único oráculo de família; Float/String seguem `_OpaqueSig`
  (testemunha `_WWild`, sem split — fora de escopo).
- Nova cabeça **`_HInt(_Iv)`**: IntLit→`[n,n]`, `a..=b`→`[a,b]`, `a..b`→`[a,b-1]`, `lo>hi`→vazio.
  `RangePattern` SAI de `_HStruct`. Fronteiras em **`BigInt`** (borda `b-1`/`maxHi+1` wrappa no int i64
  do Dart).
- `_splitInterval(Q, rows)`: corta em `{r.lo, r.hi+1}∩Q` ⟹ sub-intervalos elementares ⊆-ou-disjoint de
  todo row (nenhuma fronteira estritamente dentro). `_specializeIv(E,P)`: **aridade 0** ⟹
  `colTypes.sublist(1)` preserva a cauda SEM explodir (o ponto crítico da cauda). `_WInt(BigInt)` nova
  testemunha; printer `v.toString()`.
- `_useful`: 1 branch novo na query `_HInt` (redundância: split + `_specializeIv`; `iv.isEmpty→null`=
  morto por vacuidade) + 1 branch novo `sig is _RangeSig` na ω-query (exaustividade: `D` + `_gapValue`).

## Soundness/terminação (auditoria §F1.4)
- Termina: fronteiras finitas ⟹ elementares finitos; `_specializeIv` tira 1 coluna (aridade 0) ⟹ width↓.
- Nunca falsa-acusa: gap `maxHi+1` é comprovadamente fora da união; redundância só sai se TODO elementar
  de `Q` é coberto (⊆-or-disjoint). Range vazio (`9..=3`/`5..5`) → morto por vacuidade (correto).
- `_MatchUnsupported` ESTREITA: Range sai; sobra só List + produto (struct/record) em gap não-fechado.
  O `_HStruct→throw` de `_specializeAtom` fica MORTO p/ Int (backstop I2 defensivo).

## Regressão do W2 (a testemunha vira concreta)
- `flow_test.dart:584` `match n:Int{0=>1}`: `'_ não coberto'` → **`'1 não coberto'`** (único assert
  quebrado — detail é UNIT, não `EXPECT-FLOW`). Apêndice §F1: linhas 821/822/824/830 (`_`/`.ok(_)`/
  `unsupported` → concreto). **Nenhuma fixture de conformance** com range-em-match (só `maximal_munch`
  do lexer). Blueprint fica em `specs/014-flow-check/blueprint-match-analysis.md` §F2 (colar do relatório).
