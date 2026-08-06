// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 2 de 6. Ver `ice_generic_fn.tu`.
//
// `struct` genérico: a `Class` do Kernel precisaria de `typeParameters` e o
// campo `valor` de um `TypeParameterType`. Nada disso é emitido hoje.
//
// ⚠️ **Este fixture também é a razão de `type-generic` (`emit.dart:1867`) não
// ter catraca.** Aquele ICE guarda o USO (`let c: Caixa<Int>`), e o uso nunca é
// alcançado: a declaração é emitida antes e para aqui. Não é impossibilidade —
// é ordem: `type-generic` vira alcançável no dia em que a emissão de `struct`
// genérico nascer, e a catraca dele nasce nessa fatia, não nesta.
//
// EXPECT-ICE: ice-codegen-struct-generic

struct Caixa<T> { valor: T }

fn main() {
  print("uma caixa que a emissão ainda não sabe abrir")
}
