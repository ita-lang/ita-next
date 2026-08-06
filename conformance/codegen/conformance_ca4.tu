// **CA4 da §11** — dispatch existencial: `Pato`/`Cao`/`Robo` conformam `Fala`;
// `fn ouve(v: any Fala) => v.som()` responde DIFERENTE para cada um.
//
// É a razão de ser do ADR-0017 §1, e fecha três CAs de uma vez:
//   - **CA4**: o dispatch funciona;
//   - **CA11**: a travessia `any` de fonte local é **ZERO NÓ** — nenhum box,
//     cast ou wrapper aparece ao passar um `Pato` para `any Fala`;
//   - **CA13** (negativo): o `.dill` **não contém** `mixedInType` nem
//     `implements` sobre classe de `dart:core` — as duas armadilhas que o
//     ADR-0017 pinou para sempre.
//
// O gabarito (§7.4-d): `trait` → **`abstract class`** com requisito virando
// `Procedure` abstrato; conformer → o trait em `implementedTypes` + **todos os
// membros de conformance DENTRO da `Class`**. O `interfaceTarget` do
// `InstanceInvocation` sai do TIPO ESTÁTICO do receptor:
//   - receptor `any Fala` ⟹ o procedure ABSTRATO do trait, e a **VM resolve por
//     vtable** (Grupo B) — sem tabela nossa;
//   - receptor concreto (`p.som()`) ⟹ o procedure da própria classe.
// A escolha não é nossa: é o tipo estático que decide, e a F5 já o computou.
//
// ⚠️ **`class Robo : Fala` prova o ruling de 2026-07-15** — *"o papel vem do
// KIND, não da POSIÇÃO"*. O parser põe o 1º type após `:` em `superclass` (split
// posicional, reversível), mas ali está um TRAIT. Quem decide é o kind: trait ⟹
// conformance; `class` ⟹ herança (que segue ICE). Sem essa leitura,
// `class Robo : Fala` seria rejeitada como "superclasse que não é class" — o
// programa legítimo que o ruling existe para permitir.
//
// A linha "direto" mostra o outro lado: chamado sobre o tipo concreto, o mesmo
// método não paga existencial nenhum.

trait Fala {
  fn som() -> String
}

struct Pato : Fala {
  nome: String
  fn som() -> String => "quack"
}

struct Cao : Fala {
  nome: String
  fn som() -> String => "au"
}

class Robo : Fala {
  var carga: Int

  init(carga: Int) {
    self.carga = carga
  }

  fn som() -> String => "beep"
}

fn ouve(v: any Fala) -> String => v.som()

fn main() {
  let p = Pato(nome: "donald")
  let c = Cao(nome: "rex")
  let r = Robo(carga: 50)

  // existencial: MESMA fn, respostas DIFERENTES
  print("existencial: ${ouve(p)} ${ouve(c)} ${ouve(r)}")

  // concreto: mesma resposta, sem dispatch existencial
  print("direto: ${p.som()} ${c.som()} ${r.som()}")
}
