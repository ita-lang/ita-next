// **Chão dentro de chão** — `Map<String, List<Int>>` e `List<Map<String, Int>>`.
//
// Nenhum CA da spec 012 §11 aninha, e o aninhamento é exatamente onde a
// substituição de type-args deixa de ser trivial: `l[0]["z"]` instancia o `[]`
// de `Map` sobre um receptor que é ele próprio o resultado do `[]` de `List`.
// Com `Substitution.fromInterfaceType` do tipo ERRADO — ou com o `functionType`
// genérico —, o `E` de um vazaria para dentro do outro, e o `verifyComponent`
// acusaria *"Type parameter referenced out of scope"* num nó que o fixture
// plano nunca produz.
//
// Também é o único fixture do bloco onde o `V?` do `Map` carrega um tipo
// COMPOSTO (`List<Int>?`): a combinação de nulidade da substituição
// (`type_algebra.dart:1076-1088`) tem de sobreviver ao `.length` que vem depois
// do `match`.
//
// Golden do oráculo Dart no pin 3.12.2: `z=5` e `len=3`.

fn main() {
  let m: Map<String, List<Int>> = {"a": [1, 2, 3]}
  let l: List<Map<String, Int>> = [{"z": 5}]
  match l[0]["z"] { .some(v) => print("z=${v}"), nil => print("sem z") }
  match m["a"] { .some(v) => print("len=${v.length}"), nil => print("vazio") }
}
