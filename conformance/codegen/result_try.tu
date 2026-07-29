// **CA8 da §11** — `e?` propaga o `.err` com early-return; o caminho `.ok` segue.
// É o **núcleo do zero try/catch (P7)**.
//
// O `?` marca no CARACTERE EXATO onde a propagação acontece. A ausência de marca
// significa que nada propaga — o oposto do try/catch, onde a ausência significa
// "isto pode lançar". Aqui não há o que capturar: o fluxo é explícito no glifo.
//
// **O único gabarito com fluxo NÃO-LOCAL** (§7.4-e). A semântica é
// `match e { .ok($v) => $v, .err($e) => return .err($e) }`, e o `return` está
// DENTRO de uma expressão (`let x = f()?`). No Kernel isso pede
// **`BlockExpression`** — `Block` de statements + a `value` que ele rende:
//
//     BlockExpression(
//       Block([
//         var #try = <operando>;
//         if (#try is ItaResult$err) return ItaResult$err(#try.value);
//       ]),
//       (#try as ItaResult$ok).value as T,
//     )
//
// O `ReturnStatement` sai da FUNÇÃO, não do bloco — que é exatamente o
// early-return prometido. `cadeia(40, 0)` prova: o PRIMEIRO `?` corta o fluxo, e
// o segundo `divide` nunca roda.
//
// ⚠️ **`Result` é classe; `Option` é nativo — e a assimetria é principiada.**
// `Option<T>` ≡ `T?` tem equivalente no Kernel (nulidade) ⟹ custo zero. `Result`
// carrega payload nos DOIS lados, e nenhum tipo nativo representa "ou T ou E"
// sem perder um. A classe aqui é o preço mínimo, não conveniência — e por isso
// `ItaResult`/`ItaResult$ok`/`ItaResult$err` estão na allowlist FECHADA do
// invariante de custo zero, nomeadas uma a uma.
//
// ⚠️ O `.err` é RECONSTRUÍDO na propagação, não repassado: o objeto de origem é
// `Result<T₁,E>` e o de destino `Result<T₂,E>` — mesmo `E`, `T` diferente.
//
// A F5 já garantiu o contrato antes de chegar aqui: `try-outside-result-fn` (a
// fn tem de devolver `Result`) e `error-type-mismatch` (o `E` é IDÊNTICO — sem
// `From`, §0.5-6). A emissão não re-checa nada disso.

fn divide(a: Int, b: Int) -> Result<Int, String> =>
  if b == 0 => .err("divisao por zero") else .ok(a / b)

fn cadeia(x: Int, d: Int) -> Result<Int, String> {
  let meio = divide(x, d)?
  let outro = divide(meio, 2)?
  return .ok(outro + 100)
}

fn mostra(r: Result<Int, String>) -> String => match r {
  .ok(v) => "ok:${v}",
  .err(e) => "err:${e}"
}

fn main() {
  // caminho feliz: os DOIS `?` passam
  print(mostra(cadeia(40, 2)))

  // o PRIMEIRO `?` corta — o segundo `divide` nunca roda
  print(mostra(cadeia(40, 0)))

  // construção direta das duas variantes
  print(mostra(divide(1, 0)))
  print(mostra(divide(9, 3)))
}
