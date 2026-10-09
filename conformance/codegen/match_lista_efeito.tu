// **O escrutínio do `match` é avaliado UMA vez** (R3) — e um list-pattern o
// lê MUITAS: uma no teste de comprimento, uma por elemento, uma no `sublist`.
//
// `match efeito() { [] => 0, [a, ..r] => a + r.length }` toca o subject quatro
// vezes na árvore emitida. Se cada toque re-emitisse a subárvore do escrutínio,
// o programa chamaria `efeito()` quatro vezes — e **nenhum golden de valor puro
// perceberia**, porque o valor devolvido é o mesmo em todas. Foi assim que o
// bug 6 da auditoria de 2026-07-29 sobreviveu à suíte inteira.
//
// Aqui cada `[efeito]` no stdout é uma execução. **Uma linha `[efeito]`, não
// quatro.** Quem garante isso é o `Let` do `#subject` no `_matchExpr` — o
// escrutínio entra numa `VariableDeclaration` antes do fold, e todo uso depois
// é `VariableGet`.
//
// ⚠️ **Os nós de leitura continuam sendo novos a cada uso**, e isso não é
// contradição: um `VariableGet` novo é obrigatório (no Kernel cada nó tem UM
// pai; reusar a instância dá *"Incorrect parent pointer"* no `verifyComponent`).
// O que não pode repetir é a AVALIAÇÃO, e é ela que o `Let` fixa. As duas
// exigências puxam em sentidos opostos e o temporário satisfaz as duas.
//
// Golden do oráculo Dart no pin 3.12.2: `[10, 20, 30]` ⟹ `a` = 10, `r.length`
// = 2, soma 12 — com um único `[efeito]`.

fn efeito() -> List<Int> {
  print("[efeito]")
  return [10, 20, 30]
}

fn main() {
  print("${match efeito() { [] => 0, [a, ..r] => a + r.length }}")
}
