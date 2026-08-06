// **O corpo do `init` é TIPADO pela F5** — e este fixture existe porque a
// ausência disso SEGFAULTAVA a Dart VM.
//
// Até 2026-07-29 a F5 tinha `case ast.InitDecl(): break;`: não descia no corpo
// do `init`. A F7, que **emite** esse corpo, lia `check.exprTypes[e]` e recebia
// `null` — que `Map` devolve igual para "ausente" e para "nunca visitado". O
// emitter absorvia o `null` em silêncio, e `_arithOpFor(op, null)` caía no ramo
// INTEIRO: `a / b` sobre `Float` virava `~/`.
//
// O resultado não era "3.0 em vez de 3.5". Era:
//
//     ===== CRASH =====
//     si_signo=Segmentation fault: 11(11), si_code=SEGV_ACCERR(2)
//
// Programa legal, crash da VM, e **nenhuma fase dizia uma palavra** — nem a F5
// (não visitava), nem a F6, nem a F7 (absorvia o null), nem o verify, nem o
// golden-runner (nenhum fixture tinha aritmética dentro de um `init`).
//
// Duas coisas mudaram, e as duas importam:
//   1. a F5 tipa o corpo (`_initDecl`) — a cura, na fase dona;
//   2. a F7 ganhou pré-condição na porta do `_expr`
//      (`ice-codegen-untyped-<T>`) — a rede, para a PRÓXIMA região que alguém
//      esquecer de visitar. Foi ela que achou esta, e achou também o operando
//      de `panic`, que tinha o mesmo defeito.
//
// `let` com atribuição no `init` é INICIALIZAÇÃO, não mutação — daí `self.r`
// abaixo não cair em `assign-to-immutable`.

class Divisao {
  let r: Float
  let nome: String

  init(a: Float, b: Float, nome: String) {
    self.r = a / b
    self.nome = nome
  }
}

class Contagem {
  let dobro: Int
  let rotulo: String

  init(n: Int) {
    // Aritmética de Int no corpo do init: o outro lado da mesma armadilha.
    self.dobro = n * 2
    // Interpolação dentro do init — `Str` também precisa de tipo.
    self.rotulo = "n=${n}"
  }
}

fn main() {
  let d = Divisao(a: 7.0, b: 2.0, nome: "sete-meios")
  // 3.5, não 3.0: `/` sobre Float é divisão real. Era ISTO que segfaultava.
  print("${d.r}")
  print(d.nome)

  let c = Contagem(n: 21)
  print("${c.dobro}")
  print(c.rotulo)
}
