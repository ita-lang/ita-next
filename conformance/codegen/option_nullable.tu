// §7.4-c — `Option<T>` ≡ `T?` → **NULLABLE NATIVO** do Kernel. `nil` → `null`.
//
// É a metade executável do **CA10**: *custo zero*. Não existe classe `Option` no
// `.dill` — o opcional é a MESMA `DartType` do interno com
// `Nullability.nullable`, e `nil` é `NullLiteral`, não um `.none` construído.
//
// ⚠️ **Note o que este fixture NÃO faz: imprimir um opcional.** Pelo ruling do
// dono (2026-07-28), `${x}` com `x: T?` é ERRO — `optional-in-interpolation`. O
// dev desembrulha antes. Então a prova de que o opcional ATRAVESSA (`let`,
// parâmetro, retorno, campo de `struct`) é o programa COMPILAR e rodar; o que ele
// imprime é sempre não-opcional.
//
// Quem prova o "custo zero" de verdade é o invariante `checkNoSyntheticClasses`:
// toda `Class` no `.dill` tem de corresponder a um `struct`/`class` DECLARADO.
// Um wrapper de opcional apareceria como classe a mais e **rodaria igual** — só
// alocando um objeto por valor. Nenhum golden de stdout perceberia.
//
// Por que isso é herança e não implementação: a Dart VM já tem nulidade no
// sistema de tipos, então usá-la traz o Grupo B inteiro de graça (unboxing,
// null-check elidido pela TFA). Reimplementar `Option` como classe pagaria por
// algo que a plataforma dá.
//
// A outra metade do CA10 (o `match` imprimindo o braço `.none`) espera a fatia de
// `match` — assim como `??`, `?.` e `!`, que desugaram para `match`.

struct Usuario {
  nome: String,
  apelido: String?
}

fn talvez(v: Int?) -> Int? => v

fn contaOpcional(v: Int?) -> Int => 1

fn main() {
  // o opcional existe, atravessa e não imprime a si mesmo
  let vazio: Int? = nil
  let cheio: Int? = 5
  print("opcionais declarados=${contaOpcional(vazio) + contaOpcional(cheio)}")

  let sem = Usuario(nome: "Itá", apelido: nil)
  let com = Usuario(nome: "Pedra", apelido: "pedrinha")
  print("nomes=${sem.nome},${com.nome}")

  // ida-e-volta pela fronteira de `fn`: entra `Int?`, sai `Int?`
  print("ida-volta=${contaOpcional(talvez(cheio))}")
  print("com nil=${contaOpcional(talvez(vazio))}")
}
