---
name: doctrine-secao8
description: Doutrina de como escrever a §8 (runtime) das specs — o princípio é a razão, o dado da VM é o reforço; toda §8 é retrato datado do vendor.
metadata:
  type: feedback
---

Na §8 de qualquer spec, **o princípio da linguagem é a razão; o dado da VM é o reforço** — nunca o inverso.

**Why:** ruling do `ita-visionary` na spec 009 (2026-07-15), corrigindo um "orçamento de `dynamic`" que eu
havia proposto. Escrito ao contrário, a recusa de `dynamic` ficaria contingente à convenção de chamada da VM:
se um backend futuro baratear o dinamismo, o argumento evapora — **e P4 não evapora junto**. Custo baixo nunca
é licença. Meu próprio dado confirma o risco: as regras de unboxing MUDAM entre versões
(dart-lang/sdk#40004 *"We start with unboxed `double` fields, but might extend this to `int`…"*; hoje já existe
`numRecordFieldsForReturnValueUnboxing = 2`, que não existia). O dado da §8 é **retrato de uma tag**, não lei.

**How to apply:** (1) toda §8 abre declarando o vendor/tag (`3.12.2`, Kernel 130) — é retrato, não verdade
permanente; (2) escrever "P_x proíbe X; o backend reforça: …", nunca "X é caro na VM, logo proibido";
(3) quando o dado for leitura de código-fonte da VM (não doc), marcar o nível de confiança;
(4) o que a doc não quantifica, declarar como "medir" — não estimar. Ver [[types-nullability-f5]].
