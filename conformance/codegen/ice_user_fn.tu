// FRONTEIRA HONESTA (§7.8) — a PRÓXIMA fatia da §7.4-a: `fn` do usuário
// (`Procedure` static) e sua chamada (`StaticInvocation` pela side-table nº5).
//
// Hoje `emitMain` só aceita `main` no topo; qualquer outro item vira ICE. Quando
// o gabarito nascer, este fixture DEIXA de dar 70 e o runner acusa — o sinal para
// promovê-lo a CA verde com o seu `.out`.
//
// EXPECT-ICE: ice-codegen-toplevel-FnDecl

fn dobro(x: Int) -> Int => x * 2

fn main() {
  print("dobro=${dobro(21)}")
}
