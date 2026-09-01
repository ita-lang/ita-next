// **CA3 da spec 012 §11** — `+` de `List`, encadeado com `.length` ⟶ `3`.
//
// Emite `InstanceInvocation(a, Name('+'), Arguments([b]),
// interfaceTarget = dart:core::List::+)` (spec 012 §7.2), e o `InstanceGet` do
// CA1 sobre o RESULTADO. É o fixture que prova que o chão COMPÕE — o receptor
// do `.length` aqui não é um local, é o valor devolvido pelo `+`.
//
// É também o caso em que o `functionType` substituído decide: `List<E>::+` é
// genérico em `E`, e emitir o não-substituído dispara
// `assert(functionType.typeParameters.isEmpty)` de `expressions.dart:1912`.
// A receita é `Substitution.fromInterfaceType` sobre o tipo do receptor vindo
// da side-table nº1.
//
// ⚠️ Receptores tipados em vez dos literais nus da letra do CA — razão medida em
// `chao_length.tu`.
//
// Golden do oráculo Dart no pin 3.12.2: `(<int>[1,2] + <int>[3]).length` ⟶ `3`.

fn main() {
  let a: List<Int> = [1, 2]
  let b: List<Int> = [3]
  print("${(a + b).length}")
}
