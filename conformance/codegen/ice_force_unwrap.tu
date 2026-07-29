// FRONTEIRA HONESTA (§7.8) — o `!` (force unwrap).
//
// Diferente de `??` e `if let`, que passaram a compilar de graça quando o `match`
// de `Option` nasceu, o `!` **não** passou: ele desugara para um `match` cujo
// braço `.none` chama **`panic`** — e `panic` → `Throw` é o **CA9**, que ainda
// não tem gabarito. Por isso o ICE que sai é `expr-Panic`, não algo de `match`.
//
// É um sinal útil sobre a arquitetura: o desugaring reduz vários operadores ao
// mesmo núcleo, mas cada núcleo tem de existir. `??` precisava só de `match`;
// `!` precisa de `match` E de `panic`.
//
// Quando o CA9 nascer, este fixture fica vermelho e cobra a promoção.
//
// EXPECT-ICE: ice-codegen-expr-Panic

fn main() {
  let x: Int? = 7
  print("${x!}")
}
