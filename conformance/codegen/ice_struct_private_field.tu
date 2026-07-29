// FRONTEIRA HONESTA (§7.8) — campo de `struct` cujo nome começa com `_`.
//
// No Itá o `_` é **só um nome**: visibilidade é `pub`/`isPublic`, não convenção
// de sublinhado. Mas o memberwise baixa os campos como NAMED PARAMETERS, e no
// Dart um named parameter **não pode ser privado** — o param sai manglado
// (`_oculto@21090877`) e nenhum call-site o casa.
//
// O modo como isso falhava é o motivo de o fixture existir:
//   1. `k.Name('_oculto')` sem a `Library` estourava `Null check operator used on
//      a null value` — crash com stack trace, nem ICE (corrigido: `_memberName`);
//   2. com a library, o `.dill` era gerado, o **verifier APROVAVA**, e a VM morria
//      em runtime com `NoSuchMethodError: No constructor 'S.' with matching
//      arguments`. Erro de compilador caindo no usuário como crash de execução.
//
// Fatia futura: mangling (campo privado × param público é decidível — o par é
// gerado pelos dois lados por nós). Quando nascer, este fixture fica vermelho e
// cobra a promoção.
//
// EXPECT-ICE: ice-codegen-struct-private-field

struct Segredo {
  _oculto: Int
}

fn main() {
  print("${Segredo(_oculto: 7)._oculto}")
}
