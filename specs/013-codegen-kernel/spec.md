# Spec 013: Fase 7 — Codegen → Dart Kernel (`.dill`)

> **Tipo:** feature-fase (codegen) · **Marco:** `Fase 7 do ita-next — o degrau final do Grupo A`
> **Status:** `clarified` — **4 rulings de dono fechados em 2026-07-16** (§12-1 mut em struct PROIBIDO · §12-3 named required · §12-4 print String-only · §12-6 DIVERGE-DOCUMENTADO), com a fila integral apresentada e decidida em bloco na recomendação. §12-5 assentado como derivação (driver do modo build). Pendente só o **§12-2** (async × transformer CFE) — **roteado à fase própria, não bloqueia esta spec**. Gates de implementação restantes no §0.6: **spec da F6** e **pin do SDK**.
> **Autor / Data:** orquestração (Claude) · 2026-07-16 · **Fundamentação:** Dragon **6.2** (IR), **8.1** (fronteira do Grupo A — Cap 6 → Kernel; Cap 8+ é Grupo B), **5.3** (o que a F3 já pagou); [[ADR-0017]] (lowering de conformance — **normativo aqui**), ADR-0001/0005/0006/0011/0013; pareceres `dart-vm-expert` (vendor 3.12.2, verificado arquivo:linha), `compiler-craftsman` e `ita-visionary` de 2026-07-16.
> **Numeração:** esta spec é a **013** porque a **012 está RESERVADA** pela spec 011 §1.3 (membros de built-in — reserva normativa do dono, itens 1 e 5). Número de spec é ordem de criação, não de fase (precedente: reuso do nº 003, ADR-README).

## §0 Metadados

- **Classe da mudança:** [x] **Nova fase** — a F7 inteira: consome o contrato da F5 (as 7 side-tables) e emite `Component` Kernel serializado (`.dill`, formato **130**).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [ ] Formal/Tipos · [ ] SDD · [ ] Fluxo · [x] **Codegen/IR (§7)** · [x] **Runtime (§8)** · ⚠️ + **um dedo em F4/F5**: o chão ganha `print` (§7.6 — sem ele não existe programa observável).
- **Princípios afetados:** P4 (a emissão nunca esconde semântica), P2 (struct é valor — §7.4c e o clarify §12-1), P9/P11 (zero Python, zero codegen build-time — a F7 é o COMPILADOR emitindo, não build_runner), Art. II (3 alvos do mesmo `.dill`), Art. III (Cap 6 é a fronteira), Art. IV-1/3/4.

### §0.5 Constitution check

Sem conflito. A F7 é o que o Art. III **promete**: *"a fronteira do Grupo A vai até a emissão de código intermediário — Cap 6 → Dart Kernel"*. Três artigos viram obrigação mecânica desta spec: **Art. II** (JIT/AOT/JS do mesmo `.dill` — §7.7), **Art. IV-3** (o `itac` de CI é o binário AOT e o benchmark de compile-time FALHA em regressão — §9), **Art. IV-4** (golden-runner de paridade VM×JS quando o codegen muda — §7.7). O interop `dart:` que esta spec introduz é **explícito e enumerado** (§8.2): `dart:core::print`, e nada mais.

### §0.6 Gates — o que TEM de existir antes da implementação

| Gate | Por quê | Estado |
| :-- | :-- | :-- |
| **F6 (flow-check) implementada** | Função non-`Void` sem `return` em todo caminho **não tem corpo Kernel válido** — e o verifier do Kernel **não checa** (*"does not include any kind of type checking"*, `verifier.dart:127-129`) e a VM não o roda. Quem garante é o definite-return da F6 (ADR-0011, fase 6). Emitir sem F6 = `.dill` que **executa errado em silêncio** | ❌ spec da F6 não existe (candidata: 014) |
| **SDK pinado + vendor** | `tools/pin-dart.sh 3.12.2` (o `dart-sdk.pin` já crava versão, formato 130, sha256) — o binário `dart`, o `vm_platform.dill` e o `pkg/kernel` vendorado têm de vir da MESMA stable | ❌ pin ainda não rodado (era desnecessário até a F7 — o próprio pin o diz) |
| **Rulings do §12 fechados** | §12-1 (struct `mut`) bloqueava o F7-B | ✅ fechados em 2026-07-16 (resta só o §12-2, que não bloqueia — roteado) |

## §1 Motivação e resumo

O pipeline para na F5: `itac` tokeniza, parseia, checa — e **joga fora** o programa tipado. A F7 fecha o
círculo: `.tu → .dill → executa nos 3 alvos`. É o degrau que o [[ADR-0017]] pavimentou — a decisão de
lowering está tomada (R1–R3), a side-table nº7 existe, a superfície `any` existe. Falta a fase.

**Antes → Depois:**

```tu
// antes — `itac check examples/hello.tu` é o FIM do pipeline
fn main() { print("olá") }   // e `print` nem resolve (unresolved-before-check)
```

```tu
// depois — `itac run examples/hello.tu` imprime "olá" na VM;
// `itac build -o hello.dill` + `dart compile exe` e `dart compile js` empatam.
fn main() { print("olá") }
```

**Princípio de escopo (o que delimita TODA esta spec):** a F7 emite **exatamente o conjunto de
programas que a F5+F6 aprovam hoje**. Programa que a F5 recusa (`builtin-member-unsupported`,
`conformance-on-builtin-unsupported`, `for-binder-unsupported`, `generic-bounds-unsupported`, …)
**nunca chega** à F7 — os gabaritos correspondentes ficam especificados mas **gated**, e destravam
quando a fase produtora destravar. Corolário: **a F7 não reporta erro de usuário** — todo erro seu é
ICE (§7.8).

**Não-objetivos** (roteados, não esquecidos — a lição da 011 §1.2b):

| # | Fora | Destino | Por quê |
| :-: | :-- | :-- | :-- |
| 1 | Membros de built-in (`.length`, `xs[i]`, `.map`) | **spec 012** (reserva da 011 §1.3) | outro produtor; a F5 os recusa hoje |
| 2 | Box de built-in em fronteira `any` | **M5** | mecanismo NORMATIVO no ADR-0017 §3; inalcançável até `conformance-on-builtin-unsupported` cair |
| 3 | `async`/`await`/`stream`/`actor`/`spawn`/`emit` | fase própria (pós-013) | ⚠️ risco CONHECIDO e da mesma família da armadilha do mixin: a lowering de async pode ser transformer do pipeline CFE que bypassamos — **verificar com o `dart-vm-expert` ANTES de especificar** (§12-2) |
| 4 | Otimização (inlining, unboxing, dedup) | **Grupo B** | TFA/VM entregam (ADR-0001); nós emitimos Kernel **bem-tipado** — é a alavanca dos ~16× |
| 5 | `OperatorDecl` custom / currying / `a ** b` | **012+** | rota da 011 §1.3-5; type-directed pendente de produtor |
| 6 | Separate compilation | reaberto só se whole-program cair | preço aceito no ADR-0017 §2/§7 |
| 7 | Genéricos com bound no codegen | ADR dos bounds | ADR-0017 §7 — a witness da instanciação é problema de lá |

---

## §7 Código intermediário e geração — `[cap 6.2, 8.1]`

### 7.0 Contrato de entrada — as 7 side-tables (spec 009 §7; spec 011)

A F7 **não recomputa tipagem** (ADR-0004). Cada tabela e o que a F7 lê dela:

| nº | Tabela | O que a F7 lê |
| :-: | :-- | :-- |
| 1 | `exprTypes` | o `DartType` de todo nó — Kernel **bem-tipado** é a alavanca do ADR-0007 |
| 2 | `types` (TypeTable) | kinds, campos, generics, `traits`, `init`/`extensionInits`, `substFor`/`sourcesUnder` |
| 3 | `resolvedMembers` | `interfaceTarget` de `InstanceGet`/`InstanceInvocation` (`Reference` non-nullable) + **`origin`** — em qual `Class` o membro mora (ADR-0017 §1) |
| 4 | `annotations` | o tipo de cada anotação (assinaturas, campos) |
| 5 | `resolvedCalls` | `slot` arg→param, `typeArgs` **na ordem declarada** (⚠️ `Substitution.fromPairs` casa posicional — ordem errada = tipo trocado em silêncio), `signature` substituída |
| 6 | `binderTypes` | `VariableDeclaration.type` é **non-nullable** no Kernel; ADR-0013 proíbe `dynamic` |
| 7 | `coercions` | os sítios de travessia existencial (ADR-0017 §5). **Hoje**: fonte é sempre local ⟹ **zero nó emitido** (upcast é grátis, §1 do ADR). O gabarito do box (fonte built-in) fica **gated** (não-objetivo 2) |

### 7.1 Arquitetura de emissão

- **Construção**: AST Kernel via **`pkg/kernel` vendorado** (`third_party/dart/3.12.2/pkg` — Dart puro,
  P9 satisfeito); serialização via `BinaryPrinter`; formato **130** (o `dart-sdk.pin` é o contrato).
- ⚠️ **INVARIANTE — o `.dill` é carregado CRU pela VM; tudo que o CFE faria é NOSSO.** Isso tem **duas**
  consequências operacionais, não uma (a §7.1 antiga via só a primeira — W1 `dart-vm-expert` 2026-07-19):
  - **(A) Transformers do pipeline CFE que NÃO rodam** (verificados, ADR-0017):
    1. **`mixedInType` NUNCA é emitido** — a VM **não achata** mixin (`kernel_loader.cc::LoadPreliminaryClass`
       assume front-end já clonou; `pkg/vm/.../mixin_full_resolution.dart` não roda).
    2. **`implements` sobre classe de `dart:core` NUNCA é emitido** — `int`/`String`/`bool` são `final`;
       violar é **UB** (cids fixos de `_Smi`/`_Mint`). Feature futura cuja lowering o Dart resolve "no
       CFE" entra nesta lista **antes** do codegen (é o §12-2 do async).
  - **(B) Higiene de campo de nó fresco — passes de SANEAMENTO obrigatórios (LT-F7a).** A API crua do
    `pkg/kernel` deixa campos no DEFAULT que o *builder* da CFE setaria; o loader binário da VM lê o
    default e ou **executa errado em silêncio** ou **crasha**. `verifyComponent` **NÃO pega** esta classe.
    Três passes, rodados como último `RecursiveVisitor` sobre o `Component`, **antes** de
    `computeCanonicalNames`/`BinaryPrinter`:
    1. **`_LocalFunctionIdAssigner`** — `FunctionExpression.id`/`FunctionDeclaration.id ≥ 1`, sequencial
       **resetado por Member** (Procedure/Constructor/Field). Replica o `LocalFunctionIdGenerator` do CFE
       (`kernel/…/expressions.dart:5007`). O default `LocalFunctionId.invalid == 0` colide no
       `ClosureFunctionsCache` da VM (mapa 2-níveis, chave interna `Smi(local_function_id)` —
       `runtime/vm/closure_functions_cache.cc`): **2 closures no mesmo member ⟹ a 2ª executa a 1ª**.
       Quebra compose (`>>`)/curry — foi o colapso de closure do oracle (regressão do formato 130).
    2. **`_OffsetNormalizer`** — offsets **secundários** `-1 → 0`: `Class.startFileOffset`/`fileEndOffset`,
       `Constructor.*`, `Procedure.fileStartOffset`/`fileEndOffset`, `Field.fileEndOffset`,
       `FunctionNode.fileEndOffset`, `Block.fileEndOffset`. O `fileOffset` **primário** vem da F3; os
       secundários não. `-1` cumulativo ⟹ bus error na finalização (`KernelLoader::GenerateFieldAccessors`).
    3. **`isFinal ⟸ campo sem setter`** — todo `Field` com `setterReference == null` tem `isFinal = true`,
       senão Kernel malformado (`verifier.dart:744-747`). `struct` já protegido (§7.4c); `class` com campo
       `let`, não.
  - **Rede:** golden estrutural sobre o dump (id≥1; nenhum offset secundário -1; nenhum Field-sem-setter
    com isFinal=false) **+ o CA de 2+ closures/member** (LT-F7c) — os passes e o CA se co-verificam (o
    `verifyComponent` não pega o `localFunctionId`).
- **Membro emitido dentro de `Class`** (requisitos verificados, `verifier.dart`): parent pointer na
  `Class` (`:277-287`) · `FlagStatic` desligado · **nunca** `isExtensionMember` (`:686-693`) ·
  `TypeParamType` do corpo **re-mapeado para os `TypeParameter` da Class** (`:830`), nunca cópias frescas.
- **Spans**: todo nó Kernel recebe `fileOffset` do span-fonte (a F3 já preserva spans em nós
  sintetizados — spec 007 §5.2); é o que dá stack trace e source map honestos nos 3 alvos.

### 7.2 CLI e artefatos

| Comando | Efeito |
| :-- | :-- |
| `itac build <f.tu> [-o f.dill]` | F1→F7; grava o `.dill` |
| `itac run <f.tu>` | build + executa com o `dart` **pinado** (`.dart-sdk/3.12.2/...`); exit code do programa |
| (CI) golden-runner | roda o corpus nos 3 alvos e compara **stdout + exit code** (§7.7) |

### 7.3 Programa e `main`

`fn main()` (aridade 0, `Void`) é o entry — `Component.mainMethod`. Ausência de `main` num build
executável: erro de F5/F6 (não desta fase; ver §12-5). Exit code: `0` normal; `panic` ⟹ **≠ 0** (§7.5f).

### 7.4 Gabaritos de emissão — `[cap 8.1.3]`

**(a) Funções e chamadas.** `fn` top-level → `Procedure` static. Params do Itá baixam como **named
required** do Kernel (defaults viram `VariableDeclaration.initializer` — **a VM materializa o default,
Grupo B**). É a escolha que o doc da nº5 deixou aberta, decidida aqui: o slot do Itá salta param DO MEIO
(*"ordem obrigatória, defaults saltáveis"*, ADR-0016 §C) e posicional Dart só corta do FIM ⟹ named é a
única forma que preserva a semântica sem a F7 materializar default (*derivação; contestável no clarify §12-3*).
Chamada: `StaticInvocation` com args montados pelo `slot` da nº5; `typeArgs` na ordem declarada.

**(b) Closures.** `Closure` → `FunctionExpression`; chamada de valor-função → `FunctionInvocation`
com `functionType` da nº5 (nullable no Kernel ⟹ sem ela cai em `DynamicType`, que o ADR-0013 proíbe).

**(c) Tipos nominais.**
- `struct` → `Class` com campos `final` — **TODOS, por ruling** (§12-1, dono 2026-07-16): struct é
  imutável SEMPRE (`mut-field-on-struct` na F5). **A cópia-valor é inobservável POR imutabilidade**
  (P2: valor imutável não tem identidade a perder — mesma régua do box do ADR-0017 §3). Mutação pede
  `class` ou copy-with.
- `class` → `Class`; referência, sem memberwise (ADR-0012 §A-1).
- `init` explícito → `Constructor`; memberwise sintetizado → `Constructor` com named params = campos
  (assinatura da `TypeInfo.init` — nº2); `extensionInits` → constructors **adicionais** (ADR-0016 §B).
- `enum` sem payload → classe com constantes; com payload → **classe selada + subclasse por variante**
  (sum type). `match` destrói por teste de classe (e).
- `Option<T>` ≡ `T?` → **nullable nativo** do Kernel; `.none`/`nil` → `null`; `.some(x)` → `x`
  (spec 009 §8.4 — Option tem equivalente nativo, custo zero). `Result<T,E>` → **classe** (payload nos
  dois lados; spec 009 §8.4).
- **CopyWith** `p.{ x: 1 }` → `ConstructorInvocation` do init com campos não-mencionados lidos do
  receptor (via nº3) — só onde a F5 o aprovou (`copywith-on-custom-init` já barrou o resto).

**(d) Conformance — o ADR-0017 vira emissão (normativo):**
- `trait` → `abstract class`; requisito → procedure abstrato.
- Conformer: trait em `implementedTypes` + **todos os membros de conformance DENTRO da `Class`**
  (inline, `impl`, `extension` — a nº3/`origin` diz quem contribuiu o quê). Dispatch existencial
  (`any Voa`) = `InterfaceType` do trait + `InstanceInvocation` — vtable é Grupo B.
- **Default method** (R3): corpo 1× em `static Trait$f(self, …)` + stub `fn f(…) => Trait$f(this, …)`
  por conformer que não o sobrescreve, com `@pragma('vm:prefer-inline')` **e**
  `@pragma('dart2js:prefer-inline')` (cada backend ignora o do outro).
- **Completude é 100% nossa** — o verifier não confere `implementedTypes` (grep = zero); a F5 já
  garante (`missing-trait-member`); o corpus é a rede (§11 CA-completude).
- Travessia existencial de fonte LOCAL (nº7): **zero nó**. Fonte built-in: box do ADR-0017 §3 — gated.

**(e) Controle e match.**
- `if`/`guard`(desaçucarado)/`while`/`return` → nós diretos do Kernel. RD-1 é respeitado por
  construção: só `=>` rende valor; bloco emite statements.
- `match` → **cadeia de `is` + destructure + comparação** (decision tree simples; exaustividade e
  unreachable são F6 — a F7 confia). ⚠️ **TRAVA DURA (W1 `dart-vm-expert` 2026-07-19):** os nós de
  pattern do Dart 3 (`IfCaseStatement`, `PatternSwitchStatement`, `PatternVariableDeclaration`) são
  **CFE-internos e PROIBIDOS** no `.dill` cru — na MESMA cláusula que `ForInStatement` no
  `kernel_binary_flowgraph.cc` (*"removed by the constant evaluator"* → `UNREACHABLE()`). Logo o `match`
  baixa para nós **primitivos**: `IsExpression`/`AsExpression`/`EqualsCall`/`EqualsNull`/`IfStatement`/
  `ConditionalExpression`/`Let`. **RD-1 decide a forma:** `=>` rende ⟹ right-fold de `ConditionalExpression`;
  bloco ⟹ cadeia de `IfStatement` com o subject em **`VariableDeclaration` de bloco (NÃO `Let`)** — regra
  dart2js (ADR-0005: var capturada por closure de braço tem de ser block-var). Por família de escrutínio:
  - **enum-com-payload** (classe selada + subclasse): `IsExpression(subject, Variante)` + payload por
    `InstanceGet(AsExpression(subject, Variante), field, getterRef)` (o `as` é necessário — sem
    flow-promotion no Kernel cru).
  - **`Option`/`T?`**: `EqualsNull(subject)` (`.none`) / `Not(EqualsNull)` (`.some(x)`, bind `x = subject`).
    Custo zero — sem classe `Option` no `.dill` (CA10).
  - **escalar** (Int/Str/Float literal): `EqualsCall(subject, literal)`. **range** (Int): `>= lo && <= hi`
    via a tabela `Ops` (§7.5, `dart:core`).
  - **produto** (`struct`): `InstanceGet` dos campos (getters NOSSOS). `record`: **a confirmar** conforme
    a decisão de lowering (`RecordType` nativo ⟹ `RecordIndexGet`/`RecordNameGet`, não `InstanceGet`).
  - ⚠️ **`List` (slice): GATED pela spec 012.** O teste de comprimento (`.length`) e o bind de elemento
    (`xs[i]`) são **membros de built-in** (§1, não-objetivo 1) — a F5 os recusa hoje
    (`builtin-member-unsupported`), então `match` sobre `List` **nunca chega à F7** e o gabarito fica
    especificado mas **gated** até a 012 produzir `.length`/`[]`. As demais famílias NÃO dependem da 012.
  - **Bind** de pattern → `VariableDeclaration(type = binderTypes` nº6`)` (non-nullable; ADR-0013 proíbe
    `dynamic`). A testemunha de exaustividade da F6 **não vira código** (§7, política de fase); o **throw
    defensivo de fim-de-corpo** (fn non-`Void` que cai do fim) vem da nº8 `flowFacts` (a F7 LÊ o bit).
  Otimizar a árvore de decisão é Grupo B/roadmap — não desta spec.
- **`e?` (`Try`, nó CORE — spec 007 §5.2)** → o único gabarito com fluxo não-local:
  `match e { .ok($v) => $v, .err($e) => return .err($e) }` — early-return tipado pela assinatura
  `Result` da função (nº1/nº4).
- `ForStmt` → `ForInStatement` do Kernel (spec 007, retido por ruling) — **gated**
  (`for-binder-unsupported` na F5 até o M5).

**(f) Literais, strings, panic.**
- Literais → `IntLiteral`/`DoubleLiteral`/`BoolLiteral`/`StringLiteral`; interpolação →
  `StringConcatenation` (partes já são `Expr` desde o parse).
- List/Map literais → `ListLiteral`/`MapLiteral` com type-args da nº1.
- `panic(msg)` → `Throw` de erro dedicado (`ItaPanic`, classe emitida no módulo). **Zero try/catch na
  linguagem (P7) ⟹ nada o captura**: o isolate morre, stderr recebe a mensagem + stack trace (spans do
  7.1), exit code ≠ 0. Paridade: no JS, exceção não-capturada + exit ≠ 0.

### 7.5 Ops primitivos

`Int + Int` etc. vêm da tabela `Ops(sym)` da F5 (débito declarado — spec 009 §4.9). Emissão:
`InstanceInvocation` sobre o operador de `dart:core` correspondente (`+` de `int`) — **exatamente o que
o oracle faz** (`codegen.dart:3006`, `k.Name('+')`), agora com `interfaceTarget` tipado. Unboxing/Smi:
Grupo B. Quando o M5 migrar a tabela para `.tu`, o gabarito não muda — muda o produtor.

### 7.6 O chão ganha `print` — a MENOR superfície de I/O possível

Não existe programa observável sem I/O, e `print` hoje **nem resolve** (F4: `unresolved-before-check`).
Esta spec adiciona ao chão — **mesma taxonomia do `Ops(+)`: DÉBITO declarado, não design** (spec 009
§4.9; a doutrina do chão: tabela **fechada**, erra no desconhecido, destino `.tu` no M5):

- **F4**: `print` entra no escopo global do resolver (tabela do chão, 1 entrada).
- **F5**: assinatura `print(s: String) -> Void` — chamada com não-String é `type-mismatch` normal
  (zero coerção; quem quer `print(n)` interpola: `print("${n}")`).
- **F7**: `StaticInvocation` → `dart:core::print` — o interop explícito e enumerado do Art. II (§8.2).

⚠️ **Fica marcado**: a spec 012 (built-ins) pode substituir/expandir isto; esta entrada existe para a
F7 ter observável, não para desenhar a API de I/O do Itá (§12-4).

### 7.7 Comportamento por alvo — `[Art. II + Art. IV-4]`

| Alvo | Comportamento | Observação |
| :-- | :-- | :-- |
| **VM (JIT)** | `itac run` — referência | valida via corpus + MCP `ita` (Art. IV-1) |
| **AOT** (`dart compile exe <dill>`) | **empata a VM** byte a byte em stdout + exit code | TFA/tree-shaking não podem mudar observável |
| **JS** (`dart2js <dill>`) | paridade com VM nos CAs marcados | ⚠️ semântica numérica JS (int 2^53, `~/`, overflow) — os CAs numéricos declaram MATCH ou DIVERGE-DOCUMENTADO, spec 001/ADR-0005 |

Golden-runner no CI: **todo CA desta spec roda nos 3 alvos** (exceto os marcados VM-only com razão).

### 7.8 Erros da fase

**A F7 não tem erro de usuário.** Entrada é programa F5+F6-verde; qualquer impossibilidade interna é
**ICE** (`ice-codegen-*`, EN kebab-case) com span — e ICE em corpus é bug de fase anterior que vazou.

## §8 Runtime — premissas sobre a Dart VM — `[cap 7.1]`

- **8.1** Assume (sem reespecificar — Grupo B): carregamento de `.dill` formato 130 casado com o
  `vm_platform.dill` do pin; vtable/interface dispatch; GC; Smi/unboxing; `ForInStatement` itera
  `Iterable` (gated); async — **fora, §12-2**.
- **8.2 Interop `dart:` enumerado** (Art. II): `dart:core::print` (§7.6) · operadores primitivos de
  `dart:core` via `Ops` (§7.5) · `dart:core::Object` como raiz implícita. **Nada mais.** Cada adição
  futura edita ESTA lista.

## §9 Checklist de completude

- [ ] `tools/pin-dart.sh` rodado; `third_party/dart/3.12.2/pkg/kernel` vendorado; sha256 confere
- [ ] `itac build`/`run` no driver (funções puras testáveis, como `tokenize`/`parse`/`check`)
- [ ] **corpus `conformance/codegen/`** novo: `.tu` + golden de **stdout/exit code por alvo**
- [ ] golden-runner VM×AOT×JS no CI (Art. IV-4)
- [ ] **benchmark de compile-time** no CI com gate de regressão (Art. IV-3) — inclui o caso
  "N conformers × M defaults" (ADR-0017, vigia o R3)
- [ ] `itac` de CI vira o binário **AOT** (`tools/build-itac.sh`, ADR-0006) a partir desta fase
- [ ] tree-sitter/GRAMMAR: **N/A** (a F7 não muda superfície)

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** Não — só ADIÇÃO (`build`/`run`; `check` intacto).
- **Alternativas descartadas:** emitir Dart-fonte e chamar o CFE (herdaria os transformers e o
  compile-time do CFE — mata Art. IV-3 e o Art. II "sem SER Dart"); writer binário próprio sem
  `pkg/kernel` (re-implementar serialização de formato interno sem SemVer — frágil a cada bump);
  interpretar a AST (não é o produto — ADR-0001).

## §11 Critérios de aceite (viram `conformance/codegen/`)

- **CA1** `fn main() { print("olá, ${1 + 1}") }` ⟶ stdout `olá, 2`, exit 0 — **3 alvos**.
- **CA2** struct memberwise: `struct P { x: Int, y: Int = 2 }` + `print("${P(x: 1).y}")` ⟶ `2` — 3 alvos (defaults saltáveis chegam ao Kernel).
- **CA3** `class` com `init` explícito valida; `extensionInits` são construtores adicionais (ADR-0016 §B) — VM.
- **CA4** dispatch existencial: `Pato`/`Cao` conformam `Fala`; `fn f(v: any Fala) => print(v.som())`; lista heterogênea imprime sons DIFERENTES — **3 alvos** (é a razão de ser do ADR-0017 §1).
- **CA5** default method roda via stub com `self` correto; conformer que SOBRESCREVE vence o default — 3 alvos.
- **CA6** membro vindo de `impl`/`extension` despacha igual a inline (origin nº3 → dentro da `Class`) — VM + JS.
- **CA7** `match` sobre enum-com-payload destrói e rende (RD-1: `=>` rende) — 3 alvos.
- **CA8** `e?` propaga `.err` com early-return; caminho `.ok` segue — 3 alvos.
- **CA9** `panic("x")` ⟶ exit ≠ 0, mensagem no stderr com linha-fonte (span) — VM + AOT; JS: exceção não-capturada, exit ≠ 0.
- **CA10** `Option`: `nil` vira `null` nativo — `let x: Int? = nil` + match imprime o braço `.none`; **custo zero** (sem classe Option no `.dill` — inspecionável no dump) — VM.
- **CA11** travessia `any` de fonte local: **zero nó extra** no `.dill` (dump não contém wrapper) — VM.
- **CA12** `.dill` emitido passa `verifyComponent` do `pkg/kernel` vendorado (mesmo sabendo que a VM não o roda — é o NOSSO gate de sanidade) — CI.
- **CA13** ⚠️ negativo: o `.dill` de CA4 **não contém** `mixedInType` nem `implements` sobre classe de `dart:core` (as 2 armadilhas do ADR-0017, pinadas para sempre) — CI, teste estrutural sobre o dump.

## §12 Fila de clarify/rulings — ⚠️ ABERTA (o `/speckit-clarify` fecha)

| # | Pergunta | Bloqueia | Decisão |
| :-: | :-- | :-- | :-- |
| 1 | **struct com campo `mut`**: a cópia-valor sob mutação é observável (representação por referência ⟹ sharing = P2 quebrado) | **F7-B** (structs) | ✅ **Dono (2026-07-16): PROIBIDO.** struct é imutável SEMPRE — mutação pede `class` (P2 é o glifo) ou copy-with. Valor-semântica preservada POR CONSTRUÇÃO. Erro novo na F5: **`mut-field-on-struct`** (campo `var`/`mut` em struct). A F5 de hoje aceita ⟹ alinhamento imediato |
| 2 | **async/await/stream/actor**: a lowering é transformer do pipeline CFE que bypassamos (família da armadilha do mixin)? Verificar `pkg/vm` @3.12.2 ANTES de qualquer spec | não bloqueia a 013 | ⏳ ABERTO — roteado à spec da fase async, `dart-vm-expert` responde lá |
| 3 | Params baixam como **named required** (decisão do §7.4a) | F7-A | ✅ **Dono (2026-07-16): CONFIRMADO** — a VM materializa defaults (Grupo B); é a única forma que preserva "defaults saltáveis do meio" sem a F7 duplicar a expressão default por call-site |
| 4 | `print(s: String)` no chão — assinatura mínima | F7-A | ✅ **Dono (2026-07-16): String-only.** Zero coerção — `print(n)` é `type-mismatch`; o idioma é interpolar. Débito declarado, destino `.tu`/trait `Show` no M5 |
| 5 | `main` ausente/duplicado/com params | F7-A | ✅ Assentado como **derivação** (aceita no clarify): validação do **DRIVER em modo build** (não da emissão — o §7.8 fica intacto: F7 segue sem erro de usuário). `itac check` NÃO exige `main` (biblioteca é legítima); `itac build`/`run` exigem `fn main()` aridade 0 → `missing-main` / `invalid-main-signature` |
| 6 | Semântica numérica no JS (int 2^53) | golden-runner | ✅ **Dono (2026-07-16): DIVERGE-DOCUMENTADO.** MATCH é o default do golden-runner; CA que toca borda de 64 bits é marcado DIVERGE com a semântica JS documentada no próprio CA (postura do próprio Dart; coerente com a spec 001/Bits.*) |

## Definition of Done

- [ ] Gates do §0.6 fechados (F6 implementada; pin rodado; §12-1/3/4/5 decididos).
- [ ] CA1–CA13 no corpus `conformance/codegen/`, verdes nos alvos declarados, validados via MCP `ita`.
- [ ] Constitution check (§0.5) sem conflito aberto.
- [ ] CI verde: conformance + unit + golden-runner (Art. IV-4) + benchmark de compile-time (Art. IV-3).
- [ ] `itac` de CI é o binário AOT (ADR-0006).
