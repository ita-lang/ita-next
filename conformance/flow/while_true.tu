// CA5 (spec 014 §11) — `while true` SINTÁTICO sem break ligado NÃO completa
// (carve-out assinado da §2: o JLS usa const-expr; o Itá não tem const-fold ⟹
// restringe a literal). Com break, completa — e o return vira obrigação.
// EXPECT-FLOW: missing-return

// Verde: loop infinito — a fn non-Void nunca cai do fim.
fn giraParaSempre() -> Int {
  while true {
    let tick = 1
  }
}

// O break destrava o while ⟹ o corpo cai do fim sem return.
fn giraEQuebra() -> Int {
  while true {
    break
  }
}

// Verde: `while` de condição comum completa sempre (pode rodar 0×) — mas aqui
// o return depois paga a obrigação.
fn giraCondicional(c: Bool) -> Int {
  while c {
    let tick = 1
  }
  return 0
}
