// CA2 (spec 014 §11) — `panic` como corpo inteiro de fn non-Void: `Never` não
// completa (§2, precedente Kotlin `Nothing`) ⟹ SEM `missing-return`. O golden
// `.facts` testa a side-table nº8 direto: `completes=false` nos dois corpos.

fn explode() -> Int {
  panic("x")
}

// `let x = panic(…)` também encerra — a extensão por nó da mesma regra
// type-informed (tipo do VALOR na nº1), mesmo precedente assinado.
fn explicaAntes() -> Int {
  let motivo = "sem suporte"
  panic(motivo)
}
