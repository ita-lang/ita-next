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

- [x] **W0 · specify** `[✅ 2026-07-26 · ita-visionary]` — contrato explícito honra "sem mágica": a informação flui por campo NOMEADO, não por argumento fantasma. O `CheckResult` já É a disciplina (catálogo de tabelas numeradas c/ docstring, não blob) — promover é completá-lo.
- [x] **W1 · plan** `[✅ 2026-07-26 — debate dos 3 agentes + Dragon §1.2 + Crafting Interpreters §11.4]` — **design assentado (abaixo).** O invariante de ordem de type-params (`Procedure.function.typeParameters` segue `FnDecl.generics`) fica cravado no §7.4a quando a emissão de `fn` nascer — fora do escopo desta fatia, que é só o repasse.
- [ ] **W2 · tasks** — fatiar (abaixo).
- [ ] **W3 · implement** — os três (contexto fresco).

**Design assentado (W1, debate 2026-07-26).** Fundamentos: **Dragon §1.2** — a tabela de símbolos "é passada adiante JUNTO COM a IR para a síntese", CO-EQUAL, "usada por TODAS as fases"; §1.2.8: a IR+símbolos **é a interface** front-end↔back-end (aqui: a fronteira entre os pacotes `compiler` e `codegen`). **Crafting Interpreters §11.4** (Nystrom): side-table por IDENTIDADE, NÃO no nó da AST, com o benefício de ser DESCARTÁVEL.
- **É promoção, não criação.** O `resolution` já é `Map.identity<AstNode, ResolvedName>()` off-to-the-side (`resolver.dart:56`) — o padrão que o Nystrom §11.4 ESCOLHE. Promover = mover a REFERÊNCIA ao contrato; a AST fica intocada, a descartabilidade sobrevive (não construir IDE/incremental — só PRESERVAR, ADR-0004).
- **Campo único na `CheckResult` — ⚠️ SÓ nela, NÃO `FlowResult`.** Correção ao GREEN antigo (os 3 convergiram): dois donos de um fato é cheiro P4. Fonte única carregada adiante; o `analyzeFlow` LÊ `check.resolution` e dropa o param; a F7 alcança tudo pelo record `(check, flow)` que `flowProgram` já retorna (a interface do §1.2.8, nomeável `typedef Analysis`).
- **On-node VETADO** (os 3): guardar a resolução — ou depois a `VariableDeclaration` — num campo do nó viola a descartabilidade do Nystrom (re-emissão watch/LSP apontaria decl de run morta).
- **Docstring no padrão nº1–nº7** (guarda do `ita-visionary`): consumidor NOMEADO (F6 do DA + F7 do `VariableGet`) + prova de NÃO-derivabilidade (resolução de escopo não é recomputável sem re-rodar a F4) + proveniência F4. Senão a promoção vira cerimônia.
- **Chave `Map.identity`** (`compiler-craftsman`): com `==` estrutural, homônimos colidem; a identidade mantém o binding correto.
- **A 2ª side-table (`binder → VariableDeclaration`-Kernel) é da EMISSÃO (§7.4), não desta fatia** — `Map.identity` campo de instância do visitor de codegen, populado na baixa da decl, chave `(binder, fieldName)` no destructuring (débito D4 ressurge). Registrado p/ quando o §7.4 emitir `let`/`VariableGet`.

**Fatiamento (W2):**
- [x] **GREEN** `[✅ 2026-07-26 · compiler-craftsman]` — `resolution` promovida a campo de `CheckResult` (`type_table.dart`: import `ResolvedName` de `binding/scope.dart` + docstring no padrão); `checkTypes` (que JÁ recebia a resolution) a passa ao `CheckResult` (mesma ref `Map.identity`); `analyzeFlow` (`flow.dart`) dropou o param e lê `check.resolution`; `flowProgram` (`driver.dart:377`) chama `analyzeFlow(check)`. **Rotulada "a tabela de símbolos da F4, PROMOVIDA"** — NÃO "nº8" (ocupado por `FlowResult.completesNormally`, `flow.dart:96`): as nº1–nº7 são "a F5 produz", esta é a F4 CARREGADA (promoção, não criação). Único caller real era o driver (o `flow_test` entra por `flowProgram`).
- [x] **QUALITY** `[✅ 2026-07-26 · fiscalizado por main]` — `dart test` (compiler) **862 verde**; `analyze` limpo; nada on-node (AST intocada); zero regressão nos goldens de check/flow. Resíduo menor: `agent-memory/compiler-craftsman/f6_flow_check.md:74` cita a assinatura antiga de `analyzeFlow` — doc stale, não código.

---

## LT-F7d — Golden-runner do emitter `[✅ 2026-07-28 · rede de segurança da §7.4]`

> **Buraco que fechou:** o `emit.dart` cresceu por 3 fatias (§7.4-a/b/c) SEM teste automatizado — `sanitize`/`finalize` cobrem higiene e boa-formação (o verify aceita), nunca **o que o programa imprime**. A classe inteira de bug "`.dill` válido, saída errada" passava. Cada fatia foi fiscalizada à mão, e fiscalização manual não sobrevive à fatia seguinte.
>
> ⚠️ **Sem W0/W1** — não houve design novo a assentar: a §7.7 já especifica o golden-runner ("roda o corpus e compara **stdout + exit code**") e a §11 já manda o corpus virar `conformance/codegen/`. Esta fatia é a execução do que a spec pede, não uma decisão.

- [x] **GREEN** — `codegen/test/golden_test.dart` (harness próprio, sem `package:test`) + corpus `conformance/codegen/` (11 fixtures) + alvos `make codegen-golden[-update]`, encadeado no `make codegen-test`.
- [x] **Uma fonte de verdade** — o `_compileToDill` do `bin/itac.dart` foi PROMOVIDO a `lib/compile.dart` (`compileToDill`, devolvendo `diagnostics` em vez de escrever em stderr). O corpus exercita o MESMO caminho do `itac build`; uma réplica divergiria em silêncio na 1ª fatia nova (P4). O `itac` só imprime.
- [x] **VALIDATE — o runner é LOAD-BEARING** (mesma disciplina do teste negativo do `finalize_test`): mutação `div → '/'` em vez de `'~/'` no `emit.dart` ⟹ `arith_int.tu` acusa `div=3.5` vs golden `div=3`. O `.dill` mutante continua passando no `verifyComponent` — só a EXECUÇÃO pega. Mutação revertida (`git diff` limpo).
- [x] **QUALITY** — `codegen-analyze` limpo; `sanitize`/`finalize` intactos; `compiler` **871 verde** (nada tocado lá); 11 fixtures em ~2,4 s (o `vm_platform.dill` de 8 MB é lido 1× e desserializado FRESCO por fixture — o `finalizeProgram` muta o platform).

**Corpus (`conformance/codegen/`) — 8 verdes + 3 de fronteira.** Verdes: `hello`, `ca1_interp` (**o CA1 da §11, literal**), `arith_int` (a linha `div` trava a armadilha do `double`), `let_var`, `if_expr`, `compare`, `equality` (os 3 `interfaceTarget` distintos: `num::==`, `String::==`, `Object::==`), `logical`.

**Fronteira honesta — `// EXPECT-ICE:` é FILA DE TRABALHO EXECUTÁVEL.** Um fixture declara o `ice-codegen-*` que a emissão devolve hoje; quando a fatia nascer, ele **para de dar ICE e o runner FALHA**, cobrando a promoção a CA verde. Os três atuais mapeiam as próximas fatias da §7.4:
- `ice_user_fn.tu` → `ice-codegen-toplevel-FnDecl` (`fn` do usuário + `StaticInvocation`, nº5);
- `ice_var_assign.tu` → `ice-codegen-expr-Assign` (`VariableSet`; o ICE sai como **`expr-`**, não `stmt-`, porque atribuição no Itá é EXPRESSÃO — P3);
- `ice_cmp_on_string.tu` → `ice-codegen-cmp-on-StringType` (`"a" < "b"` passa a F5 e não existe no Kernel).

**Débito declarado:** o runner roda **só a VM (JIT)**. A §7.7 pede os 3 alvos; AOT (`dart compile exe`) e JS (`dart2js`) são fatias futuras — e o cabeçalho do relatório **declara o alvo** em vez de deixar supor que rodou os três. Também não cobre inspeção estrutural do `.dill` (CA10/CA11/CA13 — ver fila abaixo).

### LT-F7d.2 — o job de CI + a revisão dos 4 especialistas `[✅ 2026-07-28]`

> **A premissa do débito #1 estava ERRADA.** Eu havia registrado que o CI precisaria materializar o SDK pinado (~200 MB). Não precisa de nada: o `setup-dart` já instala o binário **e** o `vm_platform.dill` da mesma versão, e o vendor `third_party/dart/3.12.2/pkg` (8,7 MB) é VERSIONADO. Custo extra de download: **zero**.

- [x] **CI** — job `golden-runner (F7 → Kernel; VM/JIT — AOT e JS pendentes)`. A versão sai do `dart-sdk.pin` (uma fonte de verdade); os alvos rodam com `DART_CG=dart`. **O nome do job carrega o recorte de alvo** por exigência do `ita-visionary`: a declaração vive no docstring, no stdout e aqui — e nada disso é lido numa PR, onde se lê o nome e o ✅. *Declaração que não sobrevive à redução a um tick verde é mentira por omissão.*
- [x] **Makefile parametrizado** — `DART_CG ?= $(CURDIR)/…` **absoluto** (o `../` estava nas 7 receitas, não na variável: um override com path absoluto viraria `..//opt/…`), guarda de variável definida-porém-vazia, e alvo `codegen-guard` que diz *o que fazer* em vez de estourar `exit 127`.
- [x] **P9 — o `python3` saiu do `pin-dart.sh`** (`kver()` → `od -tu1` + `awk`, POSIX; o `--endian` do GNU od não roda em BSD). Ruling do `ita-visionary`: **é violação, não dívida tolerada** — a §7.2 já parte o Art. I em dois domínios (P8 = deps do `.tu` do usuário; **P9/P10/P11 = deps do compilador**), e este script é o Gate 2 da §0.6. Agravante: o `2>/dev/null` fazia a AUSÊNCIA de Python se disfarçar de bump de formato — diagnóstico que mente sobre a causa. (O `kver` também era chamado sobre `tag.dart`, um arquivo `.dart` — leitura sem sentido; virou `grep`.)
- [x] **Asserção do pin nas TRÊS pontas**, dentro do runner: `dart` (`Platform.version`) ↔ `vm_platform.dill` (bytes 4..7 big-endian) ↔ `pkg/kernel` vendorado (`Tag.BinaryFormatVersion`). **Por que é load-bearing:** o `.dill` que emitimos sai com **SDK hash NULO** (`tag.dart:264-273` cai no default `'0000000000'`, e `isValidSdkHash` passa se qualquer lado for nulo) ⟹ a única checagem que detectaria SDK errado **está desligada**; só o FORMATO é conferido pela VM, e um bump de PATCH com o mesmo formato passaria em silêncio. Formato **nunca hardcodado** — o `main` do SDK já está em **138**.
- [x] **Falso verde MATADO** (achado 🔴 do `compiler-craftsman`): o runner **auto-criava** golden ausente e passava. No CI o arquivo morreria com o workspace e o job reportaria verde sobre saída que ninguém leu. Agora `--update` é o único caminho que escreve; `.out` ausente FALHA; `.out` órfão num fixture `EXPECT-ICE` também.
- [x] **`EXPECT-ICE` endurecido** — igualdade por regex sobre o formato fixo do `CodegenIce` (o `contains` deixava um `EXPECT-ICE: ice-codegen` truncado casar com tudo); diretiva desconhecida/duplicada FALHA (um `EXPECT-EXITT:` caía no default 0 em silêncio — o harness aplicando a si mesmo o oposto de "diagnóstico nunca mente").
- [x] **Timeout de 15 s por fixture** (`Process.start` + kill) — quando a §7.4-e trouxer `while`/`for`, um lowering errado penduraria o job até o timeout do runner; "travou" tem de ser falha NOMEADA.
- [x] **Rodapé honesto** — `N verdes · M fronteiras declaradas`, nunca "TODOS VERDES": um fixture de fronteira contribui um ✓ e não prova emissão nenhuma.
- [x] **VALIDATE por mutação** (4 guardas, cada uma provada): golden ausente ⟹ falha; diretiva com typo ⟹ falha; `EXPECT-ICE` truncado ⟹ falha; `DART_CG=dart` com o 3.12.1 do sistema ⟹ **a asserção do pin acusa** (passa em formato 130, falha em versão — exatamente o cenário que o SDK-hash nulo deixava passar).

### LT-F7e — `fn` do usuário + os dois 🟠 + a camada intensional `[✅ 2026-07-28]`

- [x] **🟠 `Float` NASCE** — os ramos `FloatType` de `_resolveCmpOps`/`_resolveEqualsOps` eram inalcançáveis (sem `FloatType` em `_resolveCoreTypes`, sem caso de `ast.FloatLit`). A F5 já o tipa e a §7.4-f já manda `DoubleLiteral` ⟹ nasce. **E isso destapou a armadilha gêmea:** a tabela da F5 admite `div` como `(Int,Int)→Int` **e** `(Float,Float)→Float`, mas `~/` devolve `int` e `/` devolve `double` — com o mapa fixo, `7.0 / 2.0` renderia **3**. Agora `div` despacha por TIPO (`_arithTarget`). `arith_float.tu` é a gêmea de `arith_int.tu`: cada operador é o errado para o outro tipo.
- [x] **🟠 `missing-main` deixou de ser ICE** — o comentário do `emit.dart` citava um driver §12-5 que **não existia**. `checkMain(CheckResult)` entrou em `compile.dart` (entre o gate F6 e a emissão, onde o ruling o pôs), com prefixo `build-error:` — a fase que reprovou é o DRIVER. CAs NEGATIVOS `err_missing_main.tu` / `err_main_arity.tu` + diretiva `EXPECT-BUILD-ERROR:`. Os ICEs do `emitTopLevel` viram o que a §7.8 diz que são: inalcançáveis por programa de usuário.
- [x] **Camada INTENSIONAL** (`codegen/lib/invariants.dart`) — zero `dynamic` (ADR-0013) nos sítios onde emitimos tipo, alvos LIGADOS em `Instance`/`StaticInvocation`, e **CA11** (o `.dill` só com as libs do programa). Provada load-bearing por mutação, e o resultado é a tese em duas linhas: `✗ invariante violado — dynamic em VariableDeclaration` **junto de** `✓ stdout == let_var.out`. O `.dill` mutante também passa no `verifyComponent`. Escolha declarada: invariantes (baixo churn, valem para todo fixture futuro), NÃO golden textual — o dump (CA13) é fatia própria, e quando vier tem de usar `Printer(syntheticNames: NameSystem())` por fixture.
- [x] **`fn` do usuário (§7.4-a)** — `Procedure` static + `StaticInvocation`, em **DOIS PASSOS** (assinaturas → corpos). Não é estilo: é o letrec de módulo. Passo único quebraria **recursão** e **forward-reference**, e o `targetReference` é non-nullable (não há "preencher depois"). Params baixam **named required** (§12-3, ruling do dono), com o **label** como nome Kernel — o corpo referencia por OBJETO via `_kernelDecls`, nunca por nome. Args montados pelo `slot` da nº5. `ReturnStmt` entrou; `=> expr` vira `return` em fn com valor e `ExpressionStatement` em Void.
- [x] **A CATRACA FECHOU O CICLO** — o `ice_user_fn.tu` ficou vermelho sozinho (*"esperava ice-…, mas COMPILOU — promova a fixture a CA verde"*) e virou `fn_call.tu`. É a primeira prova de que o `EXPECT-ICE` não é decoração: a fila da §7.4 se esvazia sozinha. Mais `fn_recursao.tu` (recursão + label na chamada recursiva).
- [x] **QUALITY** — `analyze` limpo; **11 verdes · 2 negativos · 2 fronteiras**; `compiler` 871 verde.

### LT-F7f — `VariableSet` + `struct` `[✅ 2026-07-28]`

- [x] **`VariableSet` — `var` finalmente MUTA** (a outra metade do P1). A imutabilidade NÃO é re-checada aqui: a F5 cobra `assign-to-immutable` e o `isFinal=true` do `VariableDeclaration` faria o verifier reprovar. Compostos (`+= -= *= /=`) baixam expandidos; o `/=` obrigou a extrair a regra do `div` para UMA fonte (`_arithOpFor`) — a armadilha `~/`×`/` não pode ser fechada numa forma e reaberta na outra. **A catraca cobrou pela 2ª vez** (`ice_var_assign` → `var_assign`).
- [x] **`struct` (§7.4-c)** — `Class` com campos **todos `final`** (ruling §12-1) + `Constructor` memberwise named (`EmptyStatement` + `FieldInitializer`, a forma que o Kernel exige para campo final); `P(x:1)` → `ConstructorInvocation`; `p.x` → `InstanceGet`. Tipos registrados no passo **1a**, ANTES das assinaturas de `fn` — forward-reference vale para tipos também (`fn faz() -> Caixa` com `Caixa` declarada abaixo). `NamedType` entrou no `_emitType` (carrega a decl, nenhuma chave fixa o alcançaria).
- [x] 🔴 **OS INVARIANTES PEGARAM UM BUG DESTA MESMA FATIA, na 1ª execução:** `ADR-0013: dynamic em returnType` — o `FunctionNode` do `Constructor` usa `DynamicType` por DEFAULT. Os 8 goldens estavam **todos corretos** e o `.dill` violava o ADR-0013. ⚠️ **O oracle tem o mesmo bug** (`ita/…/codegen.dart:948` também omite o `returnType`) — é o caso literal de "portar a LIÇÃO, não o estilo" da §11.
- [x] **QUALITY** — analyze limpo; **14 verdes · 2 negativos · 1 fronteira**; compiler 871. P2 verificado: `origem` não muda quando `desloca` devolve outro `Ponto`; `var` em struct e `s.n = 2` seguem barrados pela F5.

### LT-F7g — `Option`/`T?` → nullable nativo `[✅ 2026-07-28]`

- [x] **`OptionalType` → nullable NATIVO** (`withDeclaredNullability`), **`nil` → `NullLiteral`**. Não há classe `Option` no `.dill`: o opcional é a MESMA `DartType` do interno. É herança, não implementação — a Dart VM já tem nulidade no sistema de tipos, então usá-la traz o Grupo B de graça (unboxing, null-check elidido pela TFA). Travessias verificadas: `let`, param, retorno, campo de `struct`.
- [x] **Invariante de CUSTO ZERO** (`checkNoSyntheticClasses`) — a metade estrutural do **CA10**: toda `Class` no `.dill` corresponde a uma decl do usuário. Provado load-bearing: um wrapper `Option` sintetizado é pego com **stdout idêntico**. Também vigia o box do ADR-0017 §3 na fronteira `any`.
- [x] **QUALITY** — analyze limpo; **15 verdes · 2 negativos · 2 fronteiras**; compiler 871.

**Escopo que NÃO cabia (verificado, não suposto):** `??`, `?.` e `!` **desugaram para `match`** (confirmado no `itac desugar --dump`: `a ?? 0` vira `match a { .some($x0) => $x0, .none => 0 }`) ⟹ dependem da fatia de `match`. A outra metade do CA10 (o `match` imprimindo o braço `.none`) idem.

⚠️ **RULING PENDENTE DO DONO — `${opcional}` imprime `null`, a palavra do DART.** O usuário escreve `nil` e vê `null`: é o `toString()` da VM (Grupo B) vazando na superfície do Itá. O golden `option_nullable.out` registra o comportamento de HOJE, não o desejado. É decisão de LINGUAGEM (o que a interpolação de um opcional vazio deve mostrar), não de emissão — roteado ao dono. Ligado ao P4 ("sem mágica") e ao destino `.tu`/trait `Show` do §12-4.

⚠️ **Achado da F5, não da F7:** `x == nil` dá `cannot-infer` — `nil` é forma checking-only e `==` não fornece contexto. Pode ser intencional (o idioma é `match`), mas vale confirmar.

### LT-F7h — `match` sobre `Option`/`T?` (§7.4-e, 1ª família) `[✅ 2026-07-28]`

- [x] **TRAVA DURA respeitada** — zero pattern-nodes do Dart 3 (`IfCaseStatement`/`PatternSwitchStatement`/`PatternVariableDeclaration` são CFE-internos, `UNREACHABLE()` na VM). Só `EqualsNull` · `Not` · `ConditionalExpression` · `Let`.
- [x] **RD-1 decide a forma** — `MatchExpr` é EXPRESSÃO ⟹ **right-fold de `ConditionalExpression`**. O ÚLTIMO braço vira o `otherwise` SEM teste: sound porque **a F6 já provou exaustividade** (a §7.4-e manda a F7 confiar). Sem isso sobraria um `throw` de fim-de-cadeia.
- [x] **Subject avaliado UMA vez** (`Let` antes do fold) — verificado com efeito colateral observável no fixture (`[efeito] avaliei o subject UMA vez`). Sem o `Let`, `match f() {…}` chamaria `f()` por teste de braço, e **nenhum golden de valor puro perceberia**.
- [x] **O bind exige `as`** — `x: T` é non-nullable (ADR-0013) e o subject é `T?`; o Kernel cru **não tem flow-promotion**, então o que o Dart faria por análise aqui é nó explícito.
- [x] 🎁 **`??` e `if let` passaram a compilar SEM UMA LINHA de emissão própria** — a F3 já os reduz a `match` sobre `Option` (`a ?? 0` → `match a { .some($x0) => $x0, .none => 0 }`). É a arquitetura pagando dividendo: o desugaring reduz a superfície, e uma fatia de núcleo destrava vários operadores. Fixture `coalesce_iflet.tu` trava a redução.
- [x] **`-x` e `!b`** — a linguagem não tinha unário (descoberto porque um `else -1` no fixture deu ICE). ⚠️ `unary-` é nome DEDICADO no Kernel (`names.dart:55`), e o único aritmético que `int` sobrescreve em vez de herdar — resolvê-lo pela tabela dos binários daria o alvo errado.
- [x] **QUALITY** — analyze limpo; **17 verdes · 3 negativos · 3 fronteiras**; compiler 876.

**O que NÃO destravou, e por quê:** o **`!`** (force unwrap) desugara para um `match` cujo braço `.none` chama **`panic`** — e `panic` → `Throw` é o **CA9**, ainda sem gabarito. Fixture `ice_force_unwrap.tu`. Sinal útil: `??` precisava só de `match`; `!` precisa de `match` **e** de `panic`.

⚠️ **Achado da F5 (não da F7):** `u?.nome` dá `cannot-infer` **mesmo com anotação** (`let n: String? = u?.nome`). O desugar de `?.` produz um `match` cujo braço `.none` rende **`.none`** (nó `EnumVariant`), forma checking-only que não recebe contexto ali. Logo `?.` **não chega à F7** hoje. Roteado ao dono — é da F5/desugaring.

### LT-F7j — `match` escalar + range (§7.4-e, 2ª e 3ª famílias) `[✅ 2026-07-28]`

- [x] **Literal** → `EqualsCall(subject, literal)`, `interfaceTarget` pelo TIPO do subject. Os três alvos distintos estão no corpus: `Int`/`Float`→`num::==`, `String`→`String::==`, `Bool`→`Object::==` — nenhum herdado do outro, e um walk ingênuo de superclasse erraria.
- [x] **Range** → `subject >= lo && subject <(=) hi` (dois `InstanceInvocation` de `num` sob `LogicalExpression`). Nós primitivos, TRAVA DURA respeitada. Endpoints são literais por construção (parser), então não há expressão avaliada duas vezes.
- [x] **VALIDATE por mutação — o off-by-one é pego.** Trocar `lt` por `le` no range exclusivo muda **uma única linha** (`10=pequeno` em vez de `10=medio`): o `.dill` segue válido, os tipos idênticos, o verifier aprova. Só a borda denuncia. É o caso mais puro de "roda liso e está errado" desta spec.
- [x] **QUALITY** — analyze limpo; **21 verdes · 3 negativos · 2 fronteiras**; compiler 882.

⚠️ O `_` final não é decoração: a spec 014 §F2 é explícita — ranges **nunca** fecham `Int` sem ω, então a F6 exige o catch-all. É ele que vira o `otherwise` do right-fold, sem teste.

### LT-F7k — `enum` SEM payload (§7.4-c/e) `[✅ 2026-07-28]`

- [x] **`enum` sem payload → `Class` com uma constante por variante.** Cada variante é um `static final` inicializado pelo construtor da própria classe ⟹ **objeto único**, e é isso que faz o `match` funcionar com `Object::==` puro — sem tag, sem índice, sem `IsExpression`. `.variante` como valor → `StaticGet`.
- [x] **`==` entre valores de enum** → identidade (`Object::==`). ⚠️ **`struct` NÃO entra**: struct é VALOR (P2), logo `p1 == p2` tem de ser igualdade ESTRUTURAL — identidade faria duas cópias iguais compararem `false`, exatamente a semântica de referência que o `struct` existe para negar. `==` estrutural sintetizado é fatia própria (§8.2 já a prevê); até lá, ICE.
- [x] **O invariante pegou a si mesmo** — na 1ª execução ele acusou `Cor`/`Estado` como "wrapper sintetizado", porque a lista de tipos declarados do runner só coletava `struct`/`class`. A régua **erra no desconhecido** por desenho, então cada forma nova de decl tem de entrar nela. Corrigido, com o comentário registrando o porquê.
- [x] **QUALITY** — analyze limpo; **22 verdes · 3 negativos · 3 fronteiras**; compiler 882.

### LT-F7l — `Result` + `?` (**CA8 FECHADO**) `[✅ 2026-07-28]`

- [x] **F5: construir `.ok(v)`/`.err(e)`** — `Result` é `BuiltinType` (não tem `TypeInfo` nem `EnumDecl`), então a assinatura das duas variantes sai do próprio tipo (`Σ(Result) = {ok, err}`), payload POSICIONAL. Sem isso, o `match` sobre `Result` já funcionava mas **nada podia criá-lo** — o P7 não tinha produtor.
- [x] **F7: runtime `ItaResult` selado** + `ItaResult$ok`/`ItaResult$err`. ⚠️ **A assimetria com `Option` é principiada**: `Option<T>` ≡ `T?` tem equivalente NATIVO (nulidade) ⟹ custo zero; `Result` carrega payload nos DOIS lados e nenhum tipo do Kernel representa "ou T ou E" sem perder um. Classe é o preço mínimo, não conveniência.
- [x] **O `?` → `BlockExpression`** — o ÚNICO gabarito com fluxo NÃO-LOCAL. O `return` está dentro de uma EXPRESSÃO (`let x = f()?`), e `ReturnStatement` é statement: `BlockExpression(Block([...]), value)` é o que o Kernel oferece, e **está no `binary.md`** (parte do formato, não CFE-interno como os pattern-nodes). Verificado na VM real.
- [x] **Prova do early-return**: `cadeia(40, 0)` — o PRIMEIRO `?` corta e o segundo `divide` nunca roda. Um gabarito que só devolvesse `.err` sem cortar daria o mesmo resultado neste caso, mas não no encadeado — por isso o fixture tem dois `?` em sequência.
- [x] **Payload `Object`, não `dynamic`** — `ItaResult` é não-genérico (∀ ainda é ICE) e `dynamic` violaria o ADR-0013; o invariante o pegaria. `Object` perde precisão sem perder soundness, e o `as` do destructuring devolve o tipo que a F5 provou.
- [x] **QUALITY** — analyze limpo; **24 verdes · 3 negativos · 2 fronteiras**; compiler 890.

### LT-F7m — `match` sobre PRODUTO (`struct` em pattern) `[✅ 2026-07-29]`

- [x] **O produto NÃO testa classe** — diferente do enum selado, o subject já É do tipo; não há variante a discriminar. O pattern TESTA os campos que trazem sub-pattern com teste (literal → `EqualsCall`, range → `>=`/`<(=)`) e LIGA os que trazem binder (`InstanceGet` direto). A conjunção dos testes é o teste do braço; um pattern só-de-binds casa SEMPRE.
- [x] **Sem `as` em lugar nenhum** — não há estreitamento, logo não há o que promover. É o contraste exato com o enum selado, onde o `as` é obrigatório.
- [x] 🔴 **O gate CA12 pegou um bug meu ANTES de qualquer execução:** eu reusava a MESMA instância de `InstanceGet` nas duas pontas de um range, montando árvore com dois pais para o mesmo filho. O `verifyComponent` reprovou com *"Incorrect parent pointer"*. No Kernel todo nó tem UM pai — agora cada leitura de campo é um nó novo. É a primeira vez nesta spec que o verify (e não a execução, nem os invariantes) foi quem pegou.
- [x] **A borda do range em CAMPO** — `idade: 0..18` exclui 18, que cai em `18..=64`. Mesma armadilha do `match_escalar.tu`, agora sobre `subject.campo`; os dois fixtures a fecham nos dois contextos.
- [x] **QUALITY** — analyze limpo; **25 verdes · 3 negativos · 2 fronteiras**; compiler 890.

## 📋 Placar dos CAs da §11 — auditado em 2026-07-29

| CA | estado | onde |
| :-- | :-- | :-- |
| CA1 interpolação + aritmética | ✅ | `ca1_interp.tu` |
| CA2 default saltável | ✅ | `default_saltavel.tu` |
| CA3 `class` + `init` explícito | ❌ | `class` é ICE |
| CA4 dispatch existencial (`any`) | ❌ | ADR-0017, §7.4-d |
| CA5 default method | ❌ | idem |
| CA6 membro de `impl`/`extension` | ❌ | idem |
| CA7 `match` enum-com-payload | ✅ | `enum_payload.tu` |
| CA8 `e?` propaga | ✅ | `result_try.tu` |
| CA9 `panic` exit ≠ 0 | ✅ | `panic_exit.tu` |
| CA10 `Option` custo zero | ✅ | `match_option.tu` |
| CA11 travessia `any` zero-nó | ❌ | **depende do CA4** |
| CA12 `verifyComponent` | ✅ | `finalize_test.dart` |
| CA13 negativo sobre o dump do CA4 | ❌ | **depende do CA4** |

**6 de 13.** ⚠️ **Correção de rotulagem (2026-07-29):** o invariante
`checkSerializedLibraries` estava rotulado **CA11** no código e nos relatórios —
errado. Ele verifica o `libraryFilter` da **§7.1** (só as libs do programa no
`.dill`); o CA11 é *"travessia `any` de fonte local: zero nó extra"*, que depende
da fronteira existencial e **não existe**. O rótulo errado fazia o placar contar
um CA que ninguém tinha fechado. Renomeado para `libraryFilter:`.

⚠️ Note que **CA11 e CA13 dependem do CA4** — os três caem juntos com a fatia de
conformance (§7.4-d / ADR-0017). Fechar o CA4 fecha três de uma vez.

### LT-F7n — default saltável (**CA2 FECHADO**) `[✅ 2026-07-29]`

- [x] **`struct P { x: Int, y: Int = 2 }` + `P(x: 1).y` ⟶ `2`** — o CA2 literal. O default vira `VariableDeclaration.initializer` e **quem materializa é a VM** (Grupo B): a F7 emite a expressão UMA vez, no param, e o call-site que salta não manda o named.
- [x] **A decisão de named-params (§12-3) fica PROVADA** — `Config(host:, seguro:, nome:)` salta `porta` e `timeout`, que estão no **MEIO**. O posicional do Dart só corta do FIM, então com ele a F7 teria de materializar cada default por call-site. A linha "salta o meio" do fixture é a prova executável.
- [x] **Mesma peça em `fn`** — `conecta(host: "c", retry: 9)` salta o `porta`. A decisão §12-3 é uma só.
- [x] 🔴 **O default tem de ser `ConstantExpression`.** Um `IntLiteral` cru faz a VM morrer **no LOAD**: *"Not a constant expression: unexpected kernel tag SpecializedIntLiteral"*. **Não é o verifier que reprova — é o carregador, em runtime, depois de tudo passar** (verify verde, invariantes verdes, `.dill` serializado). Terceira camada distinta a falhar nesta spec, e a única que só aparece executando. Default não-constante → ICE `default-not-const-<T>`: materializar no call-site é decisão que a §7.4-a não tomou.
- [x] **QUALITY** — analyze limpo; **26 verdes · 3 negativos · 2 fronteiras**; compiler 890.

**A §7.4-e está COMPLETA**, exceto `List` (**gated** pela spec 012) e patterns ANINHADOS (`Ret { origem: Ponto { x: 0 } }` — ICE `match-field-<T>`, exigiria compor testes sobre um receptor que já é `InstanceGet`).

## ~~🔴 BLOQUEIO DA F5~~ — RESOLVIDO (LT-F7k.2, 2026-07-28)

A família enum-**com**-payload **não é da emissão**: o gabarito da §7.4-e já está escrito. O bloqueio é uma fase antes —

```
let c: Forma = .circulo(raio: 2)     ⟹ check-error: cannot-infer
```

O `_call` da F5 não resolve callee `EnumShorthand` **com args**. Não é decisão de semântica: o `_enumShorthand` já prevê o caso (mensagem `variant-needs-payload`, `check.dart:2320`) e a gramática já o descreve (`enumCase ::= IDENT ("(" param … ")")?`). É **implementação faltando**.

**Tamanho estimado:** montar a assinatura da variante como construtor — os NOMES dos params vivem no `EnumCase` da AST, não no `VariantInfo` (que só guarda `List<Type>`) — e reusar o `_matchArgs`; mais type-args quando o enum for genérico. Fatia própria da F5, com testes próprios.

Sem construção não existe valor a destruir, então emitir a classe selada agora produziria um tipo que ninguém consegue instanciar. Fixture `ice_enum_payload.tu` cobra a promoção — e com ela vêm o **CA7** e o caminho para `Result`+`?` (**CA8**).

⚠️ **Erro meu que vale registrar:** eu vinha escrevendo `enum Cor { case vermelho }` (sintaxe de Swift). A gramática do Itá **não tem `case`** — é `enum Cor { vermelho, azul }`, com separador OPCIONAL. O parser lia `case` como nome de variante e gerava o dobro delas, o que me fez suspeitar de bug no parser por alguns minutos. Nenhum bug: teste mal escrito.

**Próximas famílias da §7.4-e:** produto (`struct` em pattern → `InstanceGet`), `List` (**gated** pela 012), e enum-com-payload assim que a F5 destravar.

### LT-F7i — `panic` → `Throw` (**CA9 FECHADO**) `[✅ 2026-07-28]`

- [x] **`panic(msg)` → `Throw(ItaPanic(msg))`** (§7.4-f). Zero try/catch (P7) ⟹ nada captura: o isolate morre, stderr recebe a mensagem, **exit 255** — o valor que a spec previu (`runtime/bin/error_exit.h::kErrorExitCode`), conferido na VM real.
- [x] **Classe de runtime sob demanda** — programa sem `panic` não carrega `ItaPanic` no `.dill`. O invariante `checkNoSyntheticClasses` ganhou uma **allowlist FECHADA** (`_runtimeClasses`), não um `startsWith('Ita')`: a régua tem de errar no desconhecido, senão qualquer wrapper futuro se disfarça de runtime e o CA10 vira letra morta.
- [x] **`toString()` sintetizado** — sem ele o stderr traria `Instance of 'ItaPanic'` em vez da mensagem. ⚠️ Feito com `StringConcatenation` de partes já-String, **não** com o `DynamicInvocation('toString')` do oracle (`codegen.dart:1168`) — aquele nó é o que o ADR-0013 proíbe, e o invariante o pegaria. Segunda vez que "portar a LIÇÃO, não o estilo" evita copiar um defeito do oracle.
- [x] 🎁 **O `!` (force unwrap) destravou** — 3ª promoção pela catraca. O ICE que ele dava (`expr-Panic`, não algo de `match`) tinha dito exatamente qual peça faltava. `??` precisava de 1 núcleo; `!` precisava de 2.
- [x] **QUALITY** — analyze limpo; **19 verdes · 3 negativos · 2 fronteiras**; compiler 876.

⚠️ **`EXPECT-EXIT: 255` é VM-only por construção.** O CA9 marca DIVERGE-DOCUMENTADO (VM/AOT=255, JS/Node=1); a paridade do ADR-0005 cobre só "exit ≠ 0". Quando o alvo JS entrar, este `EXPECT-EXIT` **precisa virar por-alvo**, ou vira promessa falsa.

---

## 🔴 RULING PENDENTE DO DONO — contexto não desce em `if`/`match` (F5, spec 010)

Investigando por que `?.` não tipa, a causa raiz apareceu — e é **maior que o `?.`**:

| forma | hoje |
| :-- | :-- |
| `fn f() -> String? => nil` | ✅ tipa |
| `let n: String? = if c => nil else "x"` | ❌ `cannot-infer` |
| `let n: String? = match x { … .none => nil }` | ❌ `cannot-infer` |

O tipo esperado desce para o corpo de `fn`, mas **não entra** nos ramos de `if`-expr nem nos braços de `match` — eles SINTETIZAM, e a síntese de um ramo `nil` falha por construção (`nil` é checking-only, §4.3).

**Consequência prática:** `u?.nome` não tipa nem com anotação, porque o desugar de `?.` produz um `match` cujo braço `.none` rende `.none`/`nil`. Logo **`?.` não chega à F7**.

**Por que NÃO implementei:** a spec 010 §4.1 enumera as formas checking-only — `nil`, `[]`, `{}`, `.variant` (+ closure §4.2) — e **`if`/`match` não estão lá**. Fazer o contexto descer neles é **regra nova**, não conserto: muda o que o Itá aceita. É a mesma linha que o `_str` respeitou antes do seu ruling de `optional-in-interpolation`.

**As opções, para o dono:**
1. **Propagar** — `if`/`match` passam a ser checking-friendly: o esperado desce a cada ramo/braço. Destrava `?.` e o idioma `let x: T? = match …`. É o comportamento de Swift/Rust/Kotlin. Custo: emenda na spec 010 (§4.1 ganha "formas que PROPAGAM", categoria distinta de "checking-only") + fatia na F5.
2. **Manter e exigir desembrulho explícito** — o dev escreve `let n: String? = match x { … .none => nil as String? }` ou anota o braço. Custo zero de implementação; custo alto de ergonomia, e deixa `?.` inutilizável na prática.
3. **Propagar só em `match`** (não em `if`) — o `?.` depende só do `match`. Recorte menor, mas assimetria entre duas formas que RD-1 trata igual.

Recomendação minha: **(1)**, e a razão é a §4.9 que a própria 010 cita — *"resolução contextual é legítima quando o glifo a PEDE"*. Um `match` cujo resultado é atribuído a slot anotado pede contexto do mesmo jeito que um `nil` pede.

---

**Fronteiras restantes:** `ice_cmp_on_string`, `ice_struct_private_field`. Antes: Novos ICEs honestos que a fatia criou, cada um uma fatia futura: `fn-generic` (∀), `fn-async` (§12-2), `param-default`, `call-toplevel-<T>` (construtor de struct/class), `call-LocalRes` (valor-função/closure).

**Fila que os 4 especialistas abriram e que NÃO cabe nesta fatia** (roteada ao dono):
- 🔴 **A camada INTENSIONAL falta, e a §11 a exige por texto normativo** (`compiler-craftsman`, fundado no Dragon cap. 8 + Nystrom §17.7 "Dumping Chunks"): CA10/CA11/CA13 dizem *"inspecionável no dump"*, *"dump não contém wrapper"*, *"teste estrutural sobre o dump"* — **3 de 13 CAs não são exprimíveis como stdout**. O runner é cego para: `interfaceTarget` nulo (⟹ `DynamicInvocation` imprime igual), `isFinal` de local (`let_var.tu` **afirma** a propriedade da §7.4-b e é o único fixture que não a testa), `dynamic` do ADR-0013, `staticType` de `ConditionalExpression`, e o `libraryFilter` (serializar `dart:core` junto roda idêntico, só cresce 8 MB — é o CA11). Recomendação: começar pelos **invariantes globais sobre o `Component`** (baixo churn, alto sinal), enriquecendo `CompileOutcome` com `libs` — um pipeline, dois leitores; golden textual depois. ⚠️ No golden textual, **nunca** `debugLibraryToString`: usa o `NameSystem` GLOBAL ⟹ o dump do 5º fixture depende dos 4 anteriores terem rodado. `Printer(buf, syntheticNames: NameSystem())` por fixture.
- 🟠 **`main` ausente/inválido dá ICE na cara do usuário** — `emit.dart:264-271` diz que *"o driver (B3) pega isto antes como `missing-main` (§12-5)"*. **Esse driver não existe**: `grep missing-main` acha só o comentário. Hoje `itac build sem_main.tu` ⟹ `ice: ice-codegen-missing-main`, exit 70, contra a §7.8 (*"a F7 não tem erro de usuário"*). Correção é um `if` antes do `emitProgram`.
- 🟠 **Ramos `Float` INALCANÇÁVEIS no `emit.dart`** — `_resolveCmpOps`/`_resolveEqualsOps` registram `FloatType` e `_compare` o aceita, mas `_resolveCoreTypes` **não** tem `FloatType` e `_expr` não tem caso de `ast.FloatLit`. Código morto que finge suporte: ou o `Float` nasce, ou o `FloatType` sai das duas tabelas.
- 🟡 **`ice-codegen-toplevel-FnDecl` não é kebab-case** (Art. IV-5) — vem do `runtimeType`. Sugestão: `ice-codegen-toplevel-fn-decl`. Mexe no `emit.dart` e nos fixtures.
- 🟡 **Buracos de corpus sobre o que já é suportado**: `IfExpr` com ramos não-`String` e aninhado; `let` que lê `let` anterior (a ordem "initializer antes de registrar o binder" é deliberada e não tem caso que a exerça); `let` com anotação explícita; `Bool` em interpolação; interpolação em primeira posição e duas adjacentes; `&&`/`||` com sub-expressões reais (hoje só literais); `EXPECT-EXIT` nunca exercido (só com o CA9).
- 🟡 **`tools/pin-dart.sh` está morto do passo 3 em diante** — o guard testa `compiler/lib/codegen/*.dart`, que nunca mais vai existir (o codegen virou pacote isolado). Os passos 4-6 referenciam `compiler/tool/gen_toml_runtime.sh` e `.claude/skills/ita-test/test.sh`, **ambos inexistentes**.
- 🟡 **`README.md:67`** ainda diz que a Fase 7 "não foi iniciada (`codegen/` vazio)". **`3.12.2` está duplicado em 5 sítios executáveis** (Makefile, `codegen/pubspec.yaml`, `pubspec.lock`, `ci.yml`, mensagem do pin-dart.sh) e nenhum lê o pin.

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
