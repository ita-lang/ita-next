// **O nome Kernel de um parâmetro é o LABEL — e é o label que a F5 compara.**
//
// Este fixture PINA um acoplamento entre duas fases que hoje se sustentam
// mutuamente e não têm nada escrito ligando uma à outra:
//
//   F5  `collect.dart:645`  →  `label: p.label ?? p.name`   (o que `sameSignature`
//                                                            compara em conformance)
//   F7  `_fnSignature`      →  `p.label ?? p.name`          (o nome Kernel do param)
//
// A auditoria de 2026-07-29 levantou a hipótese de que um conformer com nome de
// parâmetro diferente do trait morreria em `NoSuchMethodError`: o `_methodCall`
// tira os nomes dos named-args do procedure do TRAIT (via tipo estático `any
// Soma`), enquanto o conformer emite os parâmetros com os nomes DELE. O
// mecanismo está descrito certo — e o defeito **não é alcançável**, porque as
// duas fases derivam o nome da mesma expressão. Se divergem, a F5 acusa
// `trait-member-signature-mismatch` antes de a F7 rodar.
//
// O acoplamento não está registrado em spec nenhuma. Enquanto não estiver, é
// este fixture que quebra no dia em que alguém mexer num dos dois lados — por
// exemplo, relaxando a comparação da F5 para ignorar labels, ou trocando o nome
// Kernel para `p.name`. Sem ele, o efeito só apareceria em runtime.
//
// O caso interessante é o do meio: **labels IGUAIS, nomes internos DIFERENTES**.
// A F5 aprova (compara labels) e a F7 emite pelos labels, então casa. É a prova
// de que a ponte é o label, não o nome.

trait Soma {
  fn junta(de a: Int, com b: Int) -> Int
}

struct Calc : Soma {
  // Nomes internos `x`/`y` — NADA a ver com `a`/`b` do trait. Os labels
  // (`de`/`com`) são o contrato, e são o que chega ao Kernel.
  fn junta(de x: Int, com y: Int) -> Int => x + y
}

struct Vezes : Soma {
  fn junta(de p: Int, com q: Int) -> Int => p * q
}

// Chamada por trait: o `interfaceTarget` é o requisito ABSTRATO, e os named-args
// saem dos labels dele. É o sítio onde um desencontro de nomes explodiria.
fn aplica(s: any Soma, x: Int, y: Int) -> Int => s.junta(de: x, com: y)

fn main() {
  print("${aplica(s: Calc(), x: 3, y: 4)}")
  print("${aplica(s: Vezes(), x: 3, y: 4)}")

  // Chamada DIRETA no conformer, sem passar pelo trait: mesmo contrato.
  print("${Calc().junta(de: 10, com: 5)}")
}
