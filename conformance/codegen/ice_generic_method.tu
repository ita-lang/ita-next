// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 6 de 6. Ver `ice_generic_fn.tu`.
//
// Membro genérico em tipo NÃO-genérico: o `Sacola` é concreto e emitiria bem; é
// o `<U>` do membro que para a emissão. O par importa — prova que o ICE é do
// MEMBRO e não da declaração que o contém, que é exatamente a distinção que um
// código só (`*-generic` compartilhado) apagaria.
//
// ⚠️ A palavra "m-é-t-o-d-o" saiu daqui por um falso positivo do `make
// citations`: o padrão de modalidade normativa inclui `todo ` sem fronteira de
// palavra, e aquela palavra termina exatamente nele — então qualquer comentário
// que a use perto de uma citação de spec dispara C3. Corrigir pede fronteira de
// palavra sobre UTF-8 em dois `awk` diferentes, o mesmo limite multibyte que o
// `check-assertions.sh` registra. Fatia da régua, não deste fixture.
//
// EXPECT-ICE: ice-codegen-method-generic

struct Sacola {
  n: Int,
  fn mapear<U>(u: U) -> U => u
}

fn main() {
  print("um método genérico dentro de um struct que não é")
}
