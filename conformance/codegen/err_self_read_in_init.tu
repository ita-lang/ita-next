// EXPECT-ERROR: self-read-in-init
//
// **ADR-0019 R4-(A)** — no corpo do `init`, `self` só vale como ALVO.
//
// Ler `self` antes de todos os campos estarem escritos lê um valor que ainda
// não existe. É o buraco do `field-not-initialized` por outra porta, e a VM o
// entrega como `null` num tipo NÃO-NULLABLE — o quarto da mesma auditoria.
//
// Escolhida entre as três opções do ADR porque **só afrouxa depois**: quando a
// F6 tiver definite-assignment de campo, o two-phase do Swift (R4-B) aceita
// MAIS programas e não quebra nenhum escrito sob esta regra. A ordem inversa
// quebraria código.
//
// ⚠️ Hoje vale para o corpo INTEIRO, porque não há corte — tudo vira
// `initializers`. Quando o R1 do ADR-0019 for decidido, a regra relaxa para
// "antes do corte": no sufixo o objeto está completo e a leitura é livre.
//
// Fora do `init`, ler `self` sempre foi e continua legítimo.

class Retangulo {
  let largura: Int
  let area: Int

  init(l: Int) {
    self.largura = l
    self.area = self.largura * l   // ← ERRO: lê `self` no init
  }
}

fn main() {
  print("${Retangulo(l: 3).area}")
}
