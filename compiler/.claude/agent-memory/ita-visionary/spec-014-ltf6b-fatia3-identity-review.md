---
name: spec-014-ltf6b-fatia3-identity-review
description: "Review W0 da LT-F6b Fatia 3 (exaustividade de match cobre produto/List/String) — liberado-com-ressalva; substância itaiana (testemunha digitável, ban de Str-interpolada honra P4), mas 🔴 de ATRIBUIÇÃO: código carimba 'ruling do dono 2026-07-19' sem artefato citável (tasks.md:41 do ban segue [ ])."
metadata:
  type: project
---

Review de identidade da **LT-F6b Fatia 3** (exaustividade de `match`: produto struct/record como
Σ de 1 ctor, List por split de comprimento, Str constante + ban da interpolada).
Impl em `compiler/lib/frontend/analysis/match_analysis.dart` (`_print`, `_subPatternsProd`,
`_usefulList`) e `compiler/lib/frontend/semantic/check.dart:609-619` (o ban). Design em
`specs/014-flow-check/blueprint-match-analysis.md` §3.3/§F1.4.

**Veredito: liberado-com-ressalva.** A SUBSTÂNCIA é itaiana e aproxima o ideal "a linguagem te diz
exatamente o que falta": testemunhas CONCRETAS e digitáveis (`Point{x: 1, y: 0}`, `.ok(Point{x: 1,
y: 0})`, `[0]`, `[false]`, `[]`), nenhuma vaza representação interna (o `_print` só emite superfície:
`.name`, `true/false`, número, `[..]`). O ban de Str-interpolada honra P4 (pattern que depende de
runtime é guard disfarçado). §12-11 estreitou HONESTO: produto/List agora DECIDEM (verde ou
testemunha), só `class` (ruling e) e 2-rest (ruling d) restam `unsupported` — nada passou a AFIRMAR
sem verificar (List com gap+2-rest ⟹ `_MatchUnsupported`, não chute). I6 intacto (guard filtrado em
`:47-50` e `:79`, ANTES de qualquer classificação estrutural).

**🔴 ATRIBUIÇÃO FABRICADA (o achado central — estende [[doctrine-citacao-ou-nome]]):** o código
carimba DUAS decisões como "ruling do dono 2026-07-19" SEM artefato citável:
1. **Ban da Str-interpolada** (`_subPatternsProd`/check.dart:609). Mas `tasks.md:41` reserva ao dono
   "banir vs. relaxar" e SEGUE `[ ]` (não resolvido); blueprint §3.3:165 repete "ruling do dono —
   tasks.md"; a memória [[rulings-pendentes-do-dono]] não o registra resolvido; e a task me atribuiu
   como "decisão sua" (visionary). Três atribuições conflitantes, ZERO citação de onde o dono decidiu.
   A DATA não é fonte (regra dura [[nao-escrever-na-voz-do-dono]]). O ban é itaiano em substância, mas
   o carimbo "ruling do dono" precisa citar o dono OU ser re-assinado (design/visionary pendente de
   ratificação) — não vestir a voz do dono numa decisão que o projeto reservou à governança.
2. **Campo omitido = ω** (`Point{x: a}` cobre todo Point). Aqui a substância É fundamentada —
   `spec.md:103` diz "omitidos/`hasRest` → ω" (design de spec). Logo o carimbo "ruling do dono
   2026-07-19" é redundante/impreciso (é design de spec, não ruling datado), severidade menor que (1).

**⚠️ 2 flancos de diagnóstico (diretriz "diagnóstico nunca mente"):**
- **`unsupported` detail STALE** (`match_analysis.dart:69-71`): diz "cobertura de list/produto chega
  na Fatia 3 — adicione `_`", mas list/produto JÁ chegaram; os únicos alcançáveis agora são `class` e
  2-rest. Mesma classe do flanco #1 da Fatia 2 (detail nomeia forma já suportada). Não mente sobre
  SEGURANÇA (é erro honesto), mas misdescreve o PORQUÊ. Corrigir para "class/2-rest".
- **Ban não ENSINA o escape:** `interpolated-string-pattern` sai como código nu, sem `detail`. O
  tasks.md nomeia a relaxação como guard; um `detail` apontando "use um guard `if`" faria a mensagem
  ensinar (P4). Honesto, mas sub-informativo.

**Tensão P4 leve (spec-fundamentada, não bloqueia):** campo omitido = ω sem exigir `..` amacia
"nunca esconde" (a struct TEM `hasRest`; Rust exige `..`). Coerência: se omissão já = ω, por que
`hasRest`? Observação de design, não veto — spec.md:103 sanciona.
