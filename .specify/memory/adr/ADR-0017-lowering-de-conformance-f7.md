# ADR-0017 — Lowering de conformance (F7): membros na `Class`, box na fronteira existencial

- **Status:** **Accepted** — os 3 rulings do §6 foram decididos pelo dono em **2026-07-16**, com o ADR completo na mesa: **R1** híbrido aceito · **R2** existencial **MARCADO** (`any Ord`) · **R3** defaults por stub+static. As respostas estão registradas no fim do §6.
- **Data:** 2026-07-16
- **Relacionados:** [[ADR-0001]] (Dart VM permanente — a premissa dos ~16× via TFA) · [[ADR-0005]] (paridade dart2js) · [[ADR-0006]] (`itac` é whole-program AOT) · [[ADR-0011]] (F7 = Cap 6 → Kernel) · [[ADR-0012]] (§A-1; #2 `impl`/`extension` coexistem; §C-9 visão systems) · [[ADR-0015]] (trait é FOLHA) · [[ADR-0016]] (§A meta-diretriz; §E bounds não lidos) · spec 009 §4.2b (subsunção) · spec 011 (`ResolvedMember.origin` — o contrato F5→F7)

## Procedência

Preparado em 2026-07-16 por três pareceres independentes, **assinados** (Art. IV-6b): `dart-vm-expert`
(restrições verificadas no vendor `third_party/dart/3.12.2/pkg` e no SDK @3.12.2, arquivo:linha),
`compiler-craftsman` (espaço de técnicas com literatura primária) e `ita-visionary` (leitura pelos 11
princípios + Art. II). Este ADR é **auto-contido** — a conversa não é artefato; o que os pareceres
provaram está transcrito aqui com as fontes. A **recomendação é derivação da sessão**; a decisão é do dono.

## Contexto — o problema, com a cadeia verificada

O Itá tem **subsunção** (spec 009 §4.2b): `fn f(o: Ord)` aceita qualquer `T ≤ Ord` ⟹ trait-como-tipo
exige **dispatch dinâmico**. No Kernel @3.12.2, verificado linha a linha:

- `Procedure` top-level tem `enclosingClass == null` (`members.dart:63`) e só entra em
  `StaticInvocation`: o `_checkInterfaceTarget` (`verifier.dart:1604-1625`) barra não-instance-member
  (`:1605-1610`), stub de representation field (`:1611-1617`) e `enclosingClass == null` (`:1618-1624`).
- ⟹ **membro que participa de conformance TEM de ser emitido DENTRO da `Class`** do conformer, ou o
  dispatch é estático e a subsunção quebra em silêncio.

Três agravantes: (1) conformance vem de **3 sítios** (`class D : A, Trait` · `impl Trait for T` ·
`extension T : Trait`) — a F5 já entrega **qual** decl contribuiu cada membro (`ResolvedMember.origin`,
spec 011); (2) traits têm **default methods** (corpo) além de requisitos, e `implementedTypes` **nunca**
herda corpo; (3) built-ins hoje baixariam para `dart:core`, onde `int`/`String`/`bool` são **`final`**
(*"Classes cannot extend, implement, or mix in `int`"*, `sdk/lib/core/` @3.12.2) — e emitir
`implements int` via Kernel direto não é "proibido", é **UB** (cids fixos de `_Smi`/`_Mint`, intrinsics;
a VM confia no CFE e não re-checa).

**O que a identidade já cravou** (`ita-visionary`, derivação assinada): conformance em built-in
(`extension Int : Ord`) é **exigida pelo Norte** (Art. II: built-ins migram para `.tu`; no ponto final,
`extension Int : Ord` é só `extension T : Ord`, que já existe — ADR-0012 #2). Proibir para sempre
inverteria a taxonomia do `-unsupported` (que **promete** "um dia funciona") em mentira retroativa, e a
única razão disponível seria topologia do Kernel — **o backend legislando o front-end**, vedado pela
cerca já escrita em `collect.dart:376-383`. O quadrante confirma: Elixir tem `defimpl String.Chars,
for: Integer` — protocolo sobre tipo nativo é constitutivo da família.

## §1 Tipos LOCAIS — merge-na-`Class`

Trait → `abstract class` no Kernel (requisitos = procedures abstratos). Conformer → a `Class` emitida
ganha o trait em `implementedTypes` e **todos os membros de conformance dentro dela** — os vindos de
`impl`/`extension` inclusive, como procedures comuns (`stubKind: Regular`). Dispatch existencial =
interface dispatch da VM: **vtable é Grupo B, custo zero, TFA devirtualiza** (a alavanca do ADR-0001).

Requisitos mecânicos verificados (`verifier.dart`): parent pointer na `Class` (`:277-287`);
`FlagStatic` desligado; **NÃO** setar `isExtensionMember` (`:686-693` exigiria descriptor na library);
corpo vindo de `impl`/`extension` com `TypeParamType` **re-mapeado para os `TypeParameter` da Class**
(não cópias frescas — `:830`).

⚠️ **A completude é 100% nossa**: o verifier **não confere nada** de `implementedTypes` (grep = zero) e
a VM não roda o verifier — classe concreta sem membro do interface vira `NoSuchMethodError` em runtime.
Quem segura é a F5, que **já** garante (`missing-trait-member`; requisito não denota; default×default
recusado). O corpus de conformance (Art. IV-4) vira a rede.

**Exige whole-program** — que já é o modelo ([[ADR-0006]]). Coerência já é global: o collect é a prova
de que `T : Trait` existe de um jeito só; a unidade de coerência do Itá é **(tipo, NOME)** — mais
restritiva que o (tipo, trait) do Rust, consequência do "sem overload" (spec 009 §12-4) — e a spec da
F7 deve **nomeá-la**. Orphan rule fica **adiada para a época de pacotes** com a lição registrada:
Rust RFC 1023 (localidade da culpa + semver) × Swift SE-0364 (sem regra ⟹ conformances duplicadas dão
comportamento não especificado). Não é soundness aqui — é política de ecossistema.

## §2 Default methods — corpo 1× em static + stub por conformer

`implements` não herda corpo. Menu verificado:

| Saída | Custo verificado |
| :-- | :-- |
| (i) copiar o corpo por conformer | Melhor precisão de TFA (`this` concreto por cópia), mas snapshot ~linear × conformers **sem dedup real** (`program_visitor.cc::DedupInstructions` exige tabelas idênticas; cópias otimizadas por receptor divergem) + mais summaries = mais tempo de TFA (fere Art. IV-3) |
| (ii) `mixedInType` cru | **ARMADILHA, verificada**: quem achata mixin é `pkg/vm/lib/modular/transformations/mixin_full_resolution.dart` — pipeline do CFE que o Itá **bypassa**; o loader da VM (`kernel_loader.cc::LoadPreliminaryClass`) assume front-end já clonou. `.dill` com mixin cru em JIT: os membros **não existem**. (ii) = (i) reimplementado por nós, com classes anônimas de brinde |
| (iii) corpo vira `static Trait$f(self)` + stub `fn f(...) => Trait$f(this, ...)` por conformer | Corpo 1× no snapshot; stubs são os **melhores candidatos reais** ao dedup do AOT (mesma tabela de static calls); inlináveis (`vm:prefer-inline` + `dart2js:prefer-inline`, os dois — cada backend ignora o do outro). Custo: dentro do static, `self` é o **join** dos conformers ⟹ chamadas a requisitos ficam polimórficas ali |

**Recomendação (derivação da sessão): (iii).** É o padrão do próprio CFE para stubs
(`ConcreteMixinStub`/`ConcreteForwardingStub`, `members.dart:713-900`) e é o único que serve o Art. IV-3
(compile-time) e o tamanho de snapshot simultaneamente. A lição Scala fica registrada como preço aceito:
(i) e (iii) quebram igual em separate compilation futura — mas `itac` é whole-program por decisão
([[ADR-0006]]); só resolução na VM salvaria (Java 8, JVMS §5.4.3.3), e a Dart VM não resolve.

## §3 Built-ins e a fronteira existencial — box de valor

Para built-in que baixa a `dart:core` o retrofit é UB (Contexto). As alternativas com dispatch dinâmico,
custeadas nos 3 alvos (`dart-vm-expert`):

- **(a) wrapper/box** `class Ord$Int implements Ord { final int v; ... }`, alocado **no sítio de
  subsunção** para slot existencial. JIT: 1 alocação + indireção por fronteira; o `int` interno segue
  **Smi**. AOT: TFA vê os allocation sites ⟹ cone devirtualizável; `final v` unboxável. dart2js: classe
  comum. **Paridade OK nos 3 alvos.**
- **(b) witness/dictionary**: no Kernel **não há fat pointer nem argumento oculto de ABI** ⟹ a witness
  reifica como objeto e **colapsa operacionalmente em (a)** com pior ergonomia (`List<Ord>` heterogênea
  obriga o par valor+dict; `o is Ord` sem imagem em runtime; closure nunca ganha convenção unboxed).
- **(c) Int como classe própria** (representação): mata **Smi** na VM e o número primitivo no JS —
  **proibitivo nos 3 alvos simultaneamente**. Morto como representação (a *declaração* é outra coisa — §4).
- **(d) monomorfização**: não cobre existencial por definição (`List<Ord>` heterogênea decide em
  runtime; o Rust tem `dyn` porque mono não alcança) e é anti-Art. IV-3 (Go 1.18 escolheu dictionaries
  exatamente para proteger compile-time).

**Recomendação (derivação da sessão): (a), com a fronteira sendo PROPRIEDADE DECLARADA DO TIPO — nunca
por sítio.** A técnica muda em **valor vs referência** (P2), e essa fronteira **coincide** com
local/foreign: todos os foreign do Itá são tipos-VALOR (Int, Float, Bool, String, List, Map). Valor
imutável **não tem identidade a violar** (P2 nega identidade a valores) ⟹ o vazamento pior do box morre
por construção. **Box está morto para semântica de referência** — `class` boxada forjaria segunda
identidade, e identidade é a promessa do P2. (Como toda `class` é local, o caso não ocorre — mas a cerca
fica escrita para o dia em que "foreign" crescer.)

**Obrigação de spec — os 4 canais observáveis fecham, e isso se prova por corpus, não se intui** (P4):
1. `==` no slot existencial **delega ao valor** (box transparente; `Ord$Int(5) == Ord$Int(5)` ⟺ `5 == 5`);
2. `is`/`match` sobre existencial faz **round-trip** (`match o { Int i => ... }` testa o box e desembrulha
   — a F7 controla o lowering de todo type-test, então é implementável, mas TEM de estar na spec);
3. borda `dart:` **desembrulha** antes de cruzar (enumerada, Art. II);
4. mensagens de erro/panic **nunca** vazam `Ord$Int` — imprimem `Int`.

⚠️ Regra dos 3 alvos: a instância que dá o dispatch tem de ser alcançável **estaticamente** no código
emitido — **nenhum desenho de registro dinâmico** (tabela por string, lookup tardio): o dart2js não tem
equivalente de `vm:entry-point` e tree-shake sem remédio.

## §4 A fork do M5 — `Int` é DECLARAÇÃO `.tu`, representação `dart:core::int`

A fork registrada em `collect.dart:376-383` ("Int baixa pra dart:core ou ganha decl própria") é
**binária falsa** (`ita-visionary`): o Norte (Art. II) exige a **declaração** — contrato, membros e
conformances de `Int` escritos e lidos em Itá — não a **representação**. A forma que serve Art. II e
Art. III ao mesmo tempo é a **forma-Elixir**: o integer do Elixir É o integer da BEAM, com protocolos
por cima. Aqui: decl `.tu` própria (M5, des-Dartificação) + backing `dart:core::int` + membros de
extension como top-level statics (`StaticInvocation` — dispatch estático onde não há subsunção) + o box
do §3 **só** quando o valor cruza para slot existencial. Régua do custo: **absorve-se custo onde a
alternativa barata esconde semântica; cede-se representação onde a semântica observável não muda**
(layout/dispatch/unboxing = Grupo B).

## §5 O que a F5 ganha — side-table nº7: sítios de subsunção

Hoje `_isSubtype` devolve `bool` e **não registra onde** coagiu. O box do §3 precisa saber **em qual
expressão** um valor entrou em slot existencial. Fundamento: Dragon **6.5.2** — coerção implícita
permitida é **materializada** na IR (o `widen`; analogia assinada pelo `compiler-craftsman`). A
subsunção é ponto único na F5 ⟹ **uma função a instrumentar**, produzindo a **side-table nº7**
`<Expr, CoercionInfo>` (sítio, tipo-fonte, trait-alvo). Sem isso a F7 recomputaria tipagem — exatamente
o que o desenho de side-tables existe para impedir (ADR-0004).

*(Correção de 2026-07-16, mesma sessão: este § dizia "nº6" — mis-citação, a doença 3 do [[ADR-0014]].
A `CheckResult` já tem SEIS tabelas — a nº6 é `binderTypes` — e a numeração aqui não conferiu antes de
escrever. A tabela nova é a **nº7**; nada além do número muda.)*

## §6 Rulings pedidos ao dono — este ADR NÃO os decide

| # | Pergunta | O que cada resposta compra |
| :-: | :-- | :-- |
| **R1** | **Aceitar o desenho híbrido** (§1 merge local + §2(iii) defaults + §3(a) box de valor na fronteira existencial + §4 forma-Elixir)? | É a decisão-mãe. Alternativas inteiras (witness puro, mono, proibir) estão custeadas acima e nenhuma serve os 3 alvos + Art. IV-3 + P2/P4 simultaneamente |
| **R2** | **Existencial marcado (`any Ord`) ou implícito?** — ruling **aberto desde 2026-07-14**, anterior a este ADR; aqui ele é **nomeado**, não decidido | Marcado (Swift SE-0335): a fronteira do box ganha **glifo no tipo** e a tensão com P4 dissolve por sintaxe; custo: uma keyword a mais (nunca `@` — P6). Implícito: superfície menor, e o P4 passa a depender só dos 4 canais do §3 |
| **R3** | **Defaults por (iii) stub+static** (recomendado) **ou (i) cópia por conformer**? | (iii) = snapshot mínimo + compile-time; (i) = precisão máxima de TFA dentro do corpo do default. Só é observável em perf; pode começar (iii) e migrar caso o benchmark do CI acuse |

**Decisões do dono (2026-07-16):**

- **R1 — ACEITO.** O desenho híbrido dos §1–§5 está em vigor; a spec da F7 nasce dele.
- **R2 — MARCADO: `any Ord`.** O slot existencial ganha a keyword `any` no tipo (keyword, nunca `@` —
  P6). Consequências imediatas: o `grammar.ebnf` e a spec de superfície ganham a forma `any Trait`; a
  fronteira do box (§3) fica com **glifo visível** — o P4 é servido por sintaxe, e os 4 canais do §3
  continuam obrigação de corpus. O ruling aberto desde **2026-07-14** FECHA aqui. Corolário a
  especificar: `fn f(o: Ord)` com trait nu deixa de denotar existencial — a spec da superfície decide
  se vira erro (`existential-requires-any`) ou se trait nu fica reservado para o uso em bound.
  *(✅ Decidido no `grammar.ebnf` §11, 2026-07-16 — as DUAS metades: erro `existential-requires-any`
  em posição de tipo JÁ, e trait nu reservado ao bound quando bounds entrarem — bound é constraint,
  não tipo, §7. Implementado em `e8b664a`: contextual, `?` fecha por fora, cláusula segue nua.)*
- **R3 — (iii) stub+static.** Com a válvula registrada: migrável para (i) se o benchmark do CI
  (Art. IV-3) acusar hot-path em corpo de default.

## §7 Fora de escopo — nomeado, não decidido

- **Genéricos com bound** (`fn f<T: Ord>(x: T)`): bounds **não são lidos** hoje
  (`generic-bounds-unsupported`, [[ADR-0016]] §E). Quando entrarem, há uma restrição já conhecida:
  dentro de um corpo genérico, converter `T` para existencial exige a witness da **instanciação** —
  mecanismo próprio (mini-mono por instanciação, dict oculto, ou proibir a conversão no corpo). Fica
  para o ADR/spec dos bounds, com este parágrafo como aviso.
- **Orphan rule** para pacotes `.tu` de terceiros (§1 — política, não soundness).
- **Separate compilation**: preço registrado no §2; reabrir só se o modelo whole-program cair.

## Consequências (se ratificado)

- A spec da F7 nasce citando este ADR; a F5 ganha a instrumentação do §5 **antes** (side-table nº7).
- O corpus de conformance (Art. IV-4) ganha as suítes: completude de conformance (§1), os 4 canais do
  box (§3), paridade VM×JS dos três mecanismos.
- `conformance-on-builtin-unsupported` mantém a promessa: o caminho para removê-lo fica escrito (§3+§4).
- O benchmark de compile-time (Art. IV-3) ganha o caso "N conformers × M defaults" (vigia o §2).

## Fontes

Vendor `third_party/dart/3.12.2/pkg/kernel/lib/{verifier.dart, src/ast/members.dart, canonical_name.dart}`
+ `binary.md`; SDK @3.12.2 (`sdk/lib/core/`, `runtime/vm/kernel_loader.cc`, `runtime/docs/pragmas.md`,
`pkg/vm/lib/modular/transformations/mixin_full_resolution.dart`, `pkg/compiler/doc/pragmas.md`,
`type_flow/{analysis,transformer}.dart`, `program_visitor.cc`). Literatura: Wadler & Blott POPL '89;
Rust RFCs 1023/2451/0255/1105; Swift `TypeLayout.rst`, SE-0335, SE-0364; JVMS §5.4.3.3/§5.4.6; Scala
2.12 release notes; Go 1.18 generics design; Dragon 1.6.5, 6.3.x, **6.5.2**, 12.2.1 (o livro NÃO cobre
vtable/witness/coerência — registrado). Itá: `collect.dart:333-395`, `type_table.dart:55-190`,
`check.dart:1670-1700`.
