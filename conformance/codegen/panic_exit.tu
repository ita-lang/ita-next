// **CA9** (§11) — `panic("x")` ⟹ mensagem no stderr + exit ≠ 0.
//
// `panic` → `Throw` de um `ItaPanic` (§7.4-f). **Zero try/catch na linguagem
// (P7) ⟹ NADA o captura**: o isolate morre, o stderr recebe a mensagem, e o
// processo sai com código de erro.
//
// ⚠️ **O VALOR do exit code DIVERGE entre alvos, e o CA9 o marca
// DIVERGE-DOCUMENTADO:** VM/AOT = **255**
// (`runtime/bin/error_exit.h::kErrorExitCode`), JS/Node = **1**. A paridade do
// ADR-0005 cobre só a PROPRIEDADE ("exit ≠ 0"), não o número. O `EXPECT-EXIT`
// abaixo assere **255**, que é o da VM — a referência da spec 013 §7.7; os
// outros dois alvos são comparados contra ela, e para o JS o runner exige só que
// o sinal ≠ 0 bata (`(r.exitCode == 0) == (exitCode == 0)`), não o número.
// *(Correção de 2026-08-31: a redação anterior justificava o 255 dizendo que "o
// runner roda só a VM". Isso deixou de ser verdade em 2026-08-06, quando os três
// alvos entraram — o motivo real é a VM ser a referência, não ser a única.)*
//
// A linha `antes` prova que o stdout ATÉ o panic é preservado (o `print`
// aconteceu, o `Throw` veio depois). O que o stderr traz — `panic: <msg>`, e não
// `Instance of 'ItaPanic'` — vem do `toString()` que a emissão sintetiza na
// classe de runtime, e desde 2026-08-31 é ASSERTADO, não só afirmado aqui: sem o
// `EXPECT-STDERR`, este fixture ficava verde sobre qualquer morte de isolate,
// inclusive uma que não fosse o `panic`.
//
// EXPECT-EXIT: 255
// EXPECT-STDERR: panic: algo deu muito errado

fn main() {
  print("antes do panic")
  panic("algo deu muito errado")
}
