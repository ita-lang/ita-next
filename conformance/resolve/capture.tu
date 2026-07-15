// CA2 — captura: `x` usado dentro da closure cruza a fronteira de fn → hops 1,
// capturado (marca `*` no dump).
fn outer(xs) {
  let x = 1
  let ys = xs.map { x }
}
