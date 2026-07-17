// CA14 (spec 014 §11) — `self` em default de campo (008 §133, ledger (h)): o
// Kernel não tem `this` em initializer de campo. A F4 o RESOLVE de propósito;
// a proibição é da F6. Erro por OCORRÊNCIA, span no próprio `self`.
// EXPECT-FLOW: self-in-field-default

struct Ponto {
  x: Int
  y: Int = self.x
}

// Verde: default sem self é só um valor.
struct Origem {
  x: Int = 0
}
