// **CA2 da spec 012 §11** — `[]` de `List` ⟶ `20`.
//
// Emite `InstanceInvocation(xs, Name('[]'), Arguments([1]),
// interfaceTarget = dart:core::List::[])` (spec 012 §7.2). O tipo do nó sai de
// `functionType.returnType` — `InstanceInvocation` **não tem** campo
// `resultType` (esse é do `InstanceGet`), e o `functionType` tem de ser o
// SUBSTITUÍDO: emitir o genérico dá dois `problem`s no `verifyComponent`
// (`.claude/agent-memory/dart-vm-expert/builtin-members-ground-012.md`).
//
// ⚠️ Receptor tipado em vez do literal nu da letra do CA — a razão medida está
// em `chao_length.tu`, e o corte está preso por `chao_literal_nu.tu`.
//
// Golden do oráculo Dart no pin 3.12.2: `<int>[10,20,30][1]` imprime `20`.
//
// Este é o par IN-BOUNDS do `chao_oob.tu`: sozinho, um deles fecharia verde
// sobre um `[]` que só acerta um dos dois lados.

fn main() {
  let xs: List<Int> = [10, 20, 30]
  print("${xs[1]}")
}
