// **Um `match` que não destrói nada não precisa de gabarito de família.**
//
// Este fixture não estava no plano do T043 — ele saiu da sondagem que o abriu.
// Medido em 2026-09-01, ANTES da fatia: `match m { outro => outro.length }`
// sobre um `Map` era F5+F6-verde e morria em `ice-codegen-match-on-BuiltinType`,
// o MESMO código que o list-pattern devolvia. Não havia list-pattern nenhum
// aqui, e nada a destruir: o `sealed Pattern` da AST não tem `MapPattern`, então
// **todo** pattern possível sobre um `Map` é `_` ou um binder.
//
// A restrição existia porque o guard do `_matchExpr` pedia uma FAMÍLIA
// conhecida antes de olhar o que os braços de fato pediam. É a R6 no formato
// mais barato de consertar: a emissão estreitava a linguagem, e implementar
// custou um `if`. As outras duas saídas (erro nomeado, ICE com catraca) só
// valeriam se houvesse trabalho real a fazer — e não havia.
//
// ⚠️ **O que ele NÃO promete.** Um dia em que a AST ganhe `MapPattern`, este
// programa continua passando e o novo pattern cai no `_ice` — porque o guard
// libera pelo que os braços SÃO (irrefutáveis), não pelo tipo do escrutínio. A
// falha-padrão segue sendo "recusa o desconhecido" (R5).
//
// Golden do oráculo Dart no pin 3.12.2: `{"a": 1, "b": 2}.length` ⟹ 2.

fn tamanho(m: Map<String, Int>) -> Int => match m { outro => outro.length }

fn descarta(m: Map<String, Int>) -> String => match m { _ => "ignorado" }

fn main() {
  let m: Map<String, Int> = {"a": 1, "b": 2}
  print("${tamanho(m)}")
  print(descarta(m))
}
