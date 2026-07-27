---
name: kernel-localfunctionid
description: Contrato do LocalFunctionId de closures no Kernel — valores, escopo por Member, quem é Member (3.12.2)
metadata:
  type: reference
---

# LocalFunctionId (closures) — contrato Kernel 3.12.2

`expressions.dart:4987-5021`:
- `LocalFunctionId.invalid = 0`, `first = 1`.
- `LocalFunctionIdGenerator`: `_counter = first(1)`; `allocateId() => _counter++`; `isValidId(id) => id > 0 && id < _counter`.
- Doc: "Unique identifier of this function within a **[Member]**" (4992) — escopo é POR MEMBER.
- Serializado: `writeUInt30(node.id.toInt())` em FunctionExpression (`ast_to_binary.dart:2205`) e FunctionDeclaration (2518). id=0 serializa sem erro.

**Member em 3.12.2 = EXATAMENTE Field, Constructor, Procedure** (`sealed class Member`, `members.dart:11`; subclasses 267/558/917). `RedirectingFactory` NÃO é Member (só `RedirectingFactoryTarget`, helper em Procedure, `members.dart:1349`). Logo resetar o contador em Procedure/Constructor/Field cobre TODOS os members.

**O verifier NÃO checa LocalFunctionId** (grep vazio em verifier.dart). Invariante id≥1/distinto-por-member é puramente VM-side (Grupo B): `runtime/vm/closure_functions_cache.cc` NÃO está no vendor — claim de colisão não-verificável no vendor, mas o contrato Kernel (invalid=0, first=1, isValidId>0) fundamenta que id=0/duplicado é inválido.

Distinção por member basta p/ correção (chave de cache é por member); o valor exato não precisa bater com o CFE.
