// **`c.s += "x"` sobre campo `String`** — o TERCEIRO sítio do `+`.
//
// O irmão de `chao_string_compound.tu`, e ele existe separado por uma razão que
// já custou caro neste arquivo: a decisão do alvo do `+` estava escrita em
// **três** lugares — `_binary`, `_assign` (local) e `_assignMember` (campo). A
// primeira correção pegou um; a revisão adversarial pegou o segundo; o terceiro
// só não repetiu a história porque a cura passou a ser uma função só
// (`_compoundTarget`), chamada pelos três.
//
// Um fixture por sítio, e não um só: eles emitem árvores diferentes — aqui o
// receptor do `+` é um `InstanceGet` sobre um temporário hoistado, não um
// `VariableGet` —, e um fixture de local jamais exercitaria este caminho.
//
// `class` e não `struct` porque campo de `struct` é `final` pelo ruling da
// spec 013 §12-1, e a F5 barraria com `assign-to-immutable` antes da emissão.
//
// Golden do oráculo Dart no pin 3.12.2: `'ita' + '-lang'` ⟶ `ita-lang`.

class Buf {
  var s: String

  init(inicial: String) {
    self.s = inicial
  }
}

fn main() {
  let b = Buf(inicial: "ita")
  b.s += "-lang"
  print(b.s)
}
