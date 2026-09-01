// **CA4 da spec 012 §11** — `.length` de `String` ⟶ `3`. **Na letra do CA**: é o
// único dos seis cujo receptor não é literal de coleção, então nada aqui depende
// do ruling do literal nu.
//
// Emite `InstanceGet(s, Name('length'), dart:core::String::length)`.
// `String.length` conta **UTF-16 code units**, nos dois alvos (`js_string.dart:452`
// é MATCH com a VM) — `"olá"` são 3 code units porque `á` (U+00E1) está no BMP.
// Um `"olá"` com `a` + combining acute (U+0301) daria 4, e é por isso que o
// golden não pode ser lido como "número de letras".
//
// ⚠️ **Este fixture cobra um ICE que MENTE.** Medido em 2026-08-31, hoje ele dá
// `ice-codegen-member-unresolved` — nome de ESTADO DO EMISSOR, não de
// construção. A causa real é outra: a F5 tipa `.length` do chão e **retorna sem
// popular a nº3** (`check.dart:2411-2412` — `_groundField` devolve antes do
// `_lookup`, que só sabe de `NamedType`), então `resolvedMembers[m]` é `null` por
// DESIGN, não por falta de resolução. A R7 proíbe pendurar catraca num código
// assim, e a R6 chama isso de `_ice` que mente sobre a causa: a emissão do chão
// lê o receptor pela nº1 (`exprTypes`), não pela nº3.
//
// Golden do oráculo Dart no pin 3.12.2: `"olá".length` ⟶ `3`.

fn main() {
  print("${"olá".length}")
}
