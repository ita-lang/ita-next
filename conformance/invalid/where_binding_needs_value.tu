// No `where` o init é OBRIGATÓRIO (grammar §whereBinding). O caso que SÓ esta
// regra pega é o **`var`**: `var y` sem init é legal num bloco (é slot — enche
// depois), mas `where` é EXPRESSÃO e não há "depois". Sem a guarda, a Fase 3
// fabricava `match nil { y => V }`, ligando `y` a nil real sob tipo não-opcional
// (viola nullity-invariant: nil só sob `T?`).
//
// Δ 2026-07-15 (ruling do dono, spec 009 §12-7): `where { let y }` agora morre
// ANTES, em `let-requires-value` — o `let` exige valor em QUALQUER lugar, então o
// `where` nem precisa opinar (ver `invalid/let_requires_value.tu`). Esta fixture
// passou a exercitar o `var`, que é o que sobrou de exclusivo do `where`.
let r = y where { var y }
// EXPECT: parse-error: where-binding-needs-value @707+5
