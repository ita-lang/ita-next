// §7.4-a — os cinco aritméticos de `Int`, cada um `InstanceInvocation` de
// `dart:core::num` (os operadores de `int` são HERDADOS de `num`).
//
// ⚠️ **A linha `div` é a trava da armadilha do `double`:** `/` do Itá é
// `Int → Int`, mas `num operator /` devolve **`double`** — por isso o emitter
// baixa `div` para **`~/`**. Se alguém trocar de volta, a saída vira `3.5` e
// ESTE golden é quem denuncia (o `.dill` continuaria verificando).

fn main() {
  print("soma=${1 + 2}")
  print("sub=${10 - 3}")
  print("mul=${6 * 7}")
  print("div=${7 / 2}")
  print("mod=${7 % 2}")
}
