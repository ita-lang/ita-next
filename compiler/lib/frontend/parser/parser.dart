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

import 'package:ita_next_compiler/frontend/lexer/lexer.dart';
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

  /// Canto 7: suprime trailing-closure enquanto verdadeiro. Ligado nas CONDIÇÕES
  /// de `if`/`while`/`for`/`match` (o `{` ali é bloco/arms, não closure); `guard`
  /// NÃO liga (assimetria CA21). Salvo/restaurado por [_suppressedExpression].
  bool _noTrailingClosure = false;

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
        // Progresso garantido ANTES de medir o span: se a sincronização parou no
        // próprio token ofensor (que já é boundary sem handler, ex.: `init`),
        // descarta ≥1 — evita `_previous()` em `_current==0` (crash B1) sem
        // super-descartar um boundary VÁLIDO (ex.: `impl`, que ficou intacto).
        if (_current == before) _advance();
        final endOffset = _previous().offset + _previous().length;
        final len = endOffset > startTok.offset
            ? endOffset - startTok.offset
            : startTok.length;
        body.add(ErrorDecl(e.code, startTok.offset, len));
      }
      // Garantia de progresso: nunca ficar preso no mesmo token.
      if (_current == before) _advance();
    }
    return Program(body, 0, sourceLength);
  }

  // =========================================================================
  // Nível de topo (declarações + bindings/expr-stmts de módulo).
  // =========================================================================

  /// Item de topo: declaração ou statement (o Itá permite statements no escopo
  /// de módulo — scripting, §2 GRAMMAR).
  AstNode _topLevelItem() => _isDeclStart() ? _declaration() : _statement();

  /// True se o token atual INICIA uma declaração. `async`/`stream` só contam se
  /// seguidos de `fn` (`async (` é closure — expressão, não declaração).
  bool _isDeclStart() {
    final tag = _peek().tag;
    if (tag == Tag.kwAsync || tag == Tag.kwStream) return _checkAt(1, Tag.kwFn);
    return _isDeclKeyword(tag);
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
    final pubTok = _check(Tag.kwPub) ? _peek() : null;
    final isPublic = _match(Tag.kwPub);
    switch (_peek().tag) {
      case Tag.kwFn ||
          Tag.kwStatic ||
          Tag.kwOverride ||
          Tag.kwAsync ||
          Tag.kwStream:
        return _fnDecl(isPublic, start);
      case Tag.kwStruct:
        return _structDecl(isPublic, start);
      case Tag.kwClass:
        return _classDecl(isPublic, start);
      case Tag.kwEnum:
        return _enumDecl(isPublic, start);
      case Tag.kwTrait:
        return _traitDecl(isPublic, start);
      case Tag.kwActor:
        return _actorDecl(isPublic, start);
      // D3: `pub` é no-op em impl/extension/import/operator → error production.
      case Tag.kwImpl:
        _rejectMeaninglessPub(pubTok);
        return _implDecl(start);
      case Tag.kwExtension:
        _rejectMeaninglessPub(pubTok);
        return _extensionDecl(start);
      case Tag.kwImport:
        _rejectMeaninglessPub(pubTok);
        return _importDecl(start);
      case Tag.kwOperator:
        _rejectMeaninglessPub(pubTok);
        return _operatorDecl(start);
      default:
        throw ParseError(
          'expected-declaration',
          _peek().offset,
          _peek().length,
        );
    }
  }

  /// D3: `pub` diante de `impl`/`extension`/`import`/`operator` é sem sentido —
  /// `parse-error: meaningless-pub` no span do `pub` (conserta o consumo mudo
  /// do oracle; DB 4.1.4 error production).
  void _rejectMeaninglessPub(Token? pubTok) {
    if (pubTok != null) {
      throw ParseError('meaningless-pub', pubTok.offset, pubTok.length);
    }
  }

  // --- tipos de usuário -----------------------------------------------------

  /// `{ ( fieldDecl | methodDecl )* }` — corpo de struct/class/trait/extension/
  /// actor. Campos e métodos intercaláveis, ordem-fonte preservada (CA2).
  List<Decl> _typeBody() {
    _consume(Tag.lbrace, 'expected-token');
    final members = <Decl>[];
    while (!_check(Tag.rbrace) && !_isAtEnd) {
      members.add(_member());
      _match(Tag.comma);
      _match(Tag.semicolon);
    }
    _consume(Tag.rbrace, 'expected-token');
    return members;
  }

  /// Membro de corpo de tipo: método (`[pub] [static] [override] fn …`) ou campo
  /// (`[var|let] IDENT : type [= e]`).
  Decl _member() {
    final start = _peek();
    final isPublic = _match(Tag.kwPub);
    if (_check(Tag.kwFn) ||
        _check(Tag.kwStatic) ||
        _check(Tag.kwOverride) ||
        _check(Tag.kwAsync) ||
        _check(Tag.kwStream)) {
      return _fnDecl(isPublic, start);
    }
    // Campo: `(var|let)? IDENT : type (= e)?`.
    var isMutable = _match(Tag.kwVar);
    if (!isMutable) _match(Tag.kwLet); // `let x: T` = imutável explícito
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    _consume(Tag.colon, 'expected-token');
    final type = _type();
    final defaultValue = _match(Tag.eq) ? _expression() : null;
    return FieldDecl(
      isPublic,
      isMutable,
      name,
      type,
      defaultValue,
      start.offset,
      _lenFrom(start),
    );
  }

  StructDecl _structDecl(bool isPublic, Token start) {
    _consume(Tag.kwStruct, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final generics = _check(Tag.lt) ? _genericParams() : <GenericParam>[];
    // Conformances inline (`: Trait, …`) são débito (Fatia 3+) — sem CA.
    final members = _typeBody();
    return StructDecl(
      isPublic,
      name,
      generics,
      members,
      start.offset,
      _lenFrom(start),
    );
  }

  ClassDecl _classDecl(bool isPublic, Token start) {
    _consume(Tag.kwClass, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final generics = _check(Tag.lt) ? _genericParams() : <GenericParam>[];
    final superclass = _match(Tag.colon) ? _type() : null;
    final members = _typeBody();
    return ClassDecl(
      isPublic,
      name,
      generics,
      superclass,
      members,
      start.offset,
      _lenFrom(start),
    );
  }

  EnumDecl _enumDecl(bool isPublic, Token start) {
    _consume(Tag.kwEnum, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final generics = _check(Tag.lt) ? _genericParams() : <GenericParam>[];
    _consume(Tag.lbrace, 'expected-token');
    final cases = <EnumCase>[];
    final members = <Decl>[];
    while (!_check(Tag.rbrace) && !_isAtEnd) {
      if (_check(Tag.kwFn) ||
          _check(Tag.kwPub) ||
          _check(Tag.kwStatic) ||
          _check(Tag.kwOverride) ||
          _check(Tag.kwAsync) ||
          _check(Tag.kwStream)) {
        members.add(_member());
      } else {
        cases.add(_enumCase());
      }
      _match(Tag.comma);
      _match(Tag.semicolon);
    }
    _consume(Tag.rbrace, 'expected-token');
    return EnumDecl(
      isPublic,
      name,
      generics,
      cases,
      members,
      start.offset,
      _lenFrom(start),
    );
  }

  EnumCase _enumCase() {
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final payload = <Param>[];
    if (_match(Tag.lparen)) {
      if (!_check(Tag.rparen)) {
        do {
          if (_check(Tag.rparen)) break;
          payload.add(_param());
        } while (_match(Tag.comma));
      }
      _consume(Tag.rparen, 'expected-token');
    }
    return EnumCase(name, payload);
  }

  TraitDecl _traitDecl(bool isPublic, Token start) {
    _consume(Tag.kwTrait, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final generics = _check(Tag.lt) ? _genericParams() : <GenericParam>[];
    final members = _typeBody(); // fnDecl sem corpo = assinatura
    return TraitDecl(
      isPublic,
      name,
      generics,
      members,
      start.offset,
      _lenFrom(start),
    );
  }

  ActorDecl _actorDecl(bool isPublic, Token start) {
    _consume(Tag.kwActor, 'expected-token');
    final name = _consume(Tag.identifier, 'expected-token').lexeme;
    final members = _typeBody(); // actor não tem generics
    return ActorDecl(isPublic, name, members, start.offset, _lenFrom(start));
  }

  ImplDecl _implDecl(Token start) {
    _consume(Tag.kwImpl, 'expected-token');
    final first = _type();
    TypeNode? trait;
    TypeNode target;
    if (_match(Tag.kwFor)) {
      trait = first; // `impl Trait for Type`
      target = _type();
    } else {
      target = first; // `impl Type`
    }
    final members = _typeBody();
    return ImplDecl(trait, target, members, start.offset, _lenFrom(start));
  }

  ExtensionDecl _extensionDecl(Token start) {
    _consume(Tag.kwExtension, 'expected-token');
    final target = _type();
    final members = _typeBody();
    return ExtensionDecl(target, members, start.offset, _lenFrom(start));
  }

  /// `operator OPSYM ( paramList ) -> type ( precedence INT (left|right)? )? block`.
  /// (Débito: `Fixity` do modelo não distingue associatividade `left`/`right` —
  /// registrado no rodapé do ast.asdl; nenhum CA exercita.)
  OperatorDecl _operatorDecl(Token start) {
    _consume(Tag.kwOperator, 'expected-token');
    final symbol = _advance().lexeme; // OPSYM (token de operador)
    final params = _fnParams();
    _consume(Tag.arrow, 'expected-token');
    final ret = _type();
    int? precedence;
    if (_match(Tag.kwPrecedence)) {
      precedence = _consume(Tag.intLiteral, 'expected-token').literal as int;
      // `left`/`right` são identificadores contextuais — consumidos e mapeados
      // ao Fixity (débito: assoc ≠ fixity).
      if (_check(Tag.identifier) &&
          (_peek().lexeme == 'left' || _peek().lexeme == 'right')) {
        _advance();
      }
    }
    final body = _block();
    final fn = FnDecl(
      false,
      false,
      false,
      AsyncMarker.sync,
      symbol,
      const [],
      params,
      ret,
      BlockBody(body),
      start.offset,
      _lenFrom(start),
    );
    return OperatorDecl(
      symbol,
      Fixity.infix,
      precedence,
      fn,
      start.offset,
      _lenFrom(start),
    );
  }

  // --- imports (ES6, 3 formas) ----------------------------------------------

  ImportDecl _importDecl(Token start) {
    _consume(Tag.kwImport, 'expected-token');
    if (_match(Tag.lbrace)) {
      final members = <ImportMember>[];
      if (!_check(Tag.rbrace)) {
        do {
          if (_check(Tag.rbrace)) break;
          final name = _consume(Tag.identifier, 'expected-token').lexeme;
          final alias = _match(Tag.kwAs)
              ? _consume(Tag.identifier, 'expected-token').lexeme
              : null;
          members.add(ImportMember(name, alias));
        } while (_match(Tag.comma));
      }
      _consume(Tag.rbrace, 'expected-token');
      _consumeContextual('from');
      final module = _moduleString(_consumeString());
      return ImportDecl(ImportNamed(members), module, start.offset, _lenFrom(start));
    }
    if (_match(Tag.star)) {
      _consume(Tag.kwAs, 'expected-token');
      final alias = _consume(Tag.identifier, 'expected-token').lexeme;
      _consumeContextual('from');
      final module = _moduleString(_consumeString());
      return ImportDecl(ImportStar(alias), module, start.offset, _lenFrom(start));
    }
    // `import "modulo"` (bare).
    final module = _moduleString(_consumeString());
    return ImportDecl(const ImportBare(), module, start.offset, _lenFrom(start));
  }

  /// Consome um identificador contextual específico (`from`) — não é keyword.
  Token _consumeContextual(String word) {
    if (_check(Tag.identifier) && _peek().lexeme == word) return _advance();
    throw ParseError('expected-token', _peek().offset, _peek().length);
  }

  Token _consumeString() {
    if (_check(Tag.stringLiteral) || _check(Tag.multilineString)) {
      return _advance();
    }
    throw ParseError('expected-string', _peek().offset, _peek().length);
  }

  /// Extrai o valor textual de um literal de string (módulo de import). Rejeita
  /// interpolação (um módulo não pode ser interpolado).
  String _moduleString(Token t) {
    final lit = t.literal;
    if (lit is String) return lit; // multiline
    if (lit is List) {
      final sb = StringBuffer();
      for (final part in lit) {
        if (part is String) {
          sb.write(part);
        } else {
          throw ParseError('interpolated-import-module', t.offset, t.length);
        }
      }
      return sb.toString();
    }
    return '';
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
    // `IDENT IDENT? (: tipo)? (= default)?` — 2 IDENTs = label externo + nome.
    final first = _consume(Tag.identifier, 'expected-token').lexeme;
    String? label;
    String name;
    if (_check(Tag.identifier)) {
      label = first;
      name = _advance().lexeme;
    } else {
      name = first;
    }
    final type = _match(Tag.colon) ? _type() : null;
    final defaultValue = _match(Tag.eq) ? _expression() : null;
    return Param(label, name, type, defaultValue);
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

  /// Statement (§3 GRAMMAR): controle de fluxo, bindings, bare-block, expr-stmt.
  Stmt _statement() {
    switch (_peek().tag) {
      case Tag.kwLet || Tag.kwVar:
        return _letStmt();
      case Tag.kwReturn:
        return _returnStmt();
      case Tag.kwIf:
        return _ifStmt();
      case Tag.kwGuard:
        return _guardStmt();
      case Tag.kwWhile:
        return _whileStmt();
      case Tag.kwFor:
        return _forStmt();
      case Tag.kwBreak:
        final t = _advance();
        return BreakStmt(t.offset, t.length);
      case Tag.kwContinue:
        final t = _advance();
        return ContinueStmt(t.offset, t.length);
      case Tag.kwEmit:
        final start = _advance();
        return EmitStmt(_expression(), start.offset, _lenFrom(start));
      case Tag.lbrace:
        return _blockStmt(); // canto 3: em stmt-pos, `{` é bloco
      default:
        final start = _peek();
        return ExprStmt(_expression(), start.offset, _lenFrom(start));
    }
  }

  ReturnStmt _returnStmt() {
    final start = _advance(); // return
    final value = (_check(Tag.rbrace) || _isAtEnd || _check(Tag.semicolon))
        ? null
        : _expression();
    return ReturnStmt(value, start.offset, _lenFrom(start));
  }

  /// `if COND { … } ( else ( if… | { … } ) )?`. Dangling-else liga ao `if` mais
  /// interno pela recursão natural (CI 9.2 / DB 4.3.2). `if` SUPRIME a
  /// trailing-closure na condição (CA21).
  IfStmt _ifStmt() {
    final start = _peek();
    _consume(Tag.kwIf, 'expected-token');
    final cond = _suppressedExpression();
    final then = _block();
    Else? orElse;
    if (_match(Tag.kwElse)) {
      orElse = _check(Tag.kwIf)
          ? ElseIf(_ifStmt()) // else-if
          : ElseBlock(_block());
    }
    return IfStmt(cond, then, orElse, start.offset, _lenFrom(start));
  }

  /// `guard COND else { … }` ou `guard let PAT = e else { … }`. `guard` NÃO
  /// suprime trailing-closure (assimetria CA21: o `{}` da condição é closure).
  Stmt _guardStmt() {
    final start = _peek();
    _consume(Tag.kwGuard, 'expected-token');
    if (_match(Tag.kwLet)) {
      final target = _pattern();
      _consume(Tag.eq, 'expected-token');
      final value = _expression(); // `&&`-extra do guard-let é débito (Fatia 3)
      _consume(Tag.kwElse, 'expected-token');
      final orElse = _block();
      return GuardLetStmt(target, value, orElse, start.offset, _lenFrom(start));
    }
    final cond = _expression();
    _consume(Tag.kwElse, 'expected-token');
    final orElse = _block();
    return GuardStmt(cond, orElse, start.offset, _lenFrom(start));
  }

  WhileStmt _whileStmt() {
    final start = _peek();
    _consume(Tag.kwWhile, 'expected-token');
    final cond = _suppressedExpression();
    final body = _block();
    return WhileStmt(cond, body, start.offset, _lenFrom(start));
  }

  /// `for [await] PAT in ITER { … }`.
  ForStmt _forStmt() {
    final start = _peek();
    _consume(Tag.kwFor, 'expected-token');
    final isAwait = _match(Tag.kwAwait);
    final target = _pattern();
    _consume(Tag.kwIn, 'expected-token');
    final iterable = _suppressedExpression();
    final body = _block();
    return ForStmt(isAwait, target, iterable, body, start.offset, _lenFrom(start));
  }

  /// Bare-block em posição de statement (canto 3).
  BlockStmt _blockStmt() {
    final start = _peek();
    final block = _block();
    return BlockStmt(block, start.offset, _lenFrom(start));
  }

  // =========================================================================
  // Expressões — cascata de precedência de 13 níveis (D0, CI 6.2). Uma função
  // por nível, do mais FROUXO (topo) ao mais FORTE (base) — §4.2 GRAMMAR. O
  // nome de cada função É o nível (P4: precedência citável, não tabela opaca).
  // =========================================================================

  /// Entrada pública para reparse de sub-expressões (interpolação, M3).
  Expr parseExpression() => _expression();

  /// Nível 0: `where { … }` (cláusula pós-fixa) — DEFERIDO (sem nó/CA; débito).
  Expr _expression() => _assignment();

  /// Nível 1: `= += -= *= /=` — **direita**.
  Expr _assignment() {
    final start = _peek();
    final target = _pipe();
    if (_check(Tag.eq) ||
        _check(Tag.plusEq) ||
        _check(Tag.minusEq) ||
        _check(Tag.starEq) ||
        _check(Tag.slashEq)) {
      final op = _assignOp(_advance().tag);
      final value = _assignment(); // right-assoc
      return Assign(op, target, value, start.offset, _lenFrom(start));
    }
    return target;
  }

  /// Nível 2: `|>` (pipe) · `>>` (compose) — esquerda.
  Expr _pipe() {
    final start = _peek();
    var expr = _nilCoalesce();
    while (_check(Tag.pipeGt) || _check(Tag.gtGt)) {
      final op = _binOp(_advance().tag);
      final right = _nilCoalesce();
      expr = Binary(op, expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 3: `??` (nil-coalesce) — esquerda. Chama `_or` como operando, logo
  /// `||` (nível 4) liga MAIS FORTE que `??` (CA9 — golden corrigido).
  Expr _nilCoalesce() {
    final start = _peek();
    var expr = _or();
    while (_match(Tag.questionQuestion)) {
      final right = _or();
      expr = Binary('??', expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 4: `||` — esquerda.
  Expr _or() {
    final start = _peek();
    var expr = _and();
    while (_match(Tag.pipePipe)) {
      final right = _and();
      expr = Binary('||', expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 5: `&&` — esquerda.
  Expr _and() {
    final start = _peek();
    var expr = _equality();
    while (_match(Tag.ampAmp)) {
      final right = _equality();
      expr = Binary('&&', expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 6: `==` `!=` — esquerda.
  Expr _equality() {
    final start = _peek();
    var expr = _comparison();
    while (_check(Tag.eqEq) || _check(Tag.bangEq)) {
      final op = _binOp(_advance().tag);
      final right = _comparison();
      expr = Binary(op, expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 7: `<` `>` `<=` `>=` — esquerda. Em expressão, `<` é SEMPRE comparação
  /// (D2 — sem turbofish; generics só em posição de tipo).
  Expr _comparison() {
    final start = _peek();
    var expr = _range();
    while (_check(Tag.lt) ||
        _check(Tag.gt) ||
        _check(Tag.ltEq) ||
        _check(Tag.gtEq)) {
      final op = _binOp(_advance().tag);
      final right = _range();
      expr = Binary(op, expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 8: `..` `..=` (range) — **não-associativo**. Um segundo `..`/`..=`
  /// após `a..b` é `range-non-associative` (CA10 — conserta o oracle guloso).
  Expr _range() {
    final start = _peek();
    var expr = _addition();
    if (_check(Tag.dotDot) || _check(Tag.dotDotEq)) {
      final inclusive = _peek().tag == Tag.dotDotEq;
      _advance();
      final end = _addition();
      expr = RangeExpr(inclusive, expr, end, start.offset, _lenFrom(start));
      if (_check(Tag.dotDot) || _check(Tag.dotDotEq)) {
        final t = _peek();
        throw ParseError('range-non-associative', t.offset, t.length);
      }
    }
    return expr;
  }

  /// Nível 9: `+` `-` — esquerda.
  Expr _addition() {
    final start = _peek();
    var expr = _multiplication();
    while (_check(Tag.plus) || _check(Tag.minus)) {
      final op = _binOp(_advance().tag);
      final right = _multiplication();
      expr = Binary(op, expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 10: `*` `/` `%` — esquerda.
  Expr _multiplication() {
    final start = _peek();
    var expr = _power();
    while (_check(Tag.star) || _check(Tag.slash) || _check(Tag.percent)) {
      final op = _binOp(_advance().tag);
      final right = _power();
      expr = Binary(op, expr, right, start.offset, _lenFrom(start));
    }
    return expr;
  }

  /// Nível 11: `**` (potência) — **direita**.
  Expr _power() {
    final start = _peek();
    final base = _unary();
    if (_match(Tag.starStar)) {
      final exp = _power(); // right-assoc
      return Binary('**', base, exp, start.offset, _lenFrom(start));
    }
    return base;
  }

  /// Nível 12: prefixos unários `!` `-` `~` + `await`/`spawn`/`panic` (D4 —
  /// ligam no nível unário, não no `primary` guloso do oracle). Recursão em
  /// `_unary` permite `await -x`, `await await f`.
  Expr _unary() {
    final start = _peek();
    if (_match(Tag.bang)) {
      return Unary('!', _unary(), start.offset, _lenFrom(start));
    }
    if (_match(Tag.minus)) {
      return Unary('neg', _unary(), start.offset, _lenFrom(start));
    }
    if (_match(Tag.tilde)) {
      return Unary('~', _unary(), start.offset, _lenFrom(start));
    }
    if (_match(Tag.kwAwait)) {
      return Await(_unary(), start.offset, _lenFrom(start));
    }
    if (_match(Tag.kwSpawn)) {
      return Spawn(_unary(), start.offset, _lenFrom(start));
    }
    if (_match(Tag.kwPanic)) {
      return Panic(_unary(), start.offset, _lenFrom(start));
    }
    return _postfix();
  }

  /// Nível 13: pós-fixos — esquerda. `(`/`.` continuam a cadeia só na MESMA
  /// linha do operando (sensibilidade a layout, §5); `?.`/`[]`/`!`/`?` não.
  Expr _postfix() {
    final start = _peek();
    var expr = _primary();
    while (true) {
      // Offset do SELETOR/operador (`.`/`(`/`?.`/`[`/`!`/`?`) — vira o `fileOffset`
      // do Kernel (stack trace no seletor, não no início do receptor; fix A1).
      final opOffset = _peek().offset;
      if (_check(Tag.lparen) && _peek().line == _previous().line) {
        _advance(); // (
        expr = _finishCall(expr, start, opOffset);
      } else if (_check(Tag.dot) && _peek().line == _previous().line) {
        _advance(); // .
        if (_check(Tag.lbrace)) {
          // copy-with: expr.{ campo: v }
          _advance(); // {
          final fields = <FieldInit>[];
          if (!_check(Tag.rbrace)) {
            do {
              final name = _consume(Tag.identifier, 'expected-token').lexeme;
              _consume(Tag.colon, 'expected-token');
              fields.add(FieldInit(name, _bracketed(_expression)));
            } while (_match(Tag.comma));
          }
          _consume(Tag.rbrace, 'expected-token');
          expr = CopyWith(expr, fields, opOffset, start.offset, _lenFrom(start));
        } else if (_check(Tag.intLiteral)) {
          // tuple-index: t.0
          final idx = _advance();
          expr = TupleIndex(
            expr,
            idx.literal as int,
            opOffset,
            start.offset,
            _lenFrom(start),
          );
        } else {
          final member = _consume(Tag.identifier, 'expected-token').lexeme;
          expr = Member(expr, member, opOffset, start.offset, _lenFrom(start));
          // trailing closure após member, mesma linha (`expr.m { … }`)
          if (!_noTrailingClosure &&
              _check(Tag.lbrace) &&
              _peek().line == _previous().line) {
            final tc = _trailingClosure();
            expr = Call(
              expr,
              [Arg(null, tc)],
              opOffset,
              start.offset,
              _lenFrom(start),
            );
          }
        }
      } else if (_match(Tag.questionDot)) {
        final member = _consume(Tag.identifier, 'expected-token').lexeme;
        expr = OptChain(expr, member, opOffset, start.offset, _lenFrom(start));
      } else if (_match(Tag.lbracket)) {
        final index = _bracketed(_expression);
        _consume(Tag.rbracket, 'expected-token');
        expr = Index(expr, index, opOffset, start.offset, _lenFrom(start));
      } else if (_match(Tag.bang)) {
        expr = ForceUnwrap(expr, opOffset, start.offset, _lenFrom(start));
      } else if (_match(Tag.question)) {
        expr = Try(expr, opOffset, start.offset, _lenFrom(start));
      } else {
        break;
      }
    }
    return expr;
  }

  Call _finishCall(Expr callee, Token start, int opOffset) {
    // `(` já consumido. Args ficam DENTRO de `(...)` → a supressão da condição
    // externa não vale para eles (fix A1); restaura antes do check de trailing.
    final savedSuppress = _noTrailingClosure;
    _noTrailingClosure = false;
    final args = <Arg>[];
    if (!_check(Tag.rparen)) {
      do {
        if (_check(Tag.rparen)) break; // tolera vírgula final
        if (_check(Tag.identifier) && _checkAt(1, Tag.colon)) {
          final label = _advance().lexeme;
          _advance(); // :
          args.add(Arg(label, _expression()));
        } else {
          args.add(Arg(null, _expression()));
        }
      } while (_match(Tag.comma));
    }
    final rparen = _consume(Tag.rparen, 'expected-token');
    _noTrailingClosure = savedSuppress; // o `{` após `)` respeita a supressão externa
    // trailing-closure mesma-linha que o `)` (CA13 — conserta bug do oracle).
    if (!_noTrailingClosure &&
        _check(Tag.lbrace) &&
        _peek().line == rparen.line) {
      args.add(Arg(null, _trailingClosure()));
    }
    return Call(callee, args, opOffset, start.offset, _lenFrom(start));
  }

  /// Trailing-closure `{ … }` com params implícitos (`$0`, `$1`).
  Closure _trailingClosure() {
    final start = _peek();
    final body = _block();
    return Closure(
      AsyncMarker.sync,
      false, // params implícitos
      const [],
      null,
      BlockBody(body),
      start.offset,
      _lenFrom(start),
    );
  }

  Expr _primary() {
    final start = _peek();

    // async closure: `async (` — `async fn` (declaração) já foi tratado antes.
    if (_check(Tag.kwAsync) && _checkAt(1, Tag.lparen)) {
      _advance(); // async
      return _closure(true, start);
    }

    if (_match(Tag.intLiteral)) {
      return IntLit(_previous().literal as int, start.offset, start.length);
    }
    if (_match(Tag.floatLiteral)) {
      return FloatLit(_previous().literal as double, start.offset, start.length);
    }
    if (_check(Tag.stringLiteral) || _check(Tag.multilineString)) {
      return _stringLiteral(_advance());
    }
    if (_match(Tag.kwTrue)) return BoolLit(true, start.offset, start.length);
    if (_match(Tag.kwFalse)) return BoolLit(false, start.offset, start.length);
    if (_match(Tag.kwNil)) return NilLit(start.offset, start.length);
    if (_match(Tag.kwSelf)) return SelfExpr(start.offset, start.length);
    if (_check(Tag.kwMatch)) return _matchExpr();
    if (_check(Tag.kwIf)) return _ifExpr(); // if-EXPRESSÃO (ruling RD-1, opção A)
    if (_check(Tag.lparen)) return _parenOrClosure();
    if (_check(Tag.lbracket)) return _listLiteral();
    // Canto 3 (D1): em posição de EXPRESSÃO, `{` é MAP literal — nunca bloco.
    if (_check(Tag.lbrace)) return _mapLiteral();
    // enum shorthand: `.Ident` (payload vira call via pós-fixo).
    if (_match(Tag.dot)) {
      final variant = _consume(Tag.identifier, 'expected-token').lexeme;
      return EnumShorthand(variant, start.offset, _lenFrom(start));
    }
    if (_match(Tag.identifier)) {
      return Ident(_previous().lexeme, start.offset, start.length);
    }
    throw ParseError('expected-expression', start.offset, start.length);
  }

  /// if-EXPRESSÃO (ruling RD-1, opção A): `if [let PAT =] SUBJECT => then else
  /// orElse`. Ramos são EXPRESSÕES (valor explícito via `=>`, o único token
  /// "rende valor"); `else` é OBRIGATÓRIO. `binding != null` = forma if-let
  /// (desembrulho). Distingue-se do if-STATEMENT (`_ifStmt`, blocos) por posição
  /// — aqui só se chega em posição de expressão.
  IfExpr _ifExpr() {
    final start = _peek();
    _consume(Tag.kwIf, 'expected-token');
    Pattern? binding;
    final Expr subject;
    if (_match(Tag.kwLet)) {
      binding = _pattern(); // `if let PAT = SUBJECT => …`
      _consume(Tag.eq, 'expected-token');
      subject = _expression();
    } else {
      subject = _expression(); // condição booleana
    }
    _consume(Tag.fatArrow, 'expected-token');
    final then = _expression();
    _consume(Tag.kwElse, 'expected-token');
    // else-if encadeado (`… else if … => … else …`) ou expressão final.
    final orElse = _check(Tag.kwIf) ? _ifExpr() : _expression();
    return IfExpr(binding, subject, then, orElse, start.offset, _lenFrom(start));
  }

  /// `(` → agrupamento `(a)`, tupla `(a, b)` (>=2) ou closure `(params) => …`.
  /// A distinção closure-vs-grupo é o ÚNICO lookahead ilimitado (`_isClosureStart`).
  Expr _parenOrClosure() {
    final start = _peek();
    // Dentro de `(...)` a supressão da condição externa não vale (fix A1).
    return _bracketed(() {
      if (_isClosureStart()) return _closure(false, start);
      _consume(Tag.lparen, 'expected-token');
      if (_check(Tag.rparen)) {
        // `()` sozinho não é expressão (só `() => …`, já pego por _isClosureStart).
        throw ParseError('expected-expression', _peek().offset, _peek().length);
      }
      final elems = <Expr>[_expression()];
      var trailingComma = false;
      while (_match(Tag.comma)) {
        if (_check(Tag.rparen)) {
          trailingComma = true;
          break;
        }
        elems.add(_expression());
      }
      _consume(Tag.rparen, 'expected-token');
      if (elems.length == 1) {
        if (trailingComma) {
          // `(a,)` 1-tupla é degenerada (M7).
          throw ParseError('single-element-tuple', start.offset, _lenFrom(start));
        }
        return elems.first; // agrupamento (a) == a
      }
      return TupleExpr(elems, start.offset, _lenFrom(start));
    });
  }

  /// Scan-ahead: o `(` atual abre uma closure? (fecha em `)` seguido de `=>`/`->`).
  /// ÚNICO lookahead ilimitado do parser (§0.6 — vigiado pelo benchmark-guard).
  bool _isClosureStart() {
    var depth = 0;
    var i = _current;
    while (i < tokens.length) {
      final tag = tokens[i].tag;
      if (tag == Tag.lparen) {
        depth++;
      } else if (tag == Tag.rparen) {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      } else if (tag == Tag.eof) {
        return false;
      }
      i++;
    }
    return i < tokens.length &&
        (tokens[i].tag == Tag.fatArrow || tokens[i].tag == Tag.arrow);
  }

  Closure _closure(bool isAsync, Token start) {
    _consume(Tag.lparen, 'expected-token');
    final params = <Param>[];
    if (!_check(Tag.rparen)) {
      do {
        if (_check(Tag.rparen)) break;
        params.add(_param());
      } while (_match(Tag.comma));
    }
    _consume(Tag.rparen, 'expected-token');
    final returnType = _match(Tag.arrow) ? _type() : null;
    final FnBody body;
    if (_match(Tag.fatArrow)) {
      body = _check(Tag.lbrace) ? BlockBody(_block()) : ExprBody(_expression());
    } else {
      body = BlockBody(_block());
    }
    return Closure(
      isAsync ? AsyncMarker.async : AsyncMarker.sync,
      true,
      params,
      returnType,
      body,
      start.offset,
      _lenFrom(start),
    );
  }

  ListExpr _listLiteral() {
    final start = _peek();
    return _bracketed(() {
      _consume(Tag.lbracket, 'expected-token');
      final elems = <Expr>[];
      if (!_check(Tag.rbracket)) {
        do {
          if (_check(Tag.rbracket)) break;
          elems.add(_expression());
        } while (_match(Tag.comma));
      }
      _consume(Tag.rbracket, 'expected-token');
      return ListExpr(elems, start.offset, _lenFrom(start));
    });
  }

  /// Map literal `{ k: v, … }` (canto 3). Recuperação N2 boundary-aware: se o
  /// corpo falha, o construto que abriu o `{` reancora no SEU `}` (não deixa o
  /// erro subir ao top-level e cascatear) e enxerta um [ErrorExpr] (CA23).
  Expr _mapLiteral() {
    final start = _peek();
    return _bracketed(() {
      _consume(Tag.lbrace, 'expected-token');
      final entries = <MapEntryNode>[];
      try {
        if (!_check(Tag.rbrace)) {
          do {
            if (_check(Tag.rbrace)) break;
            final key = _expression();
            _consume(Tag.colon, 'expected-token');
            final value = _expression();
            entries.add(MapEntryNode(key, value));
          } while (_match(Tag.comma));
        }
        _consume(Tag.rbrace, 'expected-token');
        return MapExpr(entries, start.offset, _lenFrom(start));
      } on ParseError catch (e) {
        errors.add(e);
        _skipToCloser(Tag.rbrace);
        return ErrorExpr(e.code, start.offset, _lenFrom(start));
      }
    });
  }

  /// Descarta tokens (contando aninhamento de `{`) até consumir o `}` que casa
  /// com o `{` já aberto. Usado pela recuperação local dos brackets.
  void _skipToCloser(Tag closer) {
    var depth = 1;
    while (!_isAtEnd) {
      final tag = _peek().tag;
      if (tag == Tag.lbrace) {
        depth++;
      } else if (tag == closer) {
        depth--;
        if (depth == 0) {
          _advance();
          return;
        }
      }
      _advance();
    }
  }

  MatchExpr _matchExpr() {
    final start = _peek();
    _consume(Tag.kwMatch, 'expected-token');
    // O `{` seguinte abre os arms — suprime trailing-closure no escrutínio.
    final scrutinee = _suppressedExpression();
    _consume(Tag.lbrace, 'expected-token');
    // Arms ficam DENTRO do `{ }` do match → supressão externa não vale (fix A1).
    final arms = _bracketed(() {
      final list = <MatchArm>[];
      // Vírgula é separador OPCIONAL entre arms — newline também separa (fix A5).
      while (!_check(Tag.rbrace) && !_isAtEnd) {
        final pat = _pattern();
        final guard = _match(Tag.kwIf) ? _expression() : null;
        _consume(Tag.fatArrow, 'expected-token');
        list.add(MatchArm(pat, guard, _expression()));
        _match(Tag.comma);
      }
      return list;
    });
    _consume(Tag.rbrace, 'expected-token');
    return MatchExpr(scrutinee, arms, start.offset, _lenFrom(start));
  }

  /// Parseia uma expressão com trailing-closure SUPRIMIDO (condição de
  /// `if`/`while`/`for`/`match`). Salva/restaura o flag.
  Expr _suppressedExpression() {
    final saved = _noTrailingClosure;
    _noTrailingClosure = true;
    final e = _expression();
    _noTrailingClosure = saved;
    return e;
  }

  /// Executa [parse] com trailing-closure NÃO suprimido — dentro de um par de
  /// brackets (`()`/`[]`/`{}`), um `{` nunca é o bloco de um `if`/`while`
  /// externo, então a supressão da condição não deve vazar para lá (fix A1).
  R _bracketed<R>(R Function() parse) {
    final saved = _noTrailingClosure;
    _noTrailingClosure = false;
    try {
      return parse();
    } finally {
      _noTrailingClosure = saved;
    }
  }

  /// Constrói o nó [Str] do literal pré-computado do lexer, com as partes em
  /// ordem-fonte (M3). Interpolações são REPARSEADAS em parse-time.
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
          // ['expr', source, offsetAbsoluto] — sub-parse parse-time (M3, CA20).
          final src = part[1] as String;
          final baseOffset = part[2] as int;
          parts.add(StrInterp(_parseSubExpression(src, baseOffset)));
        }
      }
    }
    return Str(parts, t.offset, t.length);
  }

  /// Reparseia o fonte cru de uma interpolação `${…}` como uma expressão (M3).
  /// O sub-lexer recebe [baseOffset] (a posição absoluta do conteúdo no arquivo)
  /// para que os spans dos nós da sub-expressão sejam ABSOLUTOS — DWARF/source-
  /// maps corretos (conserto do débito da revisão da Fase 2).
  Expr _parseSubExpression(String src, int baseOffset) {
    final lexer = Lexer(src, baseOffset: baseOffset)..scanTokens();
    final sub = Parser(lexer.tokens, sourceLength: src.length);
    final expr = sub.parseExpression();
    errors.addAll(sub.errors);
    return expr;
  }

  String _binOp(Tag tag) => switch (tag) {
    Tag.pipeGt => '|>',
    Tag.gtGt => '>>',
    Tag.questionQuestion => '??',
    Tag.pipePipe => '||',
    Tag.ampAmp => '&&',
    Tag.eqEq => '==',
    Tag.bangEq => '!=',
    Tag.lt => '<',
    Tag.gt => '>',
    Tag.ltEq => '<=',
    Tag.gtEq => '>=',
    Tag.plus => '+',
    Tag.minus => '-',
    Tag.star => '*',
    Tag.slash => '/',
    Tag.percent => '%',
    Tag.starStar => '**',
    _ => throw StateError('não é operador binário: $tag'),
  };

  String _assignOp(Tag tag) => switch (tag) {
    Tag.eq => '=',
    Tag.plusEq => '+=',
    Tag.minusEq => '-=',
    Tag.starEq => '*=',
    Tag.slashEq => '/=',
    _ => throw StateError('não é operador de atribuição: $tag'),
  };

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
        // ">>" → ">" (fecho, consumido) + ">" (resta). Ver [_splitTypeGt].
        return _splitTypeGt(t, Tag.gt, '>');
      case Tag.gtEq:
        // ">=" → ">" (fecho, consumido) + "=" (resta, ex.: `List<Int>=default`).
        return _splitTypeGt(t, Tag.eq, '=');
      default:
        throw ParseError(code, t.offset, t.length);
    }
  }

  /// Divide `>>`/`>=` em posição de tipo (DB 4.4 — maximal-munch vs. fecha-
  /// template): consome o `>` de fecho (com o offset do token) e INSERE o
  /// restante logo após, avançando o cursor. Assim `_previous()` reflete o `>`
  /// consumido e o span do generic interno inclui o fecho (M1, fix A4). Sem
  /// re-lex, sem backtrack.
  Token _splitTypeGt(Token t, Tag restTag, String restLexeme) {
    final closer = Token(
      tag: Tag.gt,
      lexeme: '>',
      line: t.line,
      col: t.col,
      offset: t.offset,
      length: 1,
    );
    final rest = Token(
      tag: restTag,
      lexeme: restLexeme,
      line: t.line,
      col: t.col + 1,
      offset: t.offset + 1,
      length: 1,
    );
    tokens[_current] = closer;
    tokens.insert(_current + 1, rest);
    return _advance(); // consome o `>` de fecho; `_previous()` = closer
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

    // Record destructure: `{ x, y }` ou `{ x: subpat }` (bare `{`, sem IDENT
    // antes — distinto do struct-pattern `IDENT {`).
    if (_match(Tag.lbrace)) {
      final fields = <FieldPattern>[];
      if (!_check(Tag.rbrace)) {
        do {
          if (_check(Tag.rbrace)) break;
          final name = _consume(Tag.identifier, 'expected-token').lexeme;
          final sub = _match(Tag.colon) ? _pattern() : null;
          fields.add(FieldPattern(name, sub));
        } while (_match(Tag.comma));
      }
      _consume(Tag.rbrace, 'expected-token');
      return RecordPattern(fields, start.offset, _lenFrom(start));
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
    // Para NO boundary sem descartá-lo (é um ponto de resync válido — ex.: o
    // `impl` de `pub impl …` reparseia limpo). O progresso mínimo (o caso em que
    // o próprio token ofensor já é boundary) é garantido no `catch` de
    // `parseProgram`, não aqui — assim não cascateia (DB 4.4.5 / CI 6.3.3).
    while (!_isAtEnd) {
      if (_isItemBoundary(_peek().tag)) return;
      _advance();
    }
  }

  /// FIRST de um item de topo — declaração OU statement (o topo aceita ambos,
  /// §2 GRAMMAR). Boundary de re-sincronização da recuperação N2 (DB 4.4.5).
  bool _isItemBoundary(Tag tag) =>
      _isDeclKeyword(tag) ||
      switch (tag) {
        Tag.kwLet ||
        Tag.kwVar ||
        Tag.kwReturn ||
        Tag.kwIf ||
        Tag.kwGuard ||
        Tag.kwWhile ||
        Tag.kwFor ||
        Tag.kwBreak ||
        Tag.kwContinue ||
        Tag.kwEmit => true,
        _ => false,
      };

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
