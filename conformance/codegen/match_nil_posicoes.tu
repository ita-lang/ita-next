// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// 🔴 **`nil` em pattern, nas TRÊS posições — dois bugs vivos, achados em
// 2026-09-01 pelo simétrico de um terceiro.**
//
// `nil` num pattern **não** é literal escalar como `0` ou `"a"`. Pela §7.4-e,
// `.none`/`nil` viram `null` NATIVO, e o CA10 cobra que não exista classe
// `Option` no `.dill` — logo não há `operator ==` de `Option` a chamar. O
// gabarito é `EqualsNull`, e ele estava escrito **só para o subject**, dentro do
// ramo de `EnumPattern` (`.none`). Nas outras posições o `nil` chega como
// `LiteralPattern` e caía no caminho do `==`:
//
//     match x { nil => …, .some(v) => … }     ⟶ ice-codegen-match-eq-on-OptionalType
//     match c { C { v: nil } => … }           ⟶ ice-codegen-untyped-NilLit
//     match xs { [nil] => … }                 ⟶ ice-codegen-match-list-eq-on-OptionalType
//
// Os três são programas **F5+F6-verdes**. O terceiro nasceu com a fatia do
// list-pattern (T043); procurar o simétrico dele nas outras duas posições é o
// que revelou os dois primeiros, que já estavam mergeados.
//
// ⚠️ **O do campo era o pior formato.** A F5 não grava `exprTypes` para o
// `NilLit` de um pattern **de propósito** (`check.dart:801-807`, verbatim:
// *"`nil` é o caso especial: casa exatamente `T?` e NÃO sintetiza"*), então
// emitir o literal batia na pré-condição da porta e dava um ICE que nomeia
// ESTADO do emissor — ele dizia *"não tipado"* quando a verdade era *"este
// gabarito não foi aplicado aqui"*. E ele passava pelo `_equalsForKernelType`
// sem ser barrado, porque essa função resolve por `classNode.name` e o
// `classNode` de `int?` é `int` — a chave mais fraca devolvendo uma resposta
// plausível e errada (R1).
//
// ⚠️⚠️ **Por que 30 dias de CI verde não pegaram.** Os seis `match … { … nil
// => … }` de `conformance/codegen/` escrevem o braço `nil` **por último** — e o
// último braço do right-fold não ganha teste, vira o `otherwise`. Seis fixtures,
// seis vezes a mesma ordem idiomática, e a outra nunca. É o oráculo com o mesmo
// autor: não faltou cobertura de linha, faltou a **permutação**. Por isso
// `olhaA`/`olhaB` abaixo são o MESMO match com os braços trocados, e a saída
// idêntica é o que o fixture prova.
//
// **A régua violada já estava escrita no repo**, para o `+` de `String`, que
// tinha exatamente esta forma — corrigido num sítio e reaberto em dois. Verbatim
// de `conformance/codegen/var_assign.tu:13-15`: *"a armadilha `~/` (Int) × `/`
// (Float) não pode ser fechada numa forma e reaberta na outra"*. Por isso a cura
// é um sítio só (`_nilTest`), chamado pelos três.
//
// Golden do oráculo Dart no pin 3.12.2.

struct C { v: Int?, tag: String }

// A PERMUTAÇÃO: o mesmo match, `nil` primeiro e `nil` por último.
fn olhaA(x: Int?) -> String => match x { nil => "vazio", .some(v) => "tem ${v}" }
fn olhaB(x: Int?) -> String => match x { .some(v) => "tem ${v}", nil => "vazio" }

fn campo(c: C) -> String => match c {
  C { v: nil, tag: t } => "vazia ${t}",
  C { v: x, tag: t } => "cheia ${t}"
}

fn elemento(xs: List<Int?>) -> String => match xs {
  [nil] => "so-nil",
  [.., nil] => "termina-nil",
  _ => "outro"
}

fn main() {
  let tem: Int? = 7
  let vazio: Int? = nil

  print("${olhaA(tem)} ${olhaA(vazio)}")
  print("${olhaB(tem)} ${olhaB(vazio)}")

  print("${campo(C(v: nil, tag: "a"))} ${campo(C(v: 7, tag: "b"))}")

  let so: List<Int?> = [nil]
  let fim: List<Int?> = [1, nil]
  let nao: List<Int?> = [1, 2]
  print("${elemento(so)} ${elemento(fim)} ${elemento(nao)}")
}
