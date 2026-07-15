// Assinatura de trait (fn SEM corpo) também resolve os defaults dos params —
// antes o walk retornava cedo em `body == null` e o default escapava inteiro.
// O contraste era absurdo: dar um corpo à assinatura mudava se o default era
// checado (`fn f(x: Int = bogus)` passava; `... => x` acusava).
// EXPECT-ERROR: unresolved-name
trait T {
  fn f(x: Int = bogus) -> Int
}
