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
| fixtures `conformance/codegen` | 93 |
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
  medido em **2026-10-09** pela sessão `codegen`, `make gate` exit 0 (default do Makefile, **sem**
  `DART_CG=dart` — o `dart` do PATH é 3.13.2 e quebraria o contrato de formato do pin 3.12.2), sobre o
  T043 (list-pattern) e a correção do `nil` em pattern. O código foi **escrito** em 2026-09-01 e ficou
  38 dias não-comitado; os números abaixo são da remedição de hoje, não daquela sessão. Procedência
  junto do número porque é exatamente isto que apodreceu aqui: o bloco anterior dizia `2026-09-01` sem
  dizer quem mediu, e ninguém soube distinguir "medido e verde" de "escrito e nunca mais rodado".
- 🔴 **Dois bugs vivos na família `Option`, corrigidos em 2026-09-01** — achados pelo *simétrico* de um
  terceiro, não por gate. `nil` em pattern não é literal escalar: pela §7.4-e ele vira `null` nativo, e o
  gabarito `EqualsNull` estava escrito **só para o subject**, dentro do ramo de `EnumPattern` (`.none`).
  Nas outras posições o `nil` chega como `LiteralPattern` e caía no caminho do `==`:
  `match x { nil => …, .some(v) => … }` dava `match-eq-on-OptionalType`, e
  `match c { C { v: nil } => … }` dava `untyped-NilLit` — ICE que nomeia **estado** do emissor sobre
  programa legal, o formato que mente sobre a causa. Cura num sítio só (`_nilTest`), chamado pelos três,
  que é a régua que o `+` de `String` já tinha deixado escrita.
  **Por que 30 dias de CI verde não pegaram:** os seis `match … { … nil => … }` do corpus escrevem o
  braço `nil` **por último**, e o último braço do right-fold não ganha teste. Seis fixtures, seis vezes a
  mesma ordem idiomática. Não faltou cobertura de linha — faltou **permutar os braços**, e é isso que
  `match_nil_posicoes.tu` passa a fazer.
- **Golden-runner nos 3 alvos: 70 verdes · 11 negativos · 12 fronteiras** — medido em **2026-10-09**
  (sessão `codegen`, dentro do `make gate` exit 0). Os 7 fixtures novos do T043 rodaram nos **três**
  alvos com stdout byte a byte (VM, AOT e JS), e as 2 catracas bateram ICE exato
  (`ice-codegen-match-list-nested-test` / `-bind`). Eram 49 antes da LT-012b (+14 `chao_*`) e 63 antes
  do T043 (+7: os `match_lista*`, `match_nil_posicoes` e `match_map_irrefutavel`, mais 2 catracas).
- **`make test` (front-end F1–F6): 936 verdes** — remedido em **2026-10-09** (sessão `codegen`), igual
  ao medido em 2026-08-31; o T043 é só codegen e não move este número. Eram **922** em `3a2651a`
  (e em 2026-08-27 — o CA11 não tocou o front-end); os **+14** são o grupo *"errata 010 §4.1"*,
  que fez o literal de coleção não-vazio voltar a **checar** contra o esperado. Antes dele era
  impossível construir uma `List`/`Map` com conteúdo em Itá.
- **Citações sem procedência: 421 de legado · 0 novas** — e o número honesto é **421**, não 418.
  ⚠️ **`tools/check-citations.sh --update` NÃO vale neste Mac, porque a leitura da régua depende da
  plataforma.** A regra C3 casa modalidade normativa com `tolower(win(i,2)) ~ NORM`, e `NORM` tem
  termos **acentuados** (`obrigatóri`, `não pode`, `é ERRO`). O awk do macOS é o BWK
  (`/usr/bin/awk`, `version 20200816`), orientado a byte, e não minúsculiza multibyte:

  ```
  $ echo 'NÃO PODE' | awk '{ print tolower($0) }'
  nÃo pode
  ```

  Resultado medido em 2026-10-09: o scanner acha **421** no gawk do CI e **418** aqui — os 3 que
  faltam (`emit.dart:992`, `finalize.dart:1`, `:2`) têm `OBRIGATÓRIO`/`OBRIGATÓRIA` na janela de ±2
  linhas. Um `--update` rodado aqui **baixou a catraca de 421 para 418 gravando a cegueira da
  plataforma como progresso**, e o CI reprovou com `3 NOVA(S)`; a baseline foi restaurada ao conjunto
  de `53aa705`. O baseline **só desce quando o sítio foi reescrito**: 422 → 421, e não mais.
  **Por que isto é pior que o caso `DART_CG`** (ambos local≠CI): aquele **quebra alto**, este
  **aprova** — o portão local fica silenciosamente mais frouxo que o do CI, e nenhuma camada avisa.
  A fatia que fecha isto (falhar alto sem gawk, em vez de remendar o `tolower`, + self-test com
  entrada acentuada em CAPS que fica vermelho no BWK) tem nome e catraca própria, e **não** é deste
  commit.
  **Procedência inclui PLATAFORMA**, não só data e autor: `exit 0` local prova que *esta máquina*
  aprova.
- **Ledger de CAs da spec 013: 13 fechados · 0 parciais · 0 abertos** — medido em 2026-08-31.
  O último a fechar foi o **CA11** (travessia `any` de fonte local, zero nó extra), em `9fe1885`.
  A leitura anterior — *"bloqueado pela fronteira existencial do ADR-0017, hoje em ICE"* — estava
  errada nas duas metades: built-in em slot `any` dá `conformance-on-builtin-unsupported` (erro
  **nomeado** da F5, não ICE), e o box de built-in é **não-objetivo da própria spec 013**, roteado à
  M5. Um CA cujo pré-requisito a spec mandou para outra milestone fica aberto para sempre sem nada a
  fazer — R10. O que faltava era consumidor para a side-table nº7, e ele existe:
  `checkExistentialZeroNode`, cobrado por [`codegen/test/ca_ledger.dart`](../codegen/test/ca_ledger.dart).
- **Fronteiras em ICE com catraca `EXPECT-ICE`: 12 fixtures contra 176 códigos** — medido em
  **2026-10-09** (sessão `codegen`). **O placar SUBIU de 10 para 12, e separadamente a medição foi
  corrigida de 16 para 12** — as duas coisas na mesma frase de propósito, porque lidas apartadas
  parecem a regressão que a R7 proíbe. O `16` publicado nunca foi real: contava arquivos que
  *mencionam* `EXPECT-ICE` em prosa, não os que a **declaram**. Pela medida honesta
  (`rg -l '^// EXPECT-ICE:' conformance/codegen/`) o HEAD `53aa705` tem **10** e este branch tem
  **12** — as 2 catracas novas do T043 são o **pagamento**, e `16 → 12` é só a régua passando a medir
  o que diz medir.
  A maior fatia aberta segue sendo os **genéricos (∀)**: `class` · `struct` · `enum` · `trait` · `fn` ·
  `method`, cada um com fixture.
- **O denominador dos ICEs são QUATRO números, e três deles já circularam como se fossem o mesmo.**
  Medidos em 2026-10-09, cada um com o comando que o reproduz — número nu é o que apodreceu aqui
  (o `177` publicado era o pior dos quatro, e ninguém sabia o que ele contava):

  | nº | o que conta | comando |
  |--:|:--|:--|
  | **177** | ocorrências do **lexema** `_ice(` em `emit.dart` | `rg -o '_ice\(' codegen/lib/emit.dart \| wc -l` |
  | **175** | **sítios de chamada** reais | 177 − a definição (`emit.dart:62`) − **1 menção dentro de doc-comment** (`emit.dart:4674`) |
  | **176** | **códigos emitidos** — o que `make assertions` chama de "sítios" | `make assertions` → *"176 distintos em 176 sítios · 0 ambíguos"* |
  | **173** | sítios cujo código é literal de **aspas simples** colado ao parêntese | `rg -o "_ice\('[^']*'" codegen/lib/emit.dart \| wc -l` |

  **A reconciliação, que não é a que se supôs.** A hipótese natural — *"176 sítios contra 173 códigos
  distintos ⟹ ou três pares colidem (três violações da R13 que o `make assertions` deixou passar), ou
  a contagem colapsa os templates interpolados"* — está **errada nas duas metades**, e a diferença de
  três é inteiramente **artefato da forma do grep**:
  - `emit.dart:1193` usa **aspas duplas** (`_ice("class-private-field", decl)`) — o grep de aspas
    simples não o vê;
  - `emit.dart:1874` é um **ternário**: `_ice(isBreak ? 'break-outside-loop' : 'continue-outside-loop', s)`
    — **um** sítio que carrega **dois** códigos, e por isso 176 > 175;
  - `emit.dart:4674` é **comentário**, não sítio: a prosa cita `` `_ice(` `` para explicar a própria
    régua.

  Os templates **não** colapsam: `tools/check-assertions.sh` trunca cada código na primeira
  interpolação (*"a parte fixa termina na 1ª interpolação"*) e compara os **prefixos**, que é a medida
  certa para a R13 — dois sítios com o mesmo prefixo seriam acusados. Os 176 prefixos são distintos e
  há **0 ambíguos**: nenhuma violação da R13 escapou. O que a régua **não** mede, por construção, é a
  multiplicação em *runtime* de um prefixo interpolado — e é disso que trata o item seguinte.
- ⚠️ **Fatia de saneamento NOMEADA e não aberta: o código do ICE com granularidade de nó.** Remedido em
  **2026-10-09**: **41** sítios do emitter interpolam `${…runtimeType}` no código, e ali cada construção
  que a gramática permite naquela posição vira um código diferente — uma fronteira multiplicada, que um
  fixture só cobre em parte. Foi o erro corrigido no T043
  (`match-list-nested-test-${sub.runtimeType}` → `match-list-nested-test`, 4 construções → 1 código).
  Três amostras medidas em 2026-09-01 confirmam alcançáveis **e sem catraca**:
  `let-target-ListPattern` (`let [a, ..r] = xs`), `result-payload-LiteralPattern` (`.ok(0)` e `.ok(nil)`)
  e `match-field-*`. O número honesto de fronteiras mudas só sai de uma **varredura de alcançabilidade**
  — para cada forma que a gramática admite na posição, rodar o programa mínimo e anotar onde ele para.
  - 🔴 **A granularidade tem TRÊS graus, não dois — e o pior deles o README não contava de forma
    alguma.** Varredura do arquivo inteiro, **medição da sessão `orquestrador` em 2026-10-09**
    (Art. IV-6b: derivação dela, não do dono), com a contagem de `.name`/`.variant` reconciliada pela
    sessão `codegen` contra os sítios:

    | grau | o que entra no código | cardinalidade | legítimo? |
    |:--|:--|:--|:--|
    | **vocabulário fechado** | `${b.op.name}`, `${type.kind.name}`, `${shape.name}`, `${tipo.args.length}` | pequena e fixa | **sim** |
    | **forma da gramática** | `${…runtimeType}` — **41** sítios | finita, enumerável | cobrível fixture a fixture |
    | **identificador do usuário** | `.name` de campo/membro/método · `.variant` de enum — **22** sítios | **ilimitada** | **não** |

    São **30** os sítios que interpolam algo que não é `runtimeType`
    (`rg -o "_ice\('[^']*'" codegen/lib/emit.dart | rg '\$\{' | rg -vc runtimeType`), e **22** deles
    tomam um nome que o dev digita — **11 da família `.name`** (`:824`, `:826`, `:1307`, `:2304`,
    `:3452`, `:3456`, `:3563`, `:3635`, `:4299`, **`:4413`**, `:4420`) e **11 da família `.variant`**
    (`:921`, `:925`, `:944`, `:955`, `:3334`, `:3351`, `:3372`, `:3375`, `:3385`, `:3671`, `:3715`).
    Os 8 restantes são vocabulário fechado. A família **`.variant` é a maior e nunca tinha sido vista**:
    o achado começou em **um** sítio de `.name` (`:1307`, `_ice('init-field-${target.name}', decl)`,
    pela sessão `compiler`) e só a varredura mostrou que era uma família de 22, não um extremo isolado.
    **`:4413` (`ground-member-${m.name}`) entra na conta e estava fora da lista da varredura** — é o
    único dos 22 que hoje é **inalcançável com a razão escrita no sítio** (*"nada com receptor-chão e
    nome≠`length` chega aqui… a catraca nasce NESSA fatia"*), o que o faz conforme à R7 **hoje** e
    ilimitado no dia em que o chão ganhar um segundo membro. Fica contado e anotado, não omitido.

    **Por que o terceiro grau é de outra ordem:** `runtimeType` multiplica a fronteira pelas formas que
    a gramática admite — finito, enumerável, cobrível fixture a fixture. Um nome escrito pelo dev
    multiplica pelo conjunto dos identificadores digitáveis, que é **ilimitado**. Consequência dupla:
    nenhum fixture fecha a fronteira, e o `make assertions` **não acusa** — e o mecanismo exato importa,
    porque a formulação fácil (*"dois usos nunca colidem no mesmo código"*) está errada: a régua trunca
    na primeira interpolação, então os dois usos **colidem sim, no prefixo** (`init-field-` é **um**
    código para ela), e é justamente por colidirem num prefixo único que ela os **aprova**. A variação
    em runtime é invisível por construção.
    Os vizinhos `:1297`, `:1300` e `:1304` (`init-body-stmt-`, `init-body-expr-`, `init-target-`) são o
    caso comum, de segundo grau.
  - **Declarado, não consertado — e de propósito.** Este branch **não** toca nenhum dos códigos acima,
    incluindo os **6 que ele próprio introduz** (`list-subject-shape-test-`, `list-subject-shape-bind-`,
    `list-elem-eq-on-`, `list-elem-range-on-`, `list-nested-shape-test-`, `list-nested-shape-bind-`).
    O T043 portanto **paga um** código de granularidade e **contrai seis**, e o placar bruto da fatia é
    **12 `_ice` novos contra 2 catracas**. Misturar o saneamento aqui faria o PR mentir sobre o que foi
    verificado: a fatia tem nome e precisa de catraca própria.
  - **Lacuna declarada (R10):** `result-payload-LiteralPattern` com `.ok(nil)` segue **não testado**.
    Fecharia com um fixture de uma linha, e não foi escrito nesta fatia. O branco se preenche com
    código nosso, então é fatia — não limite.

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
  **T043 fechado em 2026-09-01** — o lowering de list-pattern no `_matchExpr`, que é o que o `match`
  sobre `List` sempre dependeu (não da emissão de `List`, como a `tasks.md` da 012 previa). Fecha o
  **CA8 da 012** com a letra do critério copiada, não parafraseada. 5 fixtures novos nos três alvos +
  2 catracas de fronteira. Dois achados fora do previsto: o mesmo guard recusava `match m { _ => … }`
  sobre `Map` — programa sem nada a destruir, restrição sem nome, hoje implementada — e a fronteira do
  `struct` aninhado precisa de **duas** catracas, porque o último braço do right-fold não passa pelo
  teste e só o bind a alcança.

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
O **T043 fechou em 2026-09-01**: o `match` sobre `List` (`[]`, `[_, ..r]`) emite e roda nos três alvos —
era lowering de list-pattern no `_matchExpr`, não emissão de `List`, e a `tasks.md` da 012 previa errado que
a fatia do chão o destravaria. Com ele o **CA8 fica verde pela letra** (o texto do critério está copiado em
`match_lista.tu`, não parafraseado). Segue aberto o **literal nu** como receptor (`[1,2,3].length` ⟹
`cannot-infer`), que é decisão pendente do dono, presa por `chao_literal_nu.tu` — e é só por causa dele que
esta linha continua 🟡.
