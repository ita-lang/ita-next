// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// §7.4-e — list-pattern DENTRO de list-pattern, onde o receptor do teste deixa
// de ser o subject e passa a ser uma expressão derivada.
//
// `[[1, 2], ..r]` baixa para `S.length >= 1 && S[0].length == 2 && S[0][0] == 1
// && S[0][1] == 2`. O lowering é a MESMA função, chamada com outro receptor —
// por isso o aninhamento não é uma segunda implementação, e por isso `profundo`
// (três níveis) custa zero código a mais que dois.
//
// ⚠️ **Por que isto não é a mesma fronteira do `StructPattern` aninhado.** O
// `_fieldTest` recusa sub-pattern aninhado em campo de struct desde sempre, e
// aqui o list-em-list passa. A diferença não é apreço: um `StructPattern`
// precisa resolver campos pela decl do escrutínio, e o list-em-list só precisa
// do type-arg que a F5 já deu (`args[0]`). O que falta para o struct está
// nomeado e preso por catraca em `ice_match_list_nested_test.tu` — não é
// silêncio, é fila.
//
// ⚠️ **`[[], ..]` antes de `[[1, 2], ..r]`** não é enfeite de ordem: o primeiro
// braço testa `S[0].length == 0`, o segundo `S[0].length == 2`. Se o teste de
// comprimento do ANINHADO fosse esquecido (só os elementos comparados), `[[]]`
// cairia no segundo braço com zero comparações a fazer — verde, e errado. A
// linha `primeira vazia` é o que prova que o comprimento aninhado é testado.
//
// Golden do oráculo Dart no pin 3.12.2 (list-patterns nativos, lowering do CFE).

fn olha(xss: List<List<Int>>) -> String => match xss {
  [] => "vazio",
  [[], ..] => "primeira vazia",
  [[1, 2], ..r] => "primeira eh 1-2, restam ${r.length}",
  [[a], ..] => "primeira unitaria ${a}",
  _ => "outro"
}

fn profundo(x: List<List<List<Int>>>) -> Int => match x {
  [[[a, ..], ..], ..] => a,
  _ => 0
}

fn main() {
  let vazio: List<List<Int>> = []
  print(olha(vazio))
  print(olha([[]]))
  print(olha([[1, 2], [3]]))
  print(olha([[9]]))
  print(olha([[1, 2, 3]]))

  print("${profundo([[[42, 1]]])}")
}
