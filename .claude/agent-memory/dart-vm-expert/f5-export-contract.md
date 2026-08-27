---
name: f5-export-contract
description: O que a F5 (Semântica) tem de EXPORTAR para a F7 (codegen Kernel) — CheckResult (6 tabelas), ResolvedCall, e por que MemberKind/MemberOrigin foram DERRUBADOS (o dado já existe). Inclui a prova de que o verifier do Kernel não faz type-checking e a VM não o roda.
metadata:
  type: reference
---

# Contrato de exportação F5 → F7 (re-verificado 2026-07-15, vendor 3.12.2)

Vendor: `ita/third_party/dart/3.12.2/pkg/kernel/lib/` — ⚠️ o verifier é **`lib/verifier.dart`**,
NÃO `lib/src/verifier.dart`. Nós em `lib/src/ast/{expressions,statements,functions,members,declarations,types}.dart`.

> **STATUS (commit `5e000e3`): parcial.** ✅ split `CollectResult`×`CheckResult`; tabelas 1 `exprTypes`,
> 2 `types`, 3 `resolvedMembers`, 4 `annotations`, 6 `binderTypes`. ❌ tabela 5 `ResolvedCall`;
> ❌ `_freeParams` → ordem declarada. **`MemberOrigin`/`MemberKind` — NÃO fazer (ver abaixo).**
>
> **UPDATE (auditoria 2026-07-17, código lido em `check.dart`/`collect.dart`):** os DOIS ❌ CAÍRAM.
> (a) **nº5 `resolvedCalls` EXISTE** (`check.dart:147/1302`), gravada só no caminho de sucesso.
> (b) **ordem de `typeArgs` CORRIGIDA para DECLARADA**: `quantifiers` vem de `[for g in n.generics]`
> (`check.dart:922-923`, comentário *"a lista DECLARADA, na ordem em que o usuário a escreveu"*;
> métodos idem `collect.dart:531`). `instantiate` cunha `freshVars` 1:1 com `quantifiers`
> (`unify.dart:178`) e `typeArgs=[for v in freshVars]` (`:1304`) ⟹ ordem declarada preservada.
> O bug de `Substitution.fromPairs` posicional (troca de tipo em silêncio, corrompendo TFA) está MORTO
> no lado F5. (c) **`origin` propagado** (`check.dart:1845` `origin: m.origin`, *"era descartado — furo
> de PROPAGAÇÃO"*). **Débito residual F7:** o codegen DEVE emitir `Procedure.function.typeParameters`
> na MESMA ordem `FnDecl.generics` — senão o `fromPairs` do verifier (`expressions.dart:2848`) desalinha.

## O SILÊNCIO — provado, e é maior do que eu tinha escrito
**`verifier.dart:127-129`** (doc do `VerifyingVisitor`): *"Checks that a kernel component is
well-formed. **This does not include any kind of type checking.**"* — literal. Reforços:
- Zero `isSubtypeOf` no verifier. Bound só é checado por estar **setado** (`:340`, `:1580`), nunca satisfeito.
- `VerifyGetStaticType.defaultExpression` (`:2180-2191`) só chama `getStaticType` em try/catch e
  re-lança se **crashar** — não compara com nada. Ordem trocada devolve tipo errado sem crashar ⟹ passa.
  E `verifyComponent` (`:65-79`) nem o instancia.
- **A VM não roda o verifier**: `verifyComponent` não tem **nenhum** chamador em todo o `pkg/`; é Dart,
  a VM é C++. `mrale.ph/dartvm` (Egorov): a VM **confia no CFE**, `kernel::KernelLoader::LoadEntireProgram`
  (`runtime/vm/kernel_loader.cc`) só **deserializa**, lazy. ⟹ **o verifier NÃO é Grupo B.** O Itá bypassa
  a CFE ⟹ herda a confiança sem herdar o verificador. **Recomendação: rodar `verifyComponent` nós mesmos
  nos goldens da F7** — é opt-in e de graça.
- ⚠️ **REFINO (eu tinha subestimado):** `checkTargetedInvocation` só é chamado de `visitStaticInvocation`
  (`:1262`) e `visitConstructorInvocation` (`:1320`). **`visitInstanceInvocation` (`:1628-1638`) NÃO o
  chama** — só `name == interfaceTarget.name` + `_checkInterfaceTarget` (`:1604-1625`). ⟹ em
  `InstanceInvocation` **nem a aridade** de `arguments.types` é checada. Silêncio total.

## Citações re-verificadas (todas confirmadas na linha exata)
- `verifier.dart:1305-1314` — aridade `arguments.types.length == expectedTypeParameters`;
  **Constructor → `enclosingClass.typeParameters`; resto → `function.typeParameters`** (`:1305-1307`).
- `expressions.dart:2848-2851` — `StaticInvocation.getStaticTypeInternal` =
  `Substitution.fromPairs(target.function.typeParameters, arguments.types)` ⟹ **ordem é semântica**.
- `expressions.dart:1883` `functionType` required + doc `:1869-1882` (subst do receptor **e** dos type-args).
  **NOVO `:1912`**: `assert(functionType.typeParameters.isEmpty)` ⟹ signature de Instance vem **já
  instanciado** (e assert só vale em debug).
- `verifier.dart:1337-1354` — `areArgumentsCompatible`: posicional por POSIÇÃO
  (`>= requiredParameterCount` `:1338`, `<= positionalParameters.length` `:1341`), named por NOME (`:1344-52`).
- `expressions.dart:1892` — `InstanceInvocation` exige `required Procedure interfaceTarget`.
- `verifier.dart:1495-1513` — `visitTypeParameterType`: `:1498` out-of-scope, `:1505` static-context.
- **NOVO** `expressions.dart:2261,2277-78` — `FunctionInvocation.functionType` é **nullable** e
  `getStaticTypeInternal => functionType?.returnType ?? const DynamicType()` ⟹ esquecer = `dynamic`
  silencioso (ADR-0013 proíbe).

## `ResolvedCall {slot, typeArgs, signature}` — necessário, **não suficiente**
Falta uma **regra**, não um campo: contra QUAL lista `typeArgs` é ordenado. `verifier.dart:1305-1307`
tem duas listas distintas ⟹ **`init`/nome-de-tipo → `TypeInfo.generics` (da CLASSE)**;
**método/fn → `FnDecl.generics`**. Casa exato com o Constructor×resto do Kernel.
- `signature` é **morto** para `StaticInvocation` (`:2808-2815`) e `ConstructorInvocation` (`:2898-2904`)
  — eles só têm `{targetReference, arguments, isConst}`. Usado só por Instance/FunctionInvocation.
- **Não falta target**: vem da tabela 3 ou de `TopLevelRes.decl`+D2. **Não falta `InstanceAccessKind`**
  (`:1797-1839`): derivável de `exprTypes[receiver]` + `interfaceTarget.enclosingClass`.

### Slot CRU — ruling CONFIRMADO, e a razão é a regra do Itá
`check.dart:1179-1217` (`_matchArgs`) = **"ordem obrigatória, defaults saltáveis" (Swift)** ⟹
`fn f(a, b=2, c)` aceita `f(a:1, c:3)` → slot `[0,2]`, **saltando o param 1 NO MEIO**. Dart não tem
contraparte posicional: `positionalParameters` é `List` + `requiredParameterCount` int
(`functions.dart:41-43`) ⟹ corte só do FIM. Logo:
- baixar **named** ⟹ omitir é legal; default vive em `VariableDeclaration.initializer`
  (**`statements.dart:1487-1492`**: *"For locals, this is the initial value. For parameters, this is
  the default value."*) ⟹ **a VM materializa = Grupo B**.
- baixar **posicional** ⟹ a F7 materializa no call-site (de `FnDecl.params[i].defaultValue`).
Slot cru serve às duas; materializar na F5 fecharia a porta named e jogaria Grupo B fora.

## `MemberOrigin`/`MemberKind` — DERRUBADOS (eu estava errado)
**`MemberKind` não paga aluguel.** O discriminador Kernel é real (`InstanceGet` aceita `Member`
`:579`; `InstanceInvocation` exige `Procedure` `:1892` ⟹ Field de tipo-função é obrigatoriamente
`InstanceGet`+`FunctionInvocation`), mas o **dado já existe**: `FieldInfo.decl` é `ast.FieldDecl`
(`type_table.dart:53`) e `MethodInfo.decl` é `ast.FnDecl` (`:78`) — estáticos, non-nullable
(`collect.dart:324`, `:383`) ⟹ `ResolvedMember.decl` discrimina por type-test. Só pagaria para
built-in sem decl `.tu` (`.length`) — hoje inexistente (zero hard-code no `semantic/`); se
[[chao-vs-biblioteca]] vencer (destino `.tu`), **nunca** paga.

**`MemberOrigin` — eixo errado + dado já existe:**
1. `MethodInfo.origin` (`type_table.dart:80-81`) **já é** "a decl que contribuiu"; o comentário `:63-66`
   até diz que a F7 vai precisar. `_lookup` **descarta** (`check.dart:1514-16` passa `m.decl`, não
   `m.origin`). ⟹ furo de **propagação**, não de modelagem. Propagar o **nó** > enum: o enum não diz
   QUAL extension, e é isso que o D2 (`Decl→Member`) precisa.
2. `{ownDecl, extension, impl}` **não discrimina a emissão**: `ExtensionDecl.traits` existe
   (`parser/ast.dart:178`, conformances inline `: A, B`) e `ImplDecl.trait` (`:170`) é nullable ⟹
   os DOIS podem (ou não) carregar conformance. O eixo sintático corta no lugar errado.

**A pergunta real é estrutural: o membro é baixado dentro da `Class` ou top-level com `#this`?**
- top-level ⟹ `isInstanceMember == false` (`members.dart:1198`) **e** `enclosingClass == null`
  (`members.dart:63`) ⟹ **duas** checagens de `_checkInterfaceTarget` (`verifier.dart:1605-10`,
  `:1618-24`) o barram como `interfaceTarget` ⟹ **só `StaticInvocation`, dispatch ESTÁTICO**.
- mas `check.dart:1751-1765` (`_isSubtype`) dá **`D ≤ Barker` por conformance de trait** ⟹ o Itá tem
  **subsunção** ⟹ `fn faz(b: Barker) { b.bark() }` exige dispatch **dinâmico**. O comentário `:1759-60`
  diz que o despacho (Dragon 1.6.5) é Grupo B — **mas só é Grupo B se o membro estiver na vtable**, e
  ele só está se for membro real da `Class`.
⟹ **Membro que participa de conformance TEM de ser baixado dentro da `Class`**, venha de `extension`
ou `impl`. Top-level+`#this` quebra o despacho **em silêncio**.
⟹ **O Itá não precisa copiar a lowering de extension do Dart** (`declarations.dart:605-608`,
`:764-777` — `B|get#bar(A #this)`): aquilo é a CFE servindo às regras da linguagem Dart (extension é
resolvida estaticamente). O Itá emite Kernel direto ⟹ para T **local** pode baixar tudo na `Class` e
ganhar dispatch de graça. **Isso é pergunta para o `ita-visionary`, não decisão minha.**

### ⚠️ Risco W1 aberto — orphan impl
Para T **foreign** (tipo de outra lib/Dart), baixar na `Class` é **impossível**: Dart não deixa uma
classe existente passar a implementar interface a posteriori. ⟹ **conformance de trait sobre tipo
foreign não tem baixa direta em Kernel**; exigiria witness/dictionary passing (via Rust). Decisão de
linguagem, anterior à F7.

## `TypeParamType` com duas imagens — continua de pé, com ressalva
O split `CollectResult`×`CheckResult` não toca nisso (é sobre o que SAI da fase; as duas imagens são
do **contexto de emissão** na F7). Segue: não distinguir na F5; é ambiente léxico
(`Map<TypeParamType,TypeParameter>` push/pop) na F7. **Ressalva nova:** as duas imagens só existem se a
baixa for **top-level**. Se a F7 baixar o membro dentro da `Class` (caso T local, acima), o `T` é
`TypeParameterType(class.typeParameters[i])` e a 2ª imagem **some**.

## O que a F7 sofre sem `_freeParams` na ordem declarada
`unify.dart:159-162` `instantiate` **descarta** o mapa param→fresca; `check.dart:1252-53` `_freeParams`
usa `Set` ⟹ ordem de **aparição no walk**.
1. **Ordem trocada** (`fn fold<B,A>(xs: List<A>, init: B, ...)`: declarada `[B,A]`, aparição `[A,B]`)
   → `Substitution.fromPairs` (`:2848-51`) casa posicionalmente → **tipos trocados em silêncio**,
   aridade bate ⟹ nem o verifier (se rodasse) pegaria. Em AOT o TFA propaga o tipo errado e
   unboxing/devirtualização decidem sobre ele ⟹ o dano passa do tipo estático.
2. **Aridade errada** (`T` rígido da classe entra no `_freeParams` quando o receptor é `Box<T>` no
   próprio corpo) → só o verifier pegaria (`:1308-14`) — **e ninguém o roda**; e em `InstanceInvocation`
   nem isso.
3. **Passa verde nos testes**: em `map<A,B>(xs: List<A>, f: (A)->B)` aparição == declarada. Só diverge
   quando um param declarado depois aparece antes. ⟹ bug que explode em código real do usuário.
4. Golden da F7 escrito antes do fix **congela a ordem errada**.
Fix: `instantiate` devolve o mapa; `_call` recupera a lista declarada (`FnDecl.generics`, ou
`TypeInfo.generics` p/ `init`) e emite `typeArgs` por ela. `_freeParams` deixa de ser fonte de ordem.
Closure não tem generics (sem let-generalization, §4.4) ⟹ `typeArgs = []`.

Ver [[kernel-verifier-invariants]] · [[binding-sidetable-kernel]] · [[types-nullability-f5]] · [[kernel-nodes]].
