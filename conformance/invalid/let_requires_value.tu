// `let` LIGA um valor ⟹ exige `= e` (ruling do dono 2026-07-15, spec 009 §12-7).
// Não custa imutabilidade: a linguagem já tem TRÊS caminhos imutáveis —
//   (a) condicional:  let x = if c => a else b        (P3, expr_if.tu)
//   (b) multi-passo:  let t = v where { let a = … }   (ADR-0012 A4)
//   (c) pode falhar:  let x = f()?  /  guard let      (P7)
// O uninit-let seria um QUARTO caminho, e menos honesto: o glifo `x = e`
// significaria "inicializar" OU "mutar" conforme o fluxo, SEM marca sintática —
// a mesma doença do flow-narrowing, que a spec 009 §4.6 recusa. `var` é a palavra
// honesta quando o valor muda; `var x: T` sem init segue legal (valid/stmt_let_no_init).
let ready
// EXPECT: parse-error: let-requires-value @684+9
