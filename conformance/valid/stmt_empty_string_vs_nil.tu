// INVARIANTE DE DESIGN (dono, 2026-07-11): a string vazia "" é um VALOR real —
// nó `str` de sistema —, NUNCA nil/undefined (diferente de JS/TS). O parser
// mantém TRÊS estados mutuamente distintos, sem ambiguidade:
//   • ""  → (str)   valor string vazia (tipo String, não-opcional)
//   • nil → nil     ausência INTENCIONAL — só legal sob um tipo opcional `T?`
//   • sem init      não-inicializado (valor ausente na AST) — **só `var`**
// A rejeição de `nil` sob `String` (não-opcional) é SEMÂNTICA (Fase 5), não
// sintática — ver compiler/docs/spec/nullity-invariant.md.
//
// Δ 2026-07-15 (ruling do dono, spec 009 §12-7): o 3º estado é `var`, não `let`.
// `let` LIGA um valor ⟹ exige `= e` (`let-requires-value`); `var` é SLOT ⟹ pode
// encher depois (definite-assignment é F6). A assimetria é P1 virando FORMA — os
// três estados seguem distintos, e agora a FORMA diz qual é qual.
let empty: String = ""
let nul: String? = nil
var bare: String
