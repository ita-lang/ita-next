// B1 (review de identidade): `pub init` é PRESERVADO na AST (como pub fn/pub field),
// não descartado mudo. A política de visibilidade de init é da Fase 3.
class Account { pub init(balance: Int) { self.balance = balance } }
