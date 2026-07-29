// **CA da LT-F7c** — 2+ closures no MESMO member (spec 013 §11).
//
// É o buraco por onde o bug do oracle passaria verde, e a razão de a LT-F7a
// existir: no formato Kernel 130 a VM keya o `ClosureFunctionsCache` por
// `local_function_id` (`runtime/vm/closure_functions_cache.cc`). Duas closures
// no mesmo member com id `0` **colidem — a 2ª executa o corpo da 1ª**. O
// `LocalFunctionIdAssigner` do `sanitize.dart` existe para isso, e este fixture
// é a única coisa que o exercita: até hoje ele rodava sobre 5621 nós e alterava
// ZERO, declarado como vacuoso no golden-runner.
//
// **Co-verificação EXECUTADA (2026-07-29)** — a `tasks.md` exige que este CA
// falhe sem a LT-F7a, e ele falha. Com `lib.accept(ids)` comentado:
//
//     20    ✓
//     20    ← mais1(10) deveria dar 11: EXECUTOU O CORPO DE `dobra`
//     12    ✓
//     105   ✓
//     14    ← comBase(7) deveria dar 1007: `dobra` de novo (7 * 2)
//
// Duas das cinco closures rodaram o corpo da primeira. É a lição mais cara do
// projeto, reproduzida sob demanda — e a prova de que o passe de saneamento não
// é decorativo.
//
// Cobre também CAPTURA de variável externa — que o Kernel resolve sem contexto
// explícito (*"Variables ARE in scope across function boundaries"*, binary.md) —
// e a mesma closure usada DUAS vezes, que é onde um nó reusado viraria
// `Variable declared more than once` no verifier.

fn aplica(f: (Int) -> Int, v: Int) -> Int => f(v)

// Curry manual: a closure interna CAPTURA `n`, o parâmetro do member externo.
fn somador(n: Int) -> (Int) -> Int => (x: Int) -> Int => x + n

fn main() {
  // DUAS closures no mesmo member — ids 1 e 2, não 0 e 0.
  let dobra = (x: Int) -> Int => x * 2
  let mais1 = (x: Int) -> Int => x + 1

  // Se os ids colidirem, estas duas linhas imprimem o mesmo número.
  print("${aplica(f: dobra, v: 10)}")
  print("${aplica(f: mais1, v: 10)}")

  // A MESMA closure usada duas vezes: um nó reusado quebraria o verifier.
  print("${aplica(f: dobra, v: aplica(f: dobra, v: 3))}")

  // Captura: `soma5` fecha sobre o `n` de `somador`.
  let soma5 = somador(n: 5)
  print("${aplica(f: soma5, v: 100)}")

  // Uma terceira closure no mesmo member, capturando um local.
  let base = 1000
  let comBase = (x: Int) -> Int => x + base
  print("${aplica(f: comBase, v: 7)}")
}
