// **Variante de enum com payload DEFAULT** — `.circulo()` sem argumento.
//
// Este era o único dos cinco sítios de default que lia `p.defaultValue` apenas
// para decidir `isRequired` e **descartava a expressão**. A F5 permite saltar,
// então `.circulo()` compilava — e a VM entregava `null` num named
// non-nullable. O programa imprimia `raio null` para um `Int`.
//
// Os outros quatro sítios (`_methodSignature`, `_initCtor`, `_struct`,
// `_fnSignature`) sempre chamaram `_constDefault`. Este ficou de fora, e nenhum
// fixture tinha variante COM default — a mesma forma do bug 1 (que também só
// aparecia num sítio de default e também produzia valor inválido silencioso).

enum Forma {
  circulo(raio: Int = 5),
  quadrado(lado: Int),
  rotulado(nome: String = "sem nome", peso: Int = 1),
}

fn descreve(f: Forma) -> String =>
  match f {
    .circulo(r) => "circulo ${r}"
    .quadrado(l) => "quadrado ${l}"
    .rotulado(n, p) => "rotulado ${n} peso ${p}"
  }

fn main() {
  // Todos os defaults saltados.
  let c: Forma = .circulo()
  print(descreve(f: c))

  // Default sobrescrito — o caminho normal continua funcionando.
  let c2: Forma = .circulo(raio: 9)
  print(descreve(f: c2))

  // Sem default: obrigatório.
  let q: Forma = .quadrado(lado: 3)
  print(descreve(f: q))

  // Dois defaults na mesma variante, ambos saltados.
  let r: Forma = .rotulado()
  print(descreve(f: r))
}
