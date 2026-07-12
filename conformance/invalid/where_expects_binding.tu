// `where` só aceita bindings (`let`/`var`); um statement/expressão qualquer é
// erro. A pureza (rejeitar `var`, exigir bindings sem efeito) é da Fase 3.
let r = x where { y + 1 }
// EXPECT: parse-error: where-expects-binding @173+1
