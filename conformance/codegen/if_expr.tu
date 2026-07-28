// §7.4-c — `if`-expr na forma booleana → `ConditionalExpression`, cujo
// `staticType` é o JOIN dos ramos que a F5 computou.
//
// **RD-1 vive aqui:** só `=>` rende valor, e o `else` é OBRIGATÓRIO — logo o nó
// do Kernel sempre tem `otherwise`, sem ramo sintetizado. Um `if` sem `else` não
// é esta expressão: é statement, e não chega a este gabarito.

fn main() {
  print(if 1 < 2 => "sim" else "não")
  let b = 3 == 3
  print(if b => "igual" else "diferente")
}
