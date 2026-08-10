// EXPECT-ICE: ice-codegen-class-multi-init
//
// **A fronteira que o CA3 NÃO fechou, e que estava sem catraca.** O CA3 fez os
// `init` de `extension` virarem `Constructor` adicionais (ADR-0016 §B); dois
// `init` no **CORPO** da mesma `class` continuam ICE.
//
// A distinção não é do emissor — o mecanismo é o mesmo, e emitir o segundo com
// nome derivado dos labels custaria uma linha. O que falta é o **ruling**: dois
// `init` no corpo com labels distintos é **overload de construtor**, e o do dono
// diz *"o Itá não tem overload de método"* (spec 011 §12-4) — construtor não
// estava na frase. O ADR-0016 §B decidiu outro eixo, o `corpo × extension`:
// *"`init` no CORPO **mata** o memberwise; em **`extension`** o **PRESERVA**"*.
// Quantos cabem no corpo ninguém decidiu.
//
// ⚠️ **A F5 não acusa isto** — medido em 2026-08-10, e não deduzido: este
// programa atravessa a F5 inteira e morre aqui. O `duplicate-init` desta fatia
// compara os candidatos de `extension` contra o primário; `TypeInfo.init` guarda
// um só, e o segundo `init` do corpo é descartado em silêncio lá. Enquanto o
// ruling não vem, o ICE é o diagnóstico HONESTO: nomeia a construção, não estado
// do emissor.
//
// As duas saídas, quando o dono decidir:
//   - porta ABRE  ⟹ vira `Constructor` nomeado, como os de `extension`;
//   - porta FECHA ⟹ vira `duplicate-init` na F5, estendido ao corpo.
// Em ambas, este fixture morre — que é o que uma catraca deve fazer.

class Conta {
  var saldo: Int

  init(inicial: Int) {
    self.saldo = inicial
  }

  init(zerada: Int) {
    self.saldo = 0
  }
}

fn main() {
  let c = Conta(inicial: 10)
  print("nunca chega aqui — o ICE é de EMISSÃO: ${c.saldo}")
}
