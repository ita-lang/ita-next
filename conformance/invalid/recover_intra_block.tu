// D1 — recuperação intra-bloco: `let` sem pattern vira error-stmt; o statement
// seguinte recupera NO MESMO bloco (sem engolir `}`), e o `fn g` de topo parseia
// (sem cascata). Um único erro reportado.
fn f() {
  let
  let y = 2
}
fn g() => 3
// EXPECT: parse-error: expected-pattern @222+3
