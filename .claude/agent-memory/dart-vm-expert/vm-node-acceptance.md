---
name: vm-node-acceptance
description: O TESTE certo para saber se a VM aceita um nó Kernel no .dill cru (não é o binary.md!) — BlockExpression aceito, pattern-nodes rejeitados; e a regra do ConstantExpression em default de parâmetro (constant_reader.cc), com os 3 sítios que exigem constante.
metadata:
  type: reference
---

# O que a VM ACEITA num `.dill` cru — o critério, e os casos verificados (3.12.2, 2026-07-29)

## O critério (a lição de método — vale mais que os casos)
**`binary.md` / `KERNEL_TAG_LIST` NÃO são prova de aceitação.** Contraexemplo direto: `IfCaseStatement`
(tag 149, `binary.md:1918`) e `PatternSwitchStatement` (tag 147, `:1945`) estão no `binary.md`
vendorado E no `runtime/vm/kernel_binary.h` — e são exatamente os que a VM rejeita. Estar no formato =
serializa; não = executa.

**O teste real:** existe um `case k<Nó>:` que constrói IL em `StreamingFlowGraphBuilder::BuildExpression`
/ `BuildStatement` (`runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc`)? Se cai no bloco
"internal to the front end" ou no `default: ReportUnexpectedTag`, o nó é proibido.

## Casos verificados por WebFetch @tag 3.12.2
- **`BlockExpression` (tag 82) — ACEITO**: `case kBlockExpression: return BuildBlockExpression();` em
  `BuildExpression`. É o gabarito do `?` do Itá (`_try`, early-return dentro de expressão). Também tem
  suporte de 1ª classe no vendor (`verifier.dart`, `ast_to_binary`, `ast_from_binary`, `clone`,
  `type_checker`) ⟹ nenhum transformer do caminho VM o remove.
  ⚠️ O `ReturnStatement` DENTRO do `Block` do `BlockExpression` é o ponto incomum — não achei proibição,
  mas a evidência é EMPÍRICA (roda), não documental.
- **`FunctionExpression` (tag 52) / `FunctionInvocation` (125) / `LocalFunctionInvocation` (127) — ACEITOS**:
  `case kFunctionExpression: return BuildFunctionExpression();` etc. em `BuildExpression` (@3.12.2).
  Ver [[closures-kernel]].
- **`FunctionTearOff` (tag 126) — REJEITADO**: `case kFunctionTearOff: // Removed by lowering kernel
  transformation. UNREACHABLE();`. Quem o remove é `pkg/vm/lib/modular/transformations/lowering.dart`
  (`visitFunctionTearOff → return node.receiver`) — transformer do caminho VM que o Itá NÃO roda.
  Mesma lowering também mexe em `AsExpression`, `ListLiteral`, `ForInStatement`, `StaticInvocation`
  (factory specializer) e late-var-init.
- **`kIfCaseStatement` / `kPatternSwitchStatement` / `kPatternVariableDeclaration` — REJEITADOS** em
  `BuildStatement`, com o comentário "These nodes are internal to the front end and removed by the
  constant evaluator". (O detalhe "mesma cláusula do `ForInStatement`" que a spec 013 §7.4-e afirma
  NÃO foi confirmado — o fato da rejeição, sim.)

## Default de parâmetro TEM de ser `ConstantExpression` — a regra exata
- Erro observado: *"Not a constant expression: unexpected kernel tag SpecializedIntLiteral"* ⟸
  `runtime/vm/compiler/frontend/constant_reader.cc::ConstantReader::ReadConstantExpression()`, que
  aceita SÓ `kConstantExpression`, `kFileUriConstantExpression`, `kInvalidExpression`; o `default:` é
  o `H.ReportError(...)` com essa string.
- Quem chama para defaults: **`StreamingFlowGraphBuilder::SetupDefaultParameterValues()`**
  (kernel_binary_flowgraph.cc) — para cada param opcional (posicionais além do `requiredParameterCount`
  e **todos** os named) lê a tag; `kSomething` ⟹ `constant_reader_.ReadConstantExpression()`; senão null.
  Guarda em `parsed_function()->set_default_parameter_values(...)`.
- ⚠️ **Não é "const-evaluable", é o NÓ certo**: `IntLiteral` é constante em espírito e morre igual. E
  **não é no LOAD** — é na construção do FLOWGRAPH da função (JIT: 1ª chamada; AOT: compilação) ⟹
  default malformado em `fn` nunca chamada passa despercebido no JIT.
- **Os 3 sítios que passam pelo MESMO leitor** (checklist de emissão): (1) defaults de param
  (SetupDefaultParameterValues); (2) **annotations** (`ConstantReader::ReadAnnotations()` — o Itá não
  emite, P6); (3) initializer de field **`isConst`** (`ConstantReader::ReadConstantInitializer()`).
- **NÃO se aplica** a `static final` NÃO-const: `kernel_loader.cc::ReadInitialFieldValue()` devolve
  `Object::sentinel()` ("Static fields with initializers are implicitly late") + getter implícito
  ⟹ o initializer é COMPILADO como corpo (lazy), não lido como constante. Por isso
  `Field.immutable(isStatic: true, initializer: ConstructorInvocation(...))` (constantes de enum) roda.
  Custo: 1 sentinel-check por leitura. Ver [[const-globals-f6-kernel]] para o caminho `isConst`
  (exige inline em TODO uso — `verifier.dart:1237-1242`, e o gate do Itá roda em
  `afterModularTransformations` > `afterConstantEvaluation` ⟹ `afterConst == true`).

## Gaps DECLARADOS (não fechados nesta rodada)
- **`AsExpression.isUnchecked`**: a flag existe (`expressions.dart:3939-4000`) e é serializada
  (`binary.md:1010-1016`, `Byte flags (isTypeError,isCovarianceCheck,isForDynamic,isUnchecked)`), mas
  **não consegui ler `BuildAsExpression`** (WebFetch trunca o `.cc` antes). NÃO afirmar que a VM elide
  o check. Recomendação: não marcar — é transferência de soundness, e o custo já é atacado pelo Grupo B
  (`runtime/docs/compiler/type_testing_stubs.md`: range check de ClassId inline / TTS).
- **dart2js × `BlockExpression`**: não confirmei `visitBlockExpression` em
  `pkg/compiler/lib/src/ssa/builder.dart` (truncado). Como o `?` (P7) inteiro depende do nó, é risco de
  paridade ADR-0005 a fechar antes de prometer o alvo JS.
