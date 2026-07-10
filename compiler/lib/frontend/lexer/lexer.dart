// ============================================================================
// lexer.dart — Scanner à mão do léxico do Itá (ita-next, Fase 1).
// ============================================================================
//
// Texto (String) → List<Token>. Scanner single-pass, à mão (P11: zero code
// generation — nenhum Flex/ANTLR). Técnica: maximal munch (o operador mais
// longo vence). Erros são NÃO-ABORTANTES (D3): colhe múltiplos, emite
// `Tag.invalid` para resync e segue tokenizando.
//
// Diferenças deliberadas vs o oracle `ita/` (consertos da reescrita):
//  - Separador numérico `_` FUNCIONA (D4): aceito entre dígitos em dec/hex/bin
//    e float; proibido inicial/final/duplo → `lex-malformed-number`. (O `ita/`
//    lexa `1_000` como `1` + `_000`.)
//  - Números mal-formados (`0x`/`0b` sem dígito, `2.0e` sem expoente, `1__0`)
//    viram `lex-malformed-number` em vez de CRASHAR (`int.parse('')`).
//  - INT bem-formado fora de Int64 (`99999999999999999999`, `0xFFFF…FFFF`) vira
//    `lex-integer-overflow` via `int.tryParse` — sem `FormatException` (W3/B1).
//  - Escape desconhecido (`\z`) é `lex-invalid-escape`, não char cru tolerado
//    silenciosamente como no oracle (W3/R1); o char fica no buffer p/ resync.
//  - Erros: `code` em EN kebab-case (Const. Art. IV), `hint` em PT-BR (ruling
//    W3/R2), com span real (offset+length).
//  - String literal SEMPRE é uma `List` de partes (vazia → `[]`, CA13).
//  - Sem o hack `.{` → dot+lbrace: `.` já emite `dot` e o `{` seguinte é
//    escaneado como `lbrace` naturalmente (mesmo resultado, sem dead code).
//
// Referência (ADR-0009): Crafting Interpreters, cap. 4 (scanning.md).
// ============================================================================

import 'package:ita_next_compiler/frontend/lexer/token.dart';

// =============================================================================
// LexError — erro léxico (EN kebab-case, não-abortante — D3).
// =============================================================================

/// Um erro léxico coletado durante a tokenização.
///
/// [code] é sempre um slug EN kebab-case da taxonomia fixa (§2.7):
/// `lex-unexpected-char`, `lex-unterminated-string`,
/// `lex-unterminated-multiline-string`, `lex-unterminated-block-comment`,
/// `lex-annotation-unsupported`, `lex-malformed-number`,
/// `lex-integer-overflow`, `lex-invalid-escape`.
///
/// O `code` é SEMPRE EN kebab-case (Const. Art. IV); o `hint`/`detail` humano
/// fica em PT-BR (ruling do dono).
class LexError {
  final String code;
  final int line;
  final int col;
  final int offset;
  final int length;

  /// Detalhe opcional exibido entre aspas (ex.: o caractere ofensor de
  /// `lex-unexpected-char`).
  final String? detail;

  /// Dica humana (não entra no dump de conformância; serve ao diagnóstico).
  final String? hint;

  const LexError(
    this.code,
    this.line,
    this.col, {
    required this.offset,
    this.length = 1,
    this.detail,
    this.hint,
  });

  /// Formato canônico do dump: `<code>[ '<detail>'] @<line>:<col>`.
  String format() =>
      detail != null ? "$code '$detail' @$line:$col" : '$code @$line:$col';

  @override
  String toString() => format();
}

// =============================================================================
// Comment — comentário capturado (NÃO vira token; serve a fmt/doc futuro).
// =============================================================================

class Comment {
  final String text;
  final int line;
  final int col;
  final bool isBlock;

  const Comment(this.text, this.line, this.col, {required this.isBlock});
}

// =============================================================================
// Lexer — o scanner.
// =============================================================================

/// Transforma código fonte Itá numa lista de [Token]s.
///
/// Uso:
/// ```dart
/// final lexer = Lexer(source);
/// final tokens = lexer.scanTokens();
/// if (lexer.errors.isNotEmpty) { /* trata os erros coletados */ }
/// ```
class Lexer {
  final String source;
  final List<Token> tokens = [];
  final List<LexError> errors = [];
  final List<Comment> comments = [];

  // Estado do scanner (nomes do CI scanning.md):
  int _start = 0; // offset de início do token atual
  int _current = 0; // cursor
  int _line = 1;
  int _col = 1;
  int _startLine = 1;
  int _startCol = 1;

  Lexer(this.source);

  /// Tokeniza o fonte inteiro e retorna a lista de tokens (terminada em `eof`).
  List<Token> scanTokens() {
    while (!_isAtEnd) {
      _start = _current;
      _startLine = _line;
      _startCol = _col;
      _scanToken();
    }
    tokens.add(
      Token(
        tag: Tag.eof,
        lexeme: '',
        line: _line,
        col: _col,
        offset: _current,
        length: 0,
      ),
    );
    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Núcleo — decide a categoria a partir do 1º caractere.
  // ---------------------------------------------------------------------------

  void _scanToken() {
    final c = _advance();
    switch (c) {
      // Whitespace ignorado (Itá não é sensível a indentação).
      case ' ':
      case '\r':
      case '\t':
        break;
      case '\n':
        _newline();

      // Pontuação de 1 char.
      case '(':
        _addToken(Tag.lparen);
      case ')':
        _addToken(Tag.rparen);
      case '{':
        _addToken(Tag.lbrace);
      case '}':
        _addToken(Tag.rbrace);
      case '[':
        _addToken(Tag.lbracket);
      case ']':
        _addToken(Tag.rbracket);
      case ',':
        _addToken(Tag.comma);
      case ':':
        _addToken(Tag.colon);
      case ';':
        _addToken(Tag.semicolon);
      case '#': // terminal "morto" no parser, mas tokenizado (§2.5, D5)
        _addToken(Tag.hash);
      case '~':
        _addToken(Tag.tilde);
      case '^': // terminal "morto" (§2.5, D5)
        _addToken(Tag.caret);

      // `@` proibido — Itá não tem annotations (P6, D5).
      case '@':
        _error(
          'lex-annotation-unsupported',
          hint: 'use traits, extensions ou composição',
        );
        _addToken(Tag.invalid);

      // Operadores com maximal munch.
      case '+':
        _addToken(_match('=') ? Tag.plusEq : Tag.plus);
      case '-':
        // `->` vs `-=` vs `-`: distinguem-se já no 2º char → ordem irrelevante.
        if (_match('>')) {
          _addToken(Tag.arrow);
        } else if (_match('=')) {
          _addToken(Tag.minusEq);
        } else {
          _addToken(Tag.minus);
        }
      case '*':
        // `**` antes de `*` (mais longo no mesmo prefixo).
        if (_match('*')) {
          _addToken(Tag.starStar);
        } else if (_match('=')) {
          _addToken(Tag.starEq);
        } else {
          _addToken(Tag.star);
        }
      case '/':
        if (_match('/')) {
          _lineComment();
        } else if (_match('*')) {
          _blockComment();
        } else if (_match('=')) {
          _addToken(Tag.slashEq);
        } else {
          _addToken(Tag.slash);
        }
      case '%':
        _addToken(Tag.percent);
      case '=':
        // `==`/`=>` vs `=`: distinguem-se no 2º char.
        if (_match('=')) {
          _addToken(Tag.eqEq);
        } else if (_match('>')) {
          _addToken(Tag.fatArrow);
        } else {
          _addToken(Tag.eq);
        }
      case '!':
        _addToken(_match('=') ? Tag.bangEq : Tag.bang);
      case '<':
        // `<=`/`<<` antes de `<`.
        if (_match('=')) {
          _addToken(Tag.ltEq);
        } else if (_match('<')) {
          _addToken(Tag.ltLt);
        } else {
          _addToken(Tag.lt);
        }
      case '>':
        // `>=`/`>>` antes de `>`. `>>` = gtGt neutro (não OP_COMPOSE aqui).
        if (_match('=')) {
          _addToken(Tag.gtEq);
        } else if (_match('>')) {
          _addToken(Tag.gtGt);
        } else {
          _addToken(Tag.gt);
        }
      case '&':
        // `&&` antes de `&` (terminal "morto" no parser).
        _addToken(_match('&') ? Tag.ampAmp : Tag.amp);
      case '|':
        if (_match('|')) {
          _addToken(Tag.pipePipe);
        } else if (_match('>')) {
          _addToken(Tag.pipeGt);
        } else {
          _addToken(Tag.pipe);
        }
      case '?':
        // `?.`/`??` antes de `?`.
        if (_match('.')) {
          _addToken(Tag.questionDot);
        } else if (_match('?')) {
          _addToken(Tag.questionQuestion);
        } else {
          _addToken(Tag.question);
        }
      case '.':
        // `..=` antes de `..` antes de `.`.
        if (_match('.')) {
          _addToken(_match('=') ? Tag.dotDotEq : Tag.dotDot);
        } else {
          _addToken(Tag.dot);
        }

      // Strings: `"""` (multiline) vs `""` (vazia) vs `"..."`.
      case '"':
        if (_peek() == '"' && _peekAt(1) == '"') {
          _advance(); // 2º "
          _advance(); // 3º "
          _multilineString();
        } else {
          _string();
        }

      // Números, identificadores, wildcard, closure-shorthand ou erro.
      default:
        if (_isDigit(c)) {
          _number();
        } else if (_isAlpha(c)) {
          _identifier();
        } else if (c == r'$' && _isDigit(_peek())) {
          // $0, $1 — closure shorthand (§2.1) → identifier.
          while (_isDigit(_peek())) {
            _advance();
          }
          _addToken(Tag.identifier);
        } else if (c == '_') {
          if (_isAlphaNumeric(_peek())) {
            _identifier(); // _x, _1, __ → identifier (§2.1a)
          } else {
            _addToken(Tag.underscore); // _ sozinho → wildcard
          }
        } else {
          _error('lex-unexpected-char', detail: c, length: 1);
          _addToken(Tag.invalid);
        }
    }
  }

  // ---------------------------------------------------------------------------
  // Números — INT (dec/hex/bin) + FLOAT, com separador `_` consertado (D4).
  // ---------------------------------------------------------------------------

  void _number() {
    final first = _prev(); // primeiro dígito já consumido pelo _scanToken

    // Hexadecimal: 0x...
    if (first == '0' && (_peek() == 'x' || _peek() == 'X')) {
      _advance(); // x
      if (!_isHexDigit(_peek())) return _malformedNumber(); // 0x sem dígito
      _advance(); // 1º dígito hex
      if (!_consumeDigitRun(_isHexDigit)) return _malformedNumber();
      final digits = _currentLexeme.substring(2).replaceAll('_', '');
      // B1: bem-formado mas fora do Int64 → erro léxico, NÃO crash (int.parse).
      // TODO(spec futura): decidir se hex unsigned-64 vira -1 à la Dart.
      final value = int.tryParse(digits, radix: 16);
      if (value == null) return _integerOverflow();
      _addToken(Tag.intLiteral, literal: value);
      return;
    }

    // Binário: 0b...
    if (first == '0' && (_peek() == 'b' || _peek() == 'B')) {
      _advance(); // b
      if (!_isBinDigit(_peek())) return _malformedNumber(); // 0b sem dígito
      _advance(); // 1º dígito binário
      if (!_consumeDigitRun(_isBinDigit)) return _malformedNumber();
      final digits = _currentLexeme.substring(2).replaceAll('_', '');
      // B1: guarda de overflow (int.tryParse → null quando não cabe em Int64).
      final value = int.tryParse(digits, radix: 2);
      if (value == null) return _integerOverflow();
      _addToken(Tag.intLiteral, literal: value);
      return;
    }

    // Parte inteira decimal (o 1º dígito já veio do _scanToken).
    if (!_consumeDigitRun(_isDigit)) return _malformedNumber();

    // Float? Só se houver `.` seguido de dígito (não `..`, que é range). D6.
    if (_peek() == '.' && _peekAt(1) != '.' && _isDigit(_peekAt(1))) {
      _advance(); // .
      if (!_consumeDigitRun(_isDigit)) return _malformedNumber();
      // Expoente — só existe no ramo com ponto (D6): `1e10` NÃO é float.
      if (_peek() == 'e' || _peek() == 'E') {
        _advance(); // e
        if (_peek() == '+' || _peek() == '-') _advance();
        if (!_isDigit(_peek())) return _malformedNumber(); // 2.0e sem expoente
        // B3: EXPONENT ::= [eE][+-]? [0-9]+ (SEM `_`, ao contrário da mantissa).
        // Run simples de dígitos — a grammar.ebnf é a fonte-da-verdade.
        while (_isDigit(_peek())) {
          _advance();
        }
      }
      final text = _currentLexeme.replaceAll('_', '');
      _addToken(Tag.floatLiteral, literal: double.parse(text));
      return;
    }

    final text = _currentLexeme.replaceAll('_', '');
    // B1: guarda de overflow decimal (`99999999999999999999` → Int64 estoura).
    final value = int.tryParse(text);
    if (value == null) return _integerOverflow();
    _addToken(Tag.intLiteral, literal: value);
  }

  /// Consome a continuação de um run de dígitos com separador `_` (D4).
  ///
  /// Pré-condição: pelo menos 1 dígito válido já foi consumido. Retorna
  /// `false` se encontrar `_` final ou duplo (`_` cujo próximo não é dígito).
  bool _consumeDigitRun(bool Function(String) isDigit) {
    while (true) {
      if (isDigit(_peek())) {
        _advance();
      } else if (_peek() == '_') {
        if (isDigit(_peekAt(1))) {
          _advance(); // consome `_`; a próxima volta consome o dígito
        } else {
          return false; // `_` final ou duplo
        }
      } else {
        return true;
      }
    }
  }

  /// Consome o resto do lexema "numérico-ish" e emite `lex-malformed-number`
  /// + `Tag.invalid` (não-abortante). Onde o oracle crasharia (D3/M5).
  void _malformedNumber() {
    while (_isAlphaNumeric(_peek())) {
      _advance();
    }
    _error('lex-malformed-number', length: _current - _start);
    _addToken(Tag.invalid);
  }

  /// Emite `lex-integer-overflow` + `Tag.invalid` para um literal inteiro
  /// BEM-FORMADO que não cabe em Int64 (ex.: `99999999999999999999`,
  /// `0xFFFFFFFFFFFFFFFF`). Não-abortante (D3/B1): o lexema já foi consumido,
  /// só marcamos o span como inválido para resync — sem crashar (`int.parse`).
  void _integerOverflow() {
    _error(
      'lex-integer-overflow',
      length: _current - _start,
      hint: 'o valor não cabe num inteiro de 64 bits (Int64)',
    );
    _addToken(Tag.invalid);
  }

  // ---------------------------------------------------------------------------
  // Strings — normal (escape + interpolação) e multiline (cru).
  // ---------------------------------------------------------------------------

  void _string() {
    // literal SEMPRE é uma List de partes: texto `String` e interpolações
    // `['expr', source]`. String vazia → `[]` (CA13).
    final parts = <Object>[];
    final buffer = StringBuffer();

    while (!_isAtEnd && _peek() != '"' && _peek() != '\n') {
      if (_peek() == r'\') {
        // B2: captura a posição do `\` ANTES de avançar (span do escape).
        final escLine = _line, escCol = _col, escOffset = _current;
        _advance(); // consome `\`
        final esc = _advance(); // consome o char escapado
        if (esc == '\n') _newline(); // B2: `\`+newline contabiliza a linha
        final resolved = _escapeChar(esc);
        if (resolved == null) {
          // R1: escape desconhecido (`\z`) → erro, NÃO texto cru silencioso.
          // Resync: mantém o char no buffer e segue.
          _error(
            'lex-invalid-escape',
            offset: escOffset,
            length: 2,
            line: escLine,
            col: escCol,
            detail: esc,
            hint: r'escapes válidos: \n \t \r \0 \\ \"',
          );
          buffer.write(esc);
        } else {
          buffer.write(resolved);
        }
      } else if (_peek() == r'$' && _peekAt(1) == '{') {
        // Interpolação "…${expr}…" — rastreia profundidade de `{}`.
        // B4: empurra o texto acumulado SÓ se houver algo (evita segmento vazio
        // espúrio: `"${x}"` → `[['expr','x']]`, não `['', ['expr','x']]`).
        if (buffer.isNotEmpty) parts.add(buffer.toString());
        buffer.clear();
        _advance(); // $
        _advance(); // {
        final expr = StringBuffer();
        var depth = 1;
        while (depth > 0 && !_isAtEnd) {
          final ch = _peek();
          if (ch == '{') depth++;
          if (ch == '}') depth--;
          if (depth > 0) {
            final consumed = _advance();
            if (consumed == '\n') _newline(); // B2: newline dentro de ${…}
            expr.write(consumed);
          } else {
            _advance(); // consome o `}` de fechamento
          }
        }
        parts.add(<String>['expr', expr.toString()]);
      } else {
        final ch = _advance();
        if (ch == '\r') {
          // defensivo: \r isolado não deveria aparecer dentro da string 1-linha
        }
        buffer.write(ch);
      }
    }

    if (_isAtEnd || _peek() == '\n') {
      _error(
        'lex-unterminated-string',
        length: _current - _start,
        hint: 'feche a string com aspas duplas (")',
      );
      _addToken(Tag.invalid);
      return;
    }

    _advance(); // consome o `"` de fechamento
    // Empurra o texto final SÓ se houver algo: string vazia `""` → `[]` (CA13);
    // `"abc"` → `['abc']`; `"hi ${n}!"` → `['hi ', ['expr','n'], '!']` (CA4).
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    _addToken(Tag.stringLiteral, literal: parts);
  }

  void _multilineString() {
    final buffer = StringBuffer();
    while (!_isAtEnd) {
      if (_peek() == '"' && _peekAt(1) == '"' && _peekAt(2) == '"') {
        _advance();
        _advance();
        _advance();
        // Conteúdo cru (sem escape/interpolação — D6).
        _addToken(Tag.multilineString, literal: buffer.toString());
        return;
      }
      final ch = _advance();
      if (ch == '\n') _newline();
      buffer.write(ch);
    }
    _error(
      'lex-unterminated-multiline-string',
      length: _current - _start,
      hint: 'feche com aspas triplas (""")',
    );
    _addToken(Tag.invalid);
  }

  /// Mapeia um escape VÁLIDO para seu char resolvido; `null` se o escape é
  /// desconhecido — quem chama emite `lex-invalid-escape` (R1: sem tolerância a
  /// texto cru silencioso). Conjunto válido = ESCAPE da grammar.ebnf §4.
  String? _escapeChar(String c) => switch (c) {
    'n' => '\n',
    't' => '\t',
    'r' => '\r',
    r'\' => r'\',
    '"' => '"',
    '0' => '\u0000',
    _ => null, // R1: escape desconhecido → erro (não char cru)
  };

  // ---------------------------------------------------------------------------
  // Identificadores e keywords.
  // ---------------------------------------------------------------------------

  void _identifier() {
    while (_isAlphaNumeric(_peek())) {
      _advance();
    }
    final text = _currentLexeme;
    final kw = keywords[text];
    if (kw == null) {
      _addToken(Tag.identifier);
    } else if (kw == Tag.kwTrue) {
      _addToken(kw, literal: true);
    } else if (kw == Tag.kwFalse) {
      _addToken(kw, literal: false);
    } else {
      // `nil` → literal null é indistinguível de "sem literal"; irrelevante
      // para o dump. As demais keywords não têm literal.
      _addToken(kw);
    }
  }

  // ---------------------------------------------------------------------------
  // Comentários — `//` e `/* */` aninhável (contador de profundidade).
  // Capturados em `comments`, NÃO viram tokens (D6).
  // ---------------------------------------------------------------------------

  void _lineComment() {
    final textStart = _current;
    while (!_isAtEnd && _peek() != '\n') {
      _advance();
    }
    comments.add(
      Comment(
        source.substring(textStart, _current).trimRight(),
        _startLine,
        _startCol,
        isBlock: false,
      ),
    );
  }

  void _blockComment() {
    final textStart = _current;
    var depth = 1;
    while (!_isAtEnd && depth > 0) {
      if (_peek() == '/' && _peekAt(1) == '*') {
        _advance();
        _advance();
        depth++;
      } else if (_peek() == '*' && _peekAt(1) == '/') {
        _advance();
        _advance();
        depth--;
      } else {
        // B2: consome-então-newline (mesma ordem do resto do scanner) p/ não
        // furar a coluna do token após um comentário multi-linha.
        final ch = _advance();
        if (ch == '\n') _newline();
      }
    }
    comments.add(
      Comment(
        source.substring(textStart, _current).trimRight(),
        _startLine,
        _startCol,
        isBlock: true,
      ),
    );
    if (depth > 0) {
      _error(
        'lex-unterminated-block-comment',
        length: _current - _start,
        hint: 'feche o bloco com */',
      );
      // B5: emite `Tag.invalid` por simetria de contrato com string/multiline
      // não-terminadas (§2.7) — todo caminho de erro produz um token de resync.
      _addToken(Tag.invalid);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers de leitura.
  // ---------------------------------------------------------------------------

  String _advance() {
    if (_isAtEnd) return '\u0000';
    final c = source[_current];
    _current++;
    _col++;
    return c;
  }

  String _peek() => _isAtEnd ? '\u0000' : source[_current];

  String _peekAt(int ahead) {
    final i = _current + ahead;
    return i >= source.length ? '\u0000' : source[i];
  }

  String _prev() => source[_current - 1];

  bool _match(String expected) {
    if (_isAtEnd || source[_current] != expected) return false;
    _current++;
    _col++;
    return true;
  }

  /// Atualiza `line`/`col` ao cruzar `\n` (whitespace, string multiline ou
  /// comentário). O `_advance` já mexeu no `_col`; aqui corrigimos o layout.
  void _newline() {
    _line++;
    _col = 1;
  }

  bool get _isAtEnd => _current >= source.length;

  String get _currentLexeme => source.substring(_start, _current);

  // ---------------------------------------------------------------------------
  // Classificação de caracteres (ASCII-only — D6).
  // ---------------------------------------------------------------------------

  bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39; // 0-9
  }

  bool _isBinDigit(String c) => c == '0' || c == '1';

  bool _isHexDigit(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 0x30 && u <= 0x39) || // 0-9
        (u >= 0x41 && u <= 0x46) || // A-F
        (u >= 0x61 && u <= 0x66); // a-f
  }

  bool _isAlpha(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || // A-Z
        (u >= 0x61 && u <= 0x7A); // a-z
  }

  bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c) || c == '_';

  // ---------------------------------------------------------------------------
  // Emissão de token / erro.
  // ---------------------------------------------------------------------------

  void _addToken(Tag tag, {Object? literal}) {
    tokens.add(
      Token(
        tag: tag,
        lexeme: _currentLexeme,
        line: _startLine,
        col: _startCol,
        offset: _start,
        length: _current - _start,
        literal: literal,
      ),
    );
  }

  /// Registra um erro léxico. Por padrão o span é o do token atual
  /// (`_start`/`_startLine`/`_startCol`); [offset]/[line]/[col] permitem apontar
  /// um sub-span (ex.: o `\x` de `lex-invalid-escape`, R1).
  void _error(
    String code, {
    int? length,
    String? detail,
    String? hint,
    int? offset,
    int? line,
    int? col,
  }) {
    errors.add(
      LexError(
        code,
        line ?? _startLine,
        col ?? _startCol,
        offset: offset ?? _start,
        length: length ?? (_current - _start),
        detail: detail,
        hint: hint,
      ),
    );
  }
}
