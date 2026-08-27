---
name: doctrine-vm-data-reinforces
description: Doutrina permanente — dado do backend (dart-vm-expert) REFORÇA uma decisão de identidade, nunca a FUNDAMENTA. Se o custo da VM é a razão, a razão evapora quando a VM mudar.
metadata:
  type: project
---

# Doutrina — o dado da VM reforça; nunca fundamenta

**Regra:** quando um veredito de identidade e um dado do `dart-vm-expert` apontam para o mesmo
lado, a spec deve escrever **o princípio como razão** e **o dado como reforço** — nunca o inverso.

**Why:** se a recusa de `dynamic` (ou de qualquer coisa) se apoia em *"a convenção de chamada fica
boxed"*, então a recusa é **contingente**: uma VM futura que barateie o dinamismo dissolve o
argumento — e o princípio (P4) não dissolveu junto. Inverter a ordem transforma um invariante
permanente (Art. I) numa otimização, que é rebaixamento de status constitucional por descuido de
redação. Vale o mesmo para `T?` nativo: o custo do box **autoriza** a escolha; quem a **justifica**
é a doutrina do `?` como modificador.

**How to apply:** ao revisar qualquer spec com seção §8 (Runtime), checar a ordem dos porquês.
Sintoma-padrão: "orçamento de X: aceitável quando barato" — custo baixo **nunca** é licença.
Detectado na review da spec 009 §8.3 (2026-07-15): o texto fazia a recusa de `dynamic` depender do
`unboxing_info.dart`. Ver [[phase5-types-identity-rulings]].

## Adendo (2026-07-15) — a face DUAL: nem pendurado em custo, nem em fato

A mesma regra tem um segundo lado, e eu descobri caindo nele. **Quando a identidade CITA um
mecanismo do backend como evidência, o veredito vira uma afirmação verificável — e um princípio
pendurado num fato FALSO é tão frágil quanto um pendurado em custo.** Unificação: **o princípio não
pode ficar pendurado em nada do backend** — nem em custo, nem em fato. O backend só **reforça** ou
**localiza**.

**Regra operacional — identidade nomeia a AMEAÇA, o backend diz ONDE ela mora.** Formule no nível da
**propriedade** ("nenhum estado que signifique 'não sei' pode existir na side-table"), não do
**mecanismo** ("`undetermined` é bug") — o mapeamento propriedade→mecanismo é do `dart-vm-expert`.
Se eu descer ao mecanismo, ou verifico na fonte, ou não desço.

**Meu modo de falha RECORRENTE (3 ocorrências, mesma forma — descer ao nível de representação):**
1. 2026-07-12 — "o Itá não tem Option, só `T?`/`nil`" → revertido pelo dono no mesmo dia.
2. 2026-07-12 — "desugar sobre `nil`-pattern" → revertido; o canônico é `.some`/`.none`.
3. 2026-07-15 — "`undetermined` é o `UnknownType` disfarçado" → derrubado pelo `dart-vm-expert`
   ([[phase5-types-identity-rulings]] R4). Intuição certa, mecanismo errado.
Nos três a INTUIÇÃO estava certa e a REPRESENTAÇÃO que escolhi estava errada. Ficar na propriedade.
