---
name: f7-gate-identity-review
description: "Gate de identidade pré-F7 (2026-07-24) — base ITAIANA, zero violação de princípio permanente. Chão-012 e corte-014 confirmados. Achado central: um `⚠️ Ao dono` pode SOBREVIVER à própria resolução e virar mentira-por-obsolescência (collect.dart:89 pede re-ratificação já dada no ADR-0016 §E)."
metadata:
  type: project
---

Gate de identidade que o dono pediu ANTES de começar a F7 (codegen → Dart Kernel). 3 frentes:
guarda dos 11 princípios, inventário de pendências do dono, auditoria de "voz do dono" fabricada.

**Veredito: base ITAIANA e limpa o bastante para a F7. Zero violação de princípio permanente.**
Uma limpeza recomendada ANTES de o dono varrer a lista (senão ele persegue decisão já batida) +
2 pendências que BLOQUEIAM F7 por semântica indefinida.

## Identidade — os dois pontos quentes passam
- **Chão-012** (`.length`/`[]`/`+` = CHÃO; `.map`/`.filter` = biblioteca M5): ITAIANO. Honra P4
  (tabela FECHADA, erra no desconhecido `unknown-member`, migra a `.tu` no M5 — débito registrado,
  não design permanente), P6 (`@intrinsic` descartado, spec §166), P1/P2 (`xs[i]=v` fora de escopo,
  List imutável), P11 (tabela estática do compilador, zero build-time). Norte Art. II: `.map` como
  biblioteca EXIGE `List` ter declaração — a doutrina [[doctrine-extension-declaracao-legivel]].
  Ressalva não-violação: o chão só alcança receptor TIPADO (W3 achado A, 07-20) — `[1,2,3].length`
  dá `cannot-infer` até a fatia C (spec 010). O codegen LT-012b NÃO pode assumir literal-nu compila.
- **Corte-014** ("class sem `_` = a última lacuna honesta"): ITAIANO, honra "diagnóstico nunca
  mente". `match-exhaustiveness-unsupported` é ERRO honesto (não silencia = mentira; não chuta
  `non-exhaustive` = falsa-acusa). `_` fecha qualquer coluna ⟹ só class SEM `_` dispara. Ban de
  Str-interpolada = P4 (pattern que depende de runtime é guard disfarçado). Testemunhas digitáveis,
  nada vaza representação interna.

## O achado central: `⚠️ Ao dono` que sobreviveu à própria resolução
`collect.dart:89-95` grita *"⚠️ Ao dono: o ADR-0012 §B-7 está sobre premissa falsa … precisa de
re-ratificação"*. **Essa re-ratificação JÁ ACONTECEU** — ADR-0016 §E (2026-07-16), razão nova
redigida por derivação e aceita no ato; a fila do ADR-0014 §3 entrada 5 marca `✅ RESOLVIDO`. O
comentário é uma pendência-fantasma: manda o dono re-decidir o que ele já bateu. **Corolário novo
(estende [[doctrine-citacao-ou-nome]]): um diagnóstico-ao-dono é ele próprio uma afirmação que
enferruja.** A cerca "cite o artefato" pega o ruling FABRICADO; não pega o ⚠️ que ficou VERDADEIRO
por um dia e depois virou falso. Ação: trocar o bloco por 1 linha — *"bounds descartados
(`generic-bounds-unsupported`); adiar assoc. types re-ratificado em ADR-0016 §E"*. Preservar o
"por que ERRO e não silêncio" (rationale diagnóstico, ainda válido).

## Pendências do dono — inventário consolidado (para o martelo)
BLOQUEIAM F7 (semântica INDEFINIDA + codegen emite = o "compila mas roda errado" que a reescrita mata):
- **`self` em default de PARÂMETRO** — `specs/014-flow-check/spec.md:264`. F4 resolve, Kernel não tem
  `this` em default. Rotear dart-vm-expert + dono (`self-in-param-default`?).
- **Default de param de CLOSURE** — `spec.md:265` (parser.dart:653/1386). Parseia, F5 ignora mudo, F6
  não desce. Banir vs cobrir = ruling do dono.

NÃO bloqueiam (erro honesto/inércia existe), mas são decisão pendente do dono:
- **`class` como produto no match** (ruling e) — `tasks.md:43` + `match_analysis.dart:262,696`. Sound
  vs reservar p/ match selado de hierarquia. É a "última lacuna honesta".
- **`guard let` retido como nó core** (007 T004) — `tasks.md:14` + `desugar.dart:14,197-201`. Inerte e
  funciona (mesmo blocker do `Try`, RD-1); falta ratificar em spec/ADR (promover de lacuna a decisão).
- **Label obrigatório + o `_` antes** — `type.dart:299-304` ("lacuna do dono; as duas metades são um
  ruling só"). Surface-decision aberta (ver [[rulings-pendentes-do-dono]] do projeto).
- **`dynamic` em list-pattern** (`tasks.md:42`, menor); **nome de diagnóstico do chão** (012
  design-notes.md:73, recomenda "os da spec"); **range Float/Char** (`check.dart:647`, menor).

Nit de doc (não bloqueia): spec 009 diz §12-7 "segue reaberto" (spec.md:25) E "reaberto e
re-decidido no mesmo dia" (spec.md:588). A decisão LANDOU (`let` sem init = PROIBIDO, parser.dart:674
cita §12-7). Inconsistência textual do doc, não pendência.

## Comentários a limpar (voz-do-dono / diário) — pior→menor
1. `collect.dart:89-95` — `⚠️ Ao dono` STALE (acima). Reduzir a ponteiro ADR-0016 §E.
2. `type.dart:277-304` — confissão de ~28 ln da fabricação de 07-15. Retenção DELIBERADA ("é prova,
   não registro", adendo 07-16). Agora que ADR-0016 §A/§C + Art. IV-6 existem e são citados, é
   arqueologia; candidata a graduar p/ ponteiro de 2 linhas. Decisão do dono — não é bug.
3. `check.dart:589` — "ruling do dono 2026-07-19" tem § (spec 014 §12) mas ancora na DATA; preferir
   `tasks.md LT-F6b ruling (a)`. Baixo.
4. Floreio 1ª pessoa/diário: `collect.dart:182` ("bug meu"), `:898` ("eu media"), `:869/:981`
   ("morava aqui"), `check.dart:1060` ("morava aqui"). Derivações ASSINADAS (legítimas), mas dão
   textura de diário. Trim opcional, não bloqueia.

Ver [[doctrine-citacao-ou-nome]] (a cerca), [[spec-014-ltf6b-fatia3-identity-review]] (o ban 3c, hoje
ratificado), [[crivo-5-decisoes-identity-review]] (as fabricações da fila do ADR-0014).
