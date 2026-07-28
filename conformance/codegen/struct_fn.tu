// §7.4-c × §7.4-a — `struct` atravessando a fronteira de `fn`: como PARÂMETRO,
// como RETORNO, e construído dentro do corpo.
//
// **`Caixa` é a prova do passo 1a.** Ela é declarada NO FIM do arquivo, abaixo de
// `embrulha`, que a usa como tipo de retorno — e de `main`, que a consome. Se os
// tipos não fossem registrados ANTES das assinaturas de `fn`, o `InterfaceType`
// da assinatura não teria `Class` para apontar. É a mesma razão do two-pass das
// funções, um nível acima: a forward-reference vale para tipos, não só para
// chamadas.
//
// `desloca` fecha o ciclo do valor: recebe um `Ponto`, LÊ seus campos e devolve
// um `Ponto` NOVO — que é o único jeito de "mudar" um struct no Itá (§12-1:
// mutação pede `class` ou copy-with).

struct Ponto {
  x: Int,
  y: Int
}

fn desloca(p: Ponto, dx: Int, dy: Int) -> Ponto =>
  Ponto(x: p.x + dx, y: p.y + dy)

fn distanciaHorizontal(de: Ponto, ate: Ponto) -> Int => ate.x - de.x

fn embrulha(v: Int) -> Caixa => Caixa(conteudo: v)

fn main() {
  let origem = Ponto(x: 1, y: 1)
  let movido = desloca(origem, 10, 20)
  print("movido=${movido.x},${movido.y}")

  // o original NÃO mudou — cópia-valor por imutabilidade
  print("origem=${origem.x},${origem.y}")

  print("dist=${distanciaHorizontal(origem, movido)}")
  print("caixa=${embrulha(7).conteudo}")
}

struct Caixa {
  conteudo: Int
}
