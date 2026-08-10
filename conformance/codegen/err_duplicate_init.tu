// EXPECT-ERROR: duplicate-init
//
// **CA NEGATIVO PERMANENTE.**
//
// Dois construtores com os MESMOS labels tornam a seleção um sorteio. A F5
// escolhe o `init` por label (`_labelsFit` — labels são sintáticos, conhecidos
// no call-site sem tipar os args), e com dois candidatos idênticos vence quem
// foi coletado primeiro: o outro é **código morto silencioso**, e o critério de
// desempate é a ordem TEXTUAL das `extension`.
//
// É a mesma doença que o `duplicate-member` mata um degrau acima, sob o mesmo
// princípio já cravado pelo dono: *"membros próprios de `T` **+
// `extension`/`impl` sobre `T`** → `duplicate-member` — extension está no MESMO
// nível"* (spec 011 §12-3). Colisão é erro na DECLARAÇÃO, não longe no uso.
//
// Decidido pelo dono em 2026-08-10, quando o CA3 passou a emitir um
// `Constructor` por `init` e a ambiguidade deixou de ser teórica: até então
// qualquer `init` de `extension` era ICE, e o sorteio nunca chegava a acontecer.
//
// ⚠️ **Fatia declarada, e não limite:** `init(a:, b: =1)` e `init(a:)` têm
// listas de labels DIFERENTES e ainda assim `P(a: 1)` casa com os dois — o
// `firstOrNull` desempata em silêncio. Isso não produz artefato errado (a F7
// emite o que a F5 escolheu, e o `slot` sai da mesma escolha), então o programa
// fica bem-definido; o que falta é a regra de desempate ser ESCRITA. Fecha-se
// comparando as *linguagens* de chamada aceitas em vez das listas, com o próprio
// `_labelsFit` aplicado à chamada mínima de cada candidato.

struct Ponto {
  x: Int,
  y: Int
}

extension Ponto {
  init(d: Int) {
    self.x = d
    self.y = d
  }
}

extension Ponto {
  init(d: Int) {
    self.x = 0
    self.y = d
  }
}

fn main() {
  let p = Ponto(d: 7)
  print("${p.x} ${p.y}")
}
