// **CA9** (§11) — `panic("x")` ⟹ mensagem no stderr + exit ≠ 0.
//
// `panic` → `Throw` de um `ItaPanic` (§7.4-f). **Zero try/catch na linguagem
// (P7) ⟹ NADA o captura**: o isolate morre, o stderr recebe a mensagem, e o
// processo sai com código de erro.
//
// ⚠️ **O VALOR do exit code DIVERGE entre alvos, e o CA9 o marca
// DIVERGE-DOCUMENTADO:** VM/AOT = **255**
// (`runtime/bin/error_exit.h::kErrorExitCode`), JS/Node = **1**. A paridade do
// ADR-0005 cobre só a PROPRIEDADE ("exit ≠ 0"), nunca o número. Este fixture
// assere **255** porque o runner roda **só a VM** — e é por isso que o alvo é
// declarado no cabeçalho do relatório e no nome do job de CI. Quando o alvo JS
// entrar, este `EXPECT-EXIT` precisa virar por-alvo, ou vira uma promessa falsa.
//
// A linha `antes` prova que o stdout ATÉ o panic é preservado (o `print`
// aconteceu, o `Throw` veio depois). O que o stderr traz — `panic: <msg>`, e não
// `Instance of 'ItaPanic'` — vem do `toString()` que a emissão sintetiza na
// classe de runtime.
//
// EXPECT-EXIT: 255

fn main() {
  print("antes do panic")
  panic("algo deu muito errado")
}
