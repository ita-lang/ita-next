// §7.4-e/f — o `!` (force unwrap) no caminho FELIZ.
//
// **Terceira fixture promovida pela catraca.** Era `ice_force_unwrap.tu`, com
// `// EXPECT-ICE: ice-codegen-expr-Panic`, e o ICE dizia exatamente qual peça
// faltava: não era nada de `match` — era o `panic`. Quando o CA9 nasceu, ela
// ficou vermelha sozinha e virou isto.
//
// É o que separa uma fronteira declarada de um TODO: o `!` desugara para
// `match x { .some($v) => $v, .none => panic("force-unwrap on none") }`, então
// precisava de DOIS núcleos. O `??`, que precisava só de `match`, veio de graça
// uma fatia antes. A fronteira não só cobrou — ela disse o que faltava.
//
// O caminho INFELIZ (`nil!` ⟹ panic, exit 255) vive em `panic_exit.tu`, que
// precisa de `EXPECT-EXIT` próprio.

fn primeiro(v: Int?) -> Int => v!

fn main() {
  let x: Int? = 7
  print("direto=${x!}")
  print("via fn=${primeiro(35)}")

  let s: String? = "texto"
  print("string=${s!}")
}
