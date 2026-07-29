// §7.4-c/e — `enum` SEM payload → `Class` com uma **constante por variante**,
// e `match` sobre ele por **identidade**.
//
// Cada variante é um `static final` inicializado com o construtor da própria
// classe, então cada uma é um **objeto único**. É isso que faz o `match`
// funcionar com `Object::==` puro — sem tag, sem índice, sem `IsExpression`.
// `.variante` como valor é um `StaticGet` da constante.
//
// ⚠️ **Variante COM payload não está aqui, e o motivo não é a emissão:** a F5
// ainda não sabe CONSTRUIR uma — `.circulo(raio: 2)` dá `cannot-infer`, porque o
// `_call` não resolve callee `EnumShorthand` com args. Sem construção não há
// valor a destruir, então o gabarito de classe selada + subclasse por variante
// (§7.4-e) espera aquela fatia da F5. O emitter dá
// `ice-codegen-enum-payload-<variante>` — nomeia a lacuna em vez de emitir uma
// classe que ninguém consegue instanciar.
//
// O `match` aqui é EXAUSTIVO sem `_`: a F6 fecha um enum finito (diferente de
// range sobre `Int`, que nunca fecha sem ω). O último braço vira o `otherwise`
// do right-fold, e é a exaustividade da F6 que torna isso sound.

enum Cor {
  vermelho,
  verde,
  azul
}

enum Estado {
  ligado,
  desligado
}

fn nome(c: Cor) -> String => match c {
  .vermelho => "vermelho",
  .verde => "verde",
  .azul => "azul"
}

fn ativo(e: Estado) -> Bool => match e {
  .ligado => true,
  .desligado => false
}

fn main() {
  let a: Cor = .vermelho
  let b: Cor = .verde
  let c: Cor = .azul
  print("cores=${nome(a)},${nome(b)},${nome(c)}")

  let on: Estado = .ligado
  let off: Estado = .desligado
  print("estado=${ativo(on)},${ativo(off)}")

  // a mesma variante, lida duas vezes, é o MESMO objeto — a identidade é o que
  // o `match` usa, então isto tem de casar
  let outra: Cor = .verde
  print("identidade=${if b == outra => "mesma" else "DIFERENTE"}")
}
