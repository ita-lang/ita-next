---
name: f5-export-contract
description: O contrato F5→F7 (ResolvedCall/ResolvedMember/typeArgs/origin) medido contra o Kernel — regra do prefixo ∀ por sítio, e o que ainda falta p/ o codegen
metadata:
  type: reference
---

# Contrato F5 → F7, medido contra o Kernel

Vendor: `ita/third_party/dart/3.12.2/pkg/kernel/lib/`. Tudo abaixo é Classe A (lido do vendor) salvo onde
marcado. **Este arquivo foi re-derivado em 2026-07-15** — a versão do W1 nunca chegou a ser gravada.

## A regra do prefixo ∀ — CONFIRMADA, e é por SÍTIO (não por tipo de nó)

`arguments.types` é cobrado contra **duas listas distintas** (`verifier.dart:1305-1307`):
`target is Constructor ? target.enclosingClass.typeParameters : target.function.typeParameters`.
Mesmo corte em `functions.dart:154-156` (`computeFunctionType`).

| Sítio Itá | Nó Kernel | ∀ vem de |
| :-- | :-- | :-- |
| `init` no corpo | `Constructor` | `Class.typeParameters` |
| `init` em `extension` | **`Procedure`** (não há como pendurar Constructor por retrofit) | `function.typeParameters` |
| método / `fn` top-level | `Procedure` | `function.typeParameters` |
| `static fn` de tipo genérico | `Procedure` static (ou `Factory`) | `function.typeParameters` — **cópia** dos params da classe |
| tipo-função em posição de tipo | `FunctionType` | `FunctionType.typeParameters` : `List<StructuralParameter>` (`types.dart:1090-1094`) |

⟹ o `quantifiers` do Itá **tem imagem em Kernel**, em 3 sítios distintos. **Não é Grupo B**: o Kernel não
infere type-arg nenhum (quem inferia era a CFE, que o Itá bypassa) — `Arguments.types` é lista que NÓS
preenchemos (`expressions.dart:1533-1546`).

## `static` de tipo genérico: o `T` da classe NÃO atravessa

`class A<T> { static m() }` — o `T` **não existe** dentro de `m`. Kernel:
- `verifier.dart:830`: `visitProcedure` faz `classTypeParametersAreInScope = !node.isStatic`.
- `verifier.dart:1505-1511`: `TypeParameterType` cujo `declaration is Class` em contexto static ⟹
  *"Type parameter referenced from static context"*.
- **Não é pedantismo do verifier — é runtime.** A VM resolve param-de-classe via **instantiator type
  argument vector** e param-de-função via **function type argument vector**
  (`runtime/docs/compiler/type_testing_stubs.md`, TTS calling convention). Static **não tem instanciador**.
- E **quebra em SILÊNCIO**: o serializer indexa os params da classe num stack plano e escreve os
  procedures DENTRO desse escopo (`ast_to_binary.dart:1304-1314`) ⟹ o `.dill` sai sem erro. O verifier não
  é rodado pela VM (`verifier.dart:127-129`: *"does not include any kind of type checking"*; `verifyComponent`
  sem chamador em todo o `pkg/`).

**Lowering correta p/ `Stack.nova()`** (static do Itá que usa o `T` da classe): `Procedure` static com
`function.typeParameters = [clone dos params da classe] ++ [params do método]`, corpo substituído
class-`T` → `T'`. É o que o Dart faz com **factory** — factory é `Procedure` (`members.dart:1210,1345`), e
`functions.dart:154-156` só trata `Constructor` de forma especial ⟹ a factory carrega os type params no
próprio `FunctionNode`. Sob essa lowering, a ordem `[∀ do tipo] ++ [∀ do método]` **casa** com
`function.typeParameters`.

⚠️ **Só os params da classe que OCORREM na assinatura.** `struct Stack<T> { static fn versao() -> Int }`
⟹ `function.typeParameters == []` e `arguments.types == []`. Quantificar `T` ali é phantom, e o preço é
duplo: `cannot-infer` falso na F5 **e** aridade errada de `Arguments.types` na F7.

## Onde `signature` (a assinatura substituída) é VIVA

| Forma | Nó | precisa de `functionType`? |
| :-- | :-- | :-- |
| `x.m()` | `InstanceInvocation` | **SIM, `required`** (`expressions.dart:1883`); doc `:1869-1882` exige σ do receptor **e** S dos type-args |
| `f()` local/closure | `FunctionInvocation` | **SIM na prática** — é nullable e cai em `DynamicType()` se ausente (`:2261, 2277-2278`) ⟹ ADR-0013 |
| `f()` top-level | `StaticInvocation` | não — só `{targetReference, arguments, isConst}` (`:2808-2815`) |
| `Box(v:)` | `ConstructorInvocation` | não (`:2898-2904`) |

Ordem dos `typeArgs` é **semântica e ninguém a checa**: `Substitution.fromPairs(target.function.typeParameters,
arguments.types)` (`expressions.dart:2846-2852`) é posicional ⟹ ordem errada = tipo trocado em silêncio, com a
aridade batendo.

## Dispatch — o achado que continua de pé

**Membro que participa de conformance TEM de ser baixado DENTRO da `Class`.** `_checkInterfaceTarget`
(`verifier.dart:1604-1625`) exige que o `interfaceTarget` seja instance member **com `enclosingClass`**. Se
`impl Tr for A { fn m() }` for baixado como top-level static com `#this`, a `Class A` fica sem `m` ⟹
`v.m()` com `v: Tr` cai em NoSuchMethod em runtime (a seleção da implementação é vtable = **Grupo B**, não
temos como corrigir do lado de cá). F5 entrega o necessário para essa decisão: `TypeInfo.traits`/`sources`
+ `MethodInfo.origin` + `MethodInfo.decl`.

## Obrigações de F7 que F5 não precisa alimentar (chore, não lacuna)

- `TypeParameter.bound` **e** `defaultType` são obrigatórios em todo type param (`verifier.dart:340-354`).
- `FunctionType.namedParameters` **"Must be sorted"** (`types.dart:1094`) ≠ ordem-fonte dos params do Itá.
- `positionalParameters` só trunca do FIM (`requiredParameterCount`, `functions.dart:41-43`;
  `verifier.dart:1338-1342`) ⟹ "default saltável no meio" do Itá só cabe em **named**.

## Lacunas conhecidas (2026-07-15)

Ver [[f5-gaps-2026-07]] para a lista com prioridade. As duas de fundo:
1. **`init` de `extension` não tem decl nem origin** (`TypeInfo.extensionInits` é `List<FunctionType>`) —
   F7 não acha o alvo do `StaticInvocation.targetReference`, que é non-nullable.
2. **`GenericParam.bounds` é `List<TypeNode>`** (`ast.dart:690-694`; `parser.dart:616-620` aceita `T: A + B`)
   e a F5 **descarta**. `TypeParameter.bound` do Kernel é **singular** (`types.dart:82`) ⟹ multi-bound **não
   tem imagem em Dart**.
