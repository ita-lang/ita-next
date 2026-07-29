// EXPECT-ERROR: capture-not-a-fn
//
// **CA NEGATIVO PERMANENTE** — `&` captura FUNÇÃO NOMEADA, e só.
//
// `&x` sobre um local não é captura: o local já É um valor, não há ABI a
// converter. Aceitar em silêncio faria o `&` virar decoração — um glifo que às
// vezes significa algo e às vezes nada é pior que glifo nenhum (P4).

fn main() {
  let x = 5
  let f = &x
  print("${f}")
}
