// **CA — closure como VALOR** (spec 013 §7.4-b). PROMOVIDO de fronteira.
//
// Nasceu `// EXPECT-ICE: ice-codegen-expr-Closure` e ficou VERMELHO sozinho no
// commit que emitiu `FunctionExpression` — *"esperava ice-…, mas COMPILOU — a
// fatia nasceu? promova a fixture a CA verde"*. A catraca funcionando como
// projetada, pela terceira vez no projeto.
//
// O que ele prova: `Closure` → `FunctionExpression`, e a chamada da variável
// local de tipo-função → `FunctionInvocation`.

fn main() {
  let dobra = (x: Int) -> Int => x * 2
  print("${dobra(3)}")
}
