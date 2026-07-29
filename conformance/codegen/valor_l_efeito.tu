// **O receptor de um valor-L composto é avaliado UMA vez.**
//
// `f().n += 1` tem de chamar `f()` uma vez só. Até 2026-07-29 o `_assignMember`
// chamava `_expr(target.receiver)` DUAS vezes — uma para a leitura, outra para a
// escrita — e o comentário ao lado explicava por quê: reusar o mesmo nó montaria
// árvore com dois pais, que o `checkNoSharedNodes` proíbe. O motivo estava
// certo; a cura, errada. Re-emitir a subárvore satisfaz o invariante da árvore e
// **cria** dupla execução. O remédio de um invariante virou o bug.
//
// A cura correta é o temporário (Dragon §2.8.4): o receptor é computado uma vez,
// num `Let`, e as duas pontas leem o temporário.
//
// ⚠️ **Nenhum golden anterior via isso**, porque todo fixture usava receptor
// PURO (`c.n += 1`), onde duplicar só custa nós. Por isso este fixture existe: o
// receptor imprime, e a contagem de linhas É a asserção.

class Contador {
  var n: Int

  init(n: Int) {
    self.n = n
  }
}

// A ÚNICA fonte de `Contador` do programa. Cada chamada imprime — então o
// número de "[efeito]" na saída é o número de avaliações do receptor.
fn pega(c: Contador) -> Contador {
  print("[efeito]")
  return c
}

fn main() {
  let c = Contador(n: 10)

  // Compound sobre receptor EFEITUOSO: um "[efeito]", não dois.
  pega(c: c).n += 5
  print("${c.n}")

  // Os outros três operadores compostos passam pelo mesmo caminho.
  pega(c: c).n -= 3
  print("${c.n}")

  pega(c: c).n *= 2
  print("${c.n}")

  pega(c: c).n /= 4
  print("${c.n}")

  // Atribuição simples também hoista — e também avalia uma vez só.
  pega(c: c).n = 7
  print("${c.n}")
}
