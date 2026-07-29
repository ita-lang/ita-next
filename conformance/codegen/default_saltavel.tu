// **CA2 da §11** — `struct P { x: Int, y: Int = 2 }` + `P(x: 1).y` ⟶ `2`.
// *"Defaults saltáveis chegam ao Kernel."*
//
// O default vira `VariableDeclaration.initializer` e **quem o materializa é a
// VM** (§7.4-a, Grupo B). A F7 emite a expressão UMA vez, no parâmetro; o
// call-site que salta simplesmente não manda o named.
//
// **É este fixture que fecha a decisão de named-params (ruling §12-3).** A regra
// do Itá é *"ordem obrigatória, defaults saltáveis"*: `Config(host:, seguro:,
// nome:)` salta `porta` e `timeout`, que estão no **MEIO**. O posicional do Dart
// só corta do FIM (`requiredParameterCount`), então com posicional a F7 teria de
// materializar cada default por call-site. Named é o que preserva a regra de
// graça — e a linha "salta o meio" abaixo é a prova executável disso.
//
// ⚠️ **O default tem de ser `ConstantExpression`, não a expressão comum.** Um
// `IntLiteral` cru faz a VM morrer no LOAD com *"Not a constant expression:
// unexpected kernel tag SpecializedIntLiteral"* — não é o verifier que reprova,
// é o carregador, em runtime, depois de tudo passar. A restrição é do Dart
// (default de param é const) e é o preço de deixar a VM materializar. Default
// não-constante vira ICE `default-not-const-<T>`: materializar no call-site
// seria uma decisão de emissão que a §7.4-a não tomou.
//
// A mesma peça vale para param de `fn` — a decisão §12-3 é uma só.

struct Config {
  host: String,
  porta: Int = 8080,
  seguro: Bool = false,
  timeout: Float = 1.5,
  nome: String = "padrao"
}

fn conecta(host: String, porta: Int = 80, retry: Int = 3) -> String =>
  "${host}:${porta} retry=${retry}"

fn main() {
  // o CA2 literal da spec
  print("CA2=${Config(host: "h").porta}")

  let todos = Config(host: "localhost")
  print("defaults: ${todos.host} ${todos.porta} ${todos.seguro} ${todos.timeout} ${todos.nome}")

  let expl = Config(host: "srv", porta: 443, seguro: true, timeout: 9.0, nome: "prod")
  print("explicitos: ${expl.host} ${expl.porta} ${expl.seguro} ${expl.timeout} ${expl.nome}")

  // SALTA OS DO MEIO — `porta` e `timeout` ficam no default
  let misto = Config(host: "srv", seguro: true, nome: "misto")
  print("salta o meio: ${misto.host} ${misto.porta} ${misto.seguro} ${misto.timeout} ${misto.nome}")

  // a mesma regra em `fn`
  print(conecta(host: "a"))
  print(conecta(host: "b", porta: 443))
  print(conecta(host: "c", retry: 9))
}
