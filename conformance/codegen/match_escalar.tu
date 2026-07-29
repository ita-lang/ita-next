// §7.4-e — `match` sobre ESCALAR (literal) e RANGE, a 2ª e 3ª famílias.
//
//   - literal ⟹ `EqualsCall(subject, literal)` — o mesmo nó ESPECIAL que o `==`
//     binário usa, com `interfaceTarget` resolvido pelo TIPO do subject. Os três
//     alvos distintos aparecem aqui: `Int`/`Float` → `num::==`, `String` →
//     `String::==`, `Bool` → `Object::==` (nenhum dos dois últimos é herdado do
//     primeiro — um walk ingênuo de superclasse erraria);
//   - range ⟹ `subject >= lo && subject <(=) hi`, dois `InstanceInvocation` de
//     `num` sob um `LogicalExpression`. Nós primitivos, como manda a TRAVA DURA.
//
// ⚠️ **As BORDAS são o ponto deste fixture.** `1..10` é EXCLUSIVO no fim e
// `10..=99` é inclusivo — então `10` NÃO cai no primeiro e cai no segundo, e `99`
// ainda cai no segundo. Trocar `<` por `<=` na emissão é um off-by-one que roda
// liso, passa no verifier e só erra na borda: o tipo não muda, o `.dill` é
// válido, e nenhuma outra camada percebe. Só o valor impresso denuncia.
//
// O `_` final não é decoração: a spec 014 §F2 é explícita — ranges **nunca**
// fecham `Int` sem ω, então a F6 exige o catch-all. É ele que vira o `otherwise`
// do right-fold, sem teste.

fn classifica(n: Int) -> String => match n {
  0 => "zero",
  1..10 => "pequeno (1..10, exclui o 10)",
  10..=99 => "medio (10..=99, inclui o 99)",
  _ => "grande"
}

fn inicial(s: String) -> String => match s {
  "a" => "primeira",
  "z" => "ultima",
  _ => "meio"
}

fn meio(x: Float) -> String => match x { 1.5 => "um e meio", _ => "outro" }

fn sim(v: Bool) -> String => match v { true => "sim", false => "nao" }

fn main() {
  // as BORDAS, em ordem
  print("0=${classifica(0)}")
  print("1=${classifica(1)}")
  print("9=${classifica(9)}")
  print("10=${classifica(10)}")
  print("99=${classifica(99)}")
  print("100=${classifica(100)}")

  print("str=${inicial("a")},${inicial("z")},${inicial("m")}")
  print("float=${meio(1.5)},${meio(2.0)}")
  print("bool=${sim(true)},${sim(false)}")
}
