// **CA — `f >> g` compõe, e SINTETIZA sem anotação** (spec 007 §12-C).
//
// Até 2026-07-29 a F3 reescrevia `f >> g` para `($c) => g(f($c))` com o
// parâmetro `$c` **sem anotação**. E a F5 tem regra firme: closure com param sem
// tipo não sintetiza — precisa de contexto. Medido na época:
//
//     let comp = dobra >> mais1                  ⟹ check-error: cannot-infer
//     let comp: (Int) -> Int = dobra >> mais1    ⟹ compilava
//
// Mas `f >> g` é **inteiramente sintetizável**: `f:(A)→B` e `g:(B)→C` dão
// `(A)→C`, sem nada a inferir. Quem destruía isso era a própria reescrita —
// *type-agnostic na forma*, mas **não preservava o MODO** (levava uma expressão
// que sintetiza a uma que só verifica).
//
// Ruling do dono: `>>` é NÚCLEO. A F3 não o toca, a F5 tem regra própria, a F7
// emite a closure já tipada. Companhia de `Try`, `guard let`, `CopyWith` e `**`
// — todos retidos por precisarem de tipo.
//
// Repare no `&`: composição de funções NOMEADAS precisa da captura (ADR-0020
// decisão 1), porque `fn` não é valor. Compor closures dispensa o glifo.

fn dobra(x: Int) -> Int => x * 2
fn mais1(x: Int) -> Int => x + 1
fn texto(n: Int) -> String => "n=${n}"

fn main() {
  // SEM anotação — era exatamente isto que dava `cannot-infer`.
  let comp = &dobra >> &mais1
  print("${comp(3)}")

  // A ordem importa: `>>` é "primeiro f, depois g".
  let inversa = &mais1 >> &dobra
  print("${inversa(3)}")

  // Tipos DIFERENTES nas pontas: `(Int)→Int >> (Int)→String` = `(Int)→String`.
  let descreve = &dobra >> &texto
  print(descreve(5))

  // Compondo CLOSURES — sem `&`, porque já são valores.
  let triplica = (x: Int) -> Int => x * 3
  let menos2 = (x: Int) -> Int => x - 2
  let mista = triplica >> menos2
  print("${mista(10)}")

  // Composição encadeada, associando à esquerda.
  let tripla = &dobra >> &mais1 >> &dobra
  print("${tripla(1)}")
}
