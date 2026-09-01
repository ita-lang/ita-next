// **CA1 da spec 012 §11** — `.length` de `List` ⟶ `3`.
//
// Emite `InstanceGet(xs, Name('length'), interfaceTarget = dart:core::List::length)`
// (spec 012 §7.2), com `resultType` = `int`.
//
// ⚠️ **A forma NÃO é a da letra do CA.** A spec escreve o receptor como literal
// nu — `print("${[10, 20, 30].length}")` —, e essa forma **não chega à F7**:
// medido em 2026-08-31, ela para na F5 com `check-error: cannot-infer @23+12`
// (exit 65). O receptor de um `.length` é posição **sem esperado**, e a errata
// da spec 010 §4.1 cobre só as três que têm um (`let` anotado, argumento de
// parâmetro tipado, retorno anotado). Não é lacuna da emissão: é a metade do
// literal nu que segue sob decisão pendente do dono, registrada em
// `specs/012-builtin-members/tasks.md:67`.
// O corte está preso por `chao_literal_nu.tu`, que fica VERMELHO no dia em que
// o ruling mudar.
//
// O golden não saiu do nosso emitter: `[10,20,30].length` em Dart puro, no
// `dart` do pin (3.12.2), imprime `3`.

fn main() {
  let xs: List<Int> = [10, 20, 30]
  print("${xs.length}")
}
