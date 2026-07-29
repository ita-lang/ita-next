// **A ordem textual das declarações não importa.**
//
// Isto é TEOREMA da F4 — *"two-pass no módulo (letrec): declara todos os nomes
// top-level, depois resolve os corpos ⟹ ordem textual não importa"*
// (`resolver.dart:71-75`) — e todo o pipeline o herda. Até 2026-07-29 a F7 o
// refutava: emitia os tipos em ordem fixa por espécie (traits → structs → enums
// → classes) e registrava a `Class` só DEPOIS de emitir os campos, então cada
// aresta que apontasse "para a frente" virava `ice-codegen-type-unemitted-*`
// sobre um programa perfeitamente legal.
//
// Este fixture é o grafo de tipos hostil de propósito: cada declaração menciona
// outra que aparece MAIS ABAIXO no arquivo, e uma delas se auto-referencia.
// Nenhuma ordem por espécie o salva — só shells-antes-de-membros salva.

// struct → enum declarado abaixo (a ordem por espécie punha enums depois)
struct Peca { cor: Cor, tamanho: Medida }

// struct → struct declarado abaixo
struct Medida { largura: Int, altura: Int }

enum Cor { vermelho, azul }

// auto-referência: `No` menciona `No` no próprio corpo. Não tem ordem
// topológica — nenhuma passada linear o constrói sem shell.
struct No { valor: Int, proximo: No? }

// class → struct declarado ACIMA e enum declarado abaixo
class Caixa {
  let peca: Peca
  let estado: Estado

  init(peca: Peca, estado: Estado) {
    self.peca = peca
    self.estado = estado
  }
}

enum Estado { novo, usado }

fn descreveCor(c: Cor) -> String =>
  match c {
    .vermelho => "vermelho"
    .azul => "azul"
  }

fn profundidade(n: No) -> Int =>
  match n.proximo {
    .none => 1
    .some(p) => 1 + profundidade(n: p)
  }

fn main() {
  let m = Medida(largura: 3, altura: 4)
  let p = Peca(cor: .azul, tamanho: m)
  print(descreveCor(c: p.cor))
  print("${p.tamanho.largura}")

  let c = Caixa(peca: p, estado: .novo)
  print("${c.peca.tamanho.altura}")

  let lista = No(valor: 1, proximo: No(valor: 2, proximo: nil))
  print("${profundidade(n: lista)}")
}
