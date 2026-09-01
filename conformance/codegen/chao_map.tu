// **CA10 da spec 012 §11** — `[]` de `Map` ⟶ `V?`; chave ausente é `nil`.
//
// Emite `InstanceInvocation(x, Name('[]'), Arguments([k]),
// interfaceTarget = dart:core::Map::[])`. O `Map[]` nativo do Dart já devolve
// `V?`, e a ausência vem como `null`, que É o `nil` do Itá sob `T?`
// (spec 009 §4.6). O idioma é o `match` abaixo; a emissão não acrescenta guarda.
//
// ⚠️ **Os DOIS ramos, de propósito.** A letra do CA pede só a chave ausente
// (`vazio`). Um fixture com esse ramo sozinho ficaria verde sobre um `[]` que
// devolvesse `nil` SEMPRE — o defeito de "gate cuja falha-padrão é OK". A chave
// presente é o controle.
//
// Também é o único dos seis fixtures do chão com **2 declarações**, portanto o
// único que exercita a régua de ordem (`checkOrderIndependence`) neste bloco:
// os outros têm só `main` e imprimem "nada a permutar".
//
// Golden do oráculo Dart no pin 3.12.2: `<String,int>{'a':1}['a']` ⟶ `1`,
// `['k']` ⟶ `null`.

fn olha(x: Map<String, Int>, k: String) {
  match x[k] { .some(v) => print("achou ${v}"), nil => print("vazio") }
}

fn main() {
  let m: Map<String, Int> = {"a": 1}
  olha(m, "a")
  olha(m, "k")
}
