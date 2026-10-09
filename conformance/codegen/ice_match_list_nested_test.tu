// **FRONTEIRA:** sub-pattern COMPOSTO (com sub-estrutura) dentro de
// list-pattern — `struct`, `record` e variante de enum, as três.
//
// `[[1], ..r]` funciona (`match_lista_aninhado.tu`) porque list-em-list só
// precisa do type-arg que a F5 já provou. Um pattern composto precisa de outra
// coisa: resolver campos/variantes pela DECL do escrutínio e compor teste **e**
// bind sobre um receptor que já é derivado (`S[0].x`). Isso é o mesmo trabalho
// que o `_fieldTest` tem em aberto desde sempre para
// `Ret { origem: Ponto { x: 0 } }` — e fazê-lo meio aqui e meio lá custaria
// duas vezes. **Fecha junto**, e é por isso que esta catraca e a do
// `match-field-` nomeiam uma fatia só.
//
// O programa abaixo é **F5+F6-verde** (medido em 2026-09-01): o
// `_bindListPattern` recursa em `_bindPattern(el, elem)` e o `StructPattern`
// tipa normalmente contra `P`. Não é programa errado — é fatia que falta. Se
// fosse programa errado, o erro seria da F5 e este fixture não existiria.
//
// ⚠️ **UMA fronteira, e o código do ICE agora diz isso.** A primeira versão
// desta fatia gravava `…-test-${sub.runtimeType}`, seguindo o precedente do
// `match-field-`. A varredura de alcançabilidade achou **três** construções
// chegando ao mesmo sítio em programa verde — `StructPattern` (aqui),
// `RecordPattern` (`[{ x: a, y: _ }, ..]`) e `EnumPattern` (`[.some(v), ..]`,
// `[.ok(v), ..]`). Com o `runtimeType` no código, seriam seis códigos, esta
// catraca cobriria um e os outros cinco ficariam mudos: exatamente a
// "declaração sem catraca" que a R7 existe para impedir, só que disfarçada de
// diagnóstico detalhado. O span já diz qual construção foi.
//
// ⚠️ **Este fixture e o `_bind` são DOIS, e por outro motivo.** O `_matchExpr`
// faz right-fold: o **último braço não ganha teste** (vira o `otherwise`, e a
// exaustividade é da F6). Então um pattern composto no último braço nunca passa
// por `_elemTest` — só por `_elemBind`. Um código só para os dois caminhos os
// tornaria indistinguíveis na asserção (R13). Aqui o braço aninhado é o
// PRIMEIRO, então dispara o teste; em `ice_match_list_nested_bind.tu` ele é o
// último.
//
// EXPECT-ICE: ice-codegen-match-list-nested-test

struct P { x: Int }

fn f(xs: List<P>) -> Int => match xs {
  [P { x: 0 }, ..] => 1,
  _ => 0
}

fn main() {
  let xs: List<P> = [P(x: 0)]
  print("${f(xs)}")
}
