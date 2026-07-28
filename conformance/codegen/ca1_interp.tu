// **CA1 da spec 013 §11**, literal: `fn main() { print("olá, ${1 + 1}") }` ⟶
// stdout `olá, 2`, exit 0. Exercita interpolação (`StringConcatenation`) + `Int`
// (`IntLiteral`) + aritmético (`InstanceInvocation` de `dart:core::num`).
//
// A conversão `Int`→`String` da parte interpolada é da VM (`StringBase._interpolate`),
// NÃO um `toString()` que emitimos — se um dia emitirmos, este golden não muda,
// mas o `.dill` sim (ver §7.4-a).

fn main() {
  print("olá, ${1 + 1}")
}
