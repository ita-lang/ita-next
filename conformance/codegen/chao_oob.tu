// **CA9 da spec 012 §11** — `[]` fora de faixa ⟶ panic, exit ≠ 0.
//
// Ruling do dono registrado na spec 012 §0.6 e assentado na spec 012 §4.3:
// semântica A — o `[]` nativo já dispara `RangeError` e a F7 não emite guarda;
// o throw sobe sem nada o capturar (P7, zero try/catch) e o isolate morre.
//
// A linha `antes` prova que o stdout ATÉ o estouro é preservado: sem ela, um
// `.dill` que morresse na ENTRADA de `main` (antes de qualquer emissão do chão)
// daria o mesmo exit 255 e passaria por este fixture.
//
// ⚠️ **Por que `EXPECT-STDERR: RangeError` e não a classe nem a mensagem.**
// Os três alvos divergem na CLASSE e convergem no stderr: `RangeError` na
// VM/AOT, `IndexError` no dart2js — mas `IndexError._errorName` devolve
// `"RangeError"` (`core/errors.dart:535`), então os três imprimem stderr
// começando por `RangeError`. Assertar a classe passaria na VM e quebraria no JS
// por diferença que não é nossa. Assertar a mensagem inteira também: o oráculo
// Dart no pin 3.12.2 devolve `RangeError (length): Invalid value: Only valid
// value is 0: 5` — o `(length)` e a faixa dependem do tamanho da lista.
//
// E é a substring que impede o verde pelo motivo ERRADO: `interfaceTarget` na
// classe errada produziria `NoSuchMethodError`, que também sai 255.
//
// ⚠️ **A catraca é boa; a MENSAGEM que ela congela é decisão pendente do dono.**
// O `EXPECT-STDERR` acima transforma em contrato versionado uma superfície que
// ninguém escolheu: o Itá morre hoje de duas formas visíveis — `panic: <msg>`
// (sintetizada pelo runtime, ver `panic_exit.tu`) e `RangeError (length): …`,
// sem prefixo `panic:`, sem span, nomeando uma classe de `dart:core` que o `.tu`
// nunca menciona. Não mente — mas fala Dart, e o Norte do Art. II é *"usar a
// Dart VM sem SER Dart"*. **Em aberto:** panic vindo de intrínseco ganha formato
// Itá (`panic:` + span), ou a mensagem do alvo é a resposta final? Enquanto não
// houver ruling, esta linha declara que o formato é herdado, não escolhido — a
// mesma função que o `chao_literal_nu.tu` cumpre para o literal nu.
//
// O exit **255** é da VM/AOT (`error_exit.h::kErrorExitCode`); o node sai **1**.
// O runner só exige que o sinal ≠ 0 bata entre alvos, nunca o número.
//
// EXPECT-EXIT: 255
// EXPECT-STDERR: RangeError

fn main() {
  print("antes")
  let xs: List<Int> = [1]
  print("${xs[5]}")
}
