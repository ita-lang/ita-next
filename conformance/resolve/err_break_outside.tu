// CA9 — break-outside-loop: `break` sem loop envolvente (context-flag, CI 11.5.1).
// EXPECT-ERROR: break-outside-loop
fn main() {
  break
}
