// CA13 (spec 014 §11) — código morto é ERRO (ruling §12-1), UM por região
// morta. A variante do bloco: a morte que ATRAVESSA bloco nu é UMA região
// dinâmica ⟹ UM erro (no primeiro morto, dentro do bloco). E o corpo que não
// completa NUNCA acusa `missing-return` junto — o erro segue o fix.
//
// O outro lado da moeda: "um por região" NÃO é "um por corpo". Regiões
// DISTINTAS acusam separado — morto no then E no else são DUAS regiões (o
// flag anticascata fecha ao sair de cada braço); e o stmt após um if cujos
// dois braços divergem é a SUA própria região, um erro nele.
// EXPECT-FLOW: unreachable-code
// EXPECT-FLOW: unreachable-code
// EXPECT-FLOW: unreachable-code
// EXPECT-FLOW: unreachable-code
// EXPECT-FLOW: unreachable-code

fn depoisDoReturn() -> Int {
  return 1
  let morto = 2
}

fn atravessaBloco() -> Int {
  {
    return 1
    let dentro = 2
  }
  let fora = 3
}

fn doisBracosMortos(c: Bool) -> Int {
  if c {
    return 1
    let mortoNoThen = 2
  } else {
    return 2
    let mortoNoElse = 3
  }
}

fn depoisDoIfDivergente(c: Bool) -> Int {
  if c {
    return 1
  } else {
    return 2
  }
  let morto = 3
}
