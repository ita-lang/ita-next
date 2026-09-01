// **O estado que o programa não consegue observar** — `Map<K, V?>` e o `[]` do
// chão. Dívida DECLARADA na errata da spec 012 §4.1, à espera do dono.
//
// Este fixture não celebra o comportamento: ele o **congela onde dá para ver**.
// O `[]` de `Map` devolve `optional(V)` (`check.dart:2363`), e `?` é modificador
// idempotente — `T?? = T?` pelo ruling da spec 009 §12-1 (smart constructor em
// `compiler/lib/frontend/semantic/type.dart:212-216`). Para `V = Int?` os dois
// casos colapsam no MESMO valor:
//
//     chave ausente                  ⟶ nil
//     chave presente com valor `nil` ⟶ nil
//
// A saída abaixo é a prova: `length` diz que o mapa tem **1 entrada**, e as duas
// consultas dizem `vazio`. Existe uma chave no mapa que este programa não
// alcança. O chão é uma *"tabela de tipos fixa e pequena"* (spec 012 §4.1) e não
// traz `containsKey`, então nada nele desempata os dois casos.
//
// ⚠️ **A atribuição importa.** A doc do `dart:core::Map` avisa do mesmo problema
// (`map.dart:263-269`), e é tentador escrever que o Itá "herda" a ambiguidade do
// Dart. Não herda: quem faz os dois casos colapsarem é o `T?? = T?` do Itá.
// Chamar isso de herança seria transferir o sujeito — descrever uma decisão
// nossa como limite de ferramenta.
//
// **Ao dono, em aberto:** o chão ganha um observador de chave, ou a linguagem
// aceita que um programa alcance estado que não consegue observar? Enquanto não
// houver resposta, este fixture fica — e quando houver, ele fica VERMELHO e
// cobra a atualização, em qualquer direção.
//
// Golden do oráculo Dart no pin 3.12.2: `<String,int?>{'presente': null}` tem
// `length` 1, e `['presente']` e `['ausente']` são ambos `null`.

fn olha(m: Map<String, Int?>, k: String) {
  match m[k] { .some(v) => print("  ${k}: achou ${v}"), nil => print("  ${k}: vazio") }
}

fn main() {
  let m: Map<String, Int?> = {"presente": nil}
  print("length = ${m.length}")
  olha(m, "presente")
  olha(m, "ausente")
}
