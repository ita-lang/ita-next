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

### Roteado ao dono (W1 + W3) — não bloqueia; NÃO assentar sem ruling
- [ ] **`duplicate-rest` / rest-no-meio** — `[..r, ..s]` e `[a, ..r, b]`: o parser aceita, o modelo F6 exige ≤1 rest. A F5 hoje **não inventa erro nem crasha** (liga todos) — a regra e o *home* (parser vs F5) são ruling do dono.
- [ ] **`interpolated-string-pattern`** — `match s { "a${x}b" => … }` é de-facto **aceito + checado** como literal constante (`_str` devolve `String` incondicionalmente; `check.dart` `_checkLiteralPattern` tem o ⚠️). Ruling "banir vs. relaxar" é do dono (W1 fatia 3). **Armadilha para o F6 lote 2** — a Str-Sig do Maranget assume literal CONSTANTE.
- [ ] **escrutínio `dynamic`** (menor) — comportamento de list-pattern contra `dynamic`, se/quando `dynamic` de superfície existir.

### Débito conhecido-inerte (endereçado, não bloqueia)
- [ ] **Assimetria `_mutableBinder` × `_domainBinder`** — o `_mutableBinder` (`check.dart`) desce nos elementos de list-pattern; o `_domainBinder` (`flow.dart:836`) ainda não. **Inerte hoje** (binder de list-pattern é atribuído no ponto do bind → zero falso `use-before-assign`). Alinhar é da **LT-F6b**. Comentário já corrigido.

---

## LT-F6b — Exaustividade de `match` + redundância de arm (Maranget) `[✅ FATIA 1 CONCLUÍDA 2026-07-17 · Fatias 2-3 pendentes]`

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

### Fatias 2-3 (pendentes — o resto do corte §12-11 destrava aqui)
- [ ] **Fatia 2 — `Int` por `Range` (interval-splitting):** hoje `RangePattern` é `_HStruct` → `unsupported` (conservador). Promover a átomo-de-intervalo dá exaustividade + redundância de ranges sobrepostos (`5 ⊂ 0..=9`). O W3 recomendou a promoção a `_HAtom` já agora (Int infinito → range é gap-preserving); deixei conservador por escopo — **toggle na mesa**.
- [ ] **Fatia 3 — produto (`struct`/record) + `List` (`Len_n`/`Len_{≥k}`):** expansão de campos/comprimentos. Hoje `unsupported`. ⚠️ **Aresta afiada (W3 🟡):** um destructure irrefutável único (`match p { Point{x,y} }` sem `_`) já dá `unsupported` — o detail orienta a adicionar `_`; a cobertura real chega aqui. + redundância de `String` literal (o `_atomKey` é único-por-span hoje).

---

## LT-F6c — Blindagem de corpus: CA de `match` não-exaustivo `[🟠3 · parte F6]`

> Achado **🟠3**: hoje o corpus não exercita `match` não-exaustivo — um `.dill` insound passaria verde. Este CA é a rede que teria pego o buraco no dia 1. (O par — CA de 2+ closures — vive na pipeline da F7: [`013/tasks.md` LT-F7c](../013-codegen-kernel/tasks.md).)

- [ ] **W2 · tasks** — [`speckit-tasks`](../../../.claude/skills/speckit-tasks/): adicionar ao corpus permanente `conformance/flow/match_not_exhaustive.tu` (+ `.facts`/`.errors`) e um caso de arm redundante. Registrado como **CA da spec 014 §11**.
- [ ] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/): confirmar que o CA **falha sem a LT-F6b** e passa com ela (é co-verificação da LT-F6b, não decorativo).

---

## Ordem e gate final

1. **LT-F6a** (tipar patterns) → **LT-F6b** (exaustividade) → **LT-F6c** (blindagem). LT-F6a **bloqueia** LT-F6b.
2. Ao fim, atualizar o placar da F6 no [`README.md`](../../README.md) (F6: parcial → completa) e o [`índice de specs`](../README.md).
3. **Só então** a F7 pode emitir `match` — destravar o gate §0.6-1 da [spec 013](../013-codegen-kernel/spec.md).

## Notas de execução
- Não mexer no git (checkout/branch/commit) enquanto um subagente edita o mesmo repo (Art. IV-2).
- Toda saída de programa é validada via MCP `ita`, nunca assumida (Art. IV-1).
- O oracle `ita/` é referência executável da exaustividade — comparar, não copiar (a versão dele é flat/bugada).
