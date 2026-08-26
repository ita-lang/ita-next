---
name: doctrine-argumento-de-ausencia
description: Doutrina — toda NEGATIVA sobre um espaço de busca ("a linguagem não tem X", "não há teste para X") é conjectura até o espaço ser enumerado; e "impossível" quase sempre quer dizer "impossível sem mexer no que eu já escrevi".
metadata:
  type: project
---

# Doutrina — argumento de AUSÊNCIA exige PROVA de ausência

**Regra:** toda vez que eu justificar uma feature/válvula dizendo *"a linguagem não tem como fazer
X de outro jeito"*, isso é uma **afirmação sobre a superfície** — falsificável por um único grep no
`conformance/`. **Provar antes de vereditar.** Se eu não verifiquei, não afirmo: digo "se a
superfície não cobrir, então…".

**Why:** é o vetor nº1 de over-engineering — o jeito como uma linguagem ganha uma 4ª forma de fazer
o que já fazia de três jeitos, cada uma menos honesta que a anterior. E é a forma **mais frágil** de
argumento que existe: uma linha de conformance o mata. O catálogo não-fazer
([[identity-yield-and-nao-fazer]]) existe para bloquear exatamente isto.

**Caso que gerou (2026-07-15, `let x: T` sem init):** eu argumentei *"RD-1 (blocos não rendem)
torna o uninit-let a válvula que evita cair em `var`, logo serve a P1"*. **Category error:** RD-1 é
sobre **blocos**; `if`/`match` **não são blocos, são expressões** (P3). `conformance/valid/expr_if.tu:1`
— `let m = if a > b => a else b` — mata a premissa. Pior: a linguagem cobre init imutável por
**três** caminhos (if/match-expr; `where { }`; `?`/`guard let`), não zero. Veredito revertido:
A (proibir), ver [[phase5-types-identity-rulings]] R6.

**How to apply:** gatilhos de alerta na minha própria escrita — "não há como", "logo precisa",
"a única forma", "senão cai em". Cada um exige um grep antes de sair.

**Padrão-irmão:** a mesma doença aparece como *"o Itá precisa de X porque linguagem-Y tem X"* —
quando Y tem X para curar uma doença que o Itá não tem. Já matou duas propostas: flow-narrowing
(TS/Kotlin/Dart têm null sem Option) e uninit-let (Swift pré-5.9 não tinha if-expr). **Pergunte
sempre: que doença o X cura, e nós a temos?**

**Relacionada:** [[doctrine-vm-data-reinforces]] — lá o veredito se pendura em fato do *backend*;
aqui, em fato da *superfície*. Mesma fragilidade. **Veredito de identidade não se apoia em fato
não-verificado, venha de onde vier.**

---

## AMPLIAÇÃO (2026-07-29) — a superfície era só o primeiro habitat

O enunciado original prendeu a doutrina a **um** espaço (a superfície da linguagem) quando o
invariante é sobre o **quantificador**, não sobre o espaço. A forma geral:

> **Toda frase minha que abre com uma negativa sobre um espaço de busca — *"não existe programa
> que…"*, *"não existe teste que…"*, *"não há fixture que…"*, *"nenhuma forma de…"* — é
> CONJECTURA, não observação. Vira observação depois que o espaço foi ENUMERADO; e enumerar
> começa por NOMEAR o espaço.**

Nos 3 casos de 2026-07-29 (`ccc8899`..`d159c2f`) o espaço **nunca foi nomeado** — porque nomeá-lo
já responde: (A) *"o espaço é todo `.tu` que a F5 aceita"* → e a F5 aceitava `Caixa { x }` sobre
`Ponto`; (B) *"o espaço é todo teste que possa chamar `checkOrderIndependence`"* → e o acoplamento
da régua ao `emitProgram` era escolha nossa; (C) a guarda anti-vacuidade **era ela própria vacuosa**.

### O motor (vale para os três parentes)
**A impossibilidade declarada congela como DADO o que é ESCOLHA nossa.** "Impossível" quase nunca
é sobre o espaço inteiro — é sobre o espaço *dado o que decidi não tocar*: a metade não consertada
(A), a assinatura congelada da régua (B), o código escrito e nunca exercido (C). Em prosa: 
**"impossível" quase sempre quer dizer "impossível sem mexer no que eu já escrevi".**

É a mesma **transferência de sujeito** dos parentes: um fato sobre o AUTOR (não procurei / não
implementei / não consegui) sai escrito como fato sobre o OBJETO (a linguagem não tem / a linguagem
não quer / o teste não existe) — e o objeto não contradiz.

| forma | soa como | o que esconde |
| :-- | :-- | :-- |
| argumento-de-ausência | **conhecimento** | não fiz o grep |
| restrição-para-caber | **design** | não implementei a fatia |
| **impossibilidade declarada** | **honestidade** | não achei o ângulo |

A terceira é a pior porque as outras duas são contestáveis com evidência do mesmo tipo (um grep
mata a 1ª, a spec mata a 2ª), enquanto a 3ª **encerra a colheita de evidência**: seu conteúdo é
*"aqui não há evidência a colher"*. É auto-selante, e passa em revisão porque veste o dialeto de
virtude da casa ([[doctrine-declaracao-sobrevive-ao-tick-verde]], *lacuna declarada > silêncio*).
**A nossa própria doutrina da lacuna é a camuflagem da desistência.**

### O teste do COMPLEMENTO (aplicar ANTES de escrever a frase)
> **Escreva a frase inteira: "não é possível SEM mexer em ___". Se o branco só se preenche com
> código NOSSO, não é impossibilidade — é uma escolha de não mexer, e precisa de nome, dono e
> catraca.**

Branco preenchido com algo externo (matemática, `pkg/kernel` versionado, contrato da VM) ⟹ limite
real. Cerca de 2ª ordem, para separar lacuna de desistência:
**a lacuna legítima nomeia o TRABALHO que a fecha; a desistência nomeia a DIFICULDADE que a impede**
— e a legítima **custa** alguma coisa (🟡 no ledger, recorte no nome do job, fixture que fica
VERMELHO). Frase que não custa nada é desistência.

**Modelo no repo:** `conformance/codegen/conformer_label.tu:14-21` — declara *"o defeito não é
alcançável"*, **prova** (`collect.dart:1175` + `type.dart:594-602` comparam `label`) e **mesmo
assim deixa o fixture como armadilha**. `codegen/test/ca_ledger.dart` — `lacuna` é campo
OBRIGATÓRIO quando não há evidência e derruba o CA para 🟡.

**Anti-modelo achado na auditoria:** `codegen/lib/emit.dart:1247` (*"return sem valor … a F6 já
reprovou"* — `check.dart:392` só checa `value != null` e `flow.dart:386` faz o `missing-return`
nunca disparar) e `emit.dart:1451` (*"o `let` seria erro"* — `check.dart:496-500` sintetiza `Void`
e liga sem erro). **Garantia-fantasma** é este mesmo animal apontando para o lado: em vez de
"não existe programa que…", é "outra fase já impede que…" — negativa sobre espaço, sem enumerar.
