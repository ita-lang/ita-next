// EXPECT-ICE: ice-codegen-expr-Closure
//
// **FRONTEIRA — LT-F7c.** Closure como VALOR ainda não é emitida.
//
// Este fixture é a catraca: quando a emissão de `FunctionExpression` nascer, ele
// fica VERMELHO sozinho ("esperava ice-…, mas COMPILOU — promova a CA verde") e
// vira um CA. É a fila de trabalho da spec 013 §7.4-b, executável.
//
// ⚠️ Dois sítios diferentes, dois fixtures. O `_let` emite o INITIALIZER antes
// do tipo, então um `let` de closure morre em `expr-Closure`; uma ASSINATURA que
// menciona `(Int) -> Int` morre antes, em `type-FunctionType`
// (`ice_tipo_funcao.tu`). Fundir os dois num fixture só faria a catraca disparar
// pelo motivo errado — o runner compara o código do ICE por IGUALDADE.

fn main() {
  let dobra = (x: Int) -> Int => x * 2
  print("${dobra(3)}")
}
