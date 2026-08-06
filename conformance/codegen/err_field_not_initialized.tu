// EXPECT-ERROR: field-not-initialized
//
// **CA NEGATIVO PERMANENTE.**
//
// Um `init` que não atribui todos os campos deixa um `Int` NON-NULLABLE sem
// valor. Até 2026-07-29 isso era F5-verde, F6-verde, e a F7 emitia um
// `Constructor` sem `FieldInitializer` para o campo faltante — o programa rodava
// e imprimia **`null`**.
//
// Terceiro `null` em tipo não-nullable da mesma auditoria, junto com o `return`
// nu sob `-> Int` e o payload default descartado. Os três: nenhuma fase dizia
// uma palavra, e o `verifyComponent` não type-checa.
//
// **Não é ruling — é consenso.** O invariante de nulidade ("nil só sob `T?`")
// não está em disputa, e o próprio `pkg/kernel` põe a obrigação no frontend,
// verbatim (`src/ast/initializers.dart:111-112`): *"The frontend should check
// that all final fields are initialized exactly once, and that no fields are
// assigned twice in the initializer list"*. O `checkInitializers` do verifier é
// função VAZIA (`verifier.dart:2194-2196`) — ninguém confere por nós.

class Registro {
  let nome: String
  let idade: Int

  init(nome: String) {
    self.nome = nome
    // `idade` fica sem valor — é isto que o erro acusa.
  }
}

fn main() {
  print("${Registro(nome: "ana").idade}")
}
