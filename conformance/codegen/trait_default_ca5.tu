// **CA5 da spec 013 §11** — *"default method roda via stub com `self` correto;
// conformer que SOBRESCREVE vence o default"*. Duas cláusulas, o fixture prova
// as duas.
//
// O gabarito é o **ADR-0017 §2, ruling R3 do dono (2026-07-16): (iii) stub +
// static**. O corpo do default aparece **uma vez** no `.dill`, como um
// `Procedure` STATIC do trait que recebe `self` por parâmetro; cada conformer
// que não sobrescreve ganha um **stub** de uma linha que delega a ele.
//
// As alternativas estão custeadas no ADR e as duas perdem: (i) copiar o corpo
// por conformer infla o snapshot linearmente **sem dedup real**
// (`program_visitor.cc::DedupInstructions` exige tabelas idênticas, e cópias
// otimizadas por receptor divergem); (ii) `mixedInType` cru é a ARMADILHA
// verificada — quem achata mixin é um transformer do pipeline CFE que o Itá
// **bypassa**, e no `.dill` cru os membros simplesmente **não existem**.
//
// ⚠️ **`self` dentro do default é o join dos conformers**, não um tipo concreto:
// no static ele é o `InterfaceType` do trait, então `self.nome()` ali é chamada
// POLIMÓRFICA — o preço que o ADR aceita por ter o corpo uma vez só. É o que a
// linha "via existencial" abaixo exercita.

trait Saudavel {
  // requisito: quem conforma É obrigado (`missing-trait-member` na F5)
  fn nome() -> String

  // default: quem conforma NÃO é obrigado. O corpo chama um requisito, que é o
  // caso interessante — `self` tem de chegar certo ao static.
  fn saudacao() -> String => "olá, ${self.nome()}"

  // default COM PARÂMETRO: o stub tem de repassar o named adiante, e o `self`
  // continua sendo o primeiro posicional. Sem este caso o repasse de argumentos
  // ficava sem cobertura — o fixture inteiro passaria com um stub que ignora os
  // params, porque nenhum default tinha algum.
  fn cumprimento(prefixo: String) -> String => "${prefixo}, ${self.nome()}"
}

// Conformer que USA o default: ganha o stub.
struct Pessoa : Saudavel {
  primeiro: String

  fn nome() -> String => self.primeiro
}

// Conformer que TAMBÉM usa o default, com outro `nome()`. Dois stubs para o
// mesmo static — é o par que o dedup do AOT enxerga.
struct Cidade : Saudavel {
  local: String

  fn nome() -> String => "cidade de ${self.local}"
}

// Conformer que SOBRESCREVE: a 2ª cláusula do CA5. NÃO ganha stub, e o
// `saudacao()` dele tem de vencer o default nos dois caminhos (direto e
// existencial).
//
// ⚠️ O `override` é **obrigatório** aqui, e a F5 o cobra (`missing-override`,
// spec 011 item 2): a keyword marca *"substituir implementação existente —
// superclasse concreta **ou default de trait**"*. Note que `nome()` NÃO leva
// `override`: satisfazer requisito sem corpo não é sobrepor nada, e sem essa
// cerca o erro dispararia em toda conformance de trait.
class Robo : Saudavel {
  var serie: Int

  init(serie: Int) {
    self.serie = serie
  }

  fn nome() -> String => "R${self.serie}"
  override fn saudacao() -> String => "BEEP BOOP ${self.nome()}"
}

fn cumprimenta(v: any Saudavel) -> String => v.saudacao()

fn main() {
  let p = Pessoa(primeiro: "ana")
  let c = Cidade(local: "fortaleza")
  let r = Robo(serie: 7)

  // direto: o receptor é concreto, o `interfaceTarget` é o da própria classe
  print("direto p: ${p.saudacao()}")
  print("direto c: ${c.saudacao()}")
  print("direto r: ${r.saudacao()}")

  // existencial: MESMA fn, e o default tem de rodar com o `self` de cada um —
  // é aqui que um stub com receptor errado imprimiria a saudação do vizinho
  print("via existencial: ${cumprimenta(p)}")
  print("via existencial: ${cumprimenta(c)}")

  // o override vence TAMBÉM pelo caminho existencial (vtable, Grupo B)
  print("override vence: ${cumprimenta(r)}")

  // default COM argumento: o stub repassa o named ao static
  print("com param: ${p.cumprimento(prefixo: "bom dia")}")
  print("com param: ${r.cumprimento(prefixo: "salve")}")
}
