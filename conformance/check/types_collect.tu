// Fatia A (Collect) — A1 cabeças + A2 assinaturas + generic params.
// Prova o ruling do dono 2026-07-12: `Option<T>` ≡ `T?` — o alias resolve em A2
// (uma reescrita, NÃO instanciação genérica), e por isso a NULIDADE não depende
// da fatia D. Prova também o letrec de tipos (Dragon 6.3.1: o grafo tem ciclos):
// `Caixa` cita `Point` declarado ANTES e `No` cita a si mesmo.
struct Point {
  x: Int
  y: Float
}

enum Opt<T> {
  Some(v: T)
  None
}

class Animal { name: String }
class Cachorro : Animal { raca: String }

struct Caixa {
  conteudo: Option<Int>
  vazio: String?
  ponto: Point
  fn_: (Int, String) -> Bool
  par: (Int, String)
  mutavel: Int
}

struct No { valor: Int, proximo: No? }
