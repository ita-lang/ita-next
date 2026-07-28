// FRONTEIRA HONESTA (§7.8) — não é CA verde: documenta o que a emissão AINDA
// não sabe baixar, e o `ice-codegen-*` que ela devolve em vez de mentir.
//
// `"a" < "b"` passa a F5 (o `comparison-type-mismatch` só cobra que os dois
// lados tenham o MESMO tipo, não que exista o operador), mas `String` não declara
// `<` no Kernel. Emitir um `<` de receptor `String` produziria um `.dill` que a VM
// rejeita — então o emitter para com ICE. Quando o `<` de `String` ganhar gabarito
// (ou a F5 passar a barrá-lo, virando erro 65), ESTE fixture falha e cobra a
// atualização: é essa a função dele.
//
// EXPECT-ICE: ice-codegen-cmp-on-StringType

fn main() {
  print(if "a" < "b" => "sim" else "não")
}
