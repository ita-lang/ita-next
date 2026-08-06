// **CA — `|>` sintetiza sem anotação, e aceita `fn` nomeada sem `&`.**
//
// Irmão do `compose.tu`, e a diferença entre os dois é o achado: o `>>` foi
// retido como núcleo porque a reescrita dele produzia closure com parâmetro sem
// anotação (spec 007 §12-C). O `|>` **não tem esse defeito** — o desugar o
// transforma em chamada DIRETA:
//
//     5 |> dobra   ⟶   (call (id dobra) (int 5))
//
// Sem closure, sem parâmetro sintético, modo preservado.
//
// E ele põe `dobra` em posição de **CALLEE**, que é a isenção posicional do
// `fn-not-a-value` (ADR-0020): ali o nome de uma `fn` é legítimo sem o `&`.
// Cercar por *"o nome de uma `fn` não sintetiza tipo"* teria matado a pipeline
// junto — este fixture é o que impede essa regressão.

fn dobra(x: Int) -> Int => x * 2
fn soma(a: Int, b: Int) -> Int => a + b

fn main() {
  let r = 5 |> dobra
  print("${r}")

  // O `|>` injeta o valor como PRIMEIRO argumento.
  print("${3 |> soma(b: 4)}")

  // Encadeado.
  print("${1 |> dobra |> dobra |> dobra}")
}
