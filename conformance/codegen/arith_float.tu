// §7.4-a — `Float` (→ `double` do Dart, IEEE-754 binary64): `FloatLit` baixa como
// `DoubleLiteral`, e os aritméticos vão para os MESMOS operadores de
// `dart:core::num` que os de `Int` (herdados por `double`).
//
// ⚠️ **A linha `div` é a gêmea da de `arith_int.tu`, e trava a armadilha ao
// CONTRÁRIO.** A tabela da F5 admite `div` nas duas formas — `(Int,Int)→Int` e
// `(Float,Float)→Float` — mas os alvos do Kernel são DIFERENTES: `~/` devolve
// `int`, `/` devolve `double`. Emitir `~/` aqui renderia `3`, e o tipo estático
// (`Float`) estaria mentindo sobre o valor. Cada operador é o errado para o
// outro tipo; os dois fixtures juntos é que fecham a porta nos dois sentidos.
//
// JS-DIVERGE: em JS todo número é double, e um double de valor inteiro imprime SEM o `.0` — `mul=3` contra `mul=3.0` da VM (spec 013 §12-6)
//
// A divergência é do ALVO, não da emissão: o mesmo `.dill` produz `3.0` na VM e
// no AOT. O `dart2js` não tem `int` separado de `double` para imprimir, e o
// próprio Dart assume isso na web. É a postura que a **spec 013 §12-6** mandou
// seguir — *"MATCH é o default do golden-runner"*, e o que diverge se declara.
// O golden `arith_float.js.out` guarda a saída do JS, e o runner exige que ela
// realmente DIFIRA: no dia em que empatar, a diretiva reprova e sai daqui.

fn main() {
  let x = 1.5
  print("lit=${x}")
  print("soma=${1.5 + 2.0}")
  print("sub=${5.5 - 2.0}")
  print("mul=${1.5 * 2.0}")
  print("div=${7.0 / 2.0}")
  print("mod=${7.5 % 2.0}")
  print(if 1.5 < 2.5 => "lt ok" else "lt FALHOU")
  print(if 1.5 == 1.5 => "eq ok" else "eq FALHOU")
}
