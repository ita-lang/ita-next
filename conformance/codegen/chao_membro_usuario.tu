// **O chão não sequestra membro do usuário, e o usuário não bloqueia o chão.**
//
// Os CAs da spec 012 §11 não cobrem isto, e é a regressão mais provável da
// fatia: o `_member` do emitter passou a desviar `.length` para a emissão do
// chão ANTES de consultar a nº3, e um desvio por NOME sequestraria o `c.length`
// deste programa — campo de `struct` do usuário que por acaso se chama `length`.
//
// O desvio é por **TIPO** (`_shapeOf` sobre a side-table nº1), não por lexema:
// `Caixa` é `NamedType`, logo `_shapeOf` devolve `null` e o acesso segue pelo
// caminho de campo. É a R1 no sítio onde ela é mais fácil de violar, porque
// aqui a violação seria invisível — o programa compila, roda, e imprime o
// `length` errado.
//
// Os dois no MESMO programa de propósito: um fixture com só um dos lados
// passaria com o desvio na ordem errada.
//
// Golden do oráculo Dart no pin 3.12.2: `42` e `<int>[1,2].length` ⟶ `2`.

struct Caixa { length: Int }

fn main() {
  let c = Caixa(length: 42)
  let xs: List<Int> = [1, 2]
  print("${c.length} ${xs.length}")
}
