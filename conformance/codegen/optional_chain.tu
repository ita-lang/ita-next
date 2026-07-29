// spec 010 §4.1-b (ruling do dono, 2026-07-28) — o contexto DESCE em `if`-expr e
// em `match`, e é isso que faz o **`?.`** existir na prática.
//
// Antes do ruling, `u?.nome` dava `cannot-infer` **mesmo com anotação
// explícita**. A causa não era o `?.`: o desugar dele produz
// `match u { .some($x) => $x.nome, .none => .none }`, e os braços eram
// SINTETIZADOS — a síntese de um braço `.none`/`nil` falha por construção
// (é forma checking-only, §4.3). O açúcar existia na superfície e não tipava.
//
// Com o esperado descendo a cada braço, o `.none` é checado contra `String?` e
// tudo fecha. As três formas abaixo passam pelo mesmo caminho:
//   - `?.` (desugarado para `match`);
//   - `match` escrito à mão com `nil` num braço;
//   - `if`-expr com `nil` num ramo.
//
// A emissão do `.none`-valor é `NullLiteral` — a MESMA do `nil`, porque é a
// mesma coisa: `Option` ≡ `T?`, e a variante vazia é a ausência nativa. Custo
// zero preservado (o invariante `checkNoSyntheticClasses` guarda).

struct Usuario {
  nome: String,
  apelido: String?
}

fn main() {
  let com: Usuario? = Usuario(nome: "Itá", apelido: "pedrinha")
  let sem: Usuario? = nil

  // `?.` — o que o ruling destravou
  let a: String? = com?.nome
  let b: String? = sem?.nome
  print("chain com=${a ?? "-"}")
  print("chain sem=${b ?? "-"}")

  // `match` à mão com `nil` num braço
  let m: String? = match com { .some(u) => u.nome, .none => nil }
  print("match=${m ?? "-"}")

  // `if`-expr com `nil` num ramo
  let i: String? = if true => nil else "x"
  print("if=${i ?? "vazio"}")

  // encadeado com campo que JÁ é opcional
  let ap: String? = com?.apelido
  print("apelido=${ap ?? "-"}")
}
