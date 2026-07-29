// CA NEGATIVO — **ruling do dono, 2026-07-28**: `${x}` com `x: T?` é ERRO.
//
// A alternativa que este ruling recusou: sem a regra, `${x}` de um `Int?` vazio
// imprimia **`null`** — a palavra do **DART** — na saída de um programa que
// escreveu `nil`. Era o `toString()` da VM (Grupo B) vazando na superfície da
// linguagem: o dev via um termo que não existe no Itá, e a F7 não tinha como
// consertar sem pagar um check em runtime por interpolação.
//
// A régua é a MESMA do `print` String-only (§12-4): **zero coerção, o glifo pede
// o desembrulho**. O dev usa `match` ou `??` antes de interpolar.
//
// A regra é do **TIPO**, não do valor: `let x: Int? = 5` também é erro. Fazê-la
// depender do valor exigiria análise de fluxo e mentiria em runtime.
//
// Este CA é PERMANENTE — nenhuma fatia futura o promove a verde.
//
// EXPECT-ERROR: optional-in-interpolation

fn main() {
  let apelido: String? = nil
  print("olá, ${apelido}")
}
