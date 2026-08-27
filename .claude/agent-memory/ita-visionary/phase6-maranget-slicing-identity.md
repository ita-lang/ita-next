---
name: phase6-maranget-slicing-identity
description: W0 da LT-F6b (exaustividade de match via Maranget, spec 014 §4) — o princípio da segurança do fatiamento + rulings das 4 perguntas de identidade.
metadata:
  type: project
---

# Segurança do fatiamento de Maranget (spec 014 §4) — W0 de 2026-07-17

Contexto: a exaustividade de `match` fatia em Fatia 1 (tipos FECHADOS: enum/`Option`/`Result`/`Bool`,
Wildcard/Bind=ω) e Fatias 2-3 (`Int`/`String`/`Float`/`List`/produto). Interim: `match` sobre tipo
ainda-não-modelado. Hoje exaustividade NÃO existe (`itac flow` é comando NOVO; `itac check` intocado) —
Fatia 1 é ganho puro; a régua é NÃO introduzir regressão de falsa-acusação NEM abrir buraco de soundness.

## O princípio (o entregável de identidade)
**O gate certifica só o que VERIFICOU · acusa só o que REFUTOU · confessa o resto — em superfície,
nunca em interno.** É a mesma família da Q3 (guard) e de [[doctrine-argumento-de-ausencia]]: o compilador
só afirma/acusa o que prova. Âncora: **P4 (sem mágica) + a doutrina "lacuna ≠ falsa-acusação"**, via o
idioma constitucional de **lacunas assinadas (Art. IV-6b)**. NÃO é P1 (P1 é imutabilidade — a pergunta
mis-citou; registrar a citação certa importa, Art. IV-6).

## Q1 — segurança do fatiamento: 🛑(a) · 🛑(c) · ✅(b)
DOIS invariantes, não um: (1) não falsa-acusar o código; (2) **não emitir falsa-garantia rio abaixo**
(P4 + **spec 014 §7**: *"F7 emite sem default-branch porque a fase passou"* — "passou"="exaustivo,
verificado").
- **(a) assume-exaustivo** = 🛑. Não falsa-acusa, MAS o carimbo "fase passou" MENTE p/ tipo não-modelado
  → F7 emite branch nu → cai do fim. É o buraco que **013 §0.6** diz ser o motivo da F6 existir: (a) é
  F6 com buraco no formato da própria razão de existir. "F7 não existe ainda" não salva — a segurança de
  (a) fica contingente a "Fatias 2-3 antes da F7", nada prega isso; e `itac flow` já mente no presente.
- **(c) exige ω** = 🛑. Máquina de falsa-acusação: `match s { Point{x,y} => .. }` (struct 1-construtor é
  exaustivo SEM wildcard) acusado por ignorância do compilador → usuário conserta não-bug com `_` que a
  linguagem depois marca redundante. É [[doctrine-porta-fechada]] ao contrário.
- **(b) lacuna declarada, gate-stopper** = ✅. Preserva os dois invariantes; idioma da Art. IV-6b (a 014
  já declara lacunas 6×). "Não sei construir match sobre `List` ainda" (honesto/temporário) > "construo
  mas cai do fim" (desonesto). Cercas: **C1** fraseado confessional (*"exaustividade sobre `List` ainda
  não implementada"*, NUNCA *"match não-exaustivo"*; código sugerido `match-exhaustiveness-unsupported`≠
  `match-not-exhaustive`, a nomear+assentar `compiler-craftsman`); **C2** ω-subsunção (já é Fatia 1:
  "Wildcard/Bind=ω") certifica exaustivo INDEP. do tipo → lacuna só no resíduo SEM ω-row (maioria real
  passa); dobrar a regra 009 §4.7 "infinito sem `_`⟹não-exaustivo" p/ Int/String/Float é alavanca de
  fatiamento do compiler-craftsman, não requisito meu; **C3** gate-stopper (propriedade, não mecanismo —
  warning reabriria (a)).

## Q2 — testemunha honra P4: ✅ com cerca de renderização
P4 MANDA a testemunha (esconder o caso faltante que U já conhece = mágica). ⚠️ **Cerca: a testemunha tem
de ser um pattern DIGITÁVEL em superfície.** Qualquer token interno (construtor sintético, `Ord$Int`,
gensym `$it0`, `Option$none`, índice de Σ) = violação de P4. Fatia 1 limpa por construção: `.variant`
(009 §4.7d), `.some(_)`/`.none` (009 §4.6 — canônico é `.some`/`.none`, NÃO `nil`-pattern), `.ok/.err`,
`true/false`. Cerca é guarda p/ Fatias 2-3 + checklist W3. Unificação c/ Q1: witness não-renderável em
superfície ⟹ é a lacuna (b), não witness mangled.

## Q3 — guard nunca acusado: ✅ (único tratamento são de indecidível)
P4 + doutrina "não punir por indecidível": provar braço-guardado morto exige provar o guard → impossível
→ acusar sem prova = falsa-acusação. Simetria que confirma o desenho (não conveniência): guard é OPACO
nos dois sentidos — não prova que cobre (não conta p/ exaustividade) nem que não roda (não é morto).
Maranget já exclui linhas guardadas: `¬U(P_unguarded, (ω…ω))` (spec §4). Delta vs JLS §14.11.1 é estreito
(Java tbm não deixa case guardado dominar). Nice-to-have: hint "guard não conta p/ exaustividade".

## Q4 — severidade ERRO: ✅ confirmado, régua não reabertura
`unreachable-match-arm`=ERRO → **spec 014 §12-1** (dono, 2026-07-16; assento da severidade em JLS §14.11.1
— Maranget dá algoritmo, não severidade). `match-not-exhaustive`=ERRO → política da **spec 009 §0.5-5 +
§4.7** (a 014 só executa). Coerente c/ [[phase6-flow-identity-rulings]] #1. ⚠️ Flag Art. IV-6c/d: o STRING
`unreachable-match-arm` não está cravado na spec §4 — assentar antes do código citar (senão órfão).

## Sem emenda de dono. Handoff: `compiler-craftsman` decide QUAIS tipos são indecidíveis-na-Fatia-1 e
nomeia/assenta os códigos; MCP `ita` p/ observável quando houver `.dill`.
