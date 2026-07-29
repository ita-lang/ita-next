// §7.4-c — `Option<T>` ≡ `T?` → **NULLABLE NATIVO** do Kernel. `nil` → `null`.
//
// É a metade executável do **CA10**: *custo zero*. Não existe classe `Option` no
// `.dill` — o opcional é a MESMA `DartType` do interno com
// `Nullability.nullable`, e `nil` é `NullLiteral`, não um `.none` construído. A
// outra metade do CA10 (o `match` imprimindo o braço `.none`) espera a fatia de
// `match`.
//
// O invariante `checkNoSyntheticClasses` é quem prova o "custo zero" de verdade:
// toda `Class` no `.dill` tem de corresponder a um `struct`/`class` DECLARADO.
// Um wrapper de opcional apareceria como classe a mais e **rodaria igual** — só
// alocando um objeto por valor. Nenhum golden de stdout perceberia.
//
// Por que isso é herança e não implementação: a Dart VM já tem nulidade no
// sistema de tipos, então usá-la traz o Grupo B inteiro de graça (unboxing,
// null-check elidido pela TFA). Reimplementar `Option` como classe pagaria por
// algo que a plataforma dá.
//
// ⚠️ **LACUNA DECLARADA — a interpolação de `nil` imprime `null`.** O usuário
// escreve `nil` e vê `null`: é o `toString()` da VM (Grupo B) vazando a palavra
// do Dart na superfície do Itá. Está no golden abaixo como está HOJE, não como
// deveria ser. É ruling de linguagem (o que `${opcional}` deve imprimir), não
// decisão da emissão — roteado ao dono.
//
// Ainda NÃO cobertos, e não por acaso: `??`, `?.` e `!` desugaram para `match`
// (verificado no `itac desugar --dump`), logo dependem daquela fatia.

struct Usuario {
  nome: String,
  apelido: String?
}

fn talvez(v: Int?) -> Int? => v

fn main() {
  let vazio: Int? = nil
  let cheio: Int? = 5
  print("vazio=${vazio} cheio=${cheio}")

  let sem = Usuario(nome: "Itá", apelido: nil)
  let com = Usuario(nome: "Pedra", apelido: "pedrinha")
  print("campo sem=${sem.apelido}")
  print("campo com=${com.apelido}")

  print("ida-volta=${talvez(7)}")
  print("param-nil=${talvez(vazio)}")
}
