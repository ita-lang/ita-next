---
name: ctor-init-lowering
description: Como o corpo de um `init` do Itá pode virar Kernel — ordem initializers×body confirmada na VM, as 6 formas de Initializer (sealed), o contrato duro do LocalInitializer (VM+dart2js), e por que campo `final` no .dill não é decoração (Slot::Get immutable bit).
metadata:
  type: reference
---

# `init` com corpo → `Constructor` do Kernel (verificado 2026-07-29, tag 3.12.2)

## Ordem: CONFIRMADA (o `emit.dart:844` acerta o fato, erra a conclusão)
- VM `runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc` — `StreamingFlowGraphBuilder::BuildFunctionBody`:
  `Fragment body; if (constructor) { body += BuildInitializers(...); } if (body.is_closed()) return body;`
  e só DEPOIS lê `FunctionNodeHelper::kBody`. ⟹ **initializers antes do corpo, sempre.**
  (`if (body.is_closed())` = a VM tolera fragmento de initializer que TERMINA em return/throw.)
- Doc: https://dart.dev/language/constructors — *"The right-hand side of an initializer list can't
  access `this`."* + ordem: 1. initializer list, 2. super sem-arg, 3. corpo.
- **O que o comentário do emitter erra**: (i) atribuir campo `final` no corpo não é "malformado", é
  **inexprimível** — `InstanceSet(interfaceTarget:)` → `getNonNullableMemberReferenceSetter` →
  `member.setterReference!` (`src/ast/helpers.dart:147-150`) estoura na CONSTRUÇÃO do nó; malformado
  mesmo é `Field.mutable`+`isFinal=true` (verifier `isImmutable == hasSetter`, `:744-768`);
  (ii) existe forma canônica para intercalar lógica na lista (`LocalInitializer`) — a restrição a
  "só `self.x = e`" é escopo defensável, não necessidade do Kernel.
- **Fato esquecido**: `BuildInitializers` roda ANTES da lista todos os inicializadores de
  DECLARAÇÃO (`Field.initializer`), varrendo `parent_class.fields()` em ordem de `kernel_offset`;
  campo coberto por `FieldInitializer` tem o de declaração avaliado só `only_for_side_effects=true`.
  Hoje inócuo (nossos `Field` não têm initializer) — trava design futuro de "campo com default".

## As 6 formas (`Initializer` é `sealed`, `src/ast/initializers.dart:12`)
| forma | tag | carrega | serve para |
|---|---|---|---|
| `FieldInitializer` | 8 | `Expression` | única escrita de campo pré-corpo; vale p/ campo **final E mutável** (comentário da VM: `var x; A(a,b) : x = 2*b`) |
| `LocalInitializer` | 11 | `VariableDeclaration` | avaliar expressão arbitrária NA POSIÇÃO textual |
| `AssertInitializer` | 12 | só `AssertStatement` (`:368`) | nada (gated por `--enable-asserts`) |
| `Super`/`Redirecting` | 9/10 | `Arguments` | n/a hoje |
| `InvalidInitializer` | 7 | msg | erro |

## Contrato DURO do `LocalInitializer` (os dois consumidores concordam)
- Escopo: *"in scope for the remainder of the initializer list, but is **not** in scope in the
  constructor body"* (`initializers.dart:321-324`). dart2js confirma: guarda em `_letBindings`.
- **Precisa de initializer não-nulo**: VM `case kLocalInitializer:` faz
  `Tag tag = ReadTag(); if (tag != kSomething) { UNREACHABLE(); }`; dart2js `variable.initializer!`.
- **Precisa `isFinal`** (dart2js `assert(variable.isFinal)`) e **não pode ser const**
  (VM `ASSERT(!helper.IsConst())`). ⟹ `VariableDeclaration.forValue(expr)` bate exato:
  `isFinal=true, isConst=false, type=DynamicType, isSynthesized=true` (`src/ast/statements.dart:1730-1751`).
- O CFE **usa** essa forma: comentário verbatim da VM no `case kLocalInitializer` mostra
  `A(a,b) : super(a+b), x = 2*b` sendo convertido em `A(a,b) : tmp = a+b, x = 2*b, super(tmp)`.
- dart2js: `pkg/compiler/lib/src/ssa/builder.dart::_buildInitializers` trata `ir.LocalInitializer`
  explicitamente (sem `failedAt`). Paridade OK para a forma nua.
- `VariableDeclaration` é filho legal de `LocalInitializer` (`verifier.dart:1153-1160`).

## Por que campo `final` no `.dill` não é decoração
- VM `runtime/vm/compiler/backend/slot.cc`, `Slot::Get(const Field&…)`:
  `IsImmutableBit::encode((field.is_final() && !field.is_late()) || field.is_const())`.
  Slot imutável = load forwarding/CSE através de efeitos. `late` **não** ganha.
- ⟹ trocar `let`-campo por campo mutável (para poder `InstanceSet` no corpo) paga em otimização
  E apaga a promessa do `let` do artefato.

## `late final` (a saída "sancionada pelo Dart" p/ atribuir no corpo) — NÃO usar
- Verifier deixa: `isImmutable = isLate ? (isFinal && initializer != null) : …` ⟹ `late final` sem
  initializer é MUTÁVEL p/ o verifier ⟹ tem setter ⟹ `InstanceSet` funciona.
- Mas `late` é **lowering do CFE por Target** (`lib/target/targets.dart:435-458`,
  `enabledLateLowerings`/`isLateFieldLoweringEnabled`) — emitindo Kernel cru nós NÃO rodamos esse
  transformer: é a classe-1 de armadilha (ver [[kernel-raw-api-field-hygiene]]) e landmine de
  paridade JS. Mais: sentinel-check por leitura + `LateInitializationError` novo modo de falha.

## Ninguém confere por nós
- `checkInitializers(Constructor)` é VAZIA (`verifier.dart:2194-2196`); o TODO do próprio Kernel
  (`initializers.dart:111-112`) diz que **o front-end** deve checar "todo campo final inicializado
  exatamente uma vez" e "nenhum campo atribuído duas vezes na lista".
- O algoritmo da VM casa `constructor_initialized_field_offsets` (ORDENADO) contra `class_fields`
  avançando um índice por igualdade ⟹ `FieldInitializer` duplicado desalinha o casamento.
- Campo não-nulável nunca escrito antes do corpo: `dart.dev/tools/diagnostics/not_initialized_non_nullable_instance_field`
  — o CFE proíbe; Kernel assim está fora do envelope testado da VM/AOT.

## Recomendação registrada (W1/W3, não implementada)
**Híbrido com corte no ÚLTIMO `self.campo = e`**: prefixo → `initializers` na ordem textual
(`ExprStmt`→`LocalInitializer(forValue(...))`, `Assign`→`FieldInitializer`); sufixo → `function.body`
(o `_block`/`_stmt` do emitter já existe). Gates obrigatórios no prefixo: sem leitura de `self`,
sem fluxo não-local (`?`/`Try` emite `ReturnStatement`), sem `let` que precise atravessar o corte,
sem campo repetido. Ver [[kernel-verifier-invariants]] e [[parity-js]].
