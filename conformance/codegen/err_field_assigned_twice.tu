// EXPECT-ERROR: field-assigned-twice
//
// **ADR-0019 R3-(A)** — campo `let` recebe EXATAMENTE uma atribuição no `init`.
//
// Até 2026-07-29 o compilador permitia N, em qualquer posição — e ninguém tinha
// decidido isso: caiu por acidente da isenção escrita no mesmo dia para evitar
// o falso `assign-to-immutable` dentro do `init`. Comportamento vivo
// não-registrado, que o ADR-0016 §A proíbe expressamente (a meta-diretriz Swift
// *"não se auto-executa"*).
//
// Sob a alternativa (B — quantas vezes quiser), dentro do `init` o `let` viraria
// `var` e a diferença entre os dois glifos deixaria de existir num escopo: P1
// com buraco. Quem precisa de valor condicional escreve
// `self.x = if c => 1 else 0` — forma que a linguagem já tem (RD-1).
//
// `var` fica livre: é a leitura literal do glifo.

class Contador {
  let inicial: Int
  var atual: Int

  init(a: Int) {
    self.atual = 0
    self.atual = a   // legítimo: `var`
    self.inicial = a
    self.inicial = a + 1   // ← ERRO: `let` duas vezes
  }
}

fn main() {
  print("${Contador(a: 1).inicial}")
}
