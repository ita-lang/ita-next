// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 5 de 6. Ver `ice_generic_fn.tu`.
//
// `trait` genérico: a fatia é a mais acoplada das seis, porque o trait vira a
// interface do dispatch existencial (ADR-0017) — parametrizá-lo mexe no mesmo
// lugar que o CA4/CA6/CA11 esperam. Declarada aqui para que a ordem entre as
// duas fatias seja uma decisão, não um acidente.
//
// EXPECT-ICE: ice-codegen-trait-generic

trait Cmp<T> {
  fn cmp(o: T) -> Int
}

fn main() {
  print("um trait genérico que a emissão ainda não sabe declarar")
}
