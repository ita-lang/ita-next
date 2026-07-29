// **CA — `&f`, captura de função nomeada como valor** (ADR-0020, decisão 1).
//
// Uma `fn` do Itá é chamada por LABEL (`dobro(x: 5)`); um valor de tipo-função é
// chamado por POSIÇÃO (`f(5)`). São ABIs diferentes, e até 2026-07-29 passar uma
// `fn` para um slot `(Int) -> Int` era o pior dos mundos: `itac check` ACEITAVA
// e `itac build` morria com "erro interno".
//
// O dono escolheu marcar a conversão no sítio onde ela acontece — a forma que a
// linguagem já usa no `?` (no caractere da propagação) e no `any` (no slot que
// boxa). É o Art. II: `Itá : Dart :: Elixir : Erlang`, e Elixir escreve
// `&dobro/1`. Sem aridade aqui, porque o Itá não tem overload.
//
// Swift e Rust fazem esta mesma conversão em SILÊNCIO. A eta-expansão
// (`&dobro` ⟹ `(v) => dobro(x: v)`) custa uma alocação, e o `&` é o que torna
// esse custo escrito em vez de inferido.

fn dobro(x: Int) -> Int => x * 2
fn nega(x: Int) -> Int => 0 - x
fn soma(de a: Int, com b: Int) -> Int => a + b

fn aplica(f: (Int) -> Int, v: Int) -> Int => f(v)
fn aplica2(f: (Int, Int) -> Int, a: Int, b: Int) -> Int => f(a, b)

fn main() {
  print("${aplica(f: &dobro, v: 5)}")
  print("${aplica(f: &nega, v: 7)}")

  // Dois params, e a `fn` capturada tem LABELS (`de`/`com`) — eles não
  // sobrevivem à travessia para valor, que é a regra do SE-0111.
  print("${aplica2(f: &soma, a: 3, b: 4)}")

  // A captura é um valor como outro: cabe num `let` e é chamada por posição.
  let f = &dobro
  print("${f(21)}")

  // Chamada NORMAL da mesma `fn` — o label continua obrigatório lá.
  print("${dobro(x: 50)}")
}
