---
name: doctrine-declaracao-sobrevive-ao-tick-verde
description: Doutrina — lacuna declarada só vale se a declaração sobrevive à redução do CI a um tick verde (nome do job/linha de resumo), e se tem catraca que a force a fechar.
metadata:
  type: feedback
---

# Doutrina: a declaração tem de sobreviver ao tick verde (e ter catraca)

**Regra:** um gate parcial é **fiel** quando *certifica só o que verificou, acusa só o que refutou e
confessa o resto* ([[phase6-maranget-slicing-identity]]) — mas a confissão precisa de **duas** garantias
que um comentário no fonte não dá:

1. **Sobreviver à redução.** O CI comprime tudo num nome de job e um ✅. Quem lê o PR não lê o cabeçalho
   do relatório nem o `tasks.md`. Então a lacuna tem de estar **onde o leitor olha**: no *nome do
   job/step* e na *linha de resumo* do runner ("N verdes · M fronteiras declaradas"), não só no
   docstring. Declaração que só existe no fonte é verdadeira e **inaudível** — vira mentira por omissão
   no artefato que o time consome.
2. **Ter catraca (forcing function).** Lacuna declarada sem gatilho apodrece em lacuna permanente. A
   catraca certa **fica vermelha quando a fatia nasce**, não verde. É o inverso do `xfail` clássico:
   `xfail` fica verde quando a feature chega e nunca cobra nada; o fixture `// EXPECT-ICE:` do
   `codegen/test/golden_test.dart` FALHA quando o programa passa a compilar, exigindo promoção a CA
   verde. Essa assimetria é o que separa **documentar** a lacuna de **celebrá-la**.

**Why:** 2026-07-28, W0 do job de CI do `codegen/` (PR #4). O golden-runner roda 1 de 3 alvos (a
`spec 013 §7.7` pede VM/AOT/JS). Rodar 1 e dizer 1 é honesto; exigir vermelho até os 3 existirem seria
a opção 🛑(c) do Maranget — punir o dev pela incompletude do compilador e treinar o time a ignorar CI
vermelho, que destrói o gate. O que **seria** mentira é o gate se apresentar como "golden-runner
(Art. IV-4)" verde sem dizer o alvo. Base textual: **Art. II** manda *"declara seu comportamento nos
três"* (o verbo é DECLARA, não roda); **Art. IV-4** *"nada entra sem CI verde"* é **piso de entrada**,
não teto de escopo.

**How to apply:**
- Gate parcial: o nome carrega o recorte. `golden-runner (VM/JIT — AOT e JS pendentes)`, não `codegen`.
- A catraca do escopo mora no **checklist da spec**: nenhum CA da `spec 013 §11` pode ser marcado verde
  enquanto o alvo escrito no próprio item ("3 alvos" / "VM + JS") não tiver rodado. O `§9` e a DoD
  ficam abertos — é isso que impede "declarado" de virar "aceito para sempre".
- Vale para contagem, não só para alvo: fixture de fronteira nunca entra no denominador de "corpus verde".

Relacionadas: [[phase6-maranget-slicing-identity]], [[phase7-order-f7b-before-offset]] (dívida rastreada
com gatilho), [[doctrine-p9-escopo-tooling]].
