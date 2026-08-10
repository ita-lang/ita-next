// **CA6 da spec 013 §11** — *"membro vindo de `impl`/`extension` despacha igual
// a inline (origin nº3 → dentro da `Class`)"*.
//
// O gabarito é o **ADR-0017 §1**, merge-na-`Class`: *"Conformer → a `Class`
// emitida ganha o trait em `implementedTypes` e **todos os membros de
// conformance dentro dela** — os vindos de `impl`/`extension` inclusive, como
// procedures comuns"*. Dispatch existencial vira interface dispatch da VM.
//
// ⚠️ **`impl`/`extension` não viram entidade no Kernel.** Não há `Class`
// própria, e o membro NÃO leva `isExtensionMember` — o `verifier.dart:686-693`
// exigiria um descriptor de extensão na library, e o dispatch deixaria de ser o
// mesmo de um membro inline. É justamente a indistinguibilidade que este fixture
// cobra: se a origem mudasse o dispatch, `retro` e `inline` responderiam
// diferente ao mesmo `any`.
//
// A completude é 100% NOSSA aqui: o ADR mede que *"o verifier **não confere
// nada** de `implementedTypes`"* e a VM não roda o verifier — classe concreta
// sem o membro do interface vira `NoSuchMethodError` em runtime, não erro de
// compilação.

trait Fala {
  fn som() -> String
}

// (1) conformance INLINE — o caminho que já existia (CA4)
struct Pato : Fala {
  nome: String
  fn som() -> String => "quack"
}

// (2) conformance por `impl Trait for T`: o tipo nasce SEM o trait, e o retrofit
// o acrescenta. No `.dill` tem de ficar idêntico ao caso (1).
struct Cao {
  nome: String
}

impl Fala for Cao {
  fn som() -> String => "au"
}

// (3) `extension` com conformance inline (`: Fala`) E um membro extra que NÃO
// vem de trait nenhum — o `extension` também acrescenta método comum.
struct Gato {
  nome: String
}

extension Gato : Fala {
  fn som() -> String => "miau"
  fn ronrona() -> String => "${self.nome} ronrona"
}

// (4) `impl T` SEM trait: só acrescenta membro, nenhuma conformance.
class Robo {
  var carga: Int

  init(carga: Int) {
    self.carga = carga
  }
}

impl Robo {
  fn carrega(quanto: Int) -> Int => self.carga + quanto
}

fn ouve(v: any Fala) -> String => v.som()

fn main() {
  let p = Pato(nome: "donald")
  let c = Cao(nome: "rex")
  let g = Gato(nome: "mimi")
  let r = Robo(carga: 50)

  // EXISTENCIAL: os três chegam por `any Fala`, e a origem do membro (corpo,
  // `impl`, `extension`) tem de ser INVISÍVEL aqui. É a asserção central do CA6.
  print("existencial: ${ouve(p)} ${ouve(c)} ${ouve(g)}")

  // DIRETO: mesmo resultado pelo receptor concreto
  print("direto: ${p.som()} ${c.som()} ${g.som()}")

  // membro de `extension` que não é conformance nenhuma
  print("extra: ${g.ronrona()}")

  // membro de `impl T` sem trait
  print("impl sem trait: ${r.carrega(quanto: 25)}")
}
