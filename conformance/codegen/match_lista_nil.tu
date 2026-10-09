// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// **`nil` como ELEMENTO de list-pattern** — `List<Int?>`, a interseção das duas
// famílias que a §7.4-e trata separado.
//
// Este fixture não estava no plano do T043. Ele saiu da **varredura de
// alcançabilidade** feita depois de a fatia já estar verde nos três alvos: para
// cada forma de sub-pattern que a gramática permite dentro de `[...]`, rodar um
// programa e ver onde ele para. `[nil]` sobre `List<Int?>` era F5+F6-verde e
// morria em `ice-codegen-match-list-eq-on-OptionalType` — fronteira alcançável,
// sem catraca, e sem ninguém saber que existia.
//
// **Por que caía.** O ramo de literal procurava o `==` do tipo do elemento na
// tabela `equalsOps`, e não há entrada para `OptionalType` — nem poderia haver:
// a §7.4-e manda `.none`/`nil` virar `null` NATIVO, e o CA10 cobra que **não
// exista classe `Option` no `.dill`**. O gabarito certo já estava escrito, para
// o subject; faltava aplicá-lo ao elemento. Três linhas (`EqualsNull`), o que
// torna a R6 fácil aqui: implementar, não declarar limite.
//
// ⚠️ **`nil` NÃO é `EnumPattern`.** Ele chega como `LiteralPattern` com
// `NilLit` (o parser o converte, e a F6 o classifica como `_HCtor('none')`),
// por isso é tratado no ramo do literal e não cai na fronteira dos patterns
// compostos. Um `[.some(v), ..]` — que é `EnumPattern` — continua na fronteira,
// preso por `ice_match_list_nested_test.tu`: a diferença não é a família Option,
// é ter ou não sub-estrutura a destruir.
//
// As três posições estão aqui de propósito — prefixo, meio e SUFIXO —, porque o
// elemento do sufixo tem índice calculado (`S.length - k`) e um `nil` ali passa
// por um caminho que os outros dois não exercitam.
//
// Golden do oráculo Dart no pin 3.12.2 (list-patterns nativos, lowering do CFE).

fn soNil(xs: List<Int?>) -> Bool => match xs {
  [nil] => true,
  _ => false
}

fn segundoNil(xs: List<Int?>) -> Bool => match xs {
  [_, nil, ..] => true,
  _ => false
}

fn terminaNil(xs: List<Int?>) -> Bool => match xs {
  [.., nil] => true,
  _ => false
}

fn main() {
  let so: List<Int?> = [nil]
  let um: List<Int?> = [1]
  let comMeio: List<Int?> = [1, nil, 2]
  let comFim: List<Int?> = [1, nil]

  print("${soNil(so)} ${soNil(um)} ${soNil(comMeio)}")
  print("${segundoNil(comMeio)} ${segundoNil(comFim)} ${segundoNil(um)}")
  print("${terminaNil(comFim)} ${terminaNil(comMeio)} ${terminaNil(so)}")
}
