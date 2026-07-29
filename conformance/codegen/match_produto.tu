// §7.4-e — `match` sobre PRODUTO (`struct` em pattern), a última família que
// não depende da spec 012. Com ela a §7.4-e fica completa exceto `List`.
//
// **O produto não testa CLASSE.** Diferente de enum-com-payload, aqui o subject
// JÁ é do tipo — não há variante a discriminar. O que o pattern faz é:
//   - TESTAR os campos que trazem sub-pattern com teste (literal, range) —
//     `Ponto { x: 0 }` vira `subject.x == 0`;
//   - LIGAR os campos com binder — `Ponto { x: a }` vira `a = subject.x`.
// A conjunção dos testes é o teste do braço; um pattern só-de-binds casa SEMPRE.
//
// E não há `as` em lugar nenhum: sem estreitamento de tipo, não há o que
// promover. É o contraste exato com o enum selado, onde o `as` é obrigatório.
//
// ⚠️ **A borda do range em campo:** `idade: 0..18` é EXCLUSIVO, então `18` NÃO
// cai lá — cai em `18..=64`. É a mesma armadilha do `match_escalar.tu`, agora
// sobre `subject.campo` em vez do subject; os dois fixtures a fecham nos dois
// contextos.
//
// ⚠️ **Cada leitura de campo é um nó NOVO.** No Kernel todo nó tem UM pai;
// reusar a mesma instância de `InstanceGet` nas duas pontas de um range monta
// uma árvore com dois pais para o mesmo filho. O `verifyComponent` (gate CA12)
// reprova com *"Incorrect parent pointer"* — foi exatamente assim que este bug
// apareceu aqui, antes de qualquer execução.

struct Ponto { x: Int, y: Int }
struct Pessoa { nome: String, idade: Int }

fn quadrante(p: Ponto) -> String => match p {
  Ponto { x: 0, y: 0 } => "origem",
  Ponto { x: 0, y: b } => "eixo-y em ${b}",
  Ponto { x: a, y: 0 } => "eixo-x em ${a}",
  Ponto { x: a, y: b } => "livre ${a},${b}"
}

fn faixa(p: Pessoa) -> String => match p {
  Pessoa { nome: n, idade: 0..18 } => "${n}: menor",
  Pessoa { nome: n, idade: 18..=64 } => "${n}: adulto",
  Pessoa { nome: n, idade: i } => "${n}: idoso (${i})"
}

fn main() {
  print(quadrante(Ponto(x: 0, y: 0)))
  print(quadrante(Ponto(x: 0, y: 5)))
  print(quadrante(Ponto(x: 7, y: 0)))
  print(quadrante(Ponto(x: 3, y: 4)))

  print(faixa(Pessoa(nome: "ana", idade: 10)))
  print(faixa(Pessoa(nome: "bia", idade: 18)))   // a BORDA: 18 não é menor
  print(faixa(Pessoa(nome: "caio", idade: 70)))
}
