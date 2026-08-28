// **O caso "N conformers × M defaults"** que o ADR-0017 pede nas Consequências
// para vigiar o **ADR-0017 §2**: *"O benchmark de compile-time (Art. IV-3) ganha
// o caso 'N conformers × M defaults'"*.
//
// Aqui N = **8** e M = **5**: 40 pares conformer×default sobre um trait só.
//
// ## O que ele vigia, e por que o número importa
//
// O **ADR-0017 §2** escolheu (iii) stub+static: o corpo de cada default existe
// UMA vez, como `static` do trait, e cada conformer ganha um stub que delega.
// Com esta forma o `.dill` carrega **5 corpos + 40 delegações triviais**.
//
// A alternativa (i) — copiar o corpo por conformer — carregaria **40 corpos
// completos**, e o ADR mediu por que isso não serve: *"snapshot ~linear ×
// conformers **sem dedup real**"* (`program_visitor.cc::DedupInstructions` exige
// tabelas idênticas, e cópias otimizadas por receptor divergem) *"+ mais
// summaries = mais tempo de TFA (fere Art. IV-3)"*.
//
// Com 8×5, trocar (iii) por (i) multiplica o trabalho do emitter por 8 neste
// arquivo — e é o `make bench` que enxerga isso, porque o limiar dele é por
// ARQUIVO. Um fixture de 2×1 não distinguiria as duas formas de ruído de I/O.
//
// ⚠️ Este fixture **não é decoração de benchmark**: ele também roda no
// golden-runner nos 3 alvos, então uma regressão na lowering aparece como saída
// errada antes de aparecer como lentidão.

trait Item {
  // requisitos: todo conformer os provê
  fn nome() -> String
  fn preco() -> Int

  // M = 5 defaults. O 3º chama outros dois defaults — dentro do static, `self`
  // é o join dos conformers, então essas chamadas são polimórficas.
  fn etiqueta() -> String => "[${self.nome()}]"
  fn precoTexto() -> String => "R$${self.preco()}"
  fn resumo() -> String => "${self.etiqueta()} ${self.precoTexto()}"
  fn comDesconto(abate: Int) -> Int => self.preco() - abate
  fn linha(prefixo: String) -> String => "${prefixo} ${self.resumo()}"
}

struct Livro : Item {
  titulo: String
  fn nome() -> String => self.titulo
  fn preco() -> Int => 40
}

struct Caneta : Item {
  cor: String
  fn nome() -> String => "caneta ${self.cor}"
  fn preco() -> Int => 3
}

struct Mesa : Item {
  material: String
  fn nome() -> String => "mesa de ${self.material}"
  fn preco() -> Int => 250
}

struct Fone : Item {
  marca: String
  fn nome() -> String => "fone ${self.marca}"
  fn preco() -> Int => 120
}

struct Copo : Item {
  ml: Int
  fn nome() -> String => "copo ${self.ml}ml"
  fn preco() -> Int => 8
}

struct Mochila : Item {
  litros: Int
  fn nome() -> String => "mochila ${self.litros}L"
  fn preco() -> Int => 90
}

struct Teclado : Item {
  layout: String
  fn nome() -> String => "teclado ${self.layout}"
  fn preco() -> Int => 180
}

// O oitavo SOBRESCREVE dois dos cinco defaults: mistura as duas formas no mesmo
// trait, que é o caso em que um stub emitido por engano sobre um override
// apareceria — ele venceria de volta o que o usuário escreveu.
struct Lampada : Item {
  watts: Int
  fn nome() -> String => "lâmpada ${self.watts}W"
  fn preco() -> Int => 15

  override fn etiqueta() -> String => "<${self.nome()}>"
  override fn comDesconto(abate: Int) -> Int => self.preco()
}

fn mostra(i: any Item) -> String => i.linha(prefixo: "-")

fn main() {
  let livro = Livro(titulo: "dragon book")
  let caneta = Caneta(cor: "azul")
  let mesa = Mesa(material: "carvalho")
  let fone = Fone(marca: "akg")
  let copo = Copo(ml: 300)
  let mochila = Mochila(litros: 25)
  let teclado = Teclado(layout: "abnt2")
  let lampada = Lampada(watts: 9)

  // pelo caminho EXISTENCIAL: um `any Item` por conformer, e o default `linha`
  // chama `resumo`, que chama `etiqueta` e `precoTexto` — 3 níveis de default
  print(mostra(livro))
  print(mostra(caneta))
  print(mostra(mesa))
  print(mostra(fone))
  print(mostra(copo))
  print(mostra(mochila))
  print(mostra(teclado))
  print(mostra(lampada))

  // o override do 8º vence nos dois caminhos
  print("etiqueta sobrescrita: ${lampada.etiqueta()}")
  print("desconto sobrescrito: ${lampada.comDesconto(abate: 5)}")
  print("desconto herdado:     ${teclado.comDesconto(abate: 30)}")
}
