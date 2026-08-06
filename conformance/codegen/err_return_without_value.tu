// EXPECT-ERROR: return-without-value
//
// **CA NEGATIVO PERMANENTE.**
//
// `return` nu sob `-> Int` é programa errado. Até 2026-07-29 ninguém dizia:
//
//   - a F5 só entrava no ramo `if (n.value != null)` — um `return` nu passava
//     sem ser comparado com o tipo de retorno;
//   - a F6 trata `return` como "não completa normalmente", e `missing-return` é
//     sobre o FIM do corpo (JLS §8.4.7) — um `return` nu satisfaz o predicado;
//   - a F7 emitia `ReturnStatement(null)` num `Procedure` com `returnType: int`.
//
// O programa RODAVA e imprimia **`null`** para um `Int` — valor inválido
// silencioso, contra a nullity-invariant ("nil só sob `T?`"), sem uma linha de
// diagnóstico em fase nenhuma.
//
// A cereja: o emitter afirmava que a F6 já reprovava isto. Garantia-fantasma —
// o comentário citava a fase errada sobre uma regra que não existia em fase
// nenhuma. É o caso que funda a R11 do CLAUDE.md.

fn f() -> Int {
  return
}

fn main() {
  print("${f()}")
}
