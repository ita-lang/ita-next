// CA21 (spec 014 §11) — a fixture NOMEADA do idioma de rascunho: `panic("TODO")`
// como corpo inteiro de fn non-Void é VERDE. Consequência do §2, não caso
// especial: o ExprStmt-Never não completa ⟹ o predicado do JLS §8.4.7 nem
// dispara. (É o que dissolve a tensão do §12-1: rascunho honesto não é código
// morto.)

fn aindaNaoEscrevi() -> Int {
  panic("TODO")
}

fn rascunhoComPassos() -> Int {
  let passo = 1
  panic("TODO: usar o passo")
}
