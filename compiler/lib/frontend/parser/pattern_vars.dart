// ===========================================================================
// pattern_vars.dart — Nomes ligados por um pattern (query pura sobre a AST).
// ===========================================================================
//
// Um pattern pode ligar VÁRIOS nomes (`let [a, b] = xs`, `{ x, y }`), então
// "que nomes este binding declara?" não é `n.name` — é este walk. Vive fora de
// `ast.dart` (que espelha o `ast.asdl` 1:1, só nós) e fora de qualquer fase,
// porque duas precisam da MESMA resposta:
//  - Fase 2 (parser): duplicata no bloco `where` (`where-duplicate-binding`);
//  - Fase 3 (desugar): dono de cada nome no letrec do `where` (ordenação).
// Uma cópia por fase divergiria — o `where` daria erro num nome e ordenaria por
// outro. (A Fase 4 NÃO usa: lá o walk também DECLARA no escopo, com span e
// ready-flag por binder — outra operação, não uma query.)
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';

/// Acumula em [out] os nomes que [p] liga. Folhas sem binder (`_`, literais,
/// ranges) não contribuem; `..t` contribui com `t`, `..` sozinho não.
void collectPatternVars(Pattern p, Set<String> out) {
  switch (p) {
    case WildcardPattern():
    case LiteralPattern():
    case RangePattern():
    case ErrorPattern():
      break;
    case BindPattern n:
      out.add(n.name);
    case EnumPattern n:
      for (final s in n.subpatterns) {
        collectPatternVars(s, out);
      }
    case ListPattern n:
      for (final e in n.elements) {
        collectPatternVars(e, out);
      }
    case RecordPattern n:
      for (final f in n.fields) {
        _fieldPatternVars(f, out);
      }
    case StructPattern n:
      for (final f in n.fields) {
        _fieldPatternVars(f, out);
      }
    case RestPattern n:
      if (n.name != null) out.add(n.name!);
  }
}

/// Os nomes que [p] liga, como conjunto novo.
Set<String> patternVars(Pattern p) {
  final out = <String>{};
  collectPatternVars(p, out);
  return out;
}

void _fieldPatternVars(FieldPattern f, Set<String> out) {
  if (f.pattern == null) {
    out.add(f.name); // bind homônimo `{ x }`
  } else {
    collectPatternVars(f.pattern!, out);
  }
}
