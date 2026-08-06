// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 3 de 6. Ver `ice_generic_fn.tu`.
//
// `class` genérica: além dos `typeParameters` da `Class`, o `init` vira um
// `Constructor` cujo `FunctionNode` referencia o mesmo `T` da classe — o
// `TypeParameter` tem de ser o MESMO objeto nos dois sítios, não uma cópia
// (identidade de nó, como todo o resto do Kernel). É por isso que a fatia é
// distinta da do `struct`, e por isso tem código próprio.
//
// EXPECT-ICE: ice-codegen-class-generic

class Cx<T> {
  valor: T,
  init(valor: T) { self.valor = valor }
}

fn main() {
  print("uma referência genérica que a emissão ainda não sabe montar")
}
