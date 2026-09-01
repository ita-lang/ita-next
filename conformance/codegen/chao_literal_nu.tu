// **O CORTE do bloco do chão, preso executavelmente.**
//
// Esta É a letra do **CA1 da spec 012 §11** — `print("${[10, 20, 30].length}")`.
// Ela **não compila hoje**, e não por lacuna da emissão: para na F5 com
// `cannot-infer` no list-literal, exit 65. O receptor de um `.length`/`[]`/`+` é
// posição **sem esperado**, e a errata da spec 010 §4.1 (fatia 0, 2026-08-31)
// cobre só as três posições que têm um — `let` anotado, argumento de parâmetro
// tipado, retorno anotado. A metade **sem** esperado segue `cannot-infer` por
// política (spec 009 §4.3), sob decisão do dono ainda pendente, registrada em
// `specs/012-builtin-members/tasks.md:67`.
//
// **Por que um fixture e não um comentário.** Os cinco fixtures `chao_*` vizinhos
// trocam a letra do CA por receptor tipado. Sem esta catraca, essa troca seria
// indistinguível de uma restrição-para-caber (R6): a linguagem encolhida para
// caber no emissor, com a razão escrita na prosa e nada cobrando. Aqui a razão é
// EXECUTÁVEL — se o dono decidir que o literal nu sintetiza do conteúdo, este
// fixture fica VERMELHO ("esperava cannot-infer, mas COMPILOU") e cobra a
// promoção dos cinco à letra do CA.
//
// ⚠️ **Não é um fixture negativo permanente.** Os outros `EXPECT-ERROR` do corpus
// (`err_missing_main`, `err_main_arity`) prendem erro de USUÁRIO, que fica para
// sempre. Este prende uma DECISÃO PENDENTE, e some quando ela sair — em qualquer
// direção.
//
// EXPECT-ERROR: cannot-infer

fn main() {
  print("${[10, 20, 30].length}")
}
