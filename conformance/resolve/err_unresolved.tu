// CA4 — unresolved-name: uso de nome não-declarado (Itá é estático → erro de
// compilação, diverge do Lox que adia p/ runtime).
// EXPECT-ERROR: unresolved-name
fn main() {
  let y = bogus
}
