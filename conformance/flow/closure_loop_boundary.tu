// Spec 014 §8 — a fronteira de closure ZERA o contexto de loop (o espelho
// em-fase do corte da F4): o break do while INTERNO à closure não destrava o
// `while true` EXTERNO. A fn non-Void segue verde porque o while-true, sem
// break PRÓPRIO, não completa — e o golden .facts mostra os dois corpos:
// fn completes=false, closure completes=true.

fn nuncaSai(c: Bool) -> Int {
  while true {
    let roda = () => {
      while c {
        break
      }
      let volta = 1
    }
  }
}
