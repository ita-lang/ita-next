// CA6 — duplicate-declaration: redeclaração no MESMO escopo (shadowing aninhado
// seria OK — ver shadowing.tu).
// EXPECT-ERROR: duplicate-declaration
fn main() {
  let x = 1
  let x = 2
}
