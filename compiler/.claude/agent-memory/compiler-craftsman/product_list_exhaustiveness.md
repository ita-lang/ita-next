---
name: product-list-exhaustiveness-f6
description: W1 da Fatia 3 (LT-F6b) — exaustividade/redundância de produto (struct/record/class) + List (slice) + String-redundância; Maranget §3.1 (produto=1 ctor) + rustc Slice::split; produto RIDA o motor selado, List é SEALED-like (rabo alcançável), NÃO Range-like.
metadata:
  type: project
---

# Fatia 3 (LT-F6b) — produto + List + String (W1, 2026-07-18)

Estende `match_analysis.dart` (Fatias 1+2). Fonte: **Maranget 2007 §3.1** (produto = Σ de 1 ctor,
`S` expande n campos — NÃO é §3.2) + **rustc `rustc_pattern_analysis`** (`Constructor::Slice`,
`SliceKind::{FixedLen, VarLen}`, `Slice::split`, `SplitConstructorSet{present,missing}`) para o
comprimento variável de List (Maranget §3.1 não cobre slice — lacuna PROVADA).

## Os 5 achados de código que mudam o §3.3 (confirmados, não re-descobrir)
1. **NÃO existe `RecordType`** (`type.dart`): só `NamedType` (struct/class/enum) + `TupleType`
   (produto POSICIONAL, sem nomes). Não há record estrutural.
2. **`StructPattern` e `RecordPattern` = MESMA máquina** — ambos `_bindFieldPatterns`
   (`check.dart:538-541`), exigem `NamedType` com `fields`. RecordPattern = StructPattern sem
   `typeName` (F5 já o ignora) e sem `hasRest`. ⟹ produto é UMA máquina (responde ruling d).
3. **F5 ACEITA campo parcial sem `..`** (`_bindFieldPatterns` só itera campos presentes; `hasRest`
   lido no parser mas DESCARTADO). ⟹ "campo faltante = ω ou erro" é decisão genuína da Fatia 3.
4. **Parser aceita 2-rests e rest-no-meio** (`parser.dart:1794-1804` cru). Rest-no-meio é LEGAL no
   rustc (VarLen pre+suf); 2-rests é ilegal (sem `(pre,suf)` definido) → 3º dedo, ruling-dono.
5. **String literal pattern = `LiteralPattern(Str(parts))`**; constante ⟹ `[StrLit(value)]`;
   interpolada ⟹ tem `StrInterp`. A cerca de 3c é esse teste.

## Desenho cravado (os 3 eixos)
- **PRODUTO = `_StructSig` que RIDA o motor selado** (zero branch novo em `_useful`): `_sigOf`
  devolve `_SealedSig([_Ctor(name, fieldTypes, fieldNames)])` de 1 ctor; `_Ctor` ganha
  `List<String>? fieldNames`. `_classify(Struct/Record)→_HProd(p)` (head próprio, NÃO `_HCtor`
  por-nome — produto tem 1 ctor, name-match seria frágil pq typeName é ignorado). `_specialize`
  ganha ramo `_HProd`→`_subPatternsProd` (reordena p/ ordem DECLARADA de `TypeInfo.fields`,
  **campo omitido → ω**). `isComplete({name})=true` com qualquer linha de produto ⟹ ramo complete ⟹
  recursão nos campos; column só-ω ⟹ incomplete ⟹ `_` fecha (Regime 1). Testemunha `Point{x:1,y:_}`.
  Produto NUNCA vira unsupported (campos são enum/escalar/struct/List, todos modelados).
- **LIST = `_ListSig(E)` + split por comprimento, é SEALED-like (finito após split), NÃO Range-like.**
  A diferença-chave de Int: o rabo de List É ALCANÇÁVEL (um `..resto`/VarLen cobre `[k,∞)`) ⟹
  `[]+[_,..]` é EXAUSTIVO de fato (verde REAL, não unsupported). Família = `{Len_0..Len_L} ∪ {Tail}`,
  `L=max(maxFix, maxPre+maxSuf)` — preciso `maxPre`/`maxSuf` SEPARADOS (pontas opostas: `[a,..]` vs
  `[..,z]`; representante alinha prefixo-esq/sufixo-dir, colapsa meio). `_HList(prefix,suffix,hasRest)`;
  `S(Len_n)` cria `[E×n,...cauda]`; `S(Tail)` cria `[E×(maxPre+maxSuf),...]`. Branch novo em `_useful`
  (ω-query e `qh is _HList`), 3ª via ao lado de selado/Range. Testemunha `_WList(elems,hasTail)` →
  `[_,..]`/`[false,..]`. Comprimentos em `int` (pequenos por construção — NÃO BigInt; ≠ VALORES de
  Int da Fatia 2). Redundância de VarLen-query cobre múltiplos comprimentos (parte adiável = 3b-ii).
- **STRING-redundância = `_atomKey` valor-real só p/ `Str` 1-parte `StrLit`** (`s:${value}`);
  interpolada/outro fica `u:offset:len` único (cerca sound sob QUALQUER ruling b). Exaustividade de
  String segue Fatia 1 (átomo Σ∞, testemunha `_`); 3c toca SÓ redundância. Float já tinha `f:value`.

## Rulings do dono (a fila que ele espera)
- (a) shorthand `P{x,y}` — CONFIRMO fora-de-escopo (débito D4 F4; `pattern-binder-unsupported` barra
  antes da F6). É AST, não análise.
- (b) interpolada em pattern — banir (`interpolated-string-pattern` F5) vs relaxar. Recomendo banir
  (é guard, não pattern). NÃO bloqueia 3c (cerca defensiva).
- (c) campo parcial sem `..` — ω (recomendo, natural do produto, F5 já aceita) vs erro Rust-style
  exigindo `..` (lint ortogonal, torna `hasRest` significativo). São 2 decisões: significado + lint.
- (d) 2-rests/rest-no-meio — rest-no-meio LEGAL (grátis no `_HList`); 2-rests → `duplicate-rest`
  parser (meu voto) ou F5. **BLOQUEIA 3b.**
- (e) `class` como produto — sound p/ exaustividade (toda instância tem os campos, tipo estático I5);
  permitir vs restringir a struct (reservar class p/ futuro match selado de hierarquia). Flag.
- (f) testemunha do rabo — `[_,_,..]` (rustc-like, recomendo) vs concreto `[_,_,_]`. Cosmético.

## Fatiamento: 3a produto → 3b List → 3c String
- 3a: menor delta (rida selado, zero branch em `_useful`), independente, sound só com ruling (c)=ω.
- 3b: o maior; pré-condição DURA = ruling (d). Sub-fatiável: 3b-i exaustividade (must, segurança) +
  3b-ii redundância-de-var-query (lint, abstém sem custo).
- 3c: trivial (1 ramo `_atomKey`), independente, pode entrar a qualquer hora. Ruling (b) só é higiene.
- **Após 3a+3b+3c: `match-exhaustiveness-unsupported` fica quase MORTO** (sobra 2-rest se ruling d
  não fechar + ErrorPattern backstop) — o alvo do §12-11 (lacuna estreita até backstop).

## Terminação/soundness (auditoria §F1.4)
- Produto: recursão nos campos, medida `(width, prof-pattern)` decresce; sub-patterns < list/struct.
- List: `L` finito; `_specializeLen(n)` cria n colunas E mas sub-patterns estritamente menores;
  representante do rabo (aridade maxPre+maxSuf) é fiel pra n>L (var uniforme, sem sobreposição pre/suf).
  Nunca falsa-acusa (gap = comprimento concreto produzível ou rabo honesto), nunca cala.
- Blueprint a colar em `blueprint-match-analysis.md` §F3 (do relatório W1). Tabela-âncora: P1-P7,
  L1-L9, S1-S3 (P1/L1 eram unsupported→viram verde; P5/L6 redundância; L7 exaustividade de elemento).
