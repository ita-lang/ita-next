// CA7 — shadowing aninhado: o `x` interno vence (hops 0 = mesmo escopo do `let
// x = 2`, prova que NÃO ligou ao `x` externo, que teria hops > 0).
fn main() {
  let x = 1
  {
    let x = 2
    let y = x
  }
}
