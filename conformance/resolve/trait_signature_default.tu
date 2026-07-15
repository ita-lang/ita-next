// Defaults de params numa assinatura de trait (fn SEM corpo) resolvem como em
// qualquer fn: escopo do módulo (`padrao`, letrec) e `self` disponível — uma
// assinatura de trait é método, então o default vê `self` igual ao caso com
// corpo. Não há escopo de params: nada referencia `x` por nome aqui.
trait T {
  fn f(x: Int = padrao) -> Int
  fn g(y: Int = self.base) -> Int
}

let padrao = 42
