# Tasks 013: Fase 7 — Codegen → Dart Kernel (`.dill`)

> **Spec:** [`spec.md`](./spec.md) · **Escopo:** pacote **ISOLADO `ita-next/codegen/`** (⚠️ mudou de `compiler/lib/codegen/` — ver §0-A). **Fronteira Grupo A→B:** o Itá emite Kernel (Cap 6); a VM otimiza/roda (Caps 7–12, herdado — ADR-0001).
> **Origem:** auditoria multi-agente de 2026-07-17 — achados **🔴2** (spec cega à higiene de campo do Kernel), **🟠5** (riscos latentes p/ `class`), **🟡4** (contrato F5→F6→F7 por fora), **🟠3** (CA de blindagem). **A F7 COMEÇOU em 2026-07-25** — LT-F7a (saneamento) VERDE no pacote isolado; o resto do plano segue abaixo.
> **Regras:** codegen à mão via `pkg/kernel` vendorado (P9/P11); **sem git durante subagente ativo** (Art. IV-2); comportamento observável = `verifyComponent` + MCP `ita` (VM) + paridade VM×JS. **Nunca chutar a VM** — o `dart-vm-expert` confirma na doc/fonte.

---

## §0-A Arquitetura A — pacote codegen ISOLADO (decisão do dono, 2026-07-25)

⚠️ **O codegen NÃO mora em `compiler/lib/codegen/`.** Ligar o `pkg/kernel` no
`compiler/pubspec.yaml` quebra a suíte: o `kernel` força o `_fe_analyzer_shared 98`
(via `dependency_overrides`), que colide com o `analyzer 14.0.0` que o `package:test`
do compiler puxa transitivamente (`'Diagnostic' imported from both` → `dart test`
exit 65). O oracle `ita/` nunca bateu nisso porque testa com scripts puros, sem
`package:test` — a receita de wiring dele era incompleta para o ita-next.

**Solução (o dono escolheu A entre A/B em 2026-07-25):** o backend é um pacote irmão
**`ita-next/codegen/`** (`name: ita_next_codegen`) que:
- depende de `ita_next_compiler` (path `../compiler`) — a AST, os tipos, as 7 side-tables;
- depende de `kernel` + `_fe_analyzer_shared` (path `../third_party/dart/3.12.2/pkg` + override);
- **NÃO** usa `package:test` (grafo verificado: 0 `analyzer`, 0 `test_core`) — a emissão é
  verificada por **harness próprio** (`main()` + asserts) + golden-runner + MCP `ita`, que
  o §7.7/§11 já previam. Rodar SEMPRE com o dart pinado `.dart-sdk/3.12.2/dart-sdk/bin/dart`.

Os 862 testes do `compiler` ficam intactos (o `compiler` segue SEM kernel). Memória de
projeto: `kernel-vs-package-test-conflict`.

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
- [x] **Gate 2 — pin do SDK** `[✅ 2026-07-20 — commit 72d31da]` — `make pin` (`tools/pin-dart.sh`) materializou o Dart 3.12.2 pinado (`.dart-sdk/`, gitignorado ~586MB) **e o vendor `pkg/kernel`+`_fe_analyzer_shared`** (`third_party/dart/3.12.2/pkg`, **formato 130, versionado** — 8.7MB); `vm_platform.dill` fmt 130; `pub get` autocontido. GREEN/VALIDATE (construção de nó, `verifyComponent`/CA12, golden-runner) **DESTRAVADOS**. Os passos 4-6 do pin (`toml.runtime.dill` = runtime do package manager; `hello.tu`→`.dill` = codegen DESTA fase) seguem gated até a emissão nascer — o guard do `pin-dart.sh` foi corrigido para parar limpo no Gate 2 (proxy: existência de fonte `.dart` em `compiler/lib/codegen/`, hoje só `.gitkeep`).

---

## LT-F7a — Passes de saneamento pós-construção + re-enquadrar §7.1 `[⏳ W1 ✅ 2026-07-19 (§7.1 assentada) · Gate 2 ✅ 2026-07-20 → W0/W2/W3 DESTRAVADOS]`

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
- [ ] **W3 · implement** `[destravado — Gate 2 ✅ 2026-07-20]` — [`speckit-implement`](../../../.claude/skills/speckit-implement/) + os três: revisão adversarial (o `dart-vm-expert` confirma cada invariante contra a fonte 3.12.2).

**Fatiamento (W2):**
- [x] **RED** `[✅ 2026-07-25]` — teste estrutural sobre o dump (⚠️ **bidirecional no `isFinal`** — ressalva W0): "todo `FunctionExpression`/`FunctionDeclaration` tem `id ≥ 1`"; "nenhum offset secundário `== -1`"; "nenhum `Field` **sem** setter com `isFinal=false`" **E** "nenhum `Field` **com** setter com `isFinal=true`" (senão um "seta tudo final" passa vacuamente e mata P2 do `class` com campo `var`). Falha num Component construído cru. → `codegen/test/sanitize_test.dart`.
- [x] **GREEN** `[✅ 2026-07-25]` — os 3 passes em **`codegen/lib/sanitize.dart`** (2 visitors: `OffsetNormalizer` c/ o `isFinal` bidirecional fundido; `LocalFunctionIdAssigner`) + pipeline em **`codegen/lib/finalize.dart`** (`sanitize → computeCanonicalNames → verifyComponent(ItaVerifyTarget, afterModularTransformations, skipPlatform:true) → writeComponentToBytes`) rodado antes do `BinaryPrinter`. `dart analyze` limpo.
- [~] **VALIDATE** `[parcial 2026-07-25]` — `verifyComponent` ACEITA o `.dill` saneado (gate CA12 ✅, `codegen/test/finalize_test.dart`). **Pendente:** MCP `ita` roda compose/curry na VM **e** confere paridade JS — depende da emissão nó-a-nó (§7.4) produzir um `.dill` executável (LT-F7c co-verifica).
- [ ] **QUALITY** — os 862 do `compiler` intactos (pacote isolado) + benchmark de compile-time AOT sem regressão (quando o `itac build` AOT nascer).

**Revisão adversarial W3 `[✅ 2026-07-25 · dart-vm-expert]`:** veredito **SOUND** — os invariantes load-bearing (fileOffset PRIMÁRIO + `isFinal ⟺ setter` bidirecional) casam com `verifier.dart:744-768/checkLocation`; `LocalFunctionId` completo sobre os 3 members (`Member` é sealed = Field/Constructor/Procedure). Cobertura de RED reforçada (2º member p/ o reset; Field através do verify + teste NEGATIVO provando que o pass é load-bearing). **A emissão §7.4 pode começar.** Dois follow-ups **do dono** (não bloqueiam o §7.4, mas latentes):
- ⚠️ **(a) offset SECUNDÁRIO — premissa SOB REVISÃO.** No formato, `-1` secundário é LEGAL (`ast_to_binary.dart` escreve `o+1`, round-trips) e o verifier NÃO o checa; a premissa "bus error" desta spec (§7.1) vive só no `kernel_loader.cc` da VM C++ (fora do vendor) e é CONTRADITA pelo oracle rodar `.dill` com `let`s (cujo `fileEqualsOffset == -1` fica intocado). **Decisão:** fundamentar contra a VM real, **completar** (falta `VariableDeclaration.fileEqualsOffset` + `ForInStatement.bodyOffset`, ambos default -1 — entram no 1º `let` do §7.4), ou **remover** o pass secundário. O comentário do código já foi honestado (não afirma "bus error" sem fonte).
- ⚠️ **(b) paridade de target (latente).** `ItaVerifyTarget extends NoneTarget` desabilita o tearoff-lowering que o `VmTarget` habilita ⟹ o verify fica mais permissivo: `ConstructorTearOff`/`TypedefTearOff`/`RedirectingFactoryTarget` crus passariam o gate e a VM reprovaria. Inerte hoje (sem tearoffs); **fechar ANTES** de o codegen emitir tearoff (lowering no codegen, ou espelhar as flags do `VmTarget`).

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
