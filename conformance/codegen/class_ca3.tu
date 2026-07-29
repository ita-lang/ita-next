// **CA3 da §11** — `class` com `init` explícito valida. E, junto, o **P2** fica
// OBSERVÁVEL: `struct` é valor, `class` é referência, e a diferença aparece no
// comportamento, não só na doc.
//
// **`class` nunca ganha memberwise** (ADR-0012 §A-1): sem `init` no corpo ela é
// INCONSTRUÍVEL. É esse contraste que dá conteúdo ao P2 — o glifo escolhe entre
// valor e referência, e cada um paga um preço diferente. `struct` ganha
// construtor de graça e não muta; `class` exige `init` e muta.
//
// Campo `var` de `class` baixa MUTÁVEL (`Field.mutable`, com setter), enquanto
// em `struct` todo campo é `final` pelo ruling §12-1. A linha "referencia
// compartilha" é a prova: `a` e `b` apontam para o MESMO objeto, então duas
// incrementadas somam nos dois. Se `class` fosse emitida como valor, daria 1 e 1.
//
// ⚠️ **O corpo do `init` vira `initializers`, não statements.** No Kernel, campo
// `final` só pode ser atribuído em `initializers` — atribuí-lo no corpo é
// malformado. O Itá escreve `self.saldo = inicial` dentro do `init`, então cada
// `self.campo = <expr>` é convertido. A conversão exige que o corpo seja SÓ
// atribuições a `self`: `FieldInitializer` roda ANTES do corpo, então misturar
// lógica entre elas mudaria a ordem de avaliação em silêncio. Qualquer outro
// statement vira ICE `init-body-stmt-<T>`, e um `self.x += 1` vira
// `init-body-expr-<T>` — restrição declarada, não adivinhada, e uma por fatia.

struct Ponto { x: Int, y: Int }

class Conta {
  saldo: Int,
  var ativa: Bool

  init(inicial: Int) {
    self.saldo = inicial
    self.ativa = true
  }
}

class Contador {
  var n: Int

  init(inicial: Int) {
    self.n = inicial
  }
}

fn incrementa(c: Contador) {
  c.n = c.n + 1
}

fn dobra(c: Contador) {
  c.n *= 2
}

fn main() {
  // o CA3: `init` explícito constrói
  let c = Conta(inicial: 100)
  print("conta: ${c.saldo} ${c.ativa}")

  // P2 — REFERÊNCIA: `a` e `b` são o mesmo objeto
  let a = Contador(inicial: 0)
  let b = a
  incrementa(a)
  incrementa(b)
  print("referencia compartilha: a=${a.n} b=${b.n}")

  dobra(a)
  print("compound em campo: ${b.n}")

  // P2 — VALOR: `struct` é imutável, a cópia é inobservável
  let p = Ponto(x: 1, y: 2)
  let q = p
  print("valor: p.x=${p.x} q.x=${q.x}")
}
