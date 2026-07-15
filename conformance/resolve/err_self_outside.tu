// CA8 (erro) — self-outside-method: `self` fora de método (fn top-level).
// EXPECT-ERROR: self-outside-method
fn free() -> Int => self
