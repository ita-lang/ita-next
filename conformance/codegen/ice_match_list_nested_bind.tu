// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// **FRONTEIRA:** o par de `ice_match_list_nested_test.tu` — a MESMA construção
// (`struct` aninhado em list-pattern), pelo outro caminho.
//
// Aqui o braço aninhado é o **ÚLTIMO**, e no right-fold do `_matchExpr` o último
// braço não ganha teste: ele é o `otherwise`, e quem garante que isso é sound é
// a exaustividade da F6 (§7.4-e, *"exaustividade e unreachable são F6 — a F7
// confia"*). Logo `_elemTest` nunca roda sobre este `P { x: a }`, e a fronteira
// só aparece no bind.
//
// ⚠️ **Sem este segundo caminho, a lacuna sairia como ICE de ESTADO.** O
// `a` do pattern seria declarado pela F4 e nunca ligado pelo emitter; o corpo
// `=> a` cairia em `ice-codegen-ident-unbound` — um código que nomeia defeito
// NOSSO ("um identificador ficou sem ligação") para uma causa que é outra ("esta
// fatia da linguagem não existe"). A R7 proíbe catraca sobre ICE de estado
// justamente porque ele mente sobre a causa; o conserto não é pôr catraca nele,
// é fazer o sítio certo falhar com o nome certo.
//
// EXPECT-ICE: ice-codegen-match-list-nested-bind

struct P { x: Int }

fn f(xs: List<P>) -> Int => match xs {
  [] => 0,
  [P { x: a }, ..] => a
}

fn main() {
  let xs: List<P> = [P(x: 7)]
  print("${f(xs)}")
}
