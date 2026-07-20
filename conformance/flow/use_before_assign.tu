// CA6 (spec 014 §11) — DA de `var` (JLS §16, só `var` — 009 §12-7): uso fora
// do conjunto DA é erro; atribuído nos DOIS braços entra pelo ∩; só num braço
// não entra (o caminho cond-false participa com o DA de entrada).
// EXPECT-FLOW: use-before-assign
// EXPECT-FLOW: use-before-assign

fn usaAntes() -> Int {
  var x: Int
  return x
}

// Verde: os dois braços atribuem ⟹ x sobrevive à interseção.
fn atribuiNosDois(c: Bool) -> Int {
  var x: Int
  if c {
    x = 1
  } else {
    x = 2
  }
  return x
}

fn atribuiNum(c: Bool) -> Int {
  var x: Int
  if c {
    x = 1
  }
  return x
}

// Verde: atribuição sequencial simples — o GEN do Assign.
fn atribuiDireto() -> Int {
  var x: Int
  x = 1
  return x
}
