// **CA7 da §11** — `match` sobre enum-com-payload **destrói e rende** (RD-1).
//
// **Quarta fixture promovida pela catraca**, e a única cuja lacuna estava numa
// FASE ANTERIOR: era `ice_enum_payload.tu`, e o ICE dizia
// `enum-payload-circulo` porque a **F5 não sabia construir** `.circulo(raio: 2)`
// (`cannot-infer`). Não adiantava a emissão saber o gabarito — sem construção
// não há valor a destruir. A fatia da F5 nasceu, e esta é a promoção.
//
// O gabarito (§7.4-c/e): **classe selada + uma subclasse por variante**.
//   - `.circulo(raio: 2)` → `ConstructorInvocation` da subclasse;
//   - `.circulo(r)` no pattern → `IsExpression(subject, Forma$circulo)`;
//   - o payload `r` → `InstanceGet(AsExpression(subject, Forma$circulo), raio)`.
//
// ⚠️ O **`as` é obrigatório**: o Kernel cru **não tem flow-promotion**, então o
// `is` do teste não estreita o tipo estático do subject. O que o Dart faria por
// análise, aqui é nó explícito.
//
// ⚠️ Variante SEM payload dentro de um enum selado (`.ponto`) também vira
// subclasse — mas ganha um `static final` singleton, para não alocar por uso. O
// TESTE dela continua sendo `IsExpression`, uniforme com as demais: o singleton
// é economia, não correção.
//
// O `match` é exaustivo sem `_`: enum é conjunto FINITO e a F6 o fecha.

enum Forma {
  circulo(raio: Int),
  retangulo(largura: Int, altura: Int),
  ponto
}

fn area(f: Forma) -> Int => match f {
  .circulo(r) => r * r * 3,
  .retangulo(w, h) => w * h,
  .ponto => 0
}

fn descreve(f: Forma) -> String => match f {
  .circulo(_) => "redondo",
  .retangulo(w, h) => if w == h => "quadrado" else "retangulo",
  .ponto => "nada"
}

fn main() {
  let c: Forma = .circulo(raio: 2)
  let r: Forma = .retangulo(largura: 3, altura: 4)
  let q: Forma = .retangulo(largura: 5, altura: 5)
  let p: Forma = .ponto

  print("areas=${area(c)},${area(r)},${area(q)},${area(p)}")
  print("desc=${descreve(c)},${descreve(r)},${descreve(q)},${descreve(p)}")

  // payload de DOIS campos, ligados por nome na ordem declarada
  print("dois=${match r { .retangulo(w, h) => w * 100 + h, .circulo(_) => 0, .ponto => 0 }}")
}
