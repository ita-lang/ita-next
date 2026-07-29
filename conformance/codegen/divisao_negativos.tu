// **CA — a convenção de divisão do Itá é TRUNCADA** (spec 001 §5), e o par
// coerente é o que o próprio SDK nomeia, verbatim (`num.dart:164-165`):
// *"Then `a ~/ b` corresponds to `a.remainder(b)` such that
// `a == (a ~/ b) * b + a.remainder(b)`"*.
//
// Até 2026-07-29 o Itá misturava DUAS convenções, porque pegou um método de cada
// do Dart sem que ninguém decidisse:
//
//     `~/`           →  -2   truncado (para zero)
//     `%`            →   2   EUCLIDIANO (resto nunca negativo)
//     `.remainder()` →  -1   truncado
//
// Com `~/` + `%`, a identidade fundamental da divisão QUEBRAVA:
//
//     (-7 / 3) * 3 + (-7 % 3)  =  -6 + 2  =  -4     ← deveria ser -7
//
// Isto não era escolha de design — era acidente.
//
// **Truncado e não floored/euclidiano**, nesta ordem de peso: a meta-diretriz da
// casa é o Swift (ADR-0016 §A) e Swift é truncado; custo de emissão ZERO (os
// dois são nativos — floored exigiria aritmética própria e abriria frente de
// divergência com o dart2js que o ADR-0005 vigia); e é a convenção de C, C++,
// Java, C#, Go, Rust e Swift.
//
// ⚠️ **O custo, e ele é real:** `i % n` PODE SER NEGATIVO. Índice circular sobre
// valor possivelmente negativo precisa de cuidado explícito — o mesmo custo que
// C, Java e Swift têm, e o oposto de Python.

fn ident(a: Int, b: Int) -> Int => (a / b) * b + (a % b)

fn main() {
  let neg7 = 0 - 7
  let neg3 = 0 - 3

  // O quociente trunca PARA ZERO (não para -infinito).
  print("${neg7 / 3}")
  print("${7 / neg3}")
  print("${neg7 / neg3}")

  // O resto tem o sinal do DIVIDENDO — é o que caracteriza o truncado.
  print("${neg7 % 3}")
  print("${7 % neg3}")
  print("${neg7 % neg3}")

  // E a identidade vale nos QUATRO quadrantes. Era ela que estava quebrada.
  print("${ident(a: neg7, b: 3)}")
  print("${ident(a: 7, b: neg3)}")
  print("${ident(a: neg7, b: neg3)}")
  print("${ident(a: 7, b: 3)}")
}
