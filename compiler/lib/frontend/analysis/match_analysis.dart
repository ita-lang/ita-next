// ===========================================================================
// match_analysis.dart — Fase 6 (Flow-check), LT-F6b: exaustividade + redundância
// de `match` pelo algoritmo de Maranget 2007 (§3.1 U/S/D + testemunha).
//
// Blueprint: specs/014-flow-check/blueprint-match-analysis.md §F1.
// Corte de fatiamento (ruling do dono, spec 014 §12-11): tipo não-modelado que
// um `_` NÃO fecha → `match-exhaustiveness-unsupported` (ERRO honesto), NUNCA
// silêncio (mentiria) nem `non-exhaustive` chutado (falsa-acusaria). A linguagem
// é PEDRA: ou DECIDE, ou diz "não sei" — jamais afirma o que não verificou.
//
// FATIA 1 (esta): tipos FECHADOS (enum/Option/Result/Bool) + escalares infinitos
// por literal (Int/String/Float — decidíveis por Maranget §3.2, testemunha `_`).
// Range/List/produto num gap não-fechado → unsupported (Fatia 2/3).
// ===========================================================================

import 'package:ita_next_compiler/frontend/analysis/flow.dart' show FlowError;
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// O que o walker consome: diagnósticos + braços mortos (pulados no DA).
class MatchReport {
  final List<FlowError> diagnostics;
  final Set<ast.MatchArm> deadArms;
  const MatchReport(this.diagnostics, this.deadArms);
}

/// A "não sei" honesta do §12-11: o veredito dependia de um tipo cuja estrutura
/// a Fatia 1 não modela, e nenhum `_` fechou o gap.
class _MatchUnsupported implements Exception {
  const _MatchUnsupported();
}

/// Ponto de entrada. `scrutineeType` = a nº1 (`_typeOf(scrutinee)`); `types` = a
/// `TypeTable` do `CheckResult` (Σ dos enums). Não consulta `exprTypes` (I5).
MatchReport analyzeMatch(
  ast.MatchExpr node,
  Type scrutineeType,
  TypeTable types,
) {
  final a = _MatchAnalyzer(types);
  final diags = <FlowError>[];
  final dead = <ast.MatchArm>{};

  // 1. Exaustividade: P = braços UNGUARDED (guard não conta — Maranget I6),
  //    query = (ω). Testemunha do U vira o `detail` do erro.
  final unguarded = [
    for (final arm in node.arms)
      if (arm.guard == null) [arm.pattern],
  ];
  try {
    final w = a._useful(_Matrix([scrutineeType], unguarded), [a._wildAt(node)]);
    if (w != null) {
      diags.add(FlowError(
        'match-not-exhaustive',
        node.offset,
        node.length,
        detail: '${a._print(w.single)} não coberto',
      ));
    }
  } on _MatchUnsupported {
    // §12-11: veredito indecidível pela Fatia 1 e nenhum `_` fechou. ERRO honesto,
    // sem redundância sobre um match cuja segurança não foi provada. O `detail`
    // orienta a aresta afiada (W3 🟡): a forma estrutural exige um `_` por ora.
    diags.add(FlowError(
      'match-exhaustiveness-unsupported',
      node.offset,
      node.length,
      detail: 'cobertura de list/produto/range chega na Fatia 2/3 — '
          'adicione um braço `_` para exaurir por ora',
    ));
    return MatchReport(diags, dead);
  }

  // 2. Redundância: braço `i` morto sse `¬U(P_{<i} unguarded, pᵢ)`.
  final prior = <List<ast.Pattern>>[];
  for (final arm in node.arms) {
    if (arm.guard != null) continue; // I6: guarded nunca acusado de morto
    try {
      final useful =
          a._useful(_Matrix([scrutineeType], [...prior]), [arm.pattern]);
      if (useful == null) {
        diags.add(FlowError(
          'unreachable-match-arm',
          arm.pattern.offset,
          arm.pattern.length,
        ));
        dead.add(arm); // morto NÃO entra no P_{<j} dos seguintes
      } else {
        prior.add([arm.pattern]);
      }
    } on _MatchUnsupported {
      // Redundância deste braço indecidível (ex.: `5` vs range `0..=9`). ABSTÉM
      // — não acusa nem inocenta; o braço segue vivo em P_{<j} e roda correto.
      // NÃO é mentira de exaustividade (a #1 já deu veredito): é incompletude
      // conhecida do LINT de redundância (spec 014 §12-11, nota).
      prior.add([arm.pattern]);
    }
  }
  return MatchReport(diags, dead);
}

// ---------------------------------------------------------------------------
// Matriz, construtor selado, testemunha, cabeça.
// ---------------------------------------------------------------------------

/// Matriz P (Maranget §3.1). `colTypes` = tipo de cada coluna (I5 — dirigida
/// pelo tipo, nunca re-tipa); `rows[k].length == colTypes.length`.
class _Matrix {
  final List<Type> colTypes;
  final List<List<ast.Pattern>> rows;
  _Matrix(this.colTypes, this.rows);
  int get width => colTypes.length;
}

/// Construtor do tipo da coluna: nome canônico + tipos dos argumentos.
class _Ctor {
  final String name;
  final List<Type> argTypes;
  const _Ctor(this.name, this.argTypes);
  int get arity => argTypes.length;
}

/// A tabela §4 selada. Só `_sigOf` sabe a família do tipo.
sealed class _Sig {
  const _Sig();
  List<_Ctor> get ctors;
  bool isComplete(Set<String> present);
}

class _SealedSig extends _Sig {
  @override
  final List<_Ctor> ctors;
  const _SealedSig(this.ctors);
  @override
  bool isComplete(Set<String> present) =>
      ctors.every((c) => present.contains(c.name));
}

/// `Never` — Σ = ∅, completa por VACUIDADE (`match n: Never {}` exaure).
class _EmptySig extends _Sig {
  const _EmptySig();
  @override
  List<_Ctor> get ctors => const [];
  @override
  bool isComplete(Set<String> _) => true;
}

/// Int/String/Float/List/produto: NÃO selado. Nunca completa por enumeração; o
/// veredito sai do ramo `D` (a estrutura só é tocada se o `D` deixa gap E há
/// pattern estrutural — §F1.4).
class _OpaqueSig extends _Sig {
  const _OpaqueSig();
  @override
  List<_Ctor> get ctors => const [];
  @override
  bool isComplete(Set<String> _) => false;
}

/// Testemunha de não-cobertura (Maranget §3.1).
sealed class _Wit {}

class _WWild extends _Wit {
  final Type type;
  _WWild(this.type);
}

class _WCtor extends _Wit {
  final _Ctor ctor;
  final List<_Wit> args;
  _WCtor(this.ctor, this.args);
}

/// Classificação de cabeça (§12-11): ω fecha qualquer coluna; `_HCtor` é selado
/// (decidível); `_HAtom` é literal escalar (Σ infinita, decidível por Maranget
/// §3.2); `_HStruct` é forma cuja estrutura a Fatia 1 não modela.
sealed class _Head {}

class _HWild extends _Head {}

class _HCtor extends _Head {
  final String name;
  _HCtor(this.name);
}

class _HAtom extends _Head {
  final String key;
  _HAtom(this.key);
}

class _HStruct extends _Head {}

// ---------------------------------------------------------------------------
// O analisador.
// ---------------------------------------------------------------------------

class _MatchAnalyzer {
  final TypeTable types;
  _MatchAnalyzer(this.types);

  /// A tabela §4 em código — o único ponto que conhece a família do tipo.
  _Sig _sigOf(Type t) {
    if (t is BoolType) {
      return const _SealedSig([_Ctor('true', []), _Ctor('false', [])]);
    }
    if (t is OptionalType) {
      // T? ≡ Option<T> (spec 009 §4.6).
      return _SealedSig([
        _Ctor('some', [t.inner]),
        const _Ctor('none', []),
      ]);
    }
    if (t is BuiltinType && t.kind == BuiltinKind.result) {
      return _SealedSig([
        _Ctor('ok', [t.args[0]]),
        _Ctor('err', [t.args[1]]),
      ]);
    }
    if (t is NeverType) return const _EmptySig();
    if (t is NamedType) {
      final info = types.of(t.decl);
      if (info != null && info.kind == TypeKind.enum_ && info.variants != null) {
        final subst = info.substFor(t.args); // idem _bindEnumPattern (check.dart)
        return _SealedSig([
          for (final v in info.variants!)
            _Ctor(v.name, [for (final p in v.payload) substitute(p, subst)]),
        ]);
      }
    }
    return const _OpaqueSig(); // Int/Str/Float/List/produto → Fatia 2/3
  }

  /// Normalização superfície→cabeça (§2). NÃO lança aqui — a decisão de erro é
  /// do `_useful` (só depois de saber que o `D` deixou gap).
  _Head _classify(ast.Pattern p) {
    switch (p) {
      case ast.WildcardPattern _:
      case ast.BindPattern _:
        return _HWild();
      case ast.EnumPattern n:
        return _HCtor(n.variant);
      case ast.LiteralPattern n when n.literal is ast.BoolLit:
        return _HCtor((n.literal as ast.BoolLit).value ? 'true' : 'false');
      case ast.LiteralPattern n when n.literal is ast.NilLit:
        return _HCtor('none'); // `nil` ≡ .none do Option (parser.dart:1892)
      case ast.LiteralPattern n:
        return _HAtom(_atomKey(n.literal)); // Int/Str/Float — átomo escalar
      // Estrutura que a Fatia 1 não modela (Range/List/Struct/Record + Rest).
      case ast.RangePattern _:
      case ast.ListPattern _:
      case ast.RestPattern _:
      case ast.StructPattern _:
      case ast.RecordPattern _:
        return _HStruct();
      case ast.ErrorPattern _:
        return _HStruct(); // parser já reportou; defensivo
    }
  }

  /// Chave de igualdade do literal escalar — precisa só p/ `_specializeAtom`
  /// (redundância). Int/Float exatos; Str e outros ficam ÚNICOS por span
  /// (redundância de string literal defere à Fatia 3 — incompletude HONESTA do
  /// lint, nunca falsa-acusação; a exaustividade não depende da chave).
  String _atomKey(ast.Expr lit) => switch (lit) {
        ast.IntLit n => 'i:${n.value}',
        ast.FloatLit n => 'f:${n.value}',
        _ => 'u:${lit.offset}:${lit.length}',
      };

  /// Os argumentos do construtor casado (para o `S`). Aridade garantida pela F5
  /// (`pattern-arity-mismatch`); BoolLit/NilLit têm aridade 0.
  List<ast.Pattern> _subPatterns(ast.Pattern p) {
    if (p is ast.EnumPattern) return p.subpatterns;
    return const [];
  }

  ast.Pattern _wild(ast.Pattern src) =>
      ast.WildcardPattern(src.offset, src.length);

  ast.Pattern _wildAt(ast.MatchExpr node) =>
      ast.WildcardPattern(node.offset, node.length);

  /// `S(c, P)` — especialização por construtor SELADO (coluna 0 só tem ω/_HCtor).
  _Matrix _specialize(_Ctor c, _Matrix p) {
    final newRows = <List<ast.Pattern>>[];
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HWild) {
        newRows.add([
          ...List.filled(c.arity, _wild(row[0])),
          ...row.sublist(1),
        ]);
      } else if (h is _HCtor && h.name == c.name) {
        newRows.add([..._subPatterns(row[0]), ...row.sublist(1)]);
      } // c'≠c → descarta
    }
    return _Matrix([...c.argTypes, ...p.colTypes.sublist(1)], newRows);
  }

  /// `S(literal, P)` — especialização por átomo escalar (aridade 0). Só na
  /// recursão de redundância (query = braço com literal).
  _Matrix _specializeAtom(String key, _Matrix p) {
    final newRows = <List<ast.Pattern>>[];
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HWild) {
        newRows.add(row.sublist(1)); // ω casa o literal
      } else if (h is _HAtom && h.key == key) {
        newRows.add(row.sublist(1)); // mesmo literal
      } else if (h is _HStruct) {
        throw const _MatchUnsupported(); // ex.: `5` vs `0..=9` → intervalo (Fatia 2)
      } // _HAtom(other)/_HCtor(≠) → descarta
    }
    return _Matrix(p.colTypes.sublist(1), newRows);
  }

  /// `D(P)` — SEMPRE computável: só pergunta "é ω?". Nunca modela estrutura, e
  /// por isso o veredito sempre existe (I7 — a chave do §12-11).
  _Matrix _default(_Matrix p) {
    final newRows = [
      for (final row in p.rows)
        if (_classify(row[0]) is _HWild) row.sublist(1),
    ];
    return _Matrix(p.colTypes.sublist(1), newRows);
  }

  Set<String> _presentSealed(_Matrix p) => {
        for (final row in p.rows)
          if (_classify(row[0]) case _HCtor(:final name)) name,
      };

  bool _columnHasStruct(_Matrix p) =>
      p.rows.any((row) => _classify(row[0]) is _HStruct);

  /// `U(P, q)` — utilidade. `null` = inútil (exaustivo/sem testemunha); não-null
  /// = vetor-testemunha (largura = `p.width`). Pode lançar `_MatchUnsupported`.
  List<_Wit>? _useful(_Matrix p, List<ast.Pattern> q) {
    // Caso base (0 colunas): útil ⟺ nenhuma linha (Maranget §3.1).
    if (p.width == 0) return p.rows.isEmpty ? <_Wit>[] : null;

    final sig = _sigOf(p.colTypes[0]);
    final qh = _classify(q[0]);

    // q₀ concreto: só na REDUNDÂNCIA (query = braço).
    if (qh is _HCtor) {
      final c = sig.ctors.firstWhere((x) => x.name == qh.name);
      final w = _useful(
        _specialize(c, p),
        [..._subPatterns(q[0]), ...q.sublist(1)],
      );
      return w == null ? null : _rebuild(c, w);
    }
    if (qh is _HAtom) {
      final w = _useful(_specializeAtom(qh.key, p), q.sublist(1));
      return w == null ? null : [_WWild(p.colTypes[0]), ...w];
    }
    if (qh is _HStruct) {
      throw const _MatchUnsupported(); // query estrutural → redundância indecidível
    }

    // q₀ = ω (sempre o caso da EXAUSTIVIDADE; e braço-ω na redundância).
    if (sig is _SealedSig || sig is _EmptySig) {
      final present = _presentSealed(p);
      if (sig.isComplete(present)) {
        // Σ completa. Testemunha CONCRETA vence um ramo unsupported (não-
        // exaustividade definitiva > "não sei" — §12-11).
        var anyUnsupported = false;
        for (final c in sig.ctors) {
          try {
            final w = _useful(
              _specialize(c, p),
              [...List.filled(c.arity, q[0]), ...q.sublist(1)],
            );
            if (w != null) return _rebuild(c, w);
          } on _MatchUnsupported {
            anyUnsupported = true; // guarda; segue buscando testemunha concreta
          }
        }
        if (anyUnsupported) throw const _MatchUnsupported();
        return null; // todos os ramos exaustos → EXAUSTIVO
      } else {
        final w = _useful(_default(p), q.sublist(1));
        if (w == null) return null;
        return [_missing(sig, present), ...w]; // variante FORA de Σ
      }
    } else {
      // Coluna OPAQUE contra ω. O ramo `D` SEMPRE decide o veredito.
      final w = _useful(_default(p), q.sublist(1));
      if (w == null) return null; // gap fechado (um `_` sobreviveu) → EXAUSTIVO
      // Há gap NESTA coluna opaca:
      if (_columnHasStruct(p)) {
        throw const _MatchUnsupported(); // §12-11: estrutura fecharia? não sei
      }
      // Só ω + átomos escalares ⟹ Σ infinita, testemunha `_` honesta:
      return [_WWild(p.colTypes[0]), ...w];
    }
  }

  /// Empacota os `c.arity` primeiros wits em `c(...)`; o resto são as caudas.
  List<_Wit> _rebuild(_Ctor c, List<_Wit> w) =>
      [_WCtor(c, w.sublist(0, c.arity)), ...w.sublist(c.arity)];

  /// Um construtor FORA de `present`, com args ω (SealedSig incompleta ⟹ existe).
  _Wit _missing(_Sig sig, Set<String> present) {
    final c = sig.ctors.firstWhere((x) => !present.contains(x.name));
    return _WCtor(c, [for (final at in c.argTypes) _WWild(at)]);
  }

  /// Testemunha → sintaxe de pattern do Itá (digitável em superfície — W0).
  String _print(_Wit w) => switch (w) {
        _WWild _ => '_',
        _WCtor c => c.ctor.arity == 0
            ? _ctorSurface(c.ctor.name)
            : '${_ctorSurface(c.ctor.name)}(${c.args.map(_print).join(', ')})',
      };

  String _ctorSurface(String name) => switch (name) {
        'true' => 'true',
        'false' => 'false',
        _ => '.$name', // enum/some/none/ok/err → prefixo `.`
      };
}
