// ===========================================================================
// match_analysis.dart — Fase 6 (Flow-check), LT-F6b: exaustividade + redundância
// de `match` pelo algoritmo de Maranget 2007 (§3.1 U/S/D + testemunha).
//
// Blueprint: specs/014-flow-check/blueprint-match-analysis.md §F1/§F2/§3.3.
// Corte de fatiamento (ruling do dono, spec 014 §12-11): tipo não-modelado que
// um `_` NÃO fecha → `match-exhaustiveness-unsupported` (ERRO honesto), NUNCA
// silêncio (mentiria) nem `non-exhaustive` chutado (falsa-acusaria). A linguagem
// é PEDRA: ou DECIDE, ou diz "não sei" — jamais afirma o que não verificou.
//
// COBERTURA (Fatias 1-2-3, CONCLUÍDAS): tipos FECHADOS (enum/Option/Result/Bool)
// · `Int`/range por interval-splitting (`_RangeSig`, §F2) · produto struct/record
// (`_HProd`, §3.3) · `List` por split de comprimento (`_ListSig`, §3.3) · `String`
// (redundância exata). Testemunhas CONCRETAS e digitáveis. Só resta `unsupported`
// para `class` sem um `_` (ruling e) — a última lacuna honesta. (2-rest de List
// não chega aqui: a F5 o rejeita como `duplicate-rest-pattern`, ruling (a).)
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
      // Fatia 3 modelou produto/List; 2-rest agora morre na F5
      // (`duplicate-rest-pattern`, ruling (a) do dono). Resta só `class`
      // (ruling e) sem um `_` que feche.
      detail: 'cobertura de class chega depois — '
          'adicione um braço `_` para exaurir por ora',
    ));
    return MatchReport(diags, dead);
  }

  // 2. Redundância: braço `i` morto sse `¬U(P_{<i} unguarded, pᵢ)`.
  final prior = <List<ast.Pattern>>[];
  for (final arm in node.arms) {
    if (arm.guard != null) continue; // I6: guarded nunca acusado de morto
    try {
      // `prior` passa por referência — `_useful` só LÊ a matriz (constrói novas
      // via `_specialize`/`_default`, nunca muta `p.rows`), e o `prior.add` abaixo
      // só ocorre após o retorno. Copiar a cada braço seria O(n²) à toa.
      final useful =
          a._useful(_Matrix([scrutineeType], prior), [arm.pattern]);
      if (useful == null) {
        diags.add(FlowError(
          'unreachable-match-arm',
          arm.pattern.offset,
          arm.pattern.length,
          // Se morreu por VACUIDADE (range vazio), o detail ENSINA o porquê —
          // "unreachable de onde?" viraria pergunta sem o hint (P4). Morto por
          // dominância não precisa: o span já aponta o braço.
          detail: a._vacuityDetail(arm.pattern),
        ));
        dead.add(arm); // morto NÃO entra no P_{<j} dos seguintes
      } else {
        prior.add([arm.pattern]);
      }
    } on _MatchUnsupported {
      // Redundância deste braço indecidível (ex.: cauda List/produto não-modelada,
      // Fatia 3). ABSTÉM — não acusa nem inocenta; o braço segue vivo em P_{<j} e
      // roda correto. NÃO é mentira de exaustividade (a #1 já deu veredito): é
      // incompletude conhecida do LINT de redundância (spec 014 §12-11, nota).
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
/// `fieldNames` não-nulo ⟹ é um PRODUTO (struct/record, Fatia 3a): os nomes dos
/// campos na ordem declarada, usados só pelo printer (`Point{x: _, y: _}`).
class _Ctor {
  final String name;
  final List<Type> argTypes;
  final List<String>? fieldNames;
  const _Ctor(this.name, this.argTypes, {this.fieldNames});
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

/// Float/String/List/produto: NÃO selado. Nunca completa por enumeração; o
/// veredito sai do ramo `D` (a estrutura só é tocada se o `D` deixa gap E há
/// pattern estrutural — §F1.4).
class _OpaqueSig extends _Sig {
  const _OpaqueSig();
  @override
  List<_Ctor> get ctors => const [];
  @override
  bool isComplete(Set<String> _) => false;
}

/// `Int` — Σ = ℤ ilimitada (FATIA 2, blueprint §F2). Sem range aberto no parser,
/// nenhum conjunto de intervalos exaure `Int` (só ω/`_` fecha) ⟹ nunca completa.
/// O veredito de exaustividade reusa o ramo `D`; a testemunha do gap é CONCRETA
/// (`_WInt`), e a redundância parte a reta em intervalos (interval-splitting).
class _RangeSig extends _Sig {
  const _RangeSig();
  @override
  List<_Ctor> get ctors => const [];
  @override
  bool isComplete(Set<String> _) => false;
}

/// `List<E>` — FATIA 3b. SEALED-like (finito após o split por comprimento), NÃO
/// Range-like: um `..resto` cobre `[k,∞)` ⟹ o rabo é ALCANÇÁVEL, então `[] +
/// [_, ..]` é EXAUSTIVO de fato (verde real). Split à rustc `Slice::split`; a
/// família `{Len_0..Len_L} ∪ {Tail}` tem ramo próprio no `_useful`.
class _ListSig extends _Sig {
  final Type elem;
  const _ListSig(this.elem);
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

/// Testemunha CONCRETA de gap escalar-Int (Maranget §3.2 / rustc `Missing`
/// materializado). Sobe da recursão como valor real fora da união dos intervalos
/// — `10` para `0..=9`, `1` para `0`. Fatia 2, §F2.
class _WInt extends _Wit {
  final BigInt value;
  _WInt(this.value);
}

/// Testemunha de gap de `List` (FATIA 3b) — SEMPRE um comprimento CONCRETO
/// `[e0, e1]` (nunca `[.., ..]`): o rabo é representado por um comprimento fixo
/// `> L` (a coluna descoberta), honesto e digitável. Um `..` prometeria cobrir
/// extensões que um pattern de sufixo poderia casar (W3 🟡) — evitado.
class _WList extends _Wit {
  final List<_Wit> elems;
  _WList(this.elems);
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

/// Cabeça de coluna `Int` (FATIA 2): o intervalo do pattern. `IntLit n`→`[n,n]`;
/// `a..=b`→`[a,b]`; `a..b`→`[a,b-1]`; `lo>hi`→vazio. Decidível por interval-
/// splitting (§F2) — nem `_HAtom` (não tem ordem) nem `_HStruct` (é decidível).
class _HInt extends _Head {
  final _Iv iv;
  _HInt(this.iv);
}

class _HStruct extends _Head {}

/// Cabeça de coluna PRODUTO (struct/record — FATIA 3a): 1 construtor, aridade =
/// nº campos. Não carrega nome (o produto é único por tipo; o `_Ctor` vem do
/// `_sigOf`). Contra coluna `struct_` é decidível; contra `class_` (não modelado)
/// vira `_MatchUnsupported` no `_useful` — ruling (e) pendente.
class _HProd extends _Head {}

/// Cabeça de coluna `List` (FATIA 3b): os elementos antes/depois do `..resto`.
/// Sem rest ⟹ comprimento FIXO `prefix.length` (suffix vazio); com rest ⟹
/// comprimento VARIÁVEL `≥ prefix.length + suffix.length` (rustc `SliceKind`).
/// 2-rest já morreu na F5 (`duplicate-rest-pattern`); se escapar, `_HStruct` (backstop).
class _HList extends _Head {
  final List<ast.Pattern> prefix;
  final List<ast.Pattern> suffix;
  final bool hasRest;
  _HList(this.prefix, this.suffix, this.hasRest);
  int get minLen => prefix.length + suffix.length;
}

/// Intervalo inteiro fechado `[lo,hi]`; `lo>hi` ≡ VAZIO. Fronteiras em `BigInt`:
/// as bordas de i64 (`b-1`, `maxHi+1`) wrappam no `int` do Dart (§F1.4 nota Range).
class _Iv {
  final BigInt lo, hi;
  const _Iv(this.lo, this.hi);
  bool get isEmpty => lo > hi;
  /// `this ⊇ o` (contém o intervalo `o`, que não pode ser vazio).
  bool contains(_Iv o) => !o.isEmpty && lo <= o.lo && o.hi <= hi;
}

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
    if (t is IntType) return const _RangeSig(); // Fatia 2 — interval-splitting
    if (t is BuiltinType && t.kind == BuiltinKind.list) {
      return _ListSig(t.args[0]); // Fatia 3b — split por comprimento
    }
    if (t is NamedType) {
      final info = types.of(t.decl);
      if (info != null && info.kind == TypeKind.enum_ && info.variants != null) {
        final subst = info.substFor(t.args); // idem _bindEnumPattern (check.dart)
        return _SealedSig([
          for (final v in info.variants!)
            _Ctor(v.name, [for (final p in v.payload) substitute(p, subst)]),
        ]);
      }
      // FATIA 3a — PRODUTO: `struct` é Σ de UM construtor (Maranget §3.1),
      // aridade = nº campos na ordem declarada. `class_` fica de fora (ruling
      // (e) pendente): cai no `_OpaqueSig` → `_HProd` vira `unsupported` honesto.
      if (info != null && info.kind == TypeKind.struct_ && info.fields != null) {
        final subst = info.substFor(t.args);
        return _SealedSig([
          _Ctor(
            info.name,
            [for (final f in info.fields!) substitute(f.type, subst)],
            fieldNames: [for (final f in info.fields!) f.name],
          ),
        ]);
      }
    }
    return const _OpaqueSig(); // Str/Float (átomo Σ∞) · List/class → Fatia 3+
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
      case ast.LiteralPattern n when n.literal is ast.IntLit:
        return _HInt(_toIv(p)); // Fatia 2 — intervalo [n,n] (era _HAtom)
      case ast.RangePattern _:
        return _HInt(_toIv(p)); // Fatia 2 — intervalo (era _HStruct)
      case ast.LiteralPattern n:
        return _HAtom(_atomKey(n.literal)); // Str/Float — átomo escalar (Σ∞)
      // FATIA 3a — produto (struct/record): 1 construtor, aridade = nº campos.
      case ast.StructPattern _:
      case ast.RecordPattern _:
        return _HProd();
      // FATIA 3b — List: prefixo/sufixo em torno do `..resto`. 2-rest já foi
      // rejeitado na F5 (`duplicate-rest-pattern`); o `_HStruct` é backstop I2.
      case ast.ListPattern n:
        return n.elements.whereType<ast.RestPattern>().length >= 2
            ? _HStruct()
            : _toList(n);
      case ast.RestPattern _:
        return _HStruct(); // top-level é inalcançável (só inline em ListPattern)
      case ast.ErrorPattern _:
        return _HStruct(); // parser já reportou; defensivo
    }
  }

  /// Chave de igualdade do átomo escalar SEM ordem (Float, String) — só p/
  /// `_specializeAtom` (redundância). Int saiu daqui na Fatia 2 (tem ordem ⟹
  /// `_HInt`). Float exato; `String` CONSTANTE ganha valor real (Fatia 3c —
  /// a F5 bane a interpolada, então toda Str-pattern aqui é constante ⟹ sound).
  /// Qualquer outra forma fica ÚNICA por span (incompletude honesta, nunca
  /// falsa-acusação — a exaustividade não depende da chave).
  String _atomKey(ast.Expr lit) => switch (lit) {
        ast.FloatLit n => 'f:${n.value}',
        ast.Str s when s.parts.every((p) => p is ast.StrLit) =>
          's:${s.parts.map((p) => (p as ast.StrLit).value).join()}',
        _ => 'u:${lit.offset}:${lit.length}',
      };

  /// O intervalo `[lo,hi]` (BigInt) de um pattern-Int. A F5 garante `Int` por
  /// construção (`_checkRangePattern`, check.dart:624-632) ⟹ `start`/`end` são
  /// `IntLit` — I5 (não re-tipa). `BigInt` porque `b-1`/`maxHi+1` wrappam no i64.
  _Iv _toIv(ast.Pattern p) {
    if (p is ast.LiteralPattern && p.literal is ast.IntLit) {
      final v = BigInt.from((p.literal as ast.IntLit).value);
      return _Iv(v, v);
    }
    if (p is ast.RangePattern) {
      final lo = BigInt.from((p.start as ast.IntLit).value);
      var hi = BigInt.from((p.end as ast.IntLit).value);
      if (!p.inclusive) hi -= BigInt.one; // a..b → [a, b-1]
      return _Iv(lo, hi);
    }
    throw StateError('_toIv em não-Int'); // backstop I2 (o gate F5 garante Int)
  }

  /// O `detail` de um braço morto: se por VACUIDADE (range `lo > hi`), ensina o
  /// porquê; senão `null` (morto por dominância — o span já basta). Fatia 2.
  String? _vacuityDetail(ast.Pattern p) {
    if (p is ast.RangePattern && _toIv(p).isEmpty) {
      return 'range vazio (início > fim)';
    }
    return null;
  }

  /// Os argumentos do construtor casado (para o `S`). Aridade garantida pela F5
  /// (`pattern-arity-mismatch`); BoolLit/NilLit têm aridade 0.
  List<ast.Pattern> _subPatterns(ast.Pattern p) {
    if (p is ast.EnumPattern) return p.subpatterns;
    return const [];
  }

  /// Os campos de um pattern-PRODUTO na ORDEM DECLARADA (`c.fieldNames`, de
  /// `TypeInfo.fields`), reordenando os campos escritos e preenchendo **campo
  /// omitido → ω** (DESIGN de spec — spec 014 §4, `spec.md`: "omitidos/`hasRest`
  /// → ω"; blueprint §3.3). A F5 garante: forma explícita (`x: a`) tipada,
  /// duplicata barrada (`duplicate-field-pattern`), shorthand (`x`) recusado.
  List<ast.Pattern> _subPatternsProd(ast.Pattern p, _Ctor c) {
    final fields = switch (p) {
      ast.StructPattern s => s.fields,
      ast.RecordPattern r => r.fields,
      _ => const <ast.FieldPattern>[],
    };
    return [
      for (final name in c.fieldNames!)
        fields.where((f) => f.name == name).firstOrNull?.pattern ?? _wild(p),
    ];
  }

  /// Fatoração de um `ListPattern` em (prefixo, sufixo, temRest) — os elementos
  /// antes e depois do `..resto`. Sem rest ⟹ tudo é prefixo (comprimento fixo).
  /// Chamado só com ≤1 rest (o `_classify` roteia 2-rests a `_HStruct`).
  _HList _toList(ast.ListPattern n) {
    final restIdx = n.elements.indexWhere((e) => e is ast.RestPattern);
    if (restIdx < 0) return _HList(n.elements, const [], false);
    return _HList(
      n.elements.sublist(0, restIdx),
      n.elements.sublist(restIdx + 1),
      true,
    );
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
      } else if (h is _HProd) {
        // Produto tem 1 ctor (Fatia 3a): toda linha de produto casa `c`.
        newRows.add([..._subPatternsProd(row[0], c), ...row.sublist(1)]);
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
        // Backstop I2: coluna Float/Str não tem cabeça estrutural em programa
        // verde (a F5 barra o mistyped). Int saiu para `_HInt`/`_RangeSig` e
        // nunca chega aqui. Defensivo — não removido (§F2.4).
        throw const _MatchUnsupported();
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

  Set<String> _presentSealed(_Matrix p) {
    final sig = _sigOf(p.colTypes[0]);
    // Produto = `_SealedSig` de 1 ctor; qualquer linha `_HProd` presenta-o.
    final prodName = (sig is _SealedSig && sig.ctors.length == 1)
        ? sig.ctors.first.name
        : null;
    final present = <String>{};
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HCtor) {
        present.add(h.name);
      } else if (h is _HProd && prodName != null) {
        present.add(prodName);
      }
    }
    return present;
  }

  /// Cabeça estrutural que o veredito não modela nesta coluna: `_HStruct` (List)
  /// SEMPRE; `_HProd` só quando a coluna é opaca (`class_` — a struct é
  /// `_SealedSig`, tratada no ramo selado, e nunca chega ao teste opaco).
  bool _columnHasStruct(_Matrix p) => p.rows.any((row) {
        final h = _classify(row[0]);
        return h is _HStruct || h is _HProd;
      });

  // -------------------------------------------------------------------------
  // Interval-splitting (FATIA 2, §F2) — coluna `Int`/`_RangeSig`.
  // -------------------------------------------------------------------------

  /// Os intervalos NÃO-vazios da coluna 0 (linhas-ω não têm intervalo).
  List<_Iv> _columnIvs(_Matrix p) => [
        for (final row in p.rows)
          if (_classify(row[0]) case _HInt(:final iv) when !iv.isEmpty) iv,
      ];

  /// Sub-intervalos elementares de `q`, cada um ⊆-ou-disjoint de todo intervalo
  /// de linha (nenhuma fronteira de linha cai no aberto interior) — rustc
  /// `IntRange::split`. Trabalha no meio-aberto `[lo, hi+1)`.
  List<_Iv> _splitInterval(_Iv q, List<_Iv> rows) {
    if (q.isEmpty) return const [];
    final cuts = <BigInt>{q.lo, q.hi + BigInt.one};
    for (final r in rows) {
      if (r.isEmpty) continue;
      for (final b in [r.lo, r.hi + BigInt.one]) {
        if (b > q.lo && b <= q.hi + BigInt.one) cuts.add(b);
      }
    }
    final pts = cuts.toList()..sort();
    return [
      for (var i = 0; i + 1 < pts.length; i++) _Iv(pts[i], pts[i + 1] - BigInt.one),
    ];
  }

  /// `S(E, P)` — E é um intervalo elementar NULLÁRIO ⟹ preserva a cauda
  /// (`colTypes.sublist(1)`), sem produto cartesiano coluna×intervalo.
  _Matrix _specializeIv(_Iv e, _Matrix p) {
    final newRows = <List<ast.Pattern>>[];
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HWild) {
        newRows.add(row.sublist(1)); // ω casa E
      } else if (h is _HInt && h.iv.contains(e)) {
        newRows.add(row.sublist(1)); // intervalo da linha ⊇ E
      } // disjoint/vazio → descarta
    }
    return _Matrix(p.colTypes.sublist(1), newRows);
  }

  /// Primeiro inteiro descoberto pela união dos intervalos (furo interior;
  /// senão `maxHi+1`; senão `0`). Sempre FORA da união ⟹ testemunha concreta
  /// produzível (prova §F2.4). Maranget §3.2 / rustc `Missing`.
  BigInt _gapValue(List<_Iv> ivs) {
    final s = [for (final i in ivs) if (!i.isEmpty) i]
      ..sort((a, b) => a.lo.compareTo(b.lo));
    if (s.isEmpty) return BigInt.zero;
    var cursor = s.first.lo;
    for (final iv in s) {
      if (iv.lo > cursor) return cursor; // furo interior
      if (iv.hi + BigInt.one > cursor) cursor = iv.hi + BigInt.one;
    }
    return cursor; // = maxHi+1
  }

  // -------------------------------------------------------------------------
  // Split por comprimento (FATIA 3b, §F3) — coluna `List`/`_ListSig`.
  // -------------------------------------------------------------------------

  /// `S(Len_n, P)` — especialização por comprimento EXATO `n`. ω → `n` ω's;
  /// `[p…]` fixo casa sse `len == n`; `[pre.., ..r, ..suf]` var casa sse
  /// `n ≥ minLen`, com o meio (`n - minLen`) preenchido por ω (o rest). A coluna
  /// vira `E×n` seguida da cauda.
  _Matrix _specializeLen(int n, _Matrix p, Type elem) {
    final newRows = <List<ast.Pattern>>[];
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HWild) {
        newRows.add([...List.filled(n, _wild(row[0])), ...row.sublist(1)]);
      } else if (h is _HList) {
        if (!h.hasRest && h.prefix.length == n) {
          newRows.add([...h.prefix, ...row.sublist(1)]);
        } else if (h.hasRest && n >= h.minLen) {
          newRows.add([
            ...h.prefix,
            ...List.filled(n - h.minLen, _wild(row[0])),
            ...h.suffix,
            ...row.sublist(1),
          ]);
        } // comprimento incompatível → descarta
      }
    }
    return _Matrix([...List.filled(n, elem), ...p.colTypes.sublist(1)], newRows);
  }

  /// `S(Tail, P)` — o representante do RABO em `tailArity` colunas (comprimento
  /// `> L`, com `tailArity ≥ maxPre+maxSuf`). Só VarLen casa (FixedLen ≤ L);
  /// prefixo-esq + `ω × (tailArity - minLen)` no meio + sufixo-dir (o rest cobre
  /// o meio). Por uniformidade (todo pattern trata comprimento `> L` igual), UM
  /// representante decide a cobertura de TODO o rabo. rustc `SliceKind::VarLen`.
  _Matrix _specializeTail(_Matrix p, Type elem, int tailArity) {
    final newRows = <List<ast.Pattern>>[];
    for (final row in p.rows) {
      final h = _classify(row[0]);
      if (h is _HWild) {
        newRows.add([
          ...List.filled(tailArity, _wild(row[0])),
          ...row.sublist(1),
        ]);
      } else if (h is _HList && h.hasRest) {
        // Invariante: `tailArity ≥ maxPre+maxSuf ≥ h.minLen` ⟹ o meio-ω nunca é
        // negativo. Explícito para blindar se a fórmula de `tailArity` mudar.
        assert(tailArity >= h.minLen);
        newRows.add([
          ...h.prefix,
          ...List.filled(tailArity - h.minLen, _wild(row[0])),
          ...h.suffix,
          ...row.sublist(1),
        ]);
      } // FixedLen não alcança o rabo → descarta
    }
    return _Matrix(
      [...List.filled(tailArity, elem), ...p.colTypes.sublist(1)],
      newRows,
    );
  }

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
    if (qh is _HInt) {
      // Redundância de intervalo (Fatia 2): parte a query nos boundaries das
      // linhas e vê se ALGUM elementar escapa da união. Range vazio → nunca
      // útil (morto por vacuidade, mesmo como 1º braço).
      if (qh.iv.isEmpty) return null;
      final rows = _columnIvs(p);
      for (final e in _splitInterval(qh.iv, rows)) {
        final w = _useful(_specializeIv(e, p), q.sublist(1));
        if (w != null) return [_WInt(e.lo), ...w]; // sub-intervalo NÃO coberto
      }
      return null; // todo elementar coberto → braço redundante
    }
    if (qh is _HProd) {
      // Query de produto (Fatia 3a): 1 ctor; especializa nos campos. Contra
      // coluna `struct_` (`_SealedSig` de 1 ctor) é decidível; contra `class_`
      // (`_OpaqueSig`) ou qualquer sig ≠ 1-ctor vira `unsupported` honesto
      // (ruling (e) pendente; o `!= 1` blinda o `.single` se o gate F5 falhar).
      if (sig is! _SealedSig || sig.ctors.length != 1) {
        throw const _MatchUnsupported();
      }
      final c = sig.ctors.single;
      final w = _useful(
        _specialize(c, p),
        [..._subPatternsProd(q[0], c), ...q.sublist(1)],
      );
      return w == null ? null : _rebuild(c, w);
    }
    if (qh is _HList) {
      // Redundância de List (3b-ii) defere: ABSTÉM (o driver mantém o braço
      // vivo). A EXAUSTIVIDADE (3b-i) usa ω-query e cai no ramo `_ListSig` abaixo,
      // então a segurança do gate F7 não depende deste lint.
      throw const _MatchUnsupported();
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
    } else if (sig is _RangeSig) {
      // Coluna `Int` (Fatia 2). `Int` é ℤ ilimitado ⟹ o split do DOMÍNIO é
      // desnecessário: o ramo `D` decide o veredito (cobertura monótona, §F2.4),
      // e o gap ganha valor CONCRETO. Não splita — só troca `_WWild`→`_WInt`.
      final w = _useful(_default(p), q.sublist(1));
      if (w == null) return null; // ω-rows fecham ℤ → EXAUSTIVO (Regime 1)
      return [_WInt(_gapValue(_columnIvs(p))), ...w]; // gap concreto (§3.2)
    } else if (sig is _ListSig) {
      return _usefulList(sig.elem, p, q); // Fatia 3b — split por comprimento
    } else {
      // Coluna OPAQUE contra ω (Float/String/List/produto). O `D` decide.
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

  /// Exaustividade de coluna `List` (Fatia 3b) — split por comprimento à rustc
  /// `Slice::split`. Testa cada comprimento exato `0..L` e o RABO (`> L`); a 1ª
  /// coluna descoberta vira testemunha. Família finita ⟹ SEALED-like (o `..resto`
  /// torna o rabo alcançável, ao contrário de `Int`). Só ω-query cai aqui.
  ///
  /// **`ErrorPattern` (e um 2-rest que escape a F5)** é `_HStruct`: o split o
  /// ignora (não entra em `lists` nem casa na especialização). Se o RESTO cobre
  /// tudo, o veredito é verde — um `_`/ω sempre fecha (I7). Só quando SOBRA gap E
  /// há `_HStruct` a decisão vira `unsupported` (§12-11: não chute). BACKSTOP —
  /// em programa verde a F5 já barrou o 2-rest (`duplicate-rest-pattern`).
  List<_Wit>? _usefulList(Type elem, _Matrix p, List<ast.Pattern> q) {
    final hasStruct = p.rows.any((r) => _classify(r[0]) is _HStruct);
    final wit = _listWitness(elem, p, q);
    if (wit != null && hasStruct) throw const _MatchUnsupported();
    return wit;
  }

  List<_Wit>? _listWitness(Type elem, _Matrix p, List<ast.Pattern> q) {
    final lists = [
      for (final r in p.rows)
        if (_classify(r[0]) case _HList h) h,
    ];
    var L = 0, maxPre = 0, maxSuf = 0;
    var hasRest = false;
    for (final h in lists) {
      // `minLen = prefix + suffix`; sem rest o suffix é vazio ⟹ `minLen ==
      // prefix.length`, então este único max cobre fixo E variável.
      if (h.minLen > L) L = h.minLen;
      if (h.hasRest) {
        hasRest = true;
        if (h.prefix.length > maxPre) maxPre = h.prefix.length;
        if (h.suffix.length > maxSuf) maxSuf = h.suffix.length;
      }
    }
    // Comprimentos exatos 0..L: a 1ª coluna descoberta é a testemunha.
    for (var n = 0; n <= L; n++) {
      final w = _useful(
        _specializeLen(n, p, elem),
        [...List.filled(n, q[0]), ...q.sublist(1)],
      );
      if (w != null) return [_WList(w.sublist(0, n)), ...w.sublist(n)];
    }
    // O RABO (comprimento > L). O representante tem `tailArity` colunas — sempre
    // `> L` (senão colidiria com um comprimento fixo) E `≥ maxPre+maxSuf` (para o
    // VarLen caber sem sobrepor prefixo/sufixo). Sem rest, o rabo NUNCA é coberto.
    final tailArity = hasRest
        ? ((maxPre + maxSuf) > L ? maxPre + maxSuf : L + 1)
        : L + 1;
    final w = hasRest
        ? _useful(
            _specializeTail(p, elem, tailArity),
            [...List.filled(tailArity, q[0]), ...q.sublist(1)],
          )
        : _useful(
            _specializeLen(tailArity, p, elem),
            [...List.filled(tailArity, q[0]), ...q.sublist(1)],
          );
    if (w != null) return [_WList(w.sublist(0, tailArity)), ...w.sublist(tailArity)];
    return null; // todos os comprimentos + rabo cobertos → EXAUSTIVO (verde real)
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
        _WInt i => i.value.toString(), // testemunha concreta Int (Fatia 2)
        // List (Fatia 3b) — comprimento concreto `[0, _]` (o rabo é um
        // comprimento fixo `> L`, não um `..` que sobre-generalizaria).
        _WList l => '[${l.elems.map(_print).join(', ')}]',
        // Produto (Fatia 3a) — `Point{x: 1, y: _}`, superfície digitável (P4).
        _WCtor c when c.ctor.fieldNames != null => '${c.ctor.name}{'
            '${[
            for (var i = 0; i < c.args.length; i++)
              '${c.ctor.fieldNames![i]}: ${_print(c.args[i])}'
          ].join(', ')}}',
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
