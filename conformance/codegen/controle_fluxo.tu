// AUDITORIA · Lote 3 — **controle de fluxo em STATEMENT**: `if`/`else if`/`else`,
// `while`, `break`, `continue`.
//
// **Estes construtos NÃO EXISTIAM até a auditoria de 2026-07-29.** `if c { … }`
// dava `ice-codegen-stmt-IfStmt` e `while` dava `ice-codegen-stmt-WhileStmt` —
// ou seja, a linguagem tinha funções, structs, traits, `match` e `Result`, mas
// **não tinha laço nenhum** (o `for` é gated pela 012) nem `if` de bloco. Os
// fixtures anteriores nunca os usaram porque eu escrevia tudo em forma de
// expressão.
//
// ⚠️ **`if`-expr × `if`-statement são nós DIFERENTES**, e RD-1 é quem separa:
// só `=>` rende valor. `if c => a else b` é `ConditionalExpression`;
// `if c { … }` é `IfStatement`, cujos blocos não rendem.
//
// ⚠️ **`break`/`continue` do Kernel exigem ALVO.** Não existe `break` solto, e
// não existe `ContinueStatement` para laço. O gabarito (o mesmo da CFE):
//
//     L_break: while (c) { L_cont: { …corpo… } }
//       break    → BreakStatement(L_break)
//       continue → BreakStatement(L_cont)    // sai do CORPO, não do laço
//
// Os labels só são materializados se o corpo os usar — o `while` do primeiro
// bloco sai sem envelope nenhum.
//
// O laço aninhado é a asserção que importa no `continue`: ele tem de afetar o
// laço INTERNO. Se apontasse para o label errado, `total` daria 3 em vez de 6.

fn classifica(n: Int) -> String {
  var r = ""
  if n < 0 {
    r = "negativo"
  } else if n == 0 {
    r = "zero"
  } else {
    r = "positivo"
  }
  return r
}

fn main() {
  print("if/else if/else: ${classifica(-5)} ${classifica(0)} ${classifica(7)}")

  // while simples — sem break/continue, sai sem envelope de label
  var i = 0
  var soma = 0
  while i < 5 {
    soma = soma + i
    i = i + 1
  }
  print("while: soma=${soma} i=${i}")

  // break + continue no mesmo laço
  var n = 0
  var impares = 0
  while true {
    n = n + 1
    if n > 10 { break }
    if n % 2 == 0 { continue }
    impares = impares + n
  }
  print("break+continue: impares=${impares} n=${n}")

  // ANINHADO: o `continue` afeta o laço INTERNO
  var fora = 0
  var total = 0
  while fora < 3 {
    var dentro = 0
    while dentro < 3 {
      dentro = dentro + 1
      if dentro == 2 { continue }
      total = total + 1
    }
    fora = fora + 1
  }
  print("aninhado: total=${total}")
}
