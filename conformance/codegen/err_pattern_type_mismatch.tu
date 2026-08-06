// EXPECT-ERROR: pattern-type-mismatch
//
// **CA NEGATIVO PERMANENTE** — nenhuma fatia futura o promove a verde.
//
// `match p { Caixa { x: a } }` sobre um `Ponto` é programa ERRADO, e a fase que
// o diz é a F5. Até 2026-07-29 ninguém dizia: o `check.dart` roteava
// `StructPattern` para `_bindFieldPatterns` e **nunca lia `typeName`**.
//
// Esta é a metade que faltava do bug 4 da auditoria. A outra metade era da F7,
// que resolvia os campos varrendo as classes emitidas por NOME e emitia
// `InstanceGet` com `interfaceTarget` de `Caixa.x` sobre um receptor `Ponto`.
// Aquilo passava no `verifyComponent` (ele só confere `name ==
// interfaceTarget.name`), passava no LOAD, e **rodava certo no JIT** — o
// dispatch é por selector via inline cache, então o nome basta em runtime. Só
// quebrava em AOT, onde a TFA poda pelo cone da classe do interface target.
//
// E o emitter justificava a busca por nome assim: *"resolver por nome é seguro
// aqui porque a F5 já cobrou que o pattern casa com o tipo do escrutínio
// (`pattern-type-mismatch`)"*. A garantia **não existia**. Este fixture é o que
// a faz existir — e é por isso que ele não podia ser escrito antes: enquanto a
// F5 aceitasse, não havia erro para esperar.
//
// Os dois lados agora se sustentam: a F7 resolve pela decl do subject (não pelo
// nome), e a F5 recusa o programa antes de a F7 rodar.

struct Ponto { x: Int, y: Int }

struct Caixa { x: Int, largura: Int }

fn main() {
  let p = Ponto(x: 7, y: 9)
  print("${match p { Caixa { x: a } => a }}")
}
