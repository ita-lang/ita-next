// **`+` de `String`** — chão da spec 012 §5.1 (*"`E → E₁ + E₂` … quando
// `E₁.type` é `List`/`String`"*), o irmão do `chao_concat.tu`.
//
// 🔴 **Este fixture nasceu de um BUG VIVO, achado em 2026-08-31 ao abrir a fatia
// da emissão.** Antes dele, `"ita" + "-lang"` emitia:
//
//     InstanceInvocation  name=+
//       interfaceTarget = num::+                      ← classe ERRADA
//       functionType    = String Function(num)        ← parâmetro num, arg String
//
// porque `_arithTarget` (`emit.dart`) escolhia o alvo pela **tag sintática**
// `BinaryOp.add`, sem olhar o tipo do receptor — a R1 no sítio do `+`: decisão
// da F7 com chave mais fraca (o token) do que a que a F5 já provou (o tipo).
//
// **Por que nenhum gate viu, medido nos três alvos:**
//
//     VM (JIT)  →  `ita-lang`, exit 0   (a VM resolve pelo receptor real e
//                                        DESCARTA o functionType)
//     JS        →  `ita-lang`, exit 0
//     AOT       →  `Attempt to execute code removed by Dart AOT compiler (TFA)`,
//                  exit 255
//
// A TFA conclui que um `String` nunca satisfaz `num` e **remove o corpo**. É
// literalmente o caso que o cabeçalho do `golden_test.dart` prevê — *"o AOT pega
// o que o JIT perdoa (`interfaceTarget` da classe errada)"* — e que ficou vivo
// porque o corpus não tinha nenhum `String + String`. Trinta runs de CI verdes
// sobre uma construção que não existia no corpus: o mesmo formato do `while`
// (memória `oraculo-com-o-mesmo-autor`).
//
// ⚠️ **A primeira correção deste bug cobriu só UM dos três sítios**, e o
// cabeçalho desta fixture chegou a afirmar que ela "fechava a classe". Não
// fechava: `_assign` e `_assignMember` seguiam com `_arithOpFor` cru, e
// `s += "x"` continuava morrendo em AOT. Ver `chao_string_compound.tu` e
// `chao_string_compound_campo.tu` — a cura só passou a ser uma quando virou uma
// função só (`_compoundTarget`).
//
// Os invariantes também não pegam, e a razão é fina: `checkNumericStaticTypes`
// cobra que nada com alvo em `num` tenha `returnType` **`num`** — mas o
// `_especializa` já trocara o retorno por `String`, então o gate via um nó
// "consertado" cujo ALVO seguia errado. O conserto de metade do nó mascarava a
// outra metade. E o `NaiveTypeChecker` ignora o `functionType` justamente nos
// operadores especializados (`type_checker.dart:1427`).
//
// Golden do oráculo Dart no pin 3.12.2: `'ita' + '-lang'` ⟶ `ita-lang`.

fn main() {
  let a: String = "ita"
  let b: String = "-lang"
  print(a + b)
}
