// CA10 — guard-let = escopo de continuação: `v` liga no escopo ATUAL a partir
// dali; o `let w = v` seguinte enxerga o bind (o `else` NÃO enxergaria).
fn check(o) {
  guard let v = o else { return }
  let w = v
}
