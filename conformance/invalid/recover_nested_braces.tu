// D1 — a sincronização BALANCEIA chaves: o lixo de um membro malformado pode
// conter `{…}` (o corpo do próprio membro). Sem contar profundidade, o sync
// parava no `}` do corpo e dava o TIPO por fechado — o `fn ok` seguinte era
// reparentado ao top-level (exatamente o que D1 existe para evitar), com erros
// em cascata. Aqui `fn ok` continua membro de `S`, e há UM erro só.
struct S {
  fn bad(&) -> Int { let x = 1 }
  fn ok() -> Int => 2
}
// EXPECT: parse-error: expected-token @401+1
