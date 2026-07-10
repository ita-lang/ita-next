// ============================================================================
// driver.dart — Orquestração da CLI `itac` e o dump de tokens da Fase 1.
// ============================================================================
//
// Fase 1 expõe só `itac tokenize <file.tu>`: roda o lexer e imprime UMA linha
// por token no formato `<tag> '<lexeme>' @<line>:<col>` (ex.: `kwLet 'let'
// @1:1`). Erros léxicos vão para stderr no formato kebab-case + `@line:col`.
//
// As funções puras ([tokenizeSource], [tokenDump], [errorDump]) são a API que
// o teste de conformância chama DIRETO (sem subprocess).
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/frontend/lexer/lexer.dart';
import 'package:ita_next_compiler/frontend/lexer/token.dart';

/// Resultado de tokenizar um fonte: tokens + erros coletados + comentários.
class TokenizeResult {
  final List<Token> tokens;
  final List<LexError> errors;
  final List<Comment> comments;

  const TokenizeResult(this.tokens, this.errors, this.comments);
}

/// Roda o lexer sobre [source] e devolve tokens/erros/comentários.
TokenizeResult tokenizeSource(String source) {
  final lexer = Lexer(source);
  lexer.scanTokens();
  return TokenizeResult(lexer.tokens, lexer.errors, lexer.comments);
}

/// Escapa os controles de whitespace para manter UMA linha por token no dump
/// (relevante para `multilineString`, cujo lexema cru contém `\n`).
String displayLexeme(String lexeme) => lexeme
    .replaceAll('\\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('\t', r'\t');

/// Formata um único token: `<tag> '<lexeme>' @<line>:<col>`.
String formatToken(Token t) =>
    "${t.tag.name} '${displayLexeme(t.lexeme)}' @${t.line}:${t.col}";

/// Dump completo: uma linha por token (inclusive `eof '' @L:C`).
String tokenDump(List<Token> tokens) => tokens.map(formatToken).join('\n');

/// Dump de erros: uma linha por erro (`<code>[ '<detail>'] @<line>:<col>`).
String errorDump(List<LexError> errors) =>
    errors.map((e) => e.format()).join('\n');

/// Executa `itac tokenize <file.tu>`.
///
/// Retorna o código de saída do processo: `0` ok, `65` erro léxico coletado,
/// `64` uso incorreto, `66` arquivo não encontrado.
int runTokenize(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  if (args.isEmpty) {
    stderrSink.writeln('itac tokenize: falta <file.tu>');
    return 64;
  }
  final path = args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderrSink.writeln('itac tokenize: arquivo não encontrado: $path');
    return 66;
  }

  final result = tokenizeSource(file.readAsStringSync());
  stdoutSink.writeln(tokenDump(result.tokens));
  for (final e in result.errors) {
    stderrSink.writeln(e.format());
  }
  return result.errors.isEmpty ? 0 : 65;
}
