// D5 — init opcional na forma bind: **só `var`** (Δ 2026-07-15, ruling do dono,
// spec 009 §12-7). `var` é SLOT mutável ⟹ pode encher depois (definite-assignment
// é F6). `let` LIGA um valor ⟹ exige `= e` — ver `invalid/let_requires_value.tu`.
// A assimetria é P1 virando FORMA: a gramática passa a dizer o princípio.
var count: Int
var ready
let y = 1
