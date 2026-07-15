// Default de payload que resolve: `padrao` liga ao `let` de módulo — declarado
// DEPOIS do enum e ainda assim visível (letrec de módulo, CA3). O default vê o
// escopo do módulo, como o default de param de fn; não há `self` num case.
enum E {
  Some(v: Int = padrao)
  None
}

let padrao = 42
