// CA12 — gensym: `a ?? b` vira `match a { .some($x0) => $x0, .none => b }`. O
// gensym `$x0` resolve como binder ORDINÁRIO (hops 0), sem tratamento especial.
fn main() {
  let a = 1
  let b = 2
  let r = a ?? b
}
