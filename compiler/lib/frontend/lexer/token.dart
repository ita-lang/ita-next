// ============================================================================
// token.dart — Categorias de token (Tag) e a unidade Token do léxico do Itá.
// ============================================================================
//
// Fase 1 da reescrita horizontal (ita-next). Fonte normativa: `GRAMMAR.md` §1
// do `ita/` + a spec `003-lexer-scaffold`. O `enum Tag` é LIMPO (D1): contém
// SÓ o que o lexer emite — sem `newline`, sem `gsx*`, sem `at`-token (o `@` é
// erro), sem `kwLeft`/`kwRight` (contextuais → identifier) e sem as keywords
// mortas (`const unsafe effect signal state`). São 40 keywords vivas: as 36
// reservadas do `GRAMMAR.md` §1 + 4 vivas de declaração (`static init
// override precedence`).
//
// Referência de implementação (ADR-0009): Crafting Interpreters, cap. 4
// (scanning.md). Um token que nunca é produzido é dívida (P4, "sem mágica").
// ============================================================================

/// Todas as categorias de token EMITIDAS pelo lexer do Itá.
///
/// Nada aqui é "dead code": cada valor é produzido em algum caminho do
/// scanner. Os terminais "mortos" no parser (`hash amp pipe caret ltLt`)
/// continuam presentes — o léxico é completo; filtrar é papel de fases
/// posteriores (§2.5 da spec).
enum Tag {
  // ---------------------------------------------------------------------------
  // Literais — valores escritos diretamente no código.
  // ---------------------------------------------------------------------------
  intLiteral, // 42, 0xFF, 0b1010, 1_000
  floatLiteral, // 3.14, 2.0e10
  stringLiteral, // "hello", "hi ${name}!"
  multilineString, // """..."""
  identifier, // myVar, Point, from, _x, $0
  // ---------------------------------------------------------------------------
  // Keywords reservadas (40) — reconhecidas via `keywords` após o maximal
  // munch do identificador. As 36 do GRAMMAR.md §1 + 4 vivas de declaração.
  // ---------------------------------------------------------------------------
  kwPub, // pub
  kwFn, // fn
  kwAsync, // async
  kwStream, // stream
  kwActor, // actor
  kwStruct, // struct
  kwClass, // class
  kwEnum, // enum
  kwTrait, // trait
  kwImpl, // impl
  kwExtension, // extension
  kwImport, // import
  kwOperator, // operator
  kwLet, // let
  kwVar, // var
  kwReturn, // return
  kwIf, // if
  kwElse, // else
  kwGuard, // guard
  kwWhile, // while
  kwFor, // for
  kwAwait, // await
  kwIn, // in
  kwMatch, // match
  kwSelf, // self
  kwMut, // mut
  kwWhere, // where
  kwEmit, // emit
  kwSpawn, // spawn
  kwPanic, // panic
  kwBreak, // break
  kwContinue, // continue
  kwTrue, // true
  kwFalse, // false
  kwNil, // nil
  kwAs, // as
  kwStatic, // static  — factory/método de tipo (viva de declaração)
  kwInit, // init    — construtor (viva de declaração)
  kwOverride, // override — sobrescrita (viva de declaração)
  kwPrecedence, // precedence — precedência de operador (viva de declaração)
  // ---------------------------------------------------------------------------
  // Operadores — maximal munch (o mais longo vence).
  // ---------------------------------------------------------------------------
  // Aritméticos
  plus, // +
  minus, // -
  star, // *
  slash, // /
  percent, // %
  starStar, // **
  // Atribuição
  eq, // =
  plusEq, // +=
  minusEq, // -=
  starEq, // *=
  slashEq, // /=
  // Comparação
  eqEq, // ==
  bangEq, // !=
  lt, // <
  gt, // >
  ltEq, // <=
  gtEq, // >=
  // Lógicos
  ampAmp, // &&
  pipePipe, // ||
  bang, // !
  // Bit-a-bit / terminais "mortos" no parser, mas tokenizados (§2.5, D5)
  amp, // &
  pipe, // |
  caret, // ^
  tilde, // ~
  ltLt, // <<
  gtGt, // >>  (neutro no léxico; o parser é quem decide shift vs compose)
  // Funcionais
  pipeGt, // |>
  // Setas
  arrow, // ->
  fatArrow, // =>
  // Range
  dotDot, // ..
  dotDotEq, // ..=
  // Opcionais
  questionDot, // ?.
  questionQuestion, // ??
  question, // ?
  // ---------------------------------------------------------------------------
  // Pontuação e delimitadores.
  // ---------------------------------------------------------------------------
  lparen, // (
  rparen, // )
  lbrace, // {
  rbrace, // }
  lbracket, // [
  rbracket, // ]
  comma, // ,
  colon, // :
  semicolon, // ;
  dot, // .
  hash, // #  (terminal "morto" no parser, mas tokenizado — §2.5, D5)
  underscore, // _  (wildcard de pattern/lambda; sozinho, sem sufixo)
  // ---------------------------------------------------------------------------
  // Especiais.
  // ---------------------------------------------------------------------------
  eof, // fim do arquivo
  invalid, // token inválido (erro léxico, para resync — D3)
}

// =============================================================================
// Token — unidade atômica do código fonte (D2).
// =============================================================================

/// Um único token produzido pelo [Lexer].
///
/// Além de [tag]/[lexeme]/[line]/[col], o token carrega o **span real** no
/// fonte ([offset]+[length]) — melhoria sobre o `ita/`, que só tinha
/// `line`/`col` e por isso reportava spans de erro quase sempre `length=1`
/// e recomputava o `fileOffset` no codegen (D2).
///
/// [literal] é o valor pré-computado dos literais:
/// - `intLiteral`  → `int` (dec/hex/bin, sem os `_`);
/// - `floatLiteral`→ `double`;
/// - `stringLiteral`→ `List<Object>` de partes (texto `String` e interpolações
///    `['expr', source]`); string vazia → `[]`;
/// - `multilineString`→ `String` cru (sem escape/interpolação — D6);
/// - `kwTrue`/`kwFalse`→ `bool`; `kwNil`→ `null` (com literal ausente marcado).
class Token {
  final Tag tag;
  final String lexeme;
  final int line;
  final int col;
  final int offset;
  final int length;
  final Object? literal;

  const Token({
    required this.tag,
    required this.lexeme,
    required this.line,
    required this.col,
    required this.offset,
    required this.length,
    this.literal,
  });

  @override
  String toString() {
    final lit = literal != null ? ' =$literal' : '';
    return '${tag.name}[$line:$col] "$lexeme"$lit';
  }
}

// =============================================================================
// keywords — mapa de palavras reservadas vivas (40).
// =============================================================================

/// Converte um identificador já escaneado na sua [Tag] de keyword, se houver.
///
/// Contém APENAS as 40 keywords vivas. As contextuais (`from left right all
/// race`) NÃO estão aqui de propósito: tokenizam como `identifier` e só ganham
/// significado no parser (D1). As keywords mortas (`const unsafe effect signal
/// state`) foram removidas.
const Map<String, Tag> keywords = {
  // 36 reservadas (GRAMMAR.md §1)
  'pub': Tag.kwPub,
  'fn': Tag.kwFn,
  'async': Tag.kwAsync,
  'stream': Tag.kwStream,
  'actor': Tag.kwActor,
  'struct': Tag.kwStruct,
  'class': Tag.kwClass,
  'enum': Tag.kwEnum,
  'trait': Tag.kwTrait,
  'impl': Tag.kwImpl,
  'extension': Tag.kwExtension,
  'import': Tag.kwImport,
  'operator': Tag.kwOperator,
  'let': Tag.kwLet,
  'var': Tag.kwVar,
  'return': Tag.kwReturn,
  'if': Tag.kwIf,
  'else': Tag.kwElse,
  'guard': Tag.kwGuard,
  'while': Tag.kwWhile,
  'for': Tag.kwFor,
  'await': Tag.kwAwait,
  'in': Tag.kwIn,
  'match': Tag.kwMatch,
  'self': Tag.kwSelf,
  'mut': Tag.kwMut,
  'where': Tag.kwWhere,
  'emit': Tag.kwEmit,
  'spawn': Tag.kwSpawn,
  'panic': Tag.kwPanic,
  'break': Tag.kwBreak,
  'continue': Tag.kwContinue,
  'true': Tag.kwTrue,
  'false': Tag.kwFalse,
  'nil': Tag.kwNil,
  'as': Tag.kwAs,
  // 4 vivas de declaração
  'static': Tag.kwStatic,
  'init': Tag.kwInit,
  'override': Tag.kwOverride,
  'precedence': Tag.kwPrecedence,
};
