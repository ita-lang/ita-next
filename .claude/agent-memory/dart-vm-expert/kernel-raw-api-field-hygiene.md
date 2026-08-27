---
name: kernel-raw-api-field-hygiene
description: A classe de bugs mais cara do projeto — montar nós Kernel via a API CRUA do package:kernel deixa campos no default que a VM (loader binário) reinterpreta em execução errada silenciosa OU crash. É DISTINTA do bypass de transformer do CFE. localFunctionId=invalid colapsa closures; fileOffset=-1 dá bus error; Field sem setter + isFinal=false = kernel malformado.
metadata:
  type: reference
---

# Higiene de campo da API crua do `package:kernel` (tag 3.12.2, verificado 2026-07-17)

**A lição mais cara do oracle (`ita/`) — e é uma CLASSE, não um bug.** Duas classes de armadilha
existem ao emitir Kernel direto (bypassando a CFE); a spec 013 §7.1 só nomeia a primeira:

1. **Transformer do pipeline CFE que não roda** (spec 013 §7.1 CAPTUROU): mixin não-achatado
   (`mixin_full_resolution.dart`), `implements int`. Ver [[trait-conformance-lowering]].
2. **Campo que a API crua deixa no DEFAULT e a CFE-builder setaria** (spec 013 NÃO captura — 2026-07-17):
   o loader binário da VM lê o default e executa errado/crasha. Não é transformer — é higiene de nó.

## Os 3 casos verificados da classe 2 (fonte oracle `codegen.dart:80-146` + VM 3.12.2)

- **`localFunctionId` → colapso de closure (O bug de 4 rodadas de spike).**
  - Default: `FunctionDeclaration.id = LocalFunctionId.invalid` (== 0) — VERIFICADO no vendor
    `pkg/kernel/lib/src/ast/statements.dart:2086`; idem `FunctionExpression` em `expressions.dart`.
  - VM: `runtime/vm/closure_functions_cache.cc` (tag 3.12.2, fetch confirmado 2026-07-17) — mapa de
    2 níveis: outer=member envolvente, **inner keyado por `local_function_id`** (Smi). Duas closures no
    MESMO member com id=0 colidem na chave 0 ⟹ a 2ª executa o corpo da 1ª. Quebra compose (`>>`),
    currying, qualquer fn com 2+ closures. (v128/fork keyava por `kernel_offset` — por isso o fork não via.)
  - Fix oracle: passe `_LocalFunctionIdAssigner extends RecursiveVisitor` — `node.id = LocalFunctionId(_next++)`
    em `visitFunctionExpression`/`visitFunctionDeclaration`, `_next` resetado a 1 por Procedure/Constructor/Field.
    Replica o `LocalFunctionIdGenerator` da CFE. Campo SETÁVEL — não exigiu re-arquitetura. v130 39→43, 0 regressão.
  - ⚠️ **`verifyComponent` NÃO pega** (id=invalid é estruturalmente "válido"). Só golden-runner com CA de
    2+ closures/member pega — e nenhum CA1–CA13 da spec 013 exercita isso (falta CA compose/curry).

- **`fileOffset` secundário = -1 → bus error (BUS_ADRALN) na finalização.**
  - `TreeNode.noOffset == -1`. O oracle normaliza (`_OffsetNormalizer`) TODOS os offsets secundários:
    `Class.startFileOffset/fileEndOffset`, `Constructor.startFileOffset/fileEndOffset`,
    `Procedure.fileStartOffset/fileEndOffset`, `Field.fileEndOffset`, `FunctionNode.fileEndOffset`,
    `Block.fileEndOffset` → 0 se noOffset. Crash é CUMULATIVO (*"só estoura quando há nós suficientes"*)
    ⟹ latente, aparece em escala, não no hello. Spec 013 §7.1 só cobre o `fileOffset` PRIMÁRIO (spans da F3);
    os secundários não vêm todos do range `(offset,length)`.

- **`Field.immutable` → `setterReference=null` mas `isFinal=false` = kernel malformado, VM rejeita.**
  - Todo campo sem setter TEM de ser `isFinal=true`. Ver [[kernel-verifier-invariants]]. Spec 013 §7.4c
    faz struct all-final (tangencia o caso), mas `class` com campo sem `var` pode cair nele.

## Reconfirmação fresca 2026-07-19 (W1 da F7, design-only) — fonte VM + vendor
- **`ClosureFunctionsCache` keying — VERIFICADO por WebFetch na tag 3.12.2** (`runtime/vm/closure_functions_cache.cc`):
  mapa de 2 níveis. Outer = `function.GetOutermostFunction()` (o Member envolvente). Inner =
  `Smi::New(local_function_id)`. `LookupClosureFunctionLocked`: `map2.GetOnull(Smi(local_function_id))`;
  `AddClosureFunctionLocked`: `map2.UpdateOrInsert(Smi(local_function_id), function)`. ⟹ 2 closures no MESMO
  member com id=0 colidem na chave Smi(0): a 2ª lê a 1ª. Confirmado, não é memória de treino.
- **`LocalFunctionIdGenerator` do CFE (vendor `expressions.dart:4998-5020`)**: `invalid = 0`, `first = 1`;
  `allocateId() => _counter++` começando em `first`; `isValidId ⟺ _value > 0`. UM generator por Member.
  ⟹ o `_LocalFunctionIdAssigner` (reset a 1 por Procedure/Constructor/Field, `id = _next++`) é a réplica EXATA.
- **Defaults confirmados**: `FunctionDeclaration.id = LocalFunctionId.invalid` (`statements.dart:2086`);
  `FunctionExpression.id = LocalFunctionId.invalid` (`expressions.dart:5031`). Ambos default 0 = o furo.
- **Quando rodam os 3 passes**: como último `RecursiveVisitor` sobre o `Component`, DEPOIS de toda a
  construção de nós e ANTES de `computeCanonicalNames`/`BinaryPrinter` (oracle `codegen.dart:79-146`).
  `computeCanonicalNames` religa referências; os passes de higiene só tocam campos escalares (id, offsets,
  isFinal) — ordem entre eles é indiferente, mas ambos antes do print.

## Confirmações frescas F7 W1 (2026-07-20, vendor 3.12.2 + WebFetch VM)
- **Assimetria de nome do offset de início** (foot-gun p/ a spec): `Procedure.fileStartOffset` (`members.dart:925`)
  MAS `Constructor.startFileOffset` (`:566`) e `Class.startFileOffset` (`declarations.dart:34`). O oracle acerta
  (`_OffsetNormalizer` usa `node.fileStartOffset` p/ Procedure, `node.startFileOffset` p/ os outros).
  `fileEndOffset` mora no base `Member` (`members.dart:17`) ⟹ Field/Constructor/Procedure herdam.
  No ESQUELETO (Procedure/FunctionNode/Block) os secundários são: `Procedure.fileStartOffset`+`fileEndOffset`,
  `FunctionNode.fileEndOffset` (`functions.dart:19`), `Block.fileEndOffset` (`statements.dart:91`). Todos existem na 3.12.2.
- **Mecanismo do bus error ATERRADO** (WebFetch `runtime/vm/kernel_loader.cc` @ 3.12.2): `GenerateFieldAccessors`
  usa `field_helper->end_position_` (= `Field.fileEndOffset` lido do binário) p/ `getter/setter.set_end_token_pos(...)`.
  ⟹ `fileEndOffset==-1` vira `end_token_pos` inválido no getter/setter sintetizado → crash cumulativo na finalização.
  Confirma a diagnose do oracle (`codegen.dart:73-78`), não é memória de treino.
- **`id` mora em `LocalFunction`** (`expressions.dart:4988-4994`), implementado por `FunctionExpression` (`:5031`)
  e `FunctionDeclaration` (`statements.dart:2086`) — **NÃO no `FunctionNode`**. `LocalFunctionIdGenerator` @ `:5007-5021`
  (a linha que a spec 013 cita, `:5007`, confere).
- **Ordem no oracle**: `codegen.dart:477-481` = OffsetNormalizer → LocalFunctionIdAssigner → `computeCanonicalNames`.
  ⚠️ **O oracle NÃO chama `verifyComponent`** — a F7 ADICIONA o gate (CA12), não porta. Ver [[kernel-verifier-invariants]].
- **isFinal fica DENTRO do `_OffsetNormalizer`** (`codegen.dart:101-103`): os "3 passes" da spec são fisicamente
  2 `RecursiveVisitor` (offsets+isFinal fundidos, + o assigner). Exit-code do panic: ver [[panic-exit-code]].

## Follow-up (a) do offset SECUNDÁRIO — fundamentado contra o vendor (2026-07-26, W3 F7)
**Veredito: o `-1` secundário NÃO é load-bearing para correção; a premissa "bus error" da §7.1 é
super-generalizada.** Confirmado na fonte vendorada 3.12.2 (não memória de treino):
- `writeOffset` grava `offset+1` **unsigned** (`ast_to_binary.dart:1094-1103`) ⟹ `-1` → wire `0`, lê de
  volta `-1`. **Round-trips legalmente.** `writeVariableDeclaration` serializa `fileEqualsOffset` igual
  (`:2489`); default é `noOffset==-1` (`variables.dart:475`).
- O verifier **só checa o `fileOffset` PRIMÁRIO de nó NOMEADO** — `checkLocation` (`verifier.dart:1806-1824`):
  `name==null || name.contains("#")` retorna cedo; secundários (`fileEqualsOffset`/`fileEndOffset`/
  `startFileOffset`) **nunca** são checados.
- O **único** caminho de crash real é `Field.fileEndOffset` (`kernel_loader.cc::GenerateFieldAccessors`,
  WebFetch W1) — e o `OffsetNormalizer` atual **já o cobre** (`sanitize.dart:67-68`).
- ⟹ A §7.4 pode emitir `Let`-chains (match/`where`/`Try`) com `VariableDeclaration.fileEqualsOffset==-1`
  **sem crash e sem tropeçar no verifier**. O pass defensivo é seguro para a emissão nascer em cima; o
  follow-up (a) **não é gate** — completar (`fileEqualsOffset`+`ForInStatement.bodyOffset`) ou aparar a
  premissa é ajuste de doc/escopo, melhor logo após LT-F7b e antes do grosso da lowering de match.
- ⚠️ **Gap declarado:** confiança é **JIT-load-grounded** (serializer + verifier vendorados). NÃO
  re-verifiquei o **AOT** (`dart compile exe`) — se o DWARF/stack-trace synthesis tratar `-1` diferente,
  o risco reaparece em volume. Fechar antes do bulk de `Let`s.

## Classe 3 (irmã): child atribuído DEPOIS da construção não liga `parent` (2026-07-29)
- No `pkg/kernel` **nenhum** campo-filho tem setter que liga `parent`: quem liga é o CONSTRUTOR, o
  `setParents(...)` e os helpers `addX`. ⟹ toda atribuição tardia (`node.child = x`) exige
  `x.parent = node` na mão, senão `verifyComponent` reprova com *"Incorrect parent pointer"*.
- **`LabeledStatement` é a armadilha porque o design CONVIDA**: `late Statement body` +
  `LabeledStatement(Statement? body)` que só liga o parent `if (body != null)`
  (`statements.dart:304-311`). É o único nó que se constrói vazio e se preenche depois.
- Mesmo padrão, também exigindo parent manual: `FunctionNode.body` (o `_fnBody` do emitter já o faz).
- Onde NÃO precisa: `Class.addField/addProcedure/addConstructor` (`declarations.dart:476-494`),
  `Library.addClass/addProcedure` (`libraries.dart:216-241`), `Component.adoptChildren()`.
- ⚠️ A um passo do bug: `Constructor.initializers` é parenteada **no construtor**
  (`members.dart:592-595`, `setParents`) — um `ctor.initializers.add(...)` posterior NÃO liga parent.

## Regra para a §8/spec 013 (o enquadramento que a spec erra)
A §7.1 INVARIANTE está escrita como *"nenhum transformer do CFE roda"* — enquadramento que pega a classe 1
e CEGA para a classe 2. As duas exigem uma **lista de passes de saneamento pós-construção OBRIGATÓRIOS**
(assigner de localFunctionId + normalizador de offsets + isFinal-sem-setter), rodados antes de
`computeCanonicalNames`/`BinaryPrinter`, com golden estrutural + CA de 2+ closures. É Grupo A puro
(emissão), não Grupo B.
