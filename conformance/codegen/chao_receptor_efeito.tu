// **O receptor do chão é avaliado UMA vez** (R3) — e só um receptor com EFEITO
// consegue provar isso.
//
// `xs.length` e `xs[i]` sobre um local são valor puro: re-emitir a subárvore do
// receptor produziria um `.dill` maior e stdout IDÊNTICO, e todo golden do bloco
// passaria. Foi assim que o bug 6 da auditoria de 2026-07-29 sobreviveu — o
// `_assignMember` chamava `_expr(receiver)` duas vezes e nenhum fixture usava
// receptor efeituoso.
//
// Aqui cada `[efeito]` no stdout é uma execução de `efeito()`. **Duas linhas
// `[efeito]` para dois usos**; três ou quatro seriam a duplicação.
//
// Golden do oráculo Dart no pin 3.12.2: `<int>[10,20,30][1]` ⟶ `20`,
// `.length` ⟶ `3`.

fn efeito() -> List<Int> {
  print("[efeito]")
  return [10, 20, 30]
}

fn main() {
  print("${efeito()[1]}")
  print("${efeito().length}")
}
