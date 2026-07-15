// Erro léxico DENTRO de `${…}`: a interpolação é reparseada com um lexer
// próprio (M3), cujos erros também eram descartados. Dois pontos aqui:
//  1. o erro do sub-lexer chega ao usuário (antes: só "expected-expression");
//  2. o `line:col` é ABSOLUTO — o sub-lexer conta a partir de 1:1, então sem
//     `baseLine`/`baseCol` este erro se reportaria em `@1:1`, apontando o topo
//     do arquivo em vez do `1__0` real. (`baseOffset` só corrige o offset.)
let s = "x ${1__0} y"
// EXPECT-LEX: lex-malformed-number @7:14
