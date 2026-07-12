// INVARIANTE DE DESIGN (dono, 2026-07-11): a string vazia "" é um VALOR real —
// nó `str` de sistema —, NUNCA nil/undefined (diferente de JS/TS). O parser
// mantém TRÊS estados mutuamente distintos, sem ambiguidade:
//   • ""  → (str)   valor string vazia (tipo String, não-opcional)
//   • nil → nil     ausência INTENCIONAL — só legal sob um tipo opcional `T?`
//   • sem init      não-inicializado (valor ausente na AST)
// A rejeição de `nil` sob `String` (não-opcional) é SEMÂNTICA (Fase 3), não
// sintática — ver compiler/docs/spec/nullity-invariant.md.
let empty: String = ""
let nul: String? = nil
let bare: String
