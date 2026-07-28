// §7.4-c — `&&`/`||` → `LogicalExpression`. O curto-circuito é semântica do NÓ
// (a VM o baixa para desvios no flowgraph), não algo que emitimos: as quatro
// tabelas-verdade abaixo passam ou falham inteiramente pelo Grupo B.

fn main() {
  print(if true && true => "and ok" else "and FALHOU")
  print(if true && false => "and curto FALHOU" else "and curto ok")
  print(if false || true => "or ok" else "or FALHOU")
  print(if false || false => "or vazio FALHOU" else "or vazio ok")
}
