// §7.4-c — comparações de ORDEM (`<`/`>`/`<=`/`>=`) sobre `Int`:
// `InstanceInvocation` de `dart:core::num`, mesma receita dos aritméticos
// (`bool Function(num)`).
//
// Cada linha imprime "ok" pelo ramo CERTO: um operador trocado (`<` por `<=`,
// por exemplo) não muda o tipo nem o verify — muda só a saída. É o golden que
// pega, não o `.dill`.

fn main() {
  print(if 1 < 2 => "lt ok" else "lt FALHOU")
  print(if 2 > 1 => "gt ok" else "gt FALHOU")
  print(if 2 <= 2 => "le ok" else "le FALHOU")
  print(if 2 >= 2 => "ge ok" else "ge FALHOU")
  print(if 2 < 2 => "lt estrito FALHOU" else "lt estrito ok")
}
