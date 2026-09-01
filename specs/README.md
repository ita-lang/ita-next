# Índice das specs — `ita-next`

> **Mapa fase ↔ spec do front-end.** Número de spec é **ordem de criação**, não de fase (ADR-README).
> Duas colunas de estado deliberadamente separadas: **`status`** é o rótulo do fluxo SDD no cabeçalho da
> spec (`draft` → `clarified`); **`impl`** é o estado REAL de implementação (código + `tasks.md` + goldens
> + `make test`).
>
> ⚠️ **Este arquivo já apodreceu uma vez, e o aviso "divergência é dívida de bookkeeping" não impediu.**
> Entre 2026-07-22 e 2026-08-27 ele ficou **109 commits** atrás: afirmava *"emissão não escrita, `codegen/`
> só `.gitkeep`"* enquanto `codegen/lib/` tinha 5.190 linhas em 6 arquivos, e citava `862 verde` quando a
> suíte estava em `922`. A nota de rodapé ⁴ era **literalmente correta e materialmente enganosa** — o
> `.gitkeep` que ela citava é de `compiler/lib/codegen/`, diretório abandonado quando a F7 mudou para o
> pacote isolado `codegen/`.
>
> Por isso o bloco **DERIVADO** abaixo: os sinais que uma régua sabe medir têm catraca
> (`make readme-derivado`, no portão) e reprovam quando esta página contradiz o repo. O que a régua **não**
> sabe medir está na seção *"Estado corrente"*, e ali **todo número vem datado** — porque número nu se lê
> como presente, e era assim que o `862` mentia.

---

## Sinais derivados

<!-- DERIVADO:INICIO — validado por `make readme-derivado`. Números conferidos contra o repo; não editar à mão sem rodar a régua. -->

| sinal | valor |
|:--|--:|
| specs no repo | 14 |
| CAs no ledger da spec 013 | 13 |
| fixtures `conformance/codegen` | 84 |
| fixtures `conformance/valid` | 50 |
| fixtures `conformance/desugar` | 23 |
| fixtures `conformance/invalid` | 21 |
| fixtures `conformance/resolve` | 17 |
| fixtures `conformance/flow` | 12 |
| fixtures `conformance/check` | 4 |
| arquivos `.dart` em `codegen/lib` | 6 |

<!-- DERIVADO:FIM -->

## Grupo A — o que o Itá implementa (Dragon Book caps 2–6)

| Fase | Spec | Título | `status` | `impl` |
|:-:|:-:|:--|:--|:--|
| **F1** Léxico | [003](003-lexer-scaffold/) | Léxico completo + scaffold | `clarified` | ✅ implementada |
| **F2** Sintaxe→AST | [004](004-parser-ast/) | Sintaxe completa → AST | `draft` | ✅ implementada |
| **F2** Sintaxe→AST | [005](005-decl-surface/) | Superfície declarativa | `draft` | ✅ implementada |
| **F3** Desugar | [006](006-where-typed-ops/) | `where`-expr + operadores tipados (prep) | `draft` | ✅ implementada |
| **F3** Desugar | [007](007-desugaring/) | Desugaring / lowering | `draft` | ✅ implementada¹ |
| **F4** Binding | [008](008-binding/) | Binding / resolução de nomes | `draft` | ✅ implementada² |
| **F5** Semântica | [009](009-semantic-types/) | Semântica / Tipos | `clarified` | ✅ implementada (rulings/§12) |
| **F5** Semântica | [010](010-contextual-typing/) | Tipagem contextual | `clarified` | ✅ implementada (rulings/§12) |
| **F5** Semântica | [011](011-member-resolution/) | Resolução de membro | `clarified` | ✅ implementada (rulings/§12) |
| **F5**→M5 | [012](012-builtin-members/) | **Membros de built-in** — o chão (`.length`, `xs[i]`, `+`) | `clarified` | 🟡 **chão da F5 ✅ + emissão nos 3 alvos ✅**, mas a LETRA dos CA1–CA3/CA9 não roda⁵ |
| **F6** Flow | [014](014-flow-check/) | Flow-check (fluxo + exaustividade `match`) | `clarified` | ✅ **implementada** — flow-walk + Maranget (Fatias 1-3); resíduo menor³ |
| **F7** Codegen | [013](013-codegen-kernel/) | Codegen → Dart Kernel (`.dill`) | `clarified` | 🟢 **os 13 CAs do §11 fecharam**; emissão escrita, golden-runner nos 3 alvos — fatias em ICE seguem abertas⁴ |

## Specs transversais / cross-target

| Spec | Título | `status` | `impl` |
|:-:|:--|:--|:--|
| [001](001-int-bitwise-semantics/) | Semântica de largura de `Int` + bitwise cross-target | `clarified` | 🔵 planejada — ligada ao alvo JS/M4 |
| [002](002-rewrite-compiler-dragon-book/) | **ÉPICO** — reescrita do compilador (guarda-chuva) | `clarified` | — épico, sem tasks próprias |

---

## Estado corrente — o que a régua NÃO mede

> A régua acima é estática: conta arquivos e entradas de ledger. **Suíte verde e CA fechado são estado de
> execução** — só quem roda `make test` / `make codegen-test` sabe, e esses alvos vivem em jobs de CI
> diferentes. Por isso ficam aqui, **datados**. Data ausente = número que não vale.

- **`make gate` (portão inteiro: front-end + codegen + citações + asserções + harness): verde** —
  medido em 2026-09-01, sobre a emissão do chão (LT-012b).
- **Golden-runner nos 3 alvos: 63 verdes · 11 negativos · 10 fronteiras** — medido em 2026-09-01.
  Eram 49 verdes antes da LT-012b; os +14 são os fixtures `chao_*`.
- **`make test` (front-end F1–F6): 936 verdes** — medido em 2026-08-31. Eram **922** em `3a2651a`
  (e em 2026-08-27 — o CA11 não tocou o front-end); os **+14** são o grupo *"errata 010 §4.1"*,
  que fez o literal de coleção não-vazio voltar a **checar** contra o esperado. Antes dele era
  impossível construir uma `List`/`Map` com conteúdo em Itá.
- **Citações sem procedência: 421 de legado · 0 novas** — o baseline **desceu** de 422 (a fatia
  reescreveu um dos sítios acusados). Só pode descer.
- **Ledger de CAs da spec 013: 13 fechados · 0 parciais · 0 abertos** — medido em 2026-08-31.
  O último a fechar foi o **CA11** (travessia `any` de fonte local, zero nó extra), em `9fe1885`.
  A leitura anterior — *"bloqueado pela fronteira existencial do ADR-0017, hoje em ICE"* — estava
  errada nas duas metades: built-in em slot `any` dá `conformance-on-builtin-unsupported` (erro
  **nomeado** da F5, não ICE), e o box de built-in é **não-objetivo da própria spec 013**, roteado à
  M5. Um CA cujo pré-requisito a spec mandou para outra milestone fica aberto para sempre sem nada a
  fazer — R10. O que faltava era consumidor para a side-table nº7, e ele existe:
  `checkExistentialZeroNode`, cobrado por [`codegen/test/ca_ledger.dart`](../codegen/test/ca_ledger.dart).
- **Fronteiras em ICE com catraca `EXPECT-ICE`: 16 fixtures contra 153 ICEs** — a maior fatia aberta são
  os **genéricos (∀)**: `class` · `struct` · `enum` · `trait` · `fn` · `method`, cada um com fixture.

---

### 📂 Nota sobre a spec 012 (reserva destravada — o chão saiu em 2026-07-20)

A numeração salta de **011 → 013** por ordem de criação (a 013 nasceu antes da 012). O nº **012 era uma
reserva normativa do dono** para **membros de built-in** (`.length`, indexação `xs[i]`, `+`/`.map`/`.slice`
de `List`, `Map.keys()`), registrada em:

- [`spec 013 §Numeração`](013-codegen-kernel/spec.md) — *"esta spec é a 013 porque a 012 está RESERVADA
  pela spec 011 §1.3 … Número de spec é ordem de criação, não de fase."*
- [`spec 011 §1.3`](011-member-resolution/spec.md) — o **corte do `compiler-craftsman`**: os membros de
  **tipo do usuário** (011) e os de **built-in** (012) são **produtores independentes** da tabela de tipos;
  a F5 recusava built-in com `builtin-member-unsupported` (§4.7).

**Destravada em 2026-07-20:** a pasta [`specs/012-builtin-members/`](012-builtin-members/) já existe e o
**CHÃO** (`.length`/`[]`/`+`) foi recortado do resto (`.map`/`.slice`/`Map.keys()`, que seguem p/ **M5** na
des-Dartificação → built-ins migram para `.tu`):

- **LT-012a — F5 (o chão TIPADO):** ✅ **implementada e mergeada** (PR #2, `da85bc1`; W3 🟢). A F5 deixa de
  recusar `.length`/`[]`/`+` de built-in e passa a tipá-los.
- **LT-012b — F7 (codegen do chão):** 🟢 **T040–T042 implementados em 2026-08-31/09-01.** `ListLiteral` /
  `MapLiteral` / `InstanceGet(length)` / `InstanceInvocation([] e +)`, com `functionType` e `resultType`
  substituídos por `Substitution.fromInterfaceType`. 14 fixtures `chao_*` rodando nos **três** alvos.
  A revisão adversarial de contexto limpo pegou **dois bugs 🔴 que os gates não pegaram**: o `+` de
  `String` reaberto no `+=` (dois dos três sítios de despacho) e ICE sobre `let xs: List<Int>? = [1,2]`,
  programa que a F5 declara legal no próprio docstring.
  Segue aberto o **T043**: o `match` sobre `List` continua em `ice-codegen-match-on-BuiltinType` — é
  lowering de list-pattern no `_matchExpr`, não emissão de `List`, e a `tasks.md` da 012 previa errado
  que a fatia do chão o destravaria.

Os checkboxes da LT-012a em [`012/tasks.md`](012-builtin-members/tasks.md) estão marcados, **exceto
T001–T003**: a forma **literal-nu** que descrevem (`[10,20,30].length`) dá `cannot-infer`, e o chão só
tipa sobre **receptor tipado**. ⚠️ **A atribuição à "fatia C" que esta nota fazia está errada** — a
errata da spec 010 §4.1 (2026-08-31) fechou as três posições COM esperado (`let` anotado, argumento,
retorno); o que resta é a metade **sem** esperado, que é `cannot-infer` por **política** (spec 009 §4.3)
e aguarda decisão do dono, não fatia faltando. O corte está preso executavelmente por
`conformance/codegen/chao_literal_nu.tu`. (Exceção: `"olá".length` tipa — string-literal é auto-tipado.)

---

¹ **007** tem 1 divergência declarada: `guard let` foi **retido como nó core** (RD-1), não desaçucarado
como a T004 previa. Pendente de ruling do dono — ver [`007/tasks.md` T004](007-desugaring/tasks.md).
² **008** tem 1 débito de contrato aberto: `resolution` trafega por parâmetro solto até a F7 — roteado em
[`013/tasks.md` AF4](013-codegen-kernel/tasks.md).
³ **014**: a exaustividade de `match` (Maranget U/S/D + testemunha) — o **gate DURO da F7** — **foi
implementada** (LT-F6a co-requisito na F5 ✅ 2026-07-17; LT-F6b Fatias 1-3 ✅ de `71961ab` a `f911beb`).
Resíduo menor aberto: redundância-de-`List` (3b-ii) + rulings menores — ver
[`014/tasks.md`](014-flow-check/tasks.md).
⁴ **013**: os gates de §0.6 caíram (F6 implementada, nota ³; SDK pinado+vendorado em `72d31da` — Dart
3.12.2 + `vm_platform.dill` fmt 130 + `pkg/kernel`+`_fe_analyzer_shared` em `third_party/`). A emissão
**está escrita** e roda: golden-runner nos 3 alvos (VM × AOT × JS) no CI, ledger de CAs derivado, passes de
saneamento com catraca de vacuidade. O placar do §11 fechou **13/13** em `9fe1885` (CA11, 2026-08-10) — mas
CA fechado é o §11 satisfeito, **não** a linguagem inteira emitida: as fronteiras em ICE seguem abertas, e a
maior delas são os genéricos (∀), com catraca por forma. Pipeline e fatiamento em
[`013/tasks.md`](013-codegen-kernel/tasks.md).
⁵ **012**: 🟡 **e não 🟢, de propósito.** A emissão funciona nos três alvos, mas a **letra** dos CA1/CA2/CA3/CA9
do §11 (`print("${[10,20,30].length}")`, receptor literal-nu) **não compila** — os fixtures trocam por receptor
tipado. Pela R9, um CA só é verde quando o texto INTEIRO foi verificado, e os CAs da 012 ainda não têm ledger
derivado (o `ca_ledger.dart` cobre a 013), então este resumo é markdown que o próprio commit edita — a segunda
metade da R9. Fica 🟡 até a letra rodar ou a 012 ganhar linha no ledger.
O chão da F5 (LT-012a) e a emissão dele (LT-012b, T040–T042) estão mergeados — `.length`/`[]`/`+`
e os literais de `List`/`Map` rodam nos três alvos, com 14 fixtures `chao_*` em `conformance/codegen/`.
Segue aberto o **T043**: o `match` sobre `List` (`[]`, `[_, ..r]`) continua em `ice-codegen-match-on-BuiltinType`
— é lowering de list-pattern no `_matchExpr`, não emissão de `List`, e a `tasks.md` da 012 previa errado que
a fatia do chão o destravaria. Aberto também o **literal nu** como receptor (`[1,2,3].length` ⟹ `cannot-infer`),
que é decisão pendente do dono, presa por `chao_literal_nu.tu`.
