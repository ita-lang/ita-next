// EXPECT-ICE: ice-codegen-type-FunctionType
//
// **FRONTEIRA — LT-F7c.** Tipo-função em ASSINATURA ainda não é emitido.
//
// Irmão do `ice_closure_valor.tu`, e o sítio é outro: `emitTopLevel` emite todas
// as assinaturas ANTES de qualquer corpo, então o `(Int) -> Int` do parâmetro
// morre no `_emitType` antes de o corpo ser tocado.
//
// A forma correta no Kernel é POSICIONAL — `k.FunctionType([int], int)` —, não
// `namedParameters`: a gramática de tipo é `type ::= "(" type ("," type)* ")"
// "->" type`, o slot é `type` e não `param`, logo **label não entra em
// tipo-função**. Ver ADR-0020 §1.

fn aplica(f: (Int) -> Int, v: Int) -> Int => f(v)

fn main() {
  print("${aplica(f: (x: Int) -> Int => x * 2, v: 5)}")
}
