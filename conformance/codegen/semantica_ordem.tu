// AUDITORIA · Lote 1 — **semântica observável**: ordem de avaliação e
// curto-circuito. Nada disto aparece num golden de VALOR: os resultados seriam
// idênticos com a ordem trocada ou com os dois lados avaliados.
//
// Só efeito colateral revela. Cada `[marca]` no golden é uma avaliação que
// ACONTECEU; a AUSÊNCIA de uma marca é a asserção que importa.
//
// O que cada bloco quebra se a emissão errar:
//   - args fora de ordem ⟹ `[a]` e `[b]` trocam de linha;
//   - `&&`/`||` sem curto-circuito ⟹ aparece uma marca a mais;
//   - `if`/`match` avaliando os dois lados ⟹ idem;
//   - `??` ansioso ⟹ `[alt]` aparece mesmo com o valor presente.
//
// O curto-circuito é semântica do NÓ (`LogicalExpression`) — Grupo B, a VM o
// baixa para desvios. Este fixture não testa a VM: testa que a EMISSÃO usou o
// nó certo. Trocar `LogicalExpression` por duas invocações de `bool` daria o
// mesmo valor e uma marca a mais.

fn a() -> Int { print("  [a]") return 1 }
fn b() -> Int { print("  [b]") return 2 }
fn falso() -> Bool { print("  [falso]") return false }
fn verdade() -> Bool { print("  [verdade]") return true }
fn alternativa() -> Int { print("  [alt]") return 9 }

fn main() {
  print("args esquerda->direita:")
  print("  = ${a() + b()}")

  print("&& curto-circuita (verdade NAO roda):")
  print("  = ${falso() && verdade()}")

  print("|| curto-circuita (falso NAO roda):")
  print("  = ${verdade() || falso()}")

  print("if avalia SO o ramo tomado (b NAO roda):")
  print("  = ${if true => a() else b()}")

  print("match avalia SO o braco que casa (b NAO roda):")
  print("  = ${match 1 { 1 => a(), _ => b() }}")

  print("?? nao avalia o default quando o valor existe:")
  let cheio: Int? = 5
  print("  = ${cheio ?? alternativa()}")

  print("?? avalia o default quando precisa:")
  let vazio: Int? = nil
  print("  = ${vazio ?? alternativa()}")
}
