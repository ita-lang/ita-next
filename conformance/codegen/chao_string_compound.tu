// **`a = a + b` e `a += b` têm de emitir o MESMO alvo.** Fixture METAMÓRFICO: o
// que ele afirma é uma relação entre duas formas do mesmo operador, não um
// valor — e é por isso que ele pega o que os goldens de valor não pegam.
//
// 🔴 **Nasceu de um bug que a PRIMEIRA correção do `+` deixou de pé, com a prosa
// dizendo que a classe tinha fechado.** Em 2026-08-31 o `_binary` passou a
// escolher o alvo do `+` pelo tipo do receptor — e `_assign` seguiu chamando
// `_arithOpFor` cru. As duas linhas abaixo, no mesmo programa, emitiam alvos
// DIFERENTES para o mesmo operador sobre os mesmos tipos:
//
//     print(a + b)     → String::+    ✅
//     c += "-lang"     → num::+       ❌  functionType = String Function(num)
//
// O programa é legal — a `_primitiveOps` da F5 tem a linha
// `(String, String) → String` (`check.dart:55`) e o compound consulta a MESMA
// tabela (`check.dart:2100`). Desfecho por alvo: `ita-lang` no JIT, `ita-lang`
// no JS, e `Attempt to execute code removed by Dart AOT compiler (TFA)` +
// exit 255 em AOT, porque a TFA conclui que `String` nunca satisfaz `num`.
//
// **A régua violada já estava escrita no corpus, para o outro operador com a
// mesma armadilha** — `var_assign.tu:13-15`, verbatim: *"`/=` passa pelo MESMO
// despacho por tipo que o `/` binário. A armadilha `~/` (Int) × `/` (Float) não
// pode ser fechada numa forma e reaberta na outra"*. O `div` a respeitava porque
// o resolvedor era compartilhado; o `+` a violou porque o desvio do chão nasceu
// ACIMA dele. A cura foi levá-lo para dentro (`_arithAlvo`, um sítio para as
// três formas), não replicá-lo.
//
// **O corpus não tinha nenhum `+=` sobre `String`** — os três `+=` de
// `conformance/` (`var_assign.tu`, `valor_l_efeito.tu`, `class_ca3.tu`) são
// numéricos. Mesma assinatura do bug original: a construção não existia, e o
// verde não dizia nada sobre ela.
//
// Golden do oráculo Dart no pin 3.12.2: `'ita' + '-lang'` ⟶ `ita-lang`, pelas
// duas formas.

fn main() {
  let a: String = "ita"
  let b: String = "-lang"
  print(a + b)

  var c: String = "ita"
  c += "-lang"
  print(c)
}
