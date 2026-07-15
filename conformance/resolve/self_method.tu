// CA8 — self: `self` em método liga a `SelfRes` (o nó do tipo). O SELETOR `.x`
// (Member.name) NÃO é resolvido aqui — type-directed, Fase 5.
struct P { x: Int, fn mag() -> Int => self.x }
