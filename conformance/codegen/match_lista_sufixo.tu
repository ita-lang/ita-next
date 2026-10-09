// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// §7.4-e — os elementos DEPOIS do `..resto`, que são os únicos que precisam de
// aritmética de índice. É aqui que mora o off-by-one desta fatia.
//
// Um elemento do prefixo é `S[i]`, com `i` constante. Um do SUFIXO não tem
// índice fixo — depende do comprimento em runtime:
//
//     [.., x, y]   (sufixo de 2)  ⟹  x = S[S.length - 2],  y = S[S.length - 1]
//
// O alvo do `-` não é escolha nossa: o Kernel o reserva no seu próprio nó de
// list-pattern, verbatim de `pkg/kernel/lib/src/ast/patterns.dart:465-472` (pin
// 3.12.2), campo `minusTargetReference` — *"Reference to the target of the
// `minus` method of the `length` of this list. This is used to compute tail
// indices if this pattern has a rest pattern."*
//
// ⚠️ **Inverter o sentido (`m - j` ↔ `j + 1`) roda liso e erra só na borda.**
// Com sufixo de 1 os dois dão o mesmo número, e um fixture com `[.., x]` apenas
// passaria nos dois. Por isso `doisDoFim` tem sufixo de **2** e é chamado com
// listas de comprimento 1, 2 e 3: só o comprimento 3 separa `S[length-2]` de
// `S[1]`.
//
// ⚠️ **`[a, ..r, b]` com exatamente 2 elementos** é a outra borda: o `..r` fica
// VAZIO, e `sublist(1, S.length - 1)` = `sublist(1, 1)`. O SDK é explícito de
// que isso é legal, não um erro de faixa (`list.dart:745`): *"If `end` is equal
// to `start`, then the returned list is empty."* A linha `1..2 meio=0` é a prova.
//
// ⚠️ **`termina9` testa o sufixo sem LIGAR nada** — `[.., 9]` é um literal na
// posição do fim, o caminho em que o índice calculado vira receptor de um `==`
// em vez de inicializador de um bind. `[9, 1]` responder `false` é o que separa
// "olhou o último" de "olhou o primeiro".
//
// Golden do oráculo Dart no pin 3.12.2 (list-patterns nativos, lowering do CFE).

fn extremos(xs: List<Int>) -> String => match xs {
  [] => "vazio",
  [a] => "so ${a}",
  [a, ..r, b] => "${a}..${b} meio=${r.length}"
}

fn doisDoFim(xs: List<String>) -> String => match xs {
  [.., x, y] => "${x},${y}",
  _ => "curta"
}

fn termina9(xs: List<Int>) -> Bool => match xs {
  [.., 9] => true,
  _ => false
}

fn main() {
  let vazio: List<Int> = []
  print(extremos(vazio))
  print(extremos([7]))
  print(extremos([1, 2]))
  print(extremos([1, 2, 3, 4]))

  let curta: List<String> = ["a"]
  print(doisDoFim(curta))
  print(doisDoFim(["a", "b"]))
  print(doisDoFim(["a", "b", "c"]))

  print("${termina9(vazio)} ${termina9([9])} ${termina9([1, 9])} ${termina9([9, 1])}")
}
