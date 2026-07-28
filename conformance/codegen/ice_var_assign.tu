// FRONTEIRA HONESTA (§7.8) — a REATRIBUIÇÃO de `var`. O `let`/`var` já baixa
// (§7.4-b), mas a escrita ainda não tem gabarito: o `var` do corpus verde
// (`let_var.tu`) é declarado e lido, nunca escrito.
//
// O ICE sai como `expr-Assign`, não `stmt-*` — porque no Itá a atribuição é
// **expressão** (P3, "tudo é expressão quando possível"): `n = 2` chega ao
// emitter dentro de um `ExprStmt`. O alvo Kernel é `VariableSet`.
//
// É a metade que falta de P1: sem esta fatia, `var` compila mas não muta — e o
// ICE é justamente o que impede a linguagem de fingir que mutou.
//
// EXPECT-ICE: ice-codegen-expr-Assign

fn main() {
  var n = 1
  n = 2
  print("n=${n}")
}
