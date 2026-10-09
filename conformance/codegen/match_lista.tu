// SPEC: 013 — escopo default das citações `§N` nuas deste fixture (Art. IV-6d).
// §7.4-e — `match` sobre **`List`** (o "slice"), a última família da §7.4-e.
// Fecha o **CA8 da spec 012** e o T043.
//
// ⚠️ **A previsão que estava no repo era errada, e o erro tem nome.** A spec 013
// §7.4-e marcava esta família como *"GATED pela spec 012"*, com a razão escrita:
// o teste de comprimento e o bind de elemento *"são membros de built-in … a F5
// os recusa hoje"*. A 012 aterrissou em 2026-08-31 — `.length`, `[]` e `+`
// passaram a tipar e a emitir — e o `match` sobre `List` **não destravou**:
// seguiu em `ice-codegen-match-on-BuiltinType`. Ele nunca dependeu da emissão de
// `List`. Dependia do LOWERING do list-pattern, que é trabalho próprio, no
// `_matchExpr`, e que ninguém tinha feito.
//
// **De onde vem o gabarito.** Não de nós: o formato binário do Kernel enumera,
// no nó `ListPattern` que a própria §7.4-e nos PROÍBE de emitir (CFE-interno →
// `UNREACHABLE()` na VM), exatamente os cinco alvos que este lowering usa —
// `length`, o `==`/`>=` do comprimento, `sublist`, o `-` dos índices do fim, e
// o `[]`. Verbatim de `pkg/kernel/lib/src/ast/patterns.dart:437-450` (pin
// 3.12.2), no campo `lengthCheckTargetReference`: *"If this pattern has a rest
// pattern, this is an `operator >=` method. Otherwise this is an `operator ==`
// method."* Daí as duas formas:
//
//     [a, b]       ⟹  S.length == 2  &&  <testes dos elementos>
//     [_, ..r]     ⟹  S.length >= 1  &&  r = S.sublist(1)
//
// ⚠️ **`[..r]` NÃO ganha teste de comprimento.** Seria `S.length >= 0` — uma
// tautologia sobre `int` non-nullable. O braço é IRREFUTÁVEL, e escrever um
// teste esconderia isso no dump; é a mesma coisa que o `StructPattern`
// só-de-binds já diz com `true`. A função `tudo` abaixo é quem o exercita.
//
// ⚠️ **`none` e `ok` como BINDERS** (função `privilegiado`) — este é o caso
// metamórfico, e ele não está aqui por simetria. Cinco dos oito bugs da
// auditoria de 2026-07-29 foram a F7 redecidindo por LEXEMA o que a F5 já tinha
// provado por TIPO (`p.variant == 'none'` sem olhar o subject). Um binder de
// list-pattern chamado `none` ou `ok` é um nome do USUÁRIO e nada mais: se
// alguma decisão aqui olhasse a grafia, esta linha imprimiria outra coisa.
//
// Golden do oráculo Dart no pin 3.12.2 — o mesmo programa com list-patterns
// NATIVOS, cujo lowering é feito pelo CFE, não pelo nosso emitter.

// A LETRA do CA8 (spec 012 §11 / `conformance-cases.md:52-53`), copiada, não
// parafraseada — a R9 cobra o texto INTEIRO do critério, e um fixture "parecido"
// deixaria o placar afirmar o que não rodou. Repare que `r` fica **sem uso**: o
// `..resto` nomeado emite o `sublist` mesmo assim, porque quem decide isso é o
// pattern, não o corpo.
fn m(xs: List<Int>) -> Int => match xs { [] => 0, [_, ..r] => 1 }

fn conta(xs: List<Int>) -> Int => match xs {
  [] => 0,
  [_] => 1,
  [_, _] => 2,
  [_, ..] => 3
}

fn primeiro(xs: List<Int>) -> Int => match xs {
  [] => 0,
  [a, ..] => a
}

fn cauda(xs: List<Int>) -> Int => match xs {
  [] => 0,
  [_, ..r] => r.length
}

fn tudo(xs: List<Int>) -> Int => match xs { [..r] => r.length }

fn classifica(xs: List<Int>) -> String => match xs {
  [1, 2] => "um-dois",
  [0..10] => "unico-pequeno",
  [_] => "unico",
  _ => "outro"
}

fn privilegiado(xs: List<Int>) -> Int => match xs {
  [] => 0,
  [none, ..ok] => none + ok.length
}

fn main() {
  let vazio: List<Int> = []
  let um: List<Int> = [7]
  let dois: List<Int> = [1, 2]
  let tres: List<Int> = [1, 2, 3]

  print("${m(vazio)} ${m(um)} ${m(tres)}")
  print("${conta(vazio)} ${conta(um)} ${conta(dois)} ${conta(tres)}")
  print("${primeiro(vazio)} ${primeiro(tres)}")
  print("${cauda(vazio)} ${cauda(um)} ${cauda(tres)}")
  print("${tudo(vazio)} ${tudo(tres)}")
  print("${classifica(dois)} ${classifica(um)} ${classifica([99])} ${classifica(tres)}")
  print("${privilegiado([10, 1, 2])}")
}
