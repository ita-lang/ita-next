// §7.4-c — `struct` → `Class` com campos **todos `final`** + `Constructor`
// memberwise de params named; `P(x: 1)` → `ConstructorInvocation`; `p.x` →
// `InstanceGet`. É o **CA2 da §11** ("struct memberwise") na sua forma mínima.
//
// **Todos os campos `final` é RULING (§12-1), não otimização.** Struct é imutável
// SEMPRE — campo `var` morre na F5 (`mut-field-on-struct`), e `s.n = 2` morre
// como `assign-to-immutable`. É isso que torna a cópia-valor INOBSERVÁVEL:
// valor imutável não tem identidade a perder, então representar `struct` por
// REFERÊNCIA no Kernel não quebra P2. Sem o ruling, esta mesma emissão mataria o
// P2 em silêncio — o `.dill` faria sharing onde a linguagem promete cópia.
//
// O `Constructor` recebe `EmptyStatement` e trabalha nos `initializers`
// (`FieldInitializer` por campo): é a forma que o Kernel exige para campo
// `final`, que não pode ser atribuído no corpo.
//
// Cobre ainda: campo de cada tipo do chão (Int/String/Float/Bool) e struct
// ANINHADO (`Retangulo.origem: Ponto`) — o campo cujo tipo é outra `Class`, que
// só resolve porque os tipos são registrados ANTES das assinaturas.

struct Ponto {
  x: Int,
  y: Int
}

struct Retangulo {
  origem: Ponto,
  largura: Int,
  altura: Int
}

struct Pessoa {
  nome: String,
  altura: Float,
  ativo: Bool
}

fn main() {
  let p = Ponto(x: 3, y: 4)
  print("ponto=${p.x},${p.y}")

  let r = Retangulo(origem: Ponto(x: 0, y: 7), largura: 3, altura: 4)
  print("area=${r.largura * r.altura}")
  print("aninhado=${r.origem.y}")

  let quem = Pessoa(nome: "Itá", altura: 1.75, ativo: true)
  print("${quem.nome} ${quem.altura} ${quem.ativo}")
}
