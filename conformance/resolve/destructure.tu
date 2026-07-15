// CA11 — destructuring: `a` e `b` ligam a binders DISTINTOS (offsets diferentes
// no dump). List-pattern dá um BindPattern por nome.
fn main() {
  let xs = [1, 2]
  let [a, b] = xs
  let s = a
  let t = b
}
