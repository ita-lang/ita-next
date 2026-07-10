// ===========================================================================
// ast_printer.dart — Dump S-expression determinístico da AST (`itac parse --dump`).
// ===========================================================================
//
// Modelo do `parenthesize()` do Crafting Interpreters (CI 5.4): nó = `(tag …)`.
// É o ÚNICO observável da Fase 2 (o MCP `ita` não dumpa AST) — logo, precisa ser
// 100% determinístico e conferível byte-a-byte contra os goldens `.ast`:
//   • ordem de filhos = ordem gramatical/fonte (M6);
//   • ZERO iteração de hash-map;
//   • floats normalizados com `.0`; strings com escaping canônico;
//   • UMA linha por item de topo do programa (layout congelado no GREEN);
//   • spans (`offset+length`) ELIDIDOS por padrão — `--spans` anexa `@off+len`
//     logo após a tag de cada nó de sum.
//
// Tags: binários/prefixos/pós-fixos usam o SÍMBOLO do operador; nós de erro
// dumpam SEM a mensagem (`(error-decl)`) — a mensagem/span é verificada pelo
// `// EXPECT:` do corpus, não pela forma da árvore.
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';

/// Serializa uma AST em S-expression determinística.
///
/// [spans] `true` (flag `--spans`) anexa `@offset+length` após a tag de cada
/// nó de sum. `false` (padrão) omite — é o formato dos goldens `.ast`.
class AstDumper {
  final bool spans;
  const AstDumper({this.spans = false});

  /// Dump do programa: uma linha por item de topo, na ordem-fonte.
  String dump(Program program) => program.body.map(_node).join('\n');

  // --- helpers de montagem --------------------------------------------------

  String _span(AstNode n) => spans ? '@${n.offset}+${n.length}' : '';

  /// `(tag[@span] parte1 parte2 …)` — partes já serializadas.
  String _sx(String tag, AstNode n, [List<String> parts = const []]) {
    final body = parts.isEmpty ? '' : ' ${parts.join(' ')}';
    return '($tag${_span(n)}$body)';
  }

  /// Átomo sem parênteses (`nil`, `self`) — com span opcional.
  String _atom(String s, AstNode n) => '$s${_span(n)}';

  /// Literal de string quotada com escaping canônico (nomes e conteúdo).
  String _q(String s) {
    final b = StringBuffer('"');
    for (final rune in s.runes) {
      switch (rune) {
        case 0x5C: // \
          b.write(r'\\');
        case 0x22: // "
          b.write(r'\"');
        case 0x0A: // \n
          b.write(r'\n');
        case 0x0D: // \r
          b.write(r'\r');
        case 0x09: // \t
          b.write(r'\t');
        default:
          b.writeCharCode(rune);
      }
    }
    b.write('"');
    return b.toString();
  }

  /// Float normalizado (sempre com `.` — `1` vira `1.0`).
  String _float(double v) {
    final s = v.toString();
    return s.contains('.') || s.contains('e') || s.contains('E') ? s : '$s.0';
  }

  // --- despacho por item de topo (Decl | Stmt) ------------------------------

  String _node(AstNode n) => switch (n) {
    Decl d => _decl(d),
    Stmt s => _stmt(s),
    _ => throw StateError('nó de topo inesperado: ${n.runtimeType}'),
  };

  // --- declarações ----------------------------------------------------------

  String _decl(Decl d) => switch (d) {
    FnDecl n => _fn(n),
    FieldDecl n => _sx('field', n, [
      if (n.isPublic) ':pub',
      if (n.isMutable) ':var',
      _q(n.name),
      _type(n.type),
      if (n.defaultValue != null) '(default ${_expr(n.defaultValue!)})',
    ]),
    StructDecl n => _sx('struct', n, [
      if (n.isPublic) ':pub',
      _q(n.name),
      if (n.generics.isNotEmpty) _generics(n.generics),
      ...n.members.map(_decl),
    ]),
    ClassDecl n => _sx('class', n, [
      if (n.isPublic) ':pub',
      _q(n.name),
      if (n.generics.isNotEmpty) _generics(n.generics),
      if (n.superclass != null) '(extends ${_type(n.superclass!)})',
      ...n.members.map(_decl),
    ]),
    EnumDecl n => _sx('enum', n, [
      if (n.isPublic) ':pub',
      _q(n.name),
      if (n.generics.isNotEmpty) _generics(n.generics),
      ...n.cases.map(_enumCase),
      ...n.members.map(_decl),
    ]),
    TraitDecl n => _sx('trait', n, [
      if (n.isPublic) ':pub',
      _q(n.name),
      if (n.generics.isNotEmpty) _generics(n.generics),
      ...n.members.map(_decl),
    ]),
    ImplDecl n => _sx('impl', n, [
      if (n.trait != null) '(trait ${_type(n.trait!)})',
      '(for ${_type(n.target)})',
      ...n.members.map(_decl),
    ]),
    ExtensionDecl n => _sx('extension', n, [
      _type(n.target),
      ...n.members.map(_decl),
    ]),
    ActorDecl n => _sx('actor', n, [
      if (n.isPublic) ':pub',
      _q(n.name),
      ...n.members.map(_decl),
    ]),
    OperatorDecl n => _sx('operator', n, [_q(n.symbol), _fn(n.fn)]),
    ImportDecl n => _sx('import', n, [
      _importClause(n.clause),
      '(from ${_q(n.module)})',
    ]),
    ErrorDecl n => _sx('error-decl', n),
  };

  String _fn(FnDecl n) => _sx('fn', n, [
    if (n.isPublic) ':pub',
    if (n.isStatic) ':static',
    if (n.isOverride) ':override',
    if (n.asyncMarker == AsyncMarker.async) ':async',
    if (n.asyncMarker == AsyncMarker.asyncStar) ':stream',
    _q(n.name),
    if (n.generics.isNotEmpty) _generics(n.generics),
    _params(n.params),
    if (n.returnType != null) '(ret ${_type(n.returnType!)})',
    if (n.body != null) '(=> ${_fnBody(n.body!)})',
  ]);

  String _enumCase(EnumCase c) {
    final parts = [
      _q(c.name),
      if (c.payload.isNotEmpty) '(payload ${c.payload.map(_param).join(' ')})',
    ];
    return '(case ${parts.join(' ')})';
  }

  String _importClause(ImportClause c) => switch (c) {
    ImportNamed n => '(named ${n.members.map(_importMember).join(' ')})',
    ImportStar n => '(star (as ${_q(n.alias)}))',
    ImportBare() => '(bare)',
  };

  String _importMember(ImportMember m) => m.alias == null
      ? '(item ${_q(m.name)})'
      : '(item ${_q(m.name)} (as ${_q(m.alias!)}))';

  // --- statements -----------------------------------------------------------

  String _stmt(Stmt s) => switch (s) {
    LetStmt n => _sx(n.isVar ? 'var' : 'let', n, [
      _pattern(n.target),
      if (n.type != null) _type(n.type!),
      _expr(n.value),
    ]),
    ReturnStmt n => _sx('return', n, [
      if (n.value != null) _expr(n.value!),
    ]),
    IfStmt n => _sx('if-stmt', n, [
      _expr(n.cond),
      _block(n.then),
      if (n.orElse != null) '(else ${_else(n.orElse!)})',
    ]),
    GuardStmt n => _sx('guard', n, [
      _expr(n.cond),
      '(else ${_block(n.orElse)})',
    ]),
    GuardLetStmt n => _sx('guard-let', n, [
      _pattern(n.target),
      _expr(n.value),
      '(else ${_block(n.orElse)})',
    ]),
    WhileStmt n => _sx('while', n, [_expr(n.cond), _block(n.body)]),
    ForStmt n => _sx(n.isAwait ? 'for-await' : 'for', n, [
      _pattern(n.target),
      _expr(n.iterable),
      _block(n.body),
    ]),
    BreakStmt n => _sx('break', n),
    ContinueStmt n => _sx('continue', n),
    EmitStmt n => _sx('emit', n, [_expr(n.value)]),
    ExprStmt n => _sx('expr-stmt', n, [_expr(n.expr)]),
    BlockStmt n => _block(n.block),
    ErrorStmt n => _sx('error-stmt', n),
  };

  String _block(Block b) => _sx('block', b, b.stmts.map(_stmt).toList());

  String _else(Else e) => switch (e) {
    ElseIf n => _stmt(n.ifStmt),
    ElseBlock n => _block(n.block),
  };

  // --- expressões -----------------------------------------------------------

  String _expr(Expr e) => switch (e) {
    IntLit n => _sx('int', n, ['${n.value}']),
    FloatLit n => _sx('float', n, [_float(n.value)]),
    Str n => _sx('str', n, n.parts.map(_strPart).toList()),
    BoolLit n => _sx('bool', n, [n.value ? 'true' : 'false']),
    NilLit n => _atom('nil', n),
    Ident n => _sx('id', n, [n.name]),
    SelfExpr n => _atom('self', n),
    Binary n => _sx(n.op, n, [_expr(n.left), _expr(n.right)]),
    Unary n => _sx(n.op, n, [_expr(n.operand)]),
    Await n => _sx('await', n, [_expr(n.operand)]),
    Spawn n => _sx('spawn', n, [_expr(n.operand)]),
    Panic n => _sx('panic', n, [_expr(n.operand)]),
    Assign n => _sx(n.op, n, [_expr(n.target), _expr(n.value)]),
    Call n => _sx('call', n, [_expr(n.callee), ...n.args.map(_arg)]),
    Member n => _sx('member', n, [_expr(n.receiver), _q(n.name)]),
    OptChain n => _sx('opt-chain', n, [_expr(n.receiver), _q(n.name)]),
    Index n => _sx('index', n, [_expr(n.receiver), _expr(n.index)]),
    TupleIndex n => _sx('tuple-index', n, [_expr(n.receiver), '${n.index}']),
    ForceUnwrap n => _sx('force-unwrap', n, [_expr(n.operand)]),
    Try n => _sx('try', n, [_expr(n.operand)]),
    CopyWith n => _sx('copy-with', n, [
      _expr(n.receiver),
      ...n.fields.map(_fieldInit),
    ]),
    Closure n => _sx('closure', n, [
      if (n.asyncMarker == AsyncMarker.async) ':async',
      if (n.asyncMarker == AsyncMarker.asyncStar) ':stream',
      if (n.hasExplicitParams) _params(n.params),
      if (n.returnType != null) '(ret ${_type(n.returnType!)})',
      _fnBody(n.body),
    ]),
    IfExpr n => _sx('if-expr', n, [
      _expr(n.cond),
      _block(n.then),
      _block(n.orElse),
    ]),
    MatchExpr n => _sx('match', n, [
      _expr(n.scrutinee),
      ...n.arms.map(_matchArm),
    ]),
    TupleExpr n => _sx('tuple', n, n.elements.map(_expr).toList()),
    ListExpr n => _sx('list', n, n.elements.map(_expr).toList()),
    MapExpr n => _sx('map', n, n.entries.map(_mapEntry).toList()),
    RangeExpr n => _sx(n.inclusive ? '..=' : '..', n, [
      _expr(n.start),
      _expr(n.end),
    ]),
    EnumShorthand n => _sx('enum-variant', n, [_q(n.variant)]),
    ErrorExpr n => _sx('error-expr', n),
  };

  String _strPart(StrPart p) => switch (p) {
    StrLit n => _q(n.value),
    StrInterp n => _expr(n.expr),
  };

  String _arg(Arg a) =>
      a.label == null ? _expr(a.value) : '(arg ${_q(a.label!)} ${_expr(a.value)})';

  String _fieldInit(FieldInit f) => '(field ${_q(f.name)} ${_expr(f.value)})';

  String _mapEntry(MapEntryNode e) => '(entry ${_expr(e.key)} ${_expr(e.value)})';

  String _matchArm(MatchArm a) {
    final parts = [
      _pattern(a.pattern),
      if (a.guard != null) '(if ${_expr(a.guard!)})',
      _expr(a.body),
    ];
    return '(arm ${parts.join(' ')})';
  }

  // --- tipos ----------------------------------------------------------------

  String _type(TypeNode t) => switch (t) {
    NamedType n => _sx('type', n, [n.name, ...n.args.map(_type)]),
    OptionalType n => _sx('type-optional', n, [_type(n.inner)]),
    MutType n => _sx('type-mut', n, [_type(n.inner)]),
    FunctionType n => _sx('type-fn', n, [
      if (n.isAsync) ':async',
      '(params ${n.params.map(_type).join(' ')})',
      '(ret ${_type(n.ret)})',
    ]),
    TupleType n => _sx('type-tuple', n, n.elements.map(_type).toList()),
    ErrorType n => _sx('error-type', n),
  };

  // --- patterns -------------------------------------------------------------

  String _pattern(Pattern p) => switch (p) {
    BindPattern n => _sx('bind', n, [_q(n.name)]),
    WildcardPattern n => _sx('pat-wildcard', n),
    LiteralPattern n => _sx('pat-lit', n, [_expr(n.literal)]),
    EnumPattern n => _sx('pat-enum', n, [
      _q(n.variant),
      ...n.subpatterns.map(_pattern),
    ]),
    ListPattern n => _sx('pat-list', n, n.elements.map(_pattern).toList()),
    RecordPattern n => _sx('pat-record', n, n.fields.map(_recordField).toList()),
    StructPattern n => _sx('pat-struct', n, [
      _q(n.typeName),
      ...n.fields.map(_structField),
      if (n.hasRest) '(rest)',
    ]),
    RangePattern n => _sx(n.inclusive ? 'pat-range-inc' : 'pat-range', n, [
      _expr(n.start),
      _expr(n.end),
    ]),
    RestPattern n => _sx('rest', n, [if (n.name != null) _q(n.name!)]),
    ErrorPattern n => _sx('error-pattern', n),
  };

  /// Campo de record-pattern (`{ x, y }`): homônimo dumpa como `(bind "x")`.
  String _recordField(FieldPattern f) => f.pattern == null
      ? '(bind ${_q(f.name)})'
      : '(field-pat ${_q(f.name)} ${_pattern(f.pattern!)})';

  /// Campo de struct-pattern (`P { x }`): sempre `(field-pat "x" [subpat])`.
  String _structField(FieldPattern f) => f.pattern == null
      ? '(field-pat ${_q(f.name)})'
      : '(field-pat ${_q(f.name)} ${_pattern(f.pattern!)})';

  // --- produtos compartilhados ----------------------------------------------

  String _generics(List<GenericParam> gs) =>
      '(generics ${gs.map(_generic).join(' ')})';

  String _generic(GenericParam g) => g.bounds.isEmpty
      ? '(generic ${_q(g.name)})'
      : '(generic ${_q(g.name)} (bound ${g.bounds.map(_type).join(' ')}))';

  String _params(List<Param> ps) =>
      ps.isEmpty ? '(params)' : '(params ${ps.map(_param).join(' ')})';

  String _param(Param p) {
    final parts = [
      _q(p.name),
      if (p.type != null) _type(p.type!),
      if (p.defaultValue != null) '(default ${_expr(p.defaultValue!)})',
    ];
    return '(param ${parts.join(' ')})';
  }

  String _fnBody(FnBody b) => switch (b) {
    ExprBody n => _expr(n.e),
    BlockBody n => _block(n.b),
  };
}
