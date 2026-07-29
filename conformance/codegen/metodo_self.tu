// §7.4-c/d — métodos que USAM `self`, e enums com variantes HOMÔNIMAS.
//
// **Este fixture nasceu de uma revisão adversarial da PR #18**, e trava dois bugs
// que os fixtures originais não pegavam — porque eu havia escrito só métodos que
// não tocam o próprio objeto (`fn som() => "quack"`).
//
// **Bug 1 — `self` não compilava.** `SelfExpr` não tinha caso no emitter, então
// qualquer método que lesse um campo dava `ice-codegen-expr-SelfExpr`. Um método
// que não pode ler os próprios campos é inútil: a fatia de conformance passava
// nos testes e não servia para escrever código real.
//
// **Bug 2 — variantes homônimas em enums diferentes.** A resolução da variante
// era por NOME, buscando em TODOS os enums e pegando o primeiro que casasse.
// Com `A.par` e `B.par`, o `match` sobre `B` usava a subclasse de `A`:
//
//     type 'B$par' is not a subtype of type 'A$par' in type cast
//
// O `.dill` compilava, passava no verify, e **explodia em runtime**. Nome de
// variante é único DENTRO de um enum, não entre enums — a chave tem de incluir o
// tipo do escrutínio.

trait Medida {
  fn valor() -> Int
}

struct Ponto : Medida {
  x: Int,
  y: Int

  fn soma() -> Int => self.x + self.y
  fn dobro() -> Int => self.soma() * 2
  fn valor() -> Int => self.soma()
}

class Caixa : Medida {
  var itens: Int

  init(itens: Int) {
    self.itens = itens
  }

  fn valor() -> Int => self.itens
  fn descreve() -> String => "caixa com ${self.itens}"
}

// dois enums com a MESMA variante `par`, payloads de tipos diferentes
enum A { par(v: Int), zero }
enum B { par(v: String), zero }

fn deA(x: A) -> Int => match x { .par(n) => n, .zero => 0 }
fn deB(y: B) -> String => match y { .par(s) => s, .zero => "-" }

fn mede(m: any Medida) -> Int => m.valor()

fn main() {
  let p = Ponto(x: 3, y: 4)
  print("self: ${p.soma()} ${p.dobro()}")

  let c = Caixa(itens: 5)
  print("self em class: ${c.descreve()}")

  // `self` atravessando o dispatch existencial
  print("existencial: ${mede(p)} ${mede(c)}")

  // as duas variantes homônimas resolvem para os enums CERTOS
  print("homonimas: ${deA(.par(v: 7))} ${deB(.par(v: "sete"))}")
}
