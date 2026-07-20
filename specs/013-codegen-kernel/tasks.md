# Tasks 013: Fase 7 — Codegen → Dart Kernel (`.dill`)

> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler/lib/codegen/` (hoje vazio). **Fronteira Grupo A→B:** o Itá emite Kernel (Cap 6); a VM otimiza/roda (Caps 7–12, herdado — ADR-0001).
> **Origem:** auditoria multi-agente de 2026-07-17 — achados **🔴2** (spec cega à higiene de campo do Kernel), **🟠5** (riscos latentes p/ `class`), **🟡4** (contrato F5→F6→F7 por fora), **🟠3** (CA de blindagem). A F7 **ainda não começou** — este arquivo é o plano de entrada, e várias LTs corrigem a **spec** antes de existir código.
> **Regras:** codegen à mão via `pkg/kernel` vendorado (P9/P11); **sem git durante subagente ativo** (Art. IV-2); comportamento observável = `verifyComponent` + MCP `ita` (VM) + paridade VM×JS. **Nunca chutar a VM** — o `dart-vm-expert` confirma na doc/fonte.

---

## Como ler: a pipeline W0 → W3

Cada **linha de trabalho (LT)** atravessa as 4 waves do harness SDD ([mapa](../../.claude/agents/README.md#mapa-de-disparo-na-pipeline-w0--w3)). Na F7 o **`dart-vm-expert` é protagonista do W1** — é a fronteira com o backend permanente.

| Wave | Skill | Especialista(s) | Papel |
|:-:|:--|:--|:--|
| **W0** | [`speckit-specify`](../../../.claude/skills/speckit-specify/) | [`ita-visionary`](../../.claude/agents/ita-visionary.md) | Constitution-check (Art. I/II); o `dart:` fino e enumerado; o box não vaza |
| **W1** | [`speckit-plan`](../../../.claude/skills/speckit-plan/) | [`dart-vm-expert`](../../.claude/agents/dart-vm-expert.md) + [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md) | §8 runtime, invariantes do `.dill`, comportamento por alvo · técnica de emissão (Cap 6→Kernel) |
| **W2** | [`speckit-tasks`](../../../.claude/skills/speckit-tasks/) | — | fatiar RED→GREEN→VALIDATE→QUALITY |
| **W3** | [`speckit-implement`](../../../.claude/skills/speckit-implement/) | os **três** (contexto fresco) | revisão adversarial: identidade · técnica · codegen→Kernel VM/AOT/JS |

---

## LT-F7-gate — Pré-condições da §0.6 (destravar a F7) `[🔴 bloqueia tudo abaixo]`

> A própria spec 013 §0.6 lista os gates. Sem eles, não se escreve codegen.

- [x] **Gate 1 — F6 completa** `[✅ 2026-07-19]` — exaustividade + redundância de `match` implementada (spec 014 LT-F6a/b/c, 853 verdes). A F7 confia na nº8 `flowFacts` (definite-return, para o *throw* defensivo de fim-de-corpo — spec 014 §7) **e** na exaustividade (para emitir `match` sound sem default-branch).
- [ ] **Gate 2 — pin do SDK** `[⏳ ADIADO — decisão do dono 2026-07-19: desenhar antes de baixar]` — `make pin` (`tools/pin-dart.sh`) materializa o Dart 3.12.2 pinado (~200MB) **e o vendor `pkg/kernel`** (`third_party/dart/` **ainda não existe** no `ita-next`). Bloqueia todo GREEN/VALIDATE (construção de nó, `verifyComponent`/CA12, golden-runner). O DESIGN (W1) não depende dele — a fonte 3.12.2 é a mesma tag do pin.

---

## LT-F7a — Passes de saneamento pós-construção + re-enquadrar §7.1 `[⏳ W1 ✅ 2026-07-19 (§7.1 assentada) · W2/W3 pós-pin]`

> **A lição mais cara do projeto, ainda não internalizada na spec.** A §7.1 enquadra a INVARIANTE como *"nenhum transformer do CFE roda"* — mas a causa-raiz do colapso de closure do oracle **não é um transformer**, é **higiene de campo de nó fresco**: `local_function_id=0` colide no `ClosureFunctionsCache` da VM (verificado na fonte 3.12.2: `runtime/vm/closure_functions_cache.cc`; `pkg/kernel/.../statements.dart:2086` deixa `id = LocalFunctionId.invalid == 0`). Nem `verifyComponent` nem o golden pegam. **Corrigir a spec ANTES de codar.**
>
> **✅ W1 FEITO (2026-07-19, `dart-vm-expert` protagonista, design-only).** A **§7.1 foi reescrita e assentada** com as DUAS consequências da INVARIANTE: (A) transformers que não rodam; **(B) os 3 passes de saneamento** (`_LocalFunctionIdAssigner`, `_OffsetNormalizer`, `isFinal ⟸ sem-setter`), cada um fundamentado na fonte 3.12.2 (o `ClosureFunctionsCache` reconfirmado via WebFetch). Também: a **§7.4e** ganhou a TRAVA DURA (os pattern-nodes do Dart 3 são PROIBIDOS na VM — baixa para nós primitivos) + o **gate-012** para `match` sobre `List`. Memórias: `dart-vm-expert/kernel-raw-api-field-hygiene.md` + `match-lowering-kernel.md`. **W2 (RED sobre o dump) + W3 (adversarial) esperam o Gate 2 (pin).**

- [ ] **W0 · specify** — [`speckit-specify`](../../../.claude/skills/speckit-specify/) + [`ita-visionary`](../../.claude/agents/ita-visionary.md): saneamento é P4 (o `.dill` diz a verdade do que a fonte pediu, sem colapso silencioso) — não é mágica escondida, é o contrário dela.
- [x] **W1 · plan** `[✅ 2026-07-19]` — [`speckit-plan`](../../../.claude/skills/speckit-plan/) + [`dart-vm-expert`](../../.claude/agents/dart-vm-expert.md) (**protagonista**) + [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md): **reescreveu a §7.1** para listar, além dos 2 transformers, os **passes de higiene OBRIGATÓRIOS** (fundamentação já em `dart-vm-expert` → memória `kernel-raw-api-field-hygiene.md`; oracle `ita/compiler/lib/codegen/codegen.dart:80-146`):
  - `_LocalFunctionIdAssigner` — `localFunctionId ≥ 1`, reset por `Member` (replica o `LocalFunctionIdGenerator` do CFE);
  - `_OffsetNormalizer` — offsets **secundários** `-1 → 0` (`Class.startFileOffset`/`fileEndOffset`, `Constructor.*`, `Procedure.fileStartOffset`/`fileEndOffset`, `Field.fileEndOffset`, `FunctionNode.fileEndOffset`, `Block.fileEndOffset`) — o `fileOffset` primário já vem da F3, os secundários não (achado 🟠5: bus error cumulativo);
  - `isFinal ⟸ campo sem setter` — todo `Field` sem `setterReference` tem de ter `isFinal=true`, senão Kernel malformado (achado 🟠5; `struct` já protegido, `class` não).
  - Rodados **antes** de `computeCanonicalNames`/`BinaryPrinter`.
- [ ] **W2 · tasks** — [`speckit-tasks`](../../../.claude/skills/speckit-tasks/): fatiar (abaixo).
- [ ] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/) + os três: revisão adversarial (o `dart-vm-expert` confirma cada invariante contra a fonte 3.12.2).

**Fatiamento (W2):**
- [ ] **RED** — teste estrutural sobre o dump: "todo `FunctionExpression`/`FunctionDeclaration` tem `id ≥ 1`"; "nenhum offset secundário `== -1`"; "nenhum `Field` sem setter com `isFinal=false`". Devem falhar num `.dill` construído cru.
- [ ] **GREEN** — implementar os 3 passes em `compiler/lib/codegen/` + wiring antes do `BinaryPrinter`.
- [ ] **VALIDATE** — `verifyComponent` verde + MCP `ita` roda compose/curry na VM **e** confere paridade JS.
- [ ] **QUALITY** — `make test` + benchmark de compile-time AOT sem regressão.

---

## LT-F7c — Blindagem de corpus: CA de 2+ closures no mesmo member `[🟠3 · parte F7]`

> Achado **🟠3**: **nenhum** CA1–CA13 exercita 2+ closures num member (compose/curry). É exatamente o buraco por onde o bug do oracle passaria verde. **É o teste que co-verifica a LT-F7a** — sem os passes de saneamento, ele quebra. (O par — CA de `match` não-exaustivo — vive em [`014/tasks.md` LT-F6c](../014-flow-check/tasks.md).)

- [ ] **W2 · tasks** — [`speckit-tasks`](../../../.claude/skills/speckit-tasks/): adicionar CA permanente `f >> g` (compose) e currying ao golden-runner (VM×JS), registrado na spec 013 §11.
- [ ] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/): confirmar que **falha sem LT-F7a** e passa com ela (co-verificação, não decorativo).

---

## LT-F7b (AF4) — Promover o contrato F5→F6→F7 `[🟡4]`

> Achado **🟡4**: `resolution` (F4) trafega por **parâmetro solto** (`driver.dart` `flowProgram`), não é campo de `CheckResult`. A F7 precisa do mesmo `Ident→binder` (`VariableGet(VariableDeclaration)`). E a **ordem de type-params** (correta no lado F5 — `check.dart:922-923` constrói na ordem `FnDecl.generics`) precisa ser cravada como invariante de emissão. **Promover ANTES de a F7 herdar o repasse solto** — foi a doença que a spec 011 já matou uma vez. Referenciado por [`008/tasks.md`](../008-binding/tasks.md).

- [ ] **W0 · specify** — [`speckit-specify`](../../../.claude/skills/speckit-specify/) + [`ita-visionary`](../../.claude/agents/ita-visionary.md): contrato explícito honra "sem mágica" (a informação flui por campo nomeado, não por argumento fantasma).
- [ ] **W1 · plan** — [`speckit-plan`](../../../.claude/skills/speckit-plan/) + [`compiler-craftsman`](../../.claude/agents/compiler-craftsman.md) + [`dart-vm-expert`](../../.claude/agents/dart-vm-expert.md): promover `resolution` a campo de `CheckResult`/`FlowResult`; **cravar no §7.4a** o invariante "`Procedure.function.typeParameters` segue `FnDecl.generics` na mesma ordem" (senão `Substitution.fromPairs` do verifier desalinha — `dart-vm-expert` confirma em `expressions.dart:2848`).
- [ ] **W2 · tasks** — [`speckit-tasks`](../../../.claude/skills/speckit-tasks/): fatiar (abaixo).
- [ ] **W3 · implement** — [`speckit-implement`](../../../.claude/skills/speckit-implement/) + os três.

**Fatiamento (W2):**
- [ ] **GREEN** — `type_table.dart`/`driver.dart`: `resolution` vira campo de `CheckResult` e `FlowResult`; remover o parâmetro solto de `analyzeFlow`/`flowProgram`.
- [ ] **QUALITY** — `make test` verde; nenhuma regressão nos goldens de check/flow.

---

## Rulings de emissão pendentes (roteados ao dono — NÃO bloqueiam o começo, mas travam sub-áreas)

- [ ] **§12-2** — async × transformer do CFE (spec 013): a lowering de `async` **pode** ser transformer que o Itá bypassa → `.dill` roda errado em silêncio (`ita-visionary` watch-list; `dart-vm-expert` confirma o alvo VM). Fase própria.
- [ ] **§12-9 / §12-10** (spec 014) — `self` em default de **parâmetro** (o Kernel não tem `this` em default) e default de param de **closure** (semântica indefinida). Armadilhas de emissão; `dart-vm-expert` confirma o alvo quando o dono fechar.

---

## Ordem e gate final

1. **LT-F7-gate** (F6 + pin) destrava tudo.
2. **LT-F7a** (saneamento) + **LT-F7c** (CA de closures, co-verifica) + **LT-F7b/AF4** (contrato) — corrigem spec e contrato **antes** do grosso da emissão.
3. Só então a emissão nó-a-nó da §7.4 avança, com a rede montada.

## Notas de execução
- Não mexer no git enquanto um subagente edita o mesmo repo (Art. IV-2).
- Toda saída de programa é validada via MCP `ita`, nunca assumida (Art. IV-1); paridade VM×JS pelo golden-runner quando o codegen muda.
- O oracle `ita/compiler/lib/codegen/codegen.dart` é a referência dos passes de saneamento — **portar a lição, não o estilo** (o oracle monta Kernel à mão com 6140 usos de `k.*`).
