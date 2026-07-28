// §7.4-a — `fn` do usuário: `Procedure` static + `StaticInvocation`.
//
// **Este fixture NASCEU DE FRONTEIRA.** Até 2026-07-28 ele era `ice_user_fn.tu`,
// com `// EXPECT-ICE: ice-codegen-toplevel-FnDecl`. Quando a emissão de `fn`
// nasceu, ele ficou VERMELHO sozinho — *"esperava ice-…, mas COMPILOU — promova
// a fixture a CA verde"* — e esta promoção é a resposta. A catraca fechou o ciclo
// que projetou: a fila de trabalho da §7.4 se esvazia sozinha.
//
// O que ele exercita:
//   - `=> expr` (RD-1) num `fn` que devolve valor ⟹ `return expr`;
//   - corpo de BLOCO com `return` explícito;
//   - `fn` **Void** ⟹ `ExpressionStatement`, nunca `return` de valor (que seria
//     Kernel malformado);
//   - vários params — args **named**, montados pelo slot da nº5;
//   - **label externo ≠ nome interno**: o call-site chama pelo label, o corpo usa
//     o nome, e os dois lados casam porque saem do MESMO `VariableDeclaration`;
//   - **forward-reference**: `main` chama `triplo`, declarado ABAIXO dela. É o que
//     exige o two-pass (assinaturas antes dos corpos) — num passo único o
//     `targetReference`, que é non-nullable, não teria o que apontar.

fn dobro(x: Int) -> Int => x * 2

fn saudacao(nome: String) -> String {
  return "olá, ${nome}"
}

fn anuncia(msg: String) {
  print("[log] ${msg}")
}

fn soma(a: Int, b: Int) -> Int => a + b

fn area(largura w: Int, altura h: Int) -> Int => w * h

fn main() {
  print("dobro=${dobro(21)}")
  print(saudacao("mundo"))
  anuncia("fn Void roda")
  print("soma=${soma(2, 40)}")
  print("area=${area(largura: 3, altura: 4)}")
  print("forward=${triplo(3)}")
}

fn triplo(x: Int) -> Int => x * 3
