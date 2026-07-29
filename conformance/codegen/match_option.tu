// §7.4-e — `match` sobre **`Option`/`T?`**, a primeira família de escrutínio.
//
// **Este fixture fecha o CA10 da §11**: *"`nil` vira `null` nativo — `let x: Int?
// = nil` + match imprime o braço `.none`; custo zero (sem classe Option no
// `.dill`)"*. As três metades estão aqui: o `nil` (em `vazio`), o braço `.none`
// impresso (a linha `vazio=0`), e o custo zero — garantido pelo invariante
// `checkNoSyntheticClasses`, que acusaria qualquer classe `Option` sintetizada.
// Conferido também por inspeção direta: o `.dill` de um programa com `Int?` tem
// ZERO ocorrências da string "option".
//
// ⚠️ **TRAVA DURA:** os pattern-nodes do Dart 3 (`IfCaseStatement`,
// `PatternSwitchStatement`, `PatternVariableDeclaration`) são CFE-internos e
// **PROIBIDOS** no `.dill` cru — a VM os trata na mesma cláusula do
// `ForInStatement`, com `UNREACHABLE()`. Então o `match` baixa para nós
// primitivos e nada mais: `EqualsNull` · `Not` · `ConditionalExpression` · `Let`.
//
// **RD-1 decide a forma:** `MatchExpr` é EXPRESSÃO (todo braço é `=> expr`), logo
// **right-fold de `ConditionalExpression`**. O ÚLTIMO braço não ganha teste —
// vira o `otherwise`. É sound porque a **F6 já provou exaustividade**: a §7.4-e
// diz literalmente que a F7 confia nela. Sem isso sobraria um `throw` de
// fim-de-cadeia.
//
// **Custo zero preservado:** nenhuma classe `Option` participa do teste — é
// `subject == null`. O invariante `checkNoSyntheticClasses` guarda isso.
//
// A linha `[efeito]` é a que mais importa: o subject entra num `Let` e é
// avaliado **UMA vez**. Sem isso, `match f() { … }` chamaria `f()` uma vez por
// teste de braço — e um fixture de valor puro nunca perceberia, porque o
// resultado seria o mesmo.

fn barulhento() -> Int? {
  print("[efeito] avaliei o subject UMA vez")
  return 5
}

fn main() {
  let cheio: Int? = 5
  let vazio: Int? = nil

  print("cheio=${match cheio { .some(v) => v, .none => 0 }}")
  print("vazio=${match vazio { .some(v) => v, .none => 0 }}")

  // `.some(_)` — payload descartado, sem bind
  print("tem?=${match cheio { .some(_) => "sim", .none => "não" }}")

  // binder no topo liga o subject INTEIRO (ainda opcional)
  print("wildcard=${match vazio { _ => "casa sempre" }}")

  print("efeito=${match barulhento() { .some(v) => v, .none => 0 }}")
}
