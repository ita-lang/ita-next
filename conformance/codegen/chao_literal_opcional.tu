// **Literal de coleção sob esperado OPCIONAL** — `let xs: List<Int>? = [1, 2]`.
//
// 🔴 **Nasceu de um ICE sobre programa LEGAL** — violação da R6, não fronteira.
// Medido em 2026-09-01: `itac check` dava exit 0 e `itac build` dava
// `ice-codegen-list-literal-typed-OptionalType`. O emitter lia a nº1 esperando
// um `BuiltinType` e recebia o `OptionalType` que a envolve.
//
// A legalidade é **decisão escrita** da F5, não acidente — `check.dart:2801-2802`,
// verbatim: *"`T?` desembrulha para validar e descer: `let xs: List<Int>? = [1]`
// é legal (subsunção `T ≤ T?`) e o `?` não muda o que os elementos são"*. Ela
// desembrulha para validar e descer (`:2804`) e então grava o **`expected`
// inteiro** (`:2848`), com o `?`. Quem lê a nº1 tem de fazer o mesmo
// desembrulho — ou lê um tipo que a F5 nunca prometeu ser o do container.
//
// É o formato de bug mais caro deste repo: a fase anterior tinha a decisão
// documentada no próprio docstring, e a fase seguinte a ignorou por não a ter
// lido. Não foi o gate que pegou — foi a revisão adversarial de contexto limpo.
//
// O `Map` no mesmo fixture porque o defeito era um só, em dois métodos
// (`_listExpr` e `_mapExpr`), e um fixture de List sozinho deixaria metade viva.
//
// Golden do oráculo Dart no pin 3.12.2: `<int>[1,2].length` ⟶ `2`;
// `<String,int>{'a':1}.length` ⟶ `1`.

fn main() {
  let xs: List<Int>? = [1, 2]
  let m: Map<String, Int>? = {"a": 1}
  match xs { .some(v) => print("${v.length}"), nil => print("vazio") }
  match m { .some(v) => print("${v.length}"), nil => print("vazio") }
}
