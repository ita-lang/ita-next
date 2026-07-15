// O erro LÉXICO chega ao `itac parse` (e a desugar/resolve): antes o driver
// descartava `tokenizeSource().errors` e o usuário via só o `parse-error`
// derivado do `Tag.invalid` — "expected-expression" no lugar de
// "lex-integer-overflow", que é a causa. O parse-error derivado agora é
// SUPRIMIDO (o léxico já reportou aquele token), então sobra só a causa.
// O `let b` seguinte parseia (D3: erro léxico não aborta o scan).
let a = 99999999999999999999
let b = 1
// EXPECT-LEX: lex-integer-overflow @7:9
