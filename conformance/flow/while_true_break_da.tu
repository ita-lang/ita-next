// JLS §16.2.10 (bônus do §7 do blueprint) — V é DA após `while true` sse DA
// antes de CADA break: o caminho cond-false não existe. É o que deixa verde o
// idioma init-no-loop.

fn initNoLoop() -> Int {
  var x: Int
  while true {
    x = 1
    break
  }
  return x
}

// Dois breaks, os dois com x atribuído — o ∩ dos snapshots preserva x.
fn doisBreaks(c: Bool) -> Int {
  var x: Int
  while true {
    if c {
      x = 1
      break
    }
    x = 2
    break
  }
  return x
}
