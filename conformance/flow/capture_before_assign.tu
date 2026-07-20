// CA7 (spec 014 §11) — criação de closure = OBRIGAÇÃO de DA (C# spec, DA ×
// anonymous functions): `var` livre capturado ∉ DA erra NA CRIAÇÃO, span no
// primeiro Ident capturador. E assign DENTRO da closure não flui para fora —
// o uso externo segue `use-before-assign` (a closure roda em momento
// arbitrário, ou nunca).
//
// A sutileza da PRIMEIRA fn: a closure só ESCREVE (`x = 1`) — e erra mesmo
// assim. A captura é da CÉLULA (contexto por referência no Kernel), não da
// leitura; a obrigação nasce na criação. Mais estrito que o C# (que só
// policia leituras) DE PROPÓSITO — relaxar depois aceita mais programas, é
// compatível (blueprint da 014, §5 "delta anotado" e §14-L2).
// EXPECT-FLOW: capture-before-assign
// EXPECT-FLOW: use-before-assign

fn capturaSemAtribuir() -> Int {
  var x: Int
  let f = () => {
    x = 1
  }
  return x
}

// Verde: atribuído ANTES da criação — a obrigação está paga; o uso depois lê
// o DA do caminho de fora, que já tem x.
fn capturaAtribuido() -> Int {
  var x: Int
  x = 1
  let f = () => {
    x = 2
  }
  return x
}
