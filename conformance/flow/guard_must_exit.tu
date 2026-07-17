// CA4 (spec 014 §11) — o else de um guard TEM de não completar (Swift TSPL
// "Early Exit", ruling §12-3). O sítio do erro é o BLOCO else — o pecado mora
// lá (o predicado é o MESMO `completesNormally`, sítio novo).
// EXPECT-FLOW: guard-must-exit

fn escapaNao(o: Int?) -> Int {
  guard let v = o else {
    let caiu = 1
  }
  return v
}

// Verdes: else que retorna / que panica — os dois jeitos de "sair".
fn escapaComReturn(o: Int?) -> Int {
  guard let v = o else {
    return 0
  }
  return v
}

fn escapaComPanic(o: Int?) -> Int {
  guard let v = o else {
    panic("sem valor")
  }
  return v
}

// Verde: o guard booleano usa o mesmo predicado.
fn guardBool(c: Bool) -> Int {
  guard c else {
    return 0
  }
  return 1
}
