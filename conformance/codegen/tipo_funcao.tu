// **CA — tipo-função em ASSINATURA** (spec 013 §7.4-b). PROMOVIDO de fronteira.
//
// Nasceu `// EXPECT-ICE: ice-codegen-type-FunctionType`. Irmão do
// `closure_valor.tu`, e o sítio é outro: `emitTopLevel` emite todas as
// assinaturas ANTES de qualquer corpo, então o `(Int) -> Int` do parâmetro
// passava pelo `_emitType` antes de o corpo ser tocado — por isso dois fixtures,
// e não um.
//
// A forma correta no Kernel é POSICIONAL — `k.FunctionType([int], int)` —, não
// `namedParameters`: a gramática de tipo é `type ::= "(" type ("," type)* ")"
// "->" type`, o slot é `type` e não `param`, logo **label não entra em
// tipo-função**. Ver ADR-0020 §1.

fn aplica(f: (Int) -> Int, v: Int) -> Int => f(v)

fn main() {
  print("${aplica(f: (x: Int) -> Int => x * 2, v: 5)}")
}
