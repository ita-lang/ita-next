// §7.4-e (consequência) — `??` e `if let` **funcionam sem uma linha de emissão
// própria**.
//
// Os dois são AÇÚCAR: a F3 os reescreve para `match` sobre `Option` (verificável
// com `itac desugar --dump` — `a ?? 0` vira
// `match a { .some($x0) => $x0, .none => 0 }`). Quando o `match` de `Option`
// nasceu, os dois passaram a compilar de graça.
//
// É a arquitetura pagando dividendo: o desugaring REDUZ a superfície que a
// emissão precisa conhecer, então uma fatia de `match` destrava vários
// operadores de superfície de uma vez. Este fixture existe para travar isso —
// se alguém mexer no desugaring de `??`/`if let` e a redução deixar de casar com
// o gabarito, é aqui que aparece.

fn ou(v: Int?, alt: Int) -> Int => v ?? alt

fn main() {
  let cheio: Int? = 5
  let vazio: Int? = nil

  print("?? cheio=${cheio ?? 0}")
  print("?? vazio=${vazio ?? 99}")
  print("?? via fn=${ou(vazio, 42)}")

  let s: String? = nil
  print("?? string=${s ?? "padrão"}")

  print("if-let cheio=${if let v = cheio => v else 0}")
  print("if-let vazio=${if let v = vazio => v else -1}")
}
