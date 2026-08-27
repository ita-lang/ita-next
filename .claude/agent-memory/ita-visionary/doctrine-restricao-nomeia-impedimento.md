---
name: doctrine-restricao-nomeia-impedimento
description: Doutrina — R7 vigia a restrição, ninguém vigia a RAZÃO dela; toda restrição nomeia o impedimento que a mantém viva, e o impedimento é uma asserção executável.
metadata:
  type: feedback
---

# Doutrina: a restrição nomeia o impedimento — e o impedimento é uma asserção

**Regra.** Toda restrição declarada (um `_ice`, um `case X(): break;`) registra o **impedimento**
que a mantém viva como **predicado executável**, não como frase. O gate exige que o impedimento
seja VERDADEIRO enquanto a restrição existir; quando ele cai, o teste fica **VERMELHO**.

**Why:** o `CLAUDE.md` R7 cobre a direção oposta — `_ice` novo exige fixture `EXPECT-ICE`, e o
fixture fica vermelho quando a fatia NASCE. Não existe sinal para o caso simétrico: **a restrição
fica, e a razão dela morre.** Incidente de 2026-07-29: `check.dart:326` passou a tipar o corpo do
`init` (o pré-requisito real da restrição do `emit.dart:844`), o ICE continuou cortando programa
legal, e **todo o CI seguiu verde**. O dono percebeu por acaso. `flow.dart:251-256` chegou a
NOMEAR o pré-requisito em prosa (*"Quando o `init` entrar na F5, este case vira o walk"*) — prosa
não falha ([[doctrine-declaracao-sobrevive-ao-tick-verde]]).

**How to apply — forma (espelha o `ca_ledger.dart`, que já tornou o placar DERIVADO):**
ledger de restrições com, por entrada: `id` · `sitio` · `oQueCorta` (construção na linguagem do
usuário) · `razao` **verbatim** · `impedimento` (`bool Function()`) · `fatiaQueFecha` (LT).
Teste: todo `impedimento()` vivo tem de dar `true`. Bilateral como R12 — impedimento falso
reprova; ICE que dispara sem entrada no ledger também reprova.

**Três formas de impedimento, em força decrescente:**
1. **Sonda comportamental no artefato da fase DONA** — ex.: assertar que `check.exprTypes` NÃO tem
   entrada para nó dentro do corpo do `init`. Teria ficado vermelha no próprio commit do
   `_initDecl`. `check_test.dart` já monta programas e inspeciona side-tables: o maquinário existe.
2. **Sonda no pacote externo** — quando a razão é *"o Kernel não tem como"*:
   `() => !existeNoKernel('LocalInitializer')`. Teria sido vermelha **desde o dia zero** — o ledger
   pega também razão que NUNCA foi verdadeira. (R5 já argumenta que `pkg/kernel` é externo e versionado.)
3. **Asserção estrutural na fonte** — fraca (refactor quebra); só quando 1 e 2 não cabem, e a
   entrada tem de dizer isso.

**Cercas (a lição do R12, senão vira silenciador):** o impedimento **nunca** é constante nem
re-enunciado da restriçao (*"o emissor não emite X"* é circular); ele olha OUTRO artefato. Toda
entrada nomeia a LT que a fecha — é o que faz o ledger **custar** (teste do R10).

**Limite honesto:** restrição cuja razão é *"ninguém decidiu ainda"* (ruling pendente) não tem
sonda boa — o impedimento é a AUSÊNCIA de artefato, e grep de ADR erra por redação. Para essas, a
entrada é ponteiro para a fila do dono, e a garantia **não** se reivindica. Separar os dois tipos.

**Destino:** R15 no `ita-next/CLAUDE.md` (mesmo estatuto das 14, todas nascidas de violação); se o
dono quiser vinculante para todas as fases, é bullet no Art. IV (que evolui — Governança). Não
toca Art. I/II ⟹ não exige emenda.

**Relacionadas:** [[doctrine-declaracao-sobrevive-ao-tick-verde]], [[doctrine-ice-nao-e-cerca]],
[[phase7-init-body-restoration]].
