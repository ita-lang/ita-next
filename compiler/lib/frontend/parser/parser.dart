// ===========================================================================
// parser.dart — Parser descendente-recursivo do Itá (Fase 2, spec 004).
// ===========================================================================
//
// Técnica: descendente recursivo à mão (decl/stmt) + cascata de precedência
// estilo jlox para expressões (CI cap 6.2 — uma função por nível; NÃO Pratt
// table-driven, D0). P11: zero codegen — parser escrito à mão.
//
// ESTADO (Fatia 0 — Fundação): implementa as FOLHAS do grafo de chamadas
// (`_type` e `_pattern`, completos) + a infra de recuperação N2 + um esqueleto
// mínimo (`fn`/`let`/`match`/`primary` stubs) que torna tipos e patterns
// OBSERVÁVEIS nos CA15–18. A cascata de 13 níveis (Fatia 1), os statements
// (Fatia 2) e as declarações completas (Fatia 3) crescem sobre esta base.
//
// Recuperação N2 (DB 4.1.4 / CI 6.3): ao falhar, reporta UM diagnóstico
// (kebab-case + span), sincroniza até um boundary de declaração e ENXERTA um
// nó `Error*` (nunca `null`) — a árvore permanece total e bem-tipada (M2).
// ===========================================================================

import 'package:ita_next_compiler/frontend/lexer/token.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';

// ---------------------------------------------------------------------------
// ParseError — erro sintático (EN kebab-case, span byte-preciso).
// ---------------------------------------------------------------------------

/// Um erro de parse. [code] é sempre um slug EN kebab-case (Const. Art. IV);
/// [detail] humano opcional. Formato canônico do dump:
/// `parse-error: <code>[ '<detail>'] @<offset>+<length>`.
class ParseError implements Exception {
  final String code;
  final int offset;
  final int length;
  final String? detail;

  const ParseError(this.code, this.offset, this.length, {this.detail});

  String format() => detail != null
      ? "parse-error: $code '$detail' @$offset+$length"
      : 'parse-error: $code @$offset+$length';

  @override
  String toString() => format();
}

/// Resultado de parsear um fonte: a AST (sempre total, com `Error*` enxertados)
/// + os erros coletados (vazio = parse limpo).
class ParseResult {
  final Program program;
  final List<ParseError> errors;
  const ParseResult(this.program, this.errors);
}

// ===========================================================================
// Parser.
// ===========================================================================

class Parser {
  final List<Token> tokens;
  final int sourceLength;
  final List<ParseError> errors = [];
  int _current = 0;

  Parser(this.tokens, {this.sourceLength = 0});

  /// Parseia o programa inteiro. Nunca lança: erros vão para [errors] e a
  /// árvore recebe nós `Error*` no lugar das produções falhas.
  Program parseProgram() {
    final body = <AstNode>[];
    while (!_isAtEnd) {
      final before = _current;
      try {
        body.add(_topLevelItem());
      } on ParseError catch (e) {
        errors.add(e);
        final startTok = tokens[before];
        _synchronizeDecl();
        final endOffset = _previous().offset + _previous().length;
        body.add(
          ErrorDecl(e.code, startTok.offset, endOffset - startTok.offset),
        );
      }
      // Garantia de progresso: nunca ficar preso no mesmo token.
      if (_current == before) _advance();
    }
    return Program(body, 0, sourceLength);
  }

  // =========================================================================
  // Nível de topo (declarações + bindings/expr-stmts de módulo).
  // =========================================================================

  AstNode _topLevelItem() {
    final t = _peek();
    if (_isDeclKeyword(t.tag)) return _declaration();
    if (t.tag == Tag.kwLet || t.tag == Tag.kwVar) return _letStmt();
    // Expr-statement (stub — a cascata completa entra na Fatia 1).
    final start = _peek();
    final e = _expression();
    return ExprStmt(e, start.offset, _lenFrom(start));
  }

  bool _isDeclKeyword(Tag tag) => switch (tag) {
    Tag.kwFn ||
    Tag.kwPub ||
    Tag.kwAsync ||
    Tag.kwStream ||
    Tag.kwStruct ||
    Tag.kwClass ||
    Tag.kwEnum ||
    Tag.kwTrait ||
    Tag.kwImpl ||
    Tag.kwExtension ||
    Tag.kwActor ||
    Tag.kwOperator ||
    Tag.kwImport ||
    Tag.kwStatic ||
    Tag.kwInit ||
    Tag.kwOverride => true,
    _ => false,
  };

  // =========================================================================
  // Declarações (Fatia 0: `fn` stub; demais entram na Fatia 3).
  // =========================================================================

  Decl _declaration() {
    final start = _peek();
    final isPublic = _match(Tag.kwPub);
    if (_check(Tag.kwFn) ||
        _check(Tag.kwStatic) ||
        _check(Tag.kwOverride) ||
        _check(Tag.kwAsync) ||
        _check(Tag.kwStream)) {
      return _fnDecl(isPublic, start);
    }
    throw ParseError('expected-declaration', _peek().offset, _peek().length);
  }

  FnDecl _fnDecl(bool isPublic, Token start) {
    var isStatic = false;
    var isOverride = false;
    // `static`/`override` em qualquer ordem antes de `fn` (estilo Swift).
    while (_check(Tag.kwStatic) || _check(Tag.kwOverride)) {
      if (_match(Tag.kwStatic)) {
        isStatic = true;
      } else {
        _advance();
        isOverride = true;
      }
    }
    var asyncMarker = AsyncMarker.sync;
    if (_match(Tag.kwAsync)) {
      asyncMarker = AsyncMarker.async;
    } else if (_match(Tag.kwStream)) {
      asyncMarker = AsyncMarker.asyncStar;
    }
    _consume(Tag.kwFn, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final generics = _check(Tag.lt) ? _genericParams() : <GenericParam>[];
    final params = _fnParams();
    final returnType = _match(Tag.arrow) ? _type() : null;
    final body = _fnBody();
    return FnDecl(
      isPublic,
      isStatic,
      isOverride,
      asyncMarker,
      name,
      generics,
      params,
      returnType,
      body,
      start.offset,
      _lenFrom(start),
    );
  }

  List<GenericParam> _genericParams() {
    _consume(Tag.lt, 'expected-token');
    final gs = <GenericParam>[];
    do {
      final name = _consume(Tag.identifier, 'expected-token').lexeme;
      final bounds = <TypeNode>[];
      if (_match(Tag.colon)) {
        do {
          bounds.add(_type());
        } while (_match(Tag.plus)); // `T: A + B`
      }
      gs.add(GenericParam(name, bounds));
    } while (_match(Tag.comma));
    _consumeTypeGt('expected-token');
    return gs;
  }

  List<Param> _fnParams() {
    _consume(Tag.lparen, 'expected-token');
    final params = <Param>[];
    if (!_check(Tag.rparen)) {
      do {
        if (_check(Tag.rparen)) break; // tolera vírgula final
        params.add(_param());
      } while (_match(Tag.comma));
    }
    _consume(Tag.rparen, 'expected-token');
    return params;
  }

  Param _param() {
    // Fatia 0: nome [: tipo] [= default]. Labels externos entram na Fatia 3.
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final type = _match(Tag.colon) ? _type() : null;
    final defaultValue = _match(Tag.eq) ? _expression() : null;
    return Param(null, name, type, defaultValue);
  }

  FnBody? _fnBody() {
    if (_match(Tag.fatArrow)) {
      if (_check(Tag.lbrace)) return BlockBody(_block());
      return ExprBody(_expression());
    }
    if (_check(Tag.lbrace)) return BlockBody(_block());
    return null; // assinatura sem corpo (trait)
  }

  // =========================================================================
  // Statements (Fatia 0: `let`/`var` + `block` mínimo).
  // =========================================================================

  LetStmt _letStmt() {
    final start = _peek();
    final isVar = _advance().tag == Tag.kwVar; // consome let|var
    final target = _pattern();
    final type = _match(Tag.colon) ? _type() : null;
    _consume(Tag.eq, 'expected-token');
    final value = _expression();
    return LetStmt(isVar, target, type, value, start.offset, _lenFrom(start));
  }

  Block _block() {
    final start = _peek();
    _consume(Tag.lbrace, 'expected-token');
    final stmts = <Stmt>[];
    while (!_check(Tag.rbrace) && !_isAtEnd) {
      stmts.add(_statement());
      _match(Tag.semicolon); // separadores opcionais
    }
    _consume(Tag.rbrace, 'expected-token');
    return Block(stmts, start.offset, _lenFrom(start));
  }

  /// Statement dentro de bloco (Fatia 0: `let`/`var`, `return` vazio, expr-stmt).
  Stmt _statement() {
    final t = _peek();
    if (t.tag == Tag.kwLet || t.tag == Tag.kwVar) return _letStmt();
    if (t.tag == Tag.kwReturn) {
      final start = _advance();
      final value = (_check(Tag.rbrace) || _isAtEnd || _check(Tag.semicolon))
          ? null
          : _expression();
      return ReturnStmt(value, start.offset, _lenFrom(start));
    }
    final start = _peek();
    final e = _expression();
    return ExprStmt(e, start.offset, _lenFrom(start));
  }

  // =========================================================================
  // Expressões (Fatia 0: STUB — só `primary` + `match`. Cascata → Fatia 1).
  // =========================================================================

  Expr _expression() => _primary();

  Expr _primary() {
    final start = _peek();
    if (_match(Tag.intLiteral)) {
      return IntLit(_previous().literal as int, start.offset, start.length);
    }
    if (_match(Tag.floatLiteral)) {
      return FloatLit(
        _previous().literal as double,
        start.offset,
        start.length,
      );
    }
    if (_check(Tag.stringLiteral) || _check(Tag.multilineString)) {
      return _stringLiteral(_advance());
    }
    if (_match(Tag.kwTrue)) return BoolLit(true, start.offset, start.length);
    if (_match(Tag.kwFalse)) return BoolLit(false, start.offset, start.length);
    if (_match(Tag.kwNil)) return NilLit(start.offset, start.length);
    if (_match(Tag.kwSelf)) return SelfExpr(start.offset, start.length);
    if (_check(Tag.kwMatch)) return _matchExpr();
    if (_match(Tag.identifier)) {
      return Ident(_previous().lexeme, start.offset, start.length);
    }
    if (_match(Tag.lparen)) {
      // Fatia 0: só agrupamento. Tupla/closure entram na Fatia 1.
      final e = _expression();
      _consume(Tag.rparen, 'expected-token');
      return e;
    }
    throw ParseError('expected-expression', start.offset, start.length);
  }

  MatchExpr _matchExpr() {
    final start = _peek();
    _consume(Tag.kwMatch, 'expected-token');
    final scrutinee = _expression();
    _consume(Tag.lbrace, 'expected-token');
    final arms = <MatchArm>[];
    if (!_check(Tag.rbrace)) {
      do {
        if (_check(Tag.rbrace)) break; // tolera vírgula final
        final pat = _pattern();
        final guard = _match(Tag.kwIf) ? _expression() : null;
        _consume(Tag.fatArrow, 'expected-token');
        final body = _expression();
        arms.add(MatchArm(pat, guard, body));
      } while (_match(Tag.comma));
    }
    _consume(Tag.rbrace, 'expected-token');
    return MatchExpr(scrutinee, arms, start.offset, _lenFrom(start));
  }

  /// Constrói o nó [Str] a partir do literal pré-computado do lexer (M3).
  Str _stringLiteral(Token t) {
    final parts = <StrPart>[];
    final lit = t.literal;
    if (lit is String) {
      // multilineString: conteúdo cru, sem interpolação (D6 do léxico).
      parts.add(StrLit(lit));
    } else if (lit is List) {
      for (final part in lit) {
        if (part is String) {
          parts.add(StrLit(part));
        } else if (part is List) {
          // ['expr', source] — interpolação. A sub-expressão é reparseada em
          // parse-time na Fatia 1 (CA20); na Fatia 0 nenhum CA usa strings.
          parts.add(StrInterp(Ident(part.last.toString(), t.offset, t.length)));
        }
      }
    }
    return Str(parts, t.offset, t.length);
  }

  // =========================================================================
  // Tipos (T031 — completo). §5 GRAMMAR.
  // =========================================================================

  TypeNode _type() {
    final start = _peek();

    if (_match(Tag.kwMut)) {
      final inner = _type();
      return MutType(inner, start.offset, _lenFrom(start));
    }

    // `async (A, B) -> T` — tipo-função assíncrono.
    if (_check(Tag.kwAsync)) {
      _advance();
      final inner = _type();
      if (inner is FunctionType) {
        return FunctionType(
          true,
          inner.params,
          inner.ret,
          start.offset,
          _lenFrom(start),
        );
      }
      throw ParseError('expected-function-type', start.offset, _lenFrom(start));
    }

    TypeNode type;
    if (_match(Tag.lparen)) {
      // Desambiguação de `(...)` em posição de tipo:
      //   (A, B) -> C  → função;  (A, B) → tupla (>=2);  (A) → agrupamento (= A).
      final elems = <TypeNode>[];
      if (!_check(Tag.rparen)) {
        do {
          if (_check(Tag.rparen)) break;
          elems.add(_type());
        } while (_match(Tag.comma));
      }
      _consume(Tag.rparen, 'expected-token');

      if (_match(Tag.arrow)) {
        final ret = _type();
        type = FunctionType(false, elems, ret, start.offset, _lenFrom(start));
      } else if (elems.length >= 2) {
        type = TupleType(elems, start.offset, _lenFrom(start));
      } else if (elems.length == 1) {
        type = elems[0]; // agrupamento (T) == T
      } else {
        // `()` só faz sentido como `() -> T`.
        _consume(Tag.arrow, 'expected-token');
        final ret = _type();
        type = FunctionType(false, elems, ret, start.offset, _lenFrom(start));
      }
    } else {
      final name = _consume(Tag.identifier, 'expected-type');
      final args = <TypeNode>[];
      if (_match(Tag.lt)) {
        do {
          args.add(_type());
        } while (_match(Tag.comma));
        _consumeTypeGt('expected-token');
      }
      type = NamedType(name.lexeme, args, start.offset, _lenFrom(start));
    }

    // Optional: `Type?`.
    if (_match(Tag.question)) {
      type = OptionalType(type, start.offset, _lenFrom(start));
    }
    return type;
  }

  /// Consome o `>` que fecha uma lista de type-args, aplicando token-splitting
  /// de `>>`→`>`+`>` e `>=`→`>`+`=` IN-PLACE (DB 4.4 — maximal-munch do lexer
  /// vs. fecha-template). Sem re-lex, sem backtrack.
  Token _consumeTypeGt(String code) {
    final t = _peek();
    switch (t.tag) {
      case Tag.gt:
        return _advance();
      case Tag.gtGt:
        // ">>" → ">" (consumido) + ">" (resta, reescrito in-place).
        tokens[_current] = Token(
          tag: Tag.gt,
          lexeme: '>',
          line: t.line,
          col: t.col + 1,
          offset: t.offset + 1,
          length: 1,
        );
        return Token(
          tag: Tag.gt,
          lexeme: '>',
          line: t.line,
          col: t.col,
          offset: t.offset,
          length: 1,
        );
      case Tag.gtEq:
        // ">=" → ">" (consumido) + "=" (resta, ex.: `List<Int>=default`).
        tokens[_current] = Token(
          tag: Tag.eq,
          lexeme: '=',
          line: t.line,
          col: t.col + 1,
          offset: t.offset + 1,
          length: 1,
        );
        return Token(
          tag: Tag.gt,
          lexeme: '>',
          line: t.line,
          col: t.col,
          offset: t.offset,
          length: 1,
        );
      default:
        throw ParseError(code, t.offset, t.length);
    }
  }

  // =========================================================================
  // Patterns (T032 — completo). §6 GRAMMAR.
  // =========================================================================

  Pattern _pattern() {
    final start = _peek();

    // Wildcard: `_`.
    if (_match(Tag.underscore)) {
      return WildcardPattern(start.offset, start.length);
    }

    // Enum variant: `.Name` ou `.Name(subpats)`.
    if (_match(Tag.dot)) {
      final name = _consume(Tag.identifier, 'expected-token').lexeme;
      final subs = <Pattern>[];
      if (_match(Tag.lparen)) {
        if (!_check(Tag.rparen)) {
          do {
            subs.add(_pattern());
          } while (_match(Tag.comma));
        }
        _consume(Tag.rparen, 'expected-token');
      }
      return EnumPattern(name, subs, start.offset, _lenFrom(start));
    }

    // List pattern: `[a, b, ..rest]`.
    if (_match(Tag.lbracket)) {
      final elems = <Pattern>[];
      if (!_check(Tag.rbracket)) {
        do {
          if (_check(Tag.dotDot)) {
            final restStart = _advance();
            final restName = _check(Tag.identifier) ? _advance().lexeme : null;
            elems.add(
              RestPattern(restName, restStart.offset, _lenFrom(restStart)),
            );
          } else {
            elems.add(_pattern());
          }
        } while (_match(Tag.comma));
      }
      _consume(Tag.rbracket, 'expected-token');
      return ListPattern(elems, start.offset, _lenFrom(start));
    }

    // Struct pattern: `TypeName { field, field: subpat, .. }` (lookahead k=2).
    if (_check(Tag.identifier) && _checkAt(1, Tag.lbrace)) {
      final typeName = _advance().lexeme;
      _advance(); // consome `{`
      final fields = <FieldPattern>[];
      var hasRest = false;
      if (!_check(Tag.rbrace)) {
        do {
          if (_match(Tag.dotDot)) {
            hasRest = true;
            break;
          }
          final fieldName = _consume(Tag.identifier, 'expected-token').lexeme;
          final sub = _match(Tag.colon) ? _pattern() : null;
          fields.add(FieldPattern(fieldName, sub));
        } while (_match(Tag.comma));
      }
      _consume(Tag.rbrace, 'expected-token');
      return StructPattern(
        typeName,
        fields,
        hasRest,
        start.offset,
        _lenFrom(start),
      );
    }

    // Literais (com range `1..10` / `1..=10`).
    if (_check(Tag.intLiteral)) {
      final t = _advance();
      final startExpr = IntLit(t.literal as int, t.offset, t.length);
      if (_check(Tag.dotDot) || _check(Tag.dotDotEq)) {
        final inclusive = _peek().tag == Tag.dotDotEq;
        _advance();
        final endTok = _consume(Tag.intLiteral, 'expected-token');
        final endExpr = IntLit(endTok.literal as int, endTok.offset, endTok.length);
        return RangePattern(
          inclusive,
          startExpr,
          endExpr,
          start.offset,
          _lenFrom(start),
        );
      }
      return LiteralPattern(startExpr, start.offset, _lenFrom(start));
    }
    if (_check(Tag.floatLiteral)) {
      final t = _advance();
      return LiteralPattern(
        FloatLit(t.literal as double, t.offset, t.length),
        start.offset,
        _lenFrom(start),
      );
    }
    if (_check(Tag.stringLiteral) || _check(Tag.multilineString)) {
      final str = _stringLiteral(_advance());
      return LiteralPattern(str, start.offset, _lenFrom(start));
    }
    if (_check(Tag.kwTrue) || _check(Tag.kwFalse)) {
      final t = _advance();
      return LiteralPattern(
        BoolLit(t.tag == Tag.kwTrue, t.offset, t.length),
        start.offset,
        _lenFrom(start),
      );
    }
    if (_match(Tag.kwNil)) {
      return LiteralPattern(
        NilLit(start.offset, start.length),
        start.offset,
        _lenFrom(start),
      );
    }

    // Binding: `x`.
    if (_check(Tag.identifier)) {
      final name = _advance().lexeme;
      return BindPattern(name, start.offset, _lenFrom(start));
    }

    throw ParseError('expected-pattern', start.offset, start.length);
  }

  // =========================================================================
  // Recuperação N2 (T030).
  // =========================================================================

  /// Descarta tokens até um boundary de declaração (FIRST-de-top-level ou EOF).
  /// Fatia 0: sync de nível de declaração (top-level). O sync consciente de
  /// boundary-closer para blocos internos entra na Fatia 2.
  void _synchronizeDecl() {
    while (!_isAtEnd) {
      if (_isDeclKeyword(_peek().tag) ||
          _peek().tag == Tag.kwLet ||
          _peek().tag == Tag.kwVar) {
        return;
      }
      _advance();
    }
  }

  // =========================================================================
  // Helpers de cursor.
  // =========================================================================

  Token _peek() => tokens[_current];
  Token _previous() => tokens[_current - 1];
  bool get _isAtEnd => _peek().tag == Tag.eof;

  Token _advance() {
    if (!_isAtEnd) _current++;
    return _previous();
  }

  bool _check(Tag tag) => !_isAtEnd && _peek().tag == tag;

  bool _checkAt(int n, Tag tag) {
    final i = _current + n;
    return i < tokens.length && tokens[i].tag == tag;
  }

  bool _match(Tag tag) {
    if (_check(tag)) {
      _advance();
      return true;
    }
    return false;
  }

  Token _consume(Tag tag, String code) {
    if (_check(tag)) return _advance();
    final t = _peek();
    throw ParseError(code, t.offset, t.length);
  }

  /// Comprimento do span de um nó iniciado em [start] até o último token
  /// consumido (`_previous()`).
  int _lenFrom(Token start) {
    final p = _previous();
    return (p.offset + p.length) - start.offset;
  }
}
