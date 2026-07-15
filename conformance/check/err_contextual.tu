// Fatia C — tipagem contextual (spec 010 §4.1/§4.2/§4.3).
// Os casos SEM erro estão de propósito no meio: o runner casa a lista EXATA,
// então um falso-positivo neles quebra o fixture.
// EXPECT-CHECK: cannot-infer
// EXPECT-CHECK: cannot-infer
// EXPECT-CHECK: closure-arity-mismatch
// EXPECT-CHECK: type-mismatch

fn dobra(xs: List<Int>, f: (Int) -> Int) -> List<Int> => xs
fn mapa<T, U>(xs: List<T>, f: (T) -> U) -> List<U> => []

// --- SÍNTESE: closure sem buraco não precisa de contexto (§4.2.1) ---------
// Antes da fatia C tudo isto era `cannot-infer` — um "não consigo" FALSO.
fn sintetiza() {
  let a = (x: Int) -> Int => x
  let b = () => 5
  let c = (x: Int) => x
}

// --- CHECKING-ONLY: o param é o buraco; o contexto o preenche ------------
fn herda(xs: List<Int>) {
  let a: (Int) -> Int = (x) => x
  let b = dobra(xs) { $0 * 2 }
  let c: List<Int> = mapa(xs) { $0 + 1 }
  // Aridade CONTEXTUAL (§12-A): sem `$k`, adota a esperada e ignora o arg.
  let d: List<String> = mapa(xs) { "n" }
  // `[]`/`{}` sob anotação (§4.1).
  var e: List<Int> = []
  var f: Map<String, Int> = {}
}

// Sem contexto, o param não tem de onde vir (ADR-0013: erro, nunca dynamic).
fn semContexto() { let c = (x) => x }

// `[]` tem ZERO subexpressões ⟹ 6.5.1 não tem de que construir. Definicional.
fn listaSolta() { let x = [] }

// Com `$k` a aridade do scan da F3 VALE: `dobra` quer 1, o `$1` faz 2.
fn aridade(xs: List<Int>) { let r = dobra(xs) { $0 + $1 } }

// O `U` do corpo diverge do `List<String>` esperado.
fn retornoErrado(xs: List<Int>) { let r: List<String> = mapa(xs) { $0 + 1 } }
