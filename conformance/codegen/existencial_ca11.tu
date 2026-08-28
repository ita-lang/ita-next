// **CA11 da spec 013 §11** — *"travessia `any` de fonte local: **zero nó extra**
// no `.dill` (dump não contém wrapper) — VM"*.
//
// O gabarito é a própria spec, na tabela das side-tables (spec 013 §7, linha
// nº7): *"**Hoje**: fonte é sempre local ⟹ **zero nó emitido**"*. O upcast é
// grátis pelo merge-na-`Class` do ADR-0017 §1: um `Pato` JÁ É um `Fala` no
// Kernel — o `implementedTypes` da `Class`
// diz isso —, então cruzar para um slot `any Fala` não custa nó nenhum: nem box,
// nem cast, nem temporário.
//
// ⚠️ **Este fixture não prova o CA11 sozinho, e isso é de propósito.** O que ele
// faz é EXERCITAR a travessia em quatro formas; quem verifica é o
// `checkExistentialZeroNode` (`invariants.dart`), que roda no golden-runner
// sobre os sítios que a **side-table nº7** marcou. A verificação é intensional
// por necessidade: um box do ADR-0017 §3(a) faria este programa imprimir
// EXATAMENTE a mesma coisa, só alocando um objeto por travessia. Golden de
// stdout não vê wrapper — é literalmente o defeito que a spec 013 §11 quer pinar.
//
// A régua sabe ficar vermelha: `invariants_test.dart` constrói o box e o cast à
// mão (o corpus nunca os produziu, porque a fronteira de built-in é o
// não-objetivo 2 da spec) e cobra que ambos sejam acusados.

trait Fala {
  fn som() -> String
}

struct Pato : Fala {
  nome: String
  fn som() -> String => "quack"
}

struct Cao : Fala {
  nome: String
  fn som() -> String => "au"
}

// (1) travessia em ARGUMENTO — `Pato` concreto entra num slot `any Fala`
fn ouve(v: any Fala) -> String => v.som()

// (2) travessia em RETORNO — o corpo rende um `Cao`, a assinatura diz `any Fala`
fn escolhe(alto: Bool) -> any Fala => if alto => Cao(nome: "rex") else Pato(nome: "donald")

// (3) travessia em posição de argumento com a expressão CONSTRUÍDA no sítio.
// O nó emitido aqui é um `ConstructorInvocation` — do PRÓPRIO tipo-fonte, e por
// isso legítimo. A régua distingue os dois casos: construir `Pato` é a
// expressão; construir `Fala$Pato` seria o box.
fn direto() -> String => ouve(Pato(nome: "pixel"))

fn main() {
  let p = Pato(nome: "donald")
  let c = Cao(nome: "rex")

  // (1) argumento, duas fontes locais diferentes pelo mesmo slot
  print("argumento: ${ouve(p)} ${ouve(c)}")

  // (2) retorno
  print("retorno: ${escolhe(true).som()} ${escolhe(false).som()}")

  // (3) construção no próprio sítio da travessia
  print("no sitio: ${direto()}")

  // (4) travessia em `let` ANOTADO — o binder declara `any Fala` e recebe um
  // `Pato`. É a forma que não passa por chamada nenhuma.
  let v: any Fala = p
  print("let anotado: ${v.som()}")
}
