// CA5 — read-in-own-initializer: `let a = a` (split declare/define, CI 11.3.2).
// EXPECT-ERROR: read-in-own-initializer
fn main() {
  let a = a
}
