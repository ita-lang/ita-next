// FRONTEIRA HONESTA (§7.8) — `enum` com PAYLOAD.
//
// Diferente das outras fronteiras, esta **não é da emissão**: o gabarito da
// §7.4-e já está escrito (classe selada + subclasse por variante,
// `IsExpression` + `InstanceGet(AsExpression(...))`). O bloqueio é uma fase
// antes — **a F5 não sabe CONSTRUIR uma variante com payload**:
//
//     let c: Forma = .circulo(raio: 2)     ⟹ check-error: cannot-infer
//
// O `_call` da F5 não resolve callee `EnumShorthand` com args (o
// `_enumShorthand` até prevê o caso — tem a mensagem `variant-needs-payload` —
// e a gramática já o descreve: `enumCase ::= IDENT ("(" param … ")")?`). Sem
// construção não existe valor a destruir, então emitir a classe selada agora
// produziria um tipo que ninguém consegue instanciar.
//
// Por isso o ICE é `enum-payload-<variante>` e não algo de `match`: ele nomeia a
// lacuna REAL. Quando a fatia da F5 nascer, este fixture cobra a promoção — e aí
// vem o **CA7** (`match` sobre enum-com-payload destrói e rende) e o caminho
// para `Result` + `?` (**CA8**).
//
// EXPECT-ICE: ice-codegen-enum-payload-circulo

enum Forma {
  circulo(raio: Int),
  ponto
}

fn main() {
  let p: Forma = .ponto
  print("${match p { .circulo(r) => r, .ponto => 0 }}")
}
