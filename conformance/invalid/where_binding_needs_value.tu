// No `where` o init é OBRIGATÓRIO (grammar §whereBinding): `let y` sem valor é
// legal num bloco (declara agora, atribui depois), mas `where` é EXPRESSÃO — não
// há "depois". Sem esta guarda a Fase 3 fabricava `match nil { y => V }`, ligando
// `y` a nil real sob tipo não-opcional (viola nullity-invariant: nil só sob `T?`).
let r = y where { let y }
// EXPECT: parse-error: where-binding-needs-value @347+5
