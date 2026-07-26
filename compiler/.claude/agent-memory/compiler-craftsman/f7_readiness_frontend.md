---
name: f7-readiness-frontend
description: Revisão F7-readiness do front-end (2026-07-24, 862 verdes). O que a F7 consome está sólido; zero BLOQUEADOR. 4 riscos rastreados + 4 divergências spec×código.
metadata:
  type: project
---

# F7-readiness do front-end — parecer (2026-07-24)

**Veredito: manda bala.** Gates §0.6 da 013 fechados (F6 completa, pin 3.12.2/fmt130,
rulings §12-1/3/4/5). Zero bloqueador. Caminho crítico = saneamento-first (LT-F7a) + wire
do `itac build` com F6 como gate DURO.

## Contrato que a F7 consome — SÓLIDO
- **7 side-tables declaradas E populadas** (`type_table.dart:462-492`; escritas em
  `check.dart`: nº3@1909/1953, nº5@1420, nº6@349/529/601/847/2300, nº7@2195; nº1 total).
  Fonte: spec 013 §7.0.
- **AST completa p/ emissão** (`ast.dart`): todo sum carrega `offset`+`length`; pós-fixos
  carregam `opOffset` (vira `fileOffset` do seletor — 428-431); `Param`+`MapEntryNode`
  carregam span (D2, viram nós posicionados do Kernel). Tipo resolvido NÃO mora no nó (mora
  na nº1 por identidade — correto, ADR-0004).
- **nº8 flowFacts** (`flow.dart:90-107`) — `completesNormally` por `FnDecl|Closure`
  (InitDecl fora; init não cai-do-fim). É o que a F7 lê p/ throw-defensivo.

## Divergências spec×código (o revisor pegou)
1. **`guard`/`guard let` RETIDOS como nó core** (`desugar.dart:197,201`) — mas 013 §7.4e diz
   "`guard`(desaçucarado)". FALSO: não desaçucara. Gabarito do guard-let (bind-na-CONTINUAÇÃO,
   o que barra o desugar por RD-1) NÃO está escrito. Implementável à Swift; fora do CA1-CA13.
   RISCO, não bloqueador. Precedente: 007 T004 (divergência já declarada).
2. **Tuple/record**: 013 §7.4e diz record "a confirmar", MAS a F5 JÁ tem `TupleType`
   semântico (`type.dart:384`) com alvo Kernel `RecordType` documentado; `TupleIndex`→
   `RecordIndexGet`. Decisão está mais fechada que a spec admite. RISCO baixo.
3. **Gate DURO de exaustividade existe como ANÁLISE (sound), não como PIPELINE.** F6 só roda
   em `itac flow` (comando separado); `itac check` NÃO roda F6; `itac build` NÃO EXISTE
   (`driver.dart` acaba em `runFlow`; `codegen/` só `.gitkeep`). Se o implementador copiar
   `checkProgram` (para na F5), match não-exaustivo VAZA pro `.dill`. O `build` TEM de compor
   F1→F6→F7 com F6 abortando. Rede: corpus LT-F6c (`match_not_exhaustive.tu`). RISCO/obrigação.
4. **`globalInitOrder` (Tarjan SCC / `global-init-cycle`) NUNCA implementado** — `FlowResult`
   só tem `errors`+`completesNormally`. Ficou ruling-do-dono aberto (3 modelos) no meu W1 da
   014, nunca virou código. Global top-level com refs cruzadas ⟹ F7 emite em ordem textual
   sem detecção de ciclo. Fora do CA1-CA13 (main-based). RISCO latente.

## Débitos herdados — classificação
- **chão built-ins (.length/[]/+):** LT-012a (F5) DONE, revalidada 862 verde
  (`check.dart:1882` — `builtin-member-unsupported` MORTO). LT-012b (codegen) GATED; gabarito
  pronto (012 §7.2: `InstanceGet(get:length)`/`InstanceInvocation([],+)` via `LibraryIndex`).
  ⚠️ chão só alcança receptor TIPADO — literal-nu ([1,2,3]) ainda `cannot-infer` (fatia C).
  match-sobre-List (CA8) depende de LT-012b + fatia C; já gated em 013 §7.4e. OK.
- **resolution por parâmetro solto (AF4/LT-F7b):** `CheckResult` não carrega a F4
  (`driver.dart:285-301` descarta; `flowProgram:357-377` segura e passa a `analyzeFlow`).
  F7 precisa do `Ident→binder` (VariableGet). Não-bloqueador: o `build` thread igual ao
  `flowProgram`. Promover a campo de `CheckResult`/`FlowResult` ANTES. RISCO.
- **async (Await/Spawn/Emit retidos):** gated §12-2 (transformer CFE — verificar antes). OK.
- **`for`/CopyWith/Try retidos:** for gated (`for-binder-unsupported` `check.dart:436`);
  Try/CopyWith têm gabarito (§7.4e/§7.4c). OK.

## Design LT-F7a — COMPLETO e implementável
3 passes de saneamento fundamentados na fonte 3.12.2 (`_LocalFunctionIdAssigner` id≥1 reset
por Member; `_OffsetNormalizer` secundários -1→0; `isFinal ⟺ sem-setter` BIDIRECIONAL).
Ordem: build → 2 visitors → `computeCanonicalNames` → `verifyComponent(ItaVerifyTarget)` →
`BinaryPrinter` fmt130. Trava dura §7.4e: pattern-nodes do Dart 3 PROIBIDOS no .dill cru →
match baixa p/ primitivos. Driver CommandRunner: decidido (W0), NÃO implementado
(`bin/itac.dart:32` ainda switch manual) — é parte da LT-F7a, não bloqueio.
