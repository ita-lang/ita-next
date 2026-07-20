// CA1 (spec 014 §11) — `if` sem else com return só no then: o carve-out do
// JLS §14.21 faz o if completar SEMPRE ⟹ o corpo PODE cair do fim (§8.4.7).
// Os casos verdes no meio são de propósito: o runner casa a lista EXATA, e um
// falso-positivo neles quebra o fixture (o padrão do `err_try.tu`).
// EXPECT-FLOW: missing-return

fn soPeloThen(c: Bool) -> Int {
  if c {
    return 1
  }
}

// Verde: os DOIS braços saem ⟹ o if não completa ⟹ o corpo não cai do fim.
fn pelosDois(c: Bool) -> Int {
  if c {
    return 1
  } else {
    return 2
  }
}

// Verde: else-if encadeado com saída em todo caminho.
fn cascata(a: Bool, b: Bool) -> Int {
  if a {
    return 1
  } else if b {
    return 2
  } else {
    return 3
  }
}
