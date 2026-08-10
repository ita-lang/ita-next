// EXPECT-ICE: ice-codegen-retrofit-on-EnumDecl
//
// **Fronteira do CA6:** o merge-na-`Class` do ADR-0017 §1 chegou para `struct` e
// `class`, e **não** para `enum`. A fatia que falta é a de emitir membros dentro
// da classe selada de um enum-com-payload — outro gabarito, porque o `enum` do
// Itá com payload vira *"**classe selada + subclasse por variante** (sum type)"*
// (spec 013 §7.4-c), e um membro de retrofit teria de ir para a SELADA, não para
// cada variante.
//
// ⚠️ Este fixture existe porque a guarda que o produz é o oposto de uma lacuna
// escondida. Sem ela, `extension Cor { fn nome() }` seria coletado, nunca
// emitido, e o membro sumiria do `.dill` em SILÊNCIO — a F5 aceita a declaração
// (ela só acusa no USO, com `unknown-member`), então um programa que declarasse
// a extensão sem usá-la compilaria "com sucesso" produzindo um artefato
// incompleto. A completude de `implementedTypes` é 100% nossa: o ADR-0017 §1
// mede que *"o verifier **não confere nada**"*.
//
// O ICE nomeia a CONSTRUÇÃO (`retrofit-on-EnumDecl`), não estado do emissor — é
// fronteira legítima pela régua da R7, e some no dia em que o gabarito de enum
// nascer.

enum Cor { vermelho, azul }

extension Cor {
  fn nome() -> String => "cor"
}

fn main() {
  print("nunca chega aqui — o ICE é de EMISSÃO, não de uso")
}
