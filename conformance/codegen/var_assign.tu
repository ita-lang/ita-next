// §7.4-b (fecho) — REATRIBUIÇÃO de `var` → `VariableSet`. **A outra metade do P1.**
//
// **Este fixture também nasceu de fronteira** (era `ice_var_assign.tu`, com
// `// EXPECT-ICE: ice-codegen-expr-Assign`) e foi promovido quando a emissão
// nasceu — a segunda vez que a catraca cobra sozinha.
//
// Até aqui o `let`/`var` já baixava com o `isFinal` correto, mas `var` compilava
// e **não mutava**: o glifo prometia mutação e a emissão não entregava. Agora
// entrega — e a metade IMUTÁVEL continua cobrada pela F5 (`assign-to-immutable`),
// não por aqui: `let x = 1; x = 2` e param reatribuído são erro de USUÁRIO
// (exit 65), nunca ICE.
//
// As duas últimas linhas são as que mais importam: `/=` passa pelo MESMO
// despacho por tipo que o `/` binário. A armadilha `~/` (Int) × `/` (Float) não
// pode ser fechada numa forma e reaberta na outra.

fn main() {
  var n = 1
  n = 2
  print("simples=${n}")

  n += 40
  print("mais=${n}")

  n -= 2
  n *= 2
  print("cadeia=${n}")

  var i = 7
  i /= 2
  print("div int=${i}")

  var f = 7.0
  f /= 2.0
  print("div float=${f}")
}
