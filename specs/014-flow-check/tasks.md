# Tasks 014: Fase 6 — Flow-check (lote 2: exaustividade de `match`)

> **Spec:** [`spec.md`](./spec.md) · **Blueprints:** [`blueprint-flow-walk.md`](./blueprint-flow-walk.md) (lote 1, EM MAIN) · match-analysis (lote 2, blueprint 2026-07-17) · **Escopo:** `ita-next/compiler`.
> **Origem:** auditoria multi-agente de 2026-07-17 — achado **🔴1** (exaustividade não existe; gate DURO da F7) e **🟠3** (CA de blindagem). O lote 1 (definite-return, `unreachable-code`, `guard-must-exit`) já está **em main** (`flow.dart`). Este arquivo cobre **o que falta**: o lote 2.
> **Regras:** analisador à mão (P11); AST imutável (side-tables); **sem git durante subagente ativo** (Art. IV-2); comportamento observável = `itac flow` + MCP `ita` (nunca chutar).

---

## Como ler: a pipeline W0 → W3

Cada **linha de trabalho (LT)** atravessa as 4 waves do harness SDD ([mapa](../../.claude/agents/README.md#mapa-de-disparo-na-pipeline-w0--w3)). Cada wave dispara a skill e o(s) especialista(s) certos — **é a rede de segurança**: nenhuma linha vai a GREEN sem o W1 (design fundamentado) e o W0 (constitution-check) fechados.

| Wave | Skill | Especialista(s) | Papel |
|:-:|:--|:--|:--|
| **W0** | [`speckit-specify`](../../../.claude/skills/speckit-specify/) | [`ita-visionary`](../../.claude/agents/ita-visionary.md) | Constitution-check (Art. I/II); violação = conflito aberto |
| **W1** | [`speckit-plan`](../../../.claude/skills/speckit-plan/) | [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md) + [`dart-vm-expert`](../../.claude/agents/dart-vm-expert.md) | técnica+capítulo · §8 runtime/alvo |
| **W2** | [`speckit-tasks`](../../../.claude/skills/speckit-tasks/) | — | fatiar RED→GREEN→VALIDATE→QUALITY |
| **W3** | [`speckit-implement`](../../../.claude/skills/speckit-implement/) | os **três** (contexto fresco) | revisão adversarial do diff |

---

## LT-F6a — Co-requisito na F5: tipar patterns (pré-condição dura) `[✅ CONCLUÍDA 2026-07-17]`

> A matriz de Maranget precisa que **cada coluna tenha tipo**. Hoje `check.dart:544` recusa até `[]` → `CA9` é inalcançável, e não há `pattern-type-mismatch`. **Sem isto, a exaustividade não tem sobre o que operar.** É dívida da F5, não trabalho novo da F6 (achado A1 co-requisito).
>
> **✅ FEITO (2026-07-17).** Dois dedos: **A** (list/rest tipados por `t.args[0]` — Dragon 6.5.1, não a reserva 012) + **B** (literal/range + `nil` tipam a coluna escalar). `check.dart`: `_bindListPattern`, `_checkLiteralPattern`, `_checkRangePattern`, `_mutableBinder`. **801 testes verdes** (+11), `analyze` limpo, `itac check` validado ao vivo (span byte-preciso `@33+3`). W0 ✅ (reserva 012 é `_member`, não type-arg) · W1 ✅ (tese ratificada, 6.5.1 ≠ 6.3.6) · W3 🟢 (adversarial: núcleo aguentou 7 ataques por razões estruturais).

- [x] **W0 · specify** — [`speckit-specify`](../../../.claude/skills/speckit-specify/) + [`ita-visionary`](../../.claude/agents/ita-visionary.md): ✅ liberado sem levar ao dono; 3 cercas exigidas (ErrorType→return; lacuna≠acusação; aninhado nunca vira mismatch) — todas honradas no diff.
- [x] **W1 · plan** — [`speckit-plan`](../../../.claude/skills/speckit-plan/) + [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md): ✅ regra de tipo (elemento por type-arg homogêneo; `..resto` liga `List<E>`; aninhamento por recursão); `pattern-type-mismatch` = forma incompatível, nunca lacuna nossa.
- [x] **W2 · tasks** — [`speckit-tasks`](../../../.claude/skills/speckit-tasks/): ✅ fatiado A→B.
- [x] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/) + `compiler-craftsman` (contexto fresco): 🟢 núcleo sólido; 2 flancos 🟡 aplicados (comentário estale de `flow.dart:836`; débito interp-string registrado).

**Fatiamento (W2):**
- [x] **RED** — `check_test.dart`: grupos "LT-F6a" (dedo A, 6 casos) + "fatia B" (5 casos) — falhavam antes (davam `pattern-binder-unsupported`), passam agora.
- [x] **GREEN** — `check.dart` — recusa removida; `_bindListPattern` + type-check de literal/range; `pattern-type-mismatch` emitido com span.
- [x] **VALIDATE** — `itac check` ao vivo: válido → `exit 0`; list contra `Int` / literal `String` em coluna `List<Int>` → `pattern-type-mismatch` com span.
- [x] **QUALITY** — `make test` **801 verde** + `analyze` limpo.

### Roteado ao dono (W1 + W3) — rulings da Fatia 3 DECIDIDOS em 2026-07-19
- [x] **`duplicate-rest` (2-rest) / rest-no-meio** `[✅ DONO 2026-07-19 — REVISTO p/ opção (a)]` — rest-no-meio (`[a, ..r, b]`) é **LEGAL** (suportado grátis pelo `_HList`/prefixo+sufixo, 3b). **2-rest (`[..a, ..b]`) é MALFORMADO** (divisão indefinida — onde termina `a` e começa `b`? qualquer partição casa), NÃO uma lacuna de análise. **Decisão final (opção (a)): a F5 rejeita com `duplicate-rest-pattern` nas DUAS portas** — `match` E `let`/`var` destructuring — em `check.dart` `_bindListPattern` (Cerca 3). Substitui a decisão inicial ("`unsupported` em match"): o code-review de 2026-07-19 revelou que ela deixava `let [..a, ..b] = xs` passar UNSOUND (destructuring irrefutável não tem F6). O 2-rest agora morre na F5 e não chega à F6; o `_HStruct`/`unsupported` da F6 vira backstop I2.
- [x] **`interpolated-string-pattern`** `[✅ DONO 2026-07-19]` — **BANIR** (a F5 recusa `Str` com `StrInterp` em pattern): um pattern que depende de valor de runtime é guard disfarçado — a PEDRA recusa o que não tem significado estático (P4). Fecha a pré-condição da 3c (toda Str-pattern que passa é constante ⟹ chave de igualdade sound). Implementado em `check.dart` `_checkLiteralPattern`.
- [ ] **escrutínio `dynamic`** (menor) — comportamento de list-pattern contra `dynamic`, se/quando `dynamic` de superfície existir.
- [ ] **`class` como produto** (ruling e, W1 fatia 3) — `struct` é modelado (3a); `class` fica `match-exhaustiveness-unsupported` (conservador). Permitir `class` como produto (sound) vs reservá-lo p/ futuro match selado de hierarquia — **ruling do dono**.

### Débito conhecido-inerte (endereçado, não bloqueia)
- [ ] **Assimetria `_mutableBinder` × `_domainBinder`** — o `_mutableBinder` (`check.dart`) desce nos elementos de list-pattern; o `_domainBinder` (`flow.dart:836`) ainda não. **Inerte hoje** (binder de list-pattern é atribuído no ponto do bind → zero falso `use-before-assign`). Alinhar é da **LT-F6b**. Comentário já corrigido.

---

## LT-F6b — Exaustividade de `match` + redundância de arm (Maranget) `[✅ FATIAS 1-2-3 CONCLUÍDAS · resta 3b-ii redundância-de-List + rulings menores]`

> **O achado central.** `check.dart:1660` delega à F6, mas `flow.dart` **não a faz** — existe só no blueprint. A spec 013 §7.4(e) **confia** na F6 para emitir o `match`; sem ela, o `.dill` "cai do fim" → o "compila mas roda errado" que a reescrita existe para matar. **Nenhuma linha da F7 sobre `match` antes desta LT.**
>
> **✅ FATIA 1 FEITA (2026-07-17).** Algoritmo de Maranget (`U`/`S`/`D` + testemunha) em `compiler/lib/frontend/analysis/match_analysis.dart` (~340 ln), plugado no `flow.dart` `_matchExpr`. Cobre tipos FECHADOS (enum/Option/Result/Bool) + escalar infinito por literal (Int/String/Float — testemunha `_`). **O corte do §12-11 (ruling do dono) embutido nos 3 regimes:** `_` fecha qualquer coluna (verde); escalar decide (`non-exhaustive`); estrutura não-modelada num gap → **`match-exhaustiveness-unsupported`** (a PEDRA: nem mente, nem chuta). **816 testes verdes** (+15), `analyze` limpo, validado ao vivo via `itac flow` (testemunha + span byte-preciso). W0 ✅ · W1 ✅ (design + corte revisado após §12-11) · W3 🟢 (adversarial: 12 vetores, terminação e soundness PROVADAS, zero 🔴).

- [x] **W0 · specify** — [`speckit-specify`](../../../.claude/skills/speckit-specify/) + [`ita-visionary`](../../.claude/agents/ita-visionary.md): ✅ testemunha honra P4 (digitável em superfície, nunca `Ord$Int`); guard nunca acusado; **corte do fatiamento = lacuna declarada (§12-11 do dono), não silêncio**.
- [x] **W1 · plan** — [`speckit-plan`](../../../.claude/skills/speckit-plan/) + [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md): ✅ Maranget 2007 §3.1 (`U`/`S`/`D`), `_Sig` selado, classificação de cabeça 4-vias (`_HWild`/`_HCtor`/`_HAtom`/`_HStruct`); blueprint versionado [`blueprint-match-analysis.md`](./blueprint-match-analysis.md) §F1.
- [x] **W2 · tasks** — fatiado (RED/GREEN/VALIDATE/QUALITY abaixo) + as 3 fatias de tipo.
- [x] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/) + `compiler-craftsman` (fresh): 🟢 sound + terminante; 3 🟡 endereçados (detail na aresta afiada; teste linchpin F5→F6; reconciliação doc×impl do Float).

**Fatiamento (W2):**
- [x] **RED** — `flow_test.dart` grupo "LT-F6b" (15 casos-âncora do blueprint §F1 + linchpin) — falhavam antes (F6 não fazia exaustividade), passam agora.
- [x] **GREEN** — `match_analysis.dart` (`analyzeMatch`/`_useful`/`_specialize`/`_default`/`_sigOf`); `flow.dart` `_matchExpr` chama + pula braços mortos; `FlowError` ganhou `detail`/`isWarning`; `hasErrors` = `any(!isWarning)`.
- [x] **VALIDATE** — `itac flow` ao vivo: exaustivo→`exit 0`; não-exaustivo→testemunha (`.Blue não coberto`); estrutura→`match-exhaustiveness-unsupported` com detail; `_`→verde.
- [x] **QUALITY** — `make test` **816 verde** + `analyze` limpo.

### Fatia 2 — `Int` por `Range` (interval-splitting) `[✅ CONCLUÍDA 2026-07-18]`

> **✅ FEITO (2026-07-18).** O toggle da nota §F1.4 foi **executado** (ruling do dono: testemunha CONCRETA + pipeline SDD completa). `RangePattern` + `IntLit` (coluna `Int`) saíram de `_HStruct`/`_HAtom` para um **intervalo** `[lo,hi]` em `BigInt` (`_Iv`/`_RangeSig`/`_HInt`/`_WInt`, blueprint [§F2](./blueprint-match-analysis.md)). Entrega: (a) **testemunha concreta** de gap (`10` p/ `0..=9`; `.ok(10)` aninhado; furo interior `6` p/ `[0,5]∪[10,15]`), (b) **redundância** por interval-splitting (`5 ⊂ 0..=9`, `3..=6 ⊂ 0..=9`, e por UNIÃO `2..=8 ⊂ 0..=5 ∪ 4..=10`), (c) **range vazio** (`9..=3`, `5..5`) como braço morto por vacuidade — com `detail` que ensina o porquê. **829 testes verdes** (+13), `analyze` limpo, validado ao vivo via `itac flow` (spans byte-precisos, exit 65/0). O gatilho de `match-exhaustiveness-unsupported` **estreitou** para List/produto (Range saiu).

- [x] **W1 · plan** — [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md): ✅ Maranget §3.2 (tipos ordenados) + `IntRange::split`/`SplitConstructorSet` do rustc; **correção-chave:** `Int` = ℤ ilimitado ⟹ a exaustividade **não** splita o domínio (reusa o `D` da Fatia 1, só troca `_WWild`→`_WInt(gap)`); o split fica confinado à redundância.
- [x] **W2 · tasks** — RED: `flow_test.dart` casos F2/A-K (+ regressão da testemunha `_`→concreta em `:580`).
- [x] **W3 · implement** — `match_analysis.dart` (+`_Iv`/`_RangeSig`/`_HInt`/`_WInt`/`_toIv`/`_splitInterval`/`_specializeIv`/`_gapValue`; 2 branches em `_useful`); `flow.dart`/`check.dart` **intactos**. 🟢 adversarial (`compiler-craftsman`, fresh): 6 vetores + flancos, soundness/terminação **provadas**, zero 🔴; 2 🟡 aplicados. W0 (`ita-visionary`): liberado-com-ressalva, 2 flancos aplicados (`detail` stale do `unsupported`; `detail` de vacuidade).

### ⚠️ Roteado ao dono (não bloqueia) — witness ≥ 2⁶³
- [ ] **Testemunha de gap que estoura i64.** `match n: Int { 0..=9223372036854775807 => 1 }` reporta `9223372036854775808 não coberto` (`maxHi+1`). Sob o modelo **`Int` = ℤ ilimitado** é honesto (o valor É descoberto), mas `2⁶³` **não é `Int` representável** (i64) — a testemunha deixa de ser digitável em superfície (fere P4 na borda). W0+W3 concordam: é **ruling do dono** (ex.: cair para `_` quando `gap ≥ 2⁶³`?), corner patológico, não trava a fatia.

### Fatia 3 — produto + List + String `[✅ CONCLUÍDA 2026-07-19]`

> **✅ FEITO (2026-07-19).** Três eixos (blueprint §3.3, decisões do dono acima):
> - **3a produto (`struct`/`record`):** RIDA o motor selado — `_sigOf(struct_)` → `_SealedSig` de **1 ctor** (Maranget §3.1, aridade = nº campos); `_HProd`/`_subPatternsProd` (ordem declarada, **campo omitido → ω**); testemunha concreta `Point{x: 1, y: 0}`. `class` fica `unsupported` (ruling (e)). Composição produto⊃List verde.
> - **3b List:** SEALED-like (o `..resto` torna o rabo alcançável) — split por comprimento à rustc `Slice::split`: `[] + [_, ..]` = **verde real**; testemunha concreta `[0]`/`[]`; `tailArity = max(L+1, maxPre+maxSuf)` (testemunha do rabo honesta, W3 🟡). 2-rest `[..a, ..b]` → `duplicate-rest-pattern` na F5 (ruling (a), malformado). Redundância de List **defere** (3b-ii, abstém).
> - **3c String:** redundância exata de `String` CONSTANTE (`_atomKey` = `s:${value}`); interpolada **banida na F5** (ruling (b)).
>
> **849 testes verdes** (+22: P1-6, L1-9, S1-3, +2 fixes W3), `analyze` limpo, validado ao vivo via `itac flow`/`check`. **W3 (`compiler-craftsman`, fresh):** 🔴→🟢 após aplicar o furo de soundness — **campo duplicado** (`Point{x:0, x:1}`) agora barra na F5 (`duplicate-field-pattern`), senão `_subPatternsProd` resolveria first-wins em silêncio; + testemunha do rabo + `.single` guard. **W0 (`ita-visionary`):** liberado-com-ressalva — testemunhas digitáveis (P4); o **🔴 de atribuição** (carimbo sem artefato) resolvido: os rulings do dono foram registrados acima e os comentários citam a spec/tasks. O gatilho de `match-exhaustiveness-unsupported` ficou **quase morto** (só `class` sem `_`; o 2-rest saiu para a F5).

- [x] **W1 · plan** — `compiler-craftsman`: produto = Maranget §3.1 (1 ctor); List = rustc `Slice::split`/`SplitConstructorSet`; a lista de rulings (a-f). Design na memória `product_list_exhaustiveness.md` + blueprint §3.3.
- [x] **W2 · tasks** — RED: `flow_test.dart` P1-6 (produto), L1-9 (List), S1-3 (String) + 2 fixes W3.
- [x] **W3 · implement** — `match_analysis.dart` (+`_HProd`/`_subPatternsProd`; `_HList`/`_ListSig`/`_usefulList`/`_specializeLen`/`_specializeTail`; `_atomKey` String) + `check.dart` (`duplicate-field-pattern`, ban interpolada). Adversarial 🟢 após 3 fixes (1 🔴 soundness + 2 🟡).

---

## LT-F6c — Blindagem de corpus: CA de `match` não-exaustivo `[✅ CONCLUÍDA 2026-07-19]`

> Achado **🟠3**: o corpus não exercitava `match` não-exaustivo — um `.dill` insound passaria verde. Este CA é a rede que teria pego o buraco no dia 1. (O par — CA de 2+ closures — vive na pipeline da F7: [`013/tasks.md` LT-F7c](../013-codegen-kernel/tasks.md).)
>
> **✅ FEITO (2026-07-19).** `conformance/flow/match_not_exhaustive.tu` no corpus permanente — 8 `fn` cobrindo os **3 diagnósticos × os regimes**: `match-not-exhaustive` (Bool, enum, Int, produto, List), `unreachable-match-arm` (arm dominado), `match-exhaustiveness-unsupported` (`class`, a lacuna honesta), + 1 **verde deliberado no meio** (`green_wild` — falso-positivo quebraria a lista, prova que a PEDRA não falsa-acusa). O runner `flow_test.dart` ("erros == `EXPECT-FLOW`") casa a lista EXATA em ordem-fonte; validado ao vivo via `itac flow`.

- [x] **W2 · tasks** — `conformance/flow/match_not_exhaustive.tu` com `// EXPECT-FLOW` inline (o formato do corpus; sem `.facts` — é fixture de ERRO). CA da spec 014 §11.
- [x] **W3 · implement** — co-verificação: **ANTES da LT-F6b a F6 não fazia exaustividade** ⟹ todas as 8 `fn` passavam verde ⟹ a lista `EXPECT-FLOW` só casa PORQUE a análise existe. O CA falha sem a LT-F6b (estrutural) e passa com ela. **852 testes verdes.**

---

## Ordem e gate final `[✅ F6 COMPLETA 2026-07-19]`

1. ✅ **LT-F6a** (tipar patterns) → ✅ **LT-F6b** (exaustividade, Fatias 1-2-3) → ✅ **LT-F6c** (blindagem). Toda a cadeia fechada.
2. ✅ Placar da F6 no [`README.md`](../../README.md) atualizado (parcial → **completa**, 852 verdes).
3. ✅ **O gate §0.6-1 da [spec 013](../013-codegen-kernel/spec.md) está DESTRAVADO** — a F7 pode emitir `match` (a exaustividade existe e é sound).

**Incompletudes conhecidas-declaradas (não bloqueiam a F7; nenhuma é silêncio):**
- **3b-ii** — redundância de `List` (arm de List dominado): a análise **abstém** (não falsa-acusa; o braço redundante ainda RODA correto). Lint, não soundness.
- **Rulings menores pendentes do dono:** `class` como produto (ruling (e) → `unsupported`); testemunha de gap `Int` ≥ 2⁶³ (P4 na borda); `dynamic`. (2-rest **RESOLVIDO** em 2026-07-19 — `duplicate-rest-pattern` na F5, ruling (a).)

## Notas de execução
- Não mexer no git (checkout/branch/commit) enquanto um subagente edita o mesmo repo (Art. IV-2).
- Toda saída de programa é validada via MCP `ita`, nunca assumida (Art. IV-1).
- O oracle `ita/` é referência executável da exaustividade — comparar, não copiar (a versão dele é flat/bugada).
