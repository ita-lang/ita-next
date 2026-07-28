// §7.4-b — `let`/`var` locais (`VariableDeclaration` filha direta do `Block`) e
// uso (`VariableGet`, via a 2ª side-table `binder → VariableDeclaration`).
//
// `let` baixa com `isFinal=true`, `var` com `isFinal=false` (P1/P2 sobrevivem ao
// `.dill`). A REATRIBUIÇÃO de `var` ainda não tem gabarito (`VariableSet` é fatia
// futura) — por isso o `var` aqui só é declarado e lido.

fn main() {
  let nome = "mundo"
  var contador = 3 * 2
  print("olá, ${nome}! contador=${contador}")
}
