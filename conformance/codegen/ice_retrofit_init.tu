// EXPECT-ICE: ice-codegen-retrofit-init
//
// **A outra metade da fronteira do CA6** — e a que quase passou. O merge-na-
// `Class` do ADR-0017 §1 injeta os membros de `impl`/`extension` na mesma lista
// que os do corpo, e `_addMethods` descarta tudo que não é `FnDecl` sob o
// comentário *"campos e `init` já foram"*. A premissa valia para o corpo; para o
// retrofit, não — o `InitDecl` caía no `continue` e SUMIA.
//
// ⚠️ **Isto não é hipótese: os dois modos de falha foram medidos** (2026-08-10),
// com o CA6 aplicado e antes desta guarda existir:
//
//   - `struct Ponto` + `extension Ponto { init(diagonal:) }` compilava, e
//     `Ponto(diagonal: 7)` morria em runtime com `NoSuchMethodError` — o único
//     construtor emitido era o memberwise.
//   - `class Conta { init(inicial: Int) }` + `extension Conta { init(zerada:
//     Bool) }` compilava, e `Conta(zerada: true)` imprimia `saldo=true`: o arg
//     foi ligado ao construtor do CORPO e um `Bool` gravado em campo `Int`.
//     `verifyComponent` é well-formedness, **não** type-checking
//     (`verifier.dart:127-129`), então o `.dill` malformado passou e a VM
//     confiou nele. Nenhuma fase disse uma palavra.
//
// A fronteira é NOSSA, não da linguagem: a F5 aceita a construção e até resolve
// a chamada (seleciona o `init` por labels, `check.dart:1602`), porque o
// ADR-0016 §B crava que *"`extensionInits` acumulam como **adicionais**, com
// precedência do `init` do corpo"*. Quem ainda não emite é a F7 — e é por isso
// que o ICE nomeia a construção (`retrofit-init`), não estado do emissor.
//
// Some no **CA3** (spec 013 §11), cuja 2ª cláusula é literalmente
// *"`extensionInits` são construtores adicionais (ADR-0016 §B)"*. A fatia que
// falta não é só emitir um `Constructor` a mais: a chamada precisa saber QUAL
// deles, e a escolha da F5 hoje mora só em `exprTypes[callee]` (um
// `FunctionType`, sem link com a decl) — sem uma side-table que a carregue, a F7
// teria de recomputar por labels, que é a redecisão-com-chave-mais-fraca da R1.

struct Ponto { x: Int, y: Int }

extension Ponto {
  init(diagonal: Int) {
    self.x = diagonal
    self.y = diagonal
  }
}

fn main() {
  let p = Ponto(diagonal: 7)
  print("nunca chega aqui — o ICE é de EMISSÃO, não de uso: ${p.x}")
}
