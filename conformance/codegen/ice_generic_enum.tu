// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 4 de 6. Ver `ice_generic_fn.tu`.
//
// `enum` genérico com payload: a classe SELADA e cada subclasse de variante
// precisariam carregar o `T`, e o `IsExpression` do `match` (spec 013 §7.4-e) passaria a
// testar contra um tipo parametrizado. É a mesma peça que falta ao `Result`, que
// hoje contorna emitindo payload como `Object` (`emit.dart:1858-1864`) — o
// contorno é o que esta fatia substitui.
//
// EXPECT-ICE: ice-codegen-enum-generic

enum Talvez<T> { nada, algo(v: T) }

fn main() {
  print("um enum genérico que a emissão ainda não sabe selar")
}
