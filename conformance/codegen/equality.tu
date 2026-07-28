// §7.4-c — `==`/`!=`: `EqualsCall` (nó ESPECIAL do Kernel — não
// `InstanceInvocation`) e `Not(EqualsCall)`.
//
// O `interfaceTarget` sai do TIPO do receptor, e os três casos aqui resolvem para
// classes DIFERENTES: `Int` → `num::==` (int não declara `==`), `String` →
// `String::==` (declara o seu), `Bool` → `Object::==` (bool não declara). Um walk
// ingênuo de superclasse acharia o alvo errado — por isso os três estão no corpus.

fn main() {
  print(if 1 == 1 => "int eq ok" else "int eq FALHOU")
  print(if "a" == "a" => "str eq ok" else "str eq FALHOU")
  print(if true == true => "bool eq ok" else "bool eq FALHOU")
  print(if 1 != 2 => "int ne ok" else "int ne FALHOU")
  print(if "a" != "a" => "str ne FALHOU" else "str ne ok")
}
