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

import 'package:ita_next_compiler/frontend/binding/resolver.dart';
import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/desugar/desugar.dart';
import 'package:ita_next_compiler/frontend/lexer/lexer.dart';
import 'package:ita_next_compiler/frontend/lexer/token.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:ita_next_compiler/frontend/parser/ast_printer.dart';
import 'package:ita_next_compiler/frontend/parser/parser.dart';
import 'package:ita_next_compiler/frontend/semantic/collect.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

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

// =============================================================================
// Fase 2 — parsing (`itac parse`). Funções puras chamadas DIRETO pelo teste
// de conformância (sem subprocess), espelho da Fase 1.
// =============================================================================

/// Roda o lexer + parser sobre [source] e devolve a AST + os erros das DUAS
/// fases. Os léxicos vêm do lexer principal e dos sub-lexers de interpolação
/// (`Parser.lexErrors`), ordenados por posição no fonte — antes eram
/// descartados aqui, e `parse`/`desugar`/`resolve` jamais mostravam um erro
/// léxico: o usuário via só o `parse-error` derivado do `Tag.invalid`.
ParseResult parseSource(String source) {
  final lexed = tokenizeSource(source);
  final parser = Parser(lexed.tokens, sourceLength: source.length);
  final program = parser.parseProgram();
  final lexErrors = [...lexed.errors, ...parser.lexErrors]
    ..sort((a, b) => a.offset.compareTo(b.offset));
  return ParseResult(program, parser.errors, lexErrors: lexErrors);
}

/// Dump S-expression determinístico da AST (`--dump`). [spans] anexa `@off+len`.
String parseDump(Program program, {bool spans = false}) =>
    AstDumper(spans: spans).dump(program);

/// Dump de erros de parse: uma linha por erro (`parse-error: <code> @off+len`).
String parseErrorDump(List<ParseError> errors) =>
    errors.map((e) => e.format()).join('\n');

/// Preâmbulo comum de `parse`/`desugar`/`resolve`: lê as flags, valida o
/// argumento, abre o arquivo e parseia. Devolve o parse OU o exit-code do
/// problema de USO (`64` falta arquivo, `66` não encontrado) — os erros de
/// PARSE seguem no `ParseResult`, porque cada comando decide o que fazer com
/// eles (`parse` reporta e segue; `desugar`/`resolve` abortam).
({ParseResult? parsed, bool dump, bool spans, int? code}) _readAndParse(
  String command,
  List<String> args,
  StringSink err,
) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final dump = args.contains('--dump');
  final spans = args.contains('--spans');

  if (positional.isEmpty) {
    err.writeln('itac $command: falta <file.tu>');
    return (parsed: null, dump: dump, spans: spans, code: 64);
  }
  final path = positional.first;
  final file = File(path);
  if (!file.existsSync()) {
    err.writeln('itac $command: arquivo não encontrado: $path');
    return (parsed: null, dump: dump, spans: spans, code: 66);
  }
  return (
    parsed: parseSource(file.readAsStringSync()),
    dump: dump,
    spans: spans,
    code: null,
  );
}

/// Reporta os erros das Fases 1-2 na ordem das fases (léxicos primeiro — são a
/// causa; um `parse-error` derivado de `Tag.invalid` nem chega aqui, o parser
/// não o reporta).
void _reportFrontErrors(ParseResult result, StringSink err) {
  for (final e in result.lexErrors) {
    err.writeln(e.format());
  }
  for (final e in result.errors) {
    err.writeln(e.format());
  }
}

/// Reporta os erros de Fase 1-2 e devolve `65`; `null` se o fonte veio limpo.
/// As Fases 3/4 pressupõem árvore bem-formada da Fase 2, então abortam aqui —
/// inclusive por erro LÉXICO: um `Tag.invalid` já envenenou a árvore.
int? _abortOnFrontErrors(ParseResult result, StringSink err) {
  if (!result.hasErrors) return null;
  _reportFrontErrors(result, err);
  return 65;
}

/// Executa `itac parse <file.tu> [--dump] [--spans]`.
///
/// Retorna: `0` ok, `65` erro de parse coletado, `64` uso incorreto, `66`
/// arquivo não encontrado.
int runParse(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final cli = _readAndParse('parse', args, stderrSink);
  if (cli.code != null) return cli.code!;
  final result = cli.parsed!;

  // `parse` NÃO aborta: dumpa a árvore (com os nós de erro enxertados — M2) e
  // só então reporta. É o observável da recuperação (D1/D3).
  if (cli.dump) stdoutSink.writeln(parseDump(result.program, spans: cli.spans));
  _reportFrontErrors(result, stderrSink);
  return result.hasErrors ? 65 : 0;
}

// =============================================================================
// Fase 3 — desugaring (`itac desugar`). Funções puras chamadas DIRETO pelo teste
// de conformância (sem subprocess), espelho das Fases 1–2.
// =============================================================================

/// Dump S-expression da AST CANÔNICA (`desugar --dump`): parse → desugar →
/// `AstDumper`. Espelho de [parseDump] — a Fase 3 reusa o MESMO printer (o único
/// observável da árvore), só troca a árvore de entrada.
String desugarDump(Program program, {bool spans = false}) =>
    AstDumper(spans: spans).dump(desugarProgram(program));

/// Executa `itac desugar <file.tu> [--dump] [--spans]`.
///
/// Retorna: `0` ok, `65` erro de parse coletado, `64` uso incorreto, `66`
/// arquivo não encontrado. (Erros de parse abortam antes do desugar — a Fase 3
/// pressupõe uma árvore bem-formada da Fase 2.)
int runDesugar(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final cli = _readAndParse('desugar', args, stderrSink);
  if (cli.code != null) return cli.code!;
  final result = cli.parsed!;

  final aborted = _abortOnFrontErrors(result, stderrSink);
  if (aborted != null) return aborted;

  if (cli.dump) {
    stdoutSink.writeln(desugarDump(result.program, spans: cli.spans));
  }
  return 0;
}

// =============================================================================
// Fase 4 — binding / resolução de nomes (`itac resolve`). Pipeline parse →
// desugar → bind. Funções puras chamadas DIRETO pelo teste de conformância.
// =============================================================================

/// Resolve um programa BRUTO (Fase 2): desaçucara (Fase 3) e liga os nomes
/// (Fase 4). Devolve a árvore canônica + a side-table + os erros de binding.
ResolveResult resolveProgram(Program program) {
  final canonical = desugarProgram(program);
  final resolver = Resolver()..run(canonical);
  return ResolveResult(canonical, resolver.resolution, resolver.errors);
}

/// Dump S-expression da AST canônica ANOTADA (`resolve --dump`): cada
/// `Ident`/`SelfExpr` ganha a resolução (`->L…^h[*]` / `->T…` / `->S…` / `->?`)
/// como último filho. Reusa o `AstDumper` via callback [AstDumper.annotate] — a
/// forma da árvore é idêntica ao `desugar --dump`, só os nomes ganham o alvo.
///
/// Recebe o [res] pronto (não um `Program`): quem dumpa em geral também quer os
/// erros, e resolver por dentro obrigaria a resolver DUAS vezes — era por isso
/// que o driver reinlinava o `annotate` + `AstDumper` em vez de chamar aqui.
String resolveDump(ResolveResult res, {bool spans = false}) {
  String annotate(AstNode node) => formatResolution(res.resolution[node]);
  return AstDumper(spans: spans, annotate: annotate).dump(res.program);
}

/// Dump de erros de binding: uma linha por erro
/// (`resolve-error: <code> @<off>+<len>`).
String resolveErrorDump(List<BindingError> errors) =>
    errors.map((e) => e.format()).join('\n');

/// Executa `itac resolve <file.tu> [--dump] [--spans]`.
///
/// Retorna: `0` ok, `65` erro de parse OU de binding coletado, `64` uso
/// incorreto, `66` arquivo não encontrado. (Erros de parse abortam antes do
/// desugar/bind — a Fase 4 pressupõe uma árvore bem-formada.)
int runResolve(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final cli = _readAndParse('resolve', args, stderrSink);
  if (cli.code != null) return cli.code!;
  final parsed = cli.parsed!;

  final aborted = _abortOnFrontErrors(parsed, stderrSink);
  if (aborted != null) return aborted;

  final res = resolveProgram(parsed.program);
  if (cli.dump) stdoutSink.writeln(resolveDump(res, spans: cli.spans));
  for (final e in res.errors) {
    stderrSink.writeln(e.format());
  }
  return res.errors.isEmpty ? 0 : 65;
}

// =============================================================================
// Fase 5 — semântica/tipos (`itac check`). Spec 009. Funções puras chamadas
// DIRETO pelo teste de conformância, espelho das Fases 1–4.
// =============================================================================

/// Checa um programa BRUTO (Fase 2): desaçucara (F3), liga os nomes (F4) e roda
/// a semântica (F5). **Fatia A** (Collect) por ora — B (check) e D (unificação)
/// entram nas fatias seguintes (spec 009 §5.4).
CheckResult checkProgram(Program program) {
  final resolved = resolveProgram(program);
  // A F5 CONSOME a resolução da F4 e não reconstrói escopo (contrato ADR-0011).
  // Erro de binding aborta antes: tipar nome não-resolvido é cascata.
  if (resolved.errors.isNotEmpty) {
    return CheckResult(
      resolved.program,
      TypeTable(),
      [
        for (final e in resolved.errors)
          CheckError('unresolved-before-check', e.offset, e.length),
      ],
      const {},
    );
  }
  return collectTypes(resolved.program);
}

/// Dump da tabela de tipos (`check --dump-types`) — o observável da fatia A.
String typeTableDump(CheckResult res) => res.types.dump();

/// Dump de erros da F5: uma linha por erro (`check-error: <code> @<off>+<len>`).
String checkErrorDump(List<CheckError> errors) =>
    errors.map((e) => e.format()).join('\n');

/// Executa `itac check <file.tu> [--dump-types]`.
///
/// Retorna: `0` ok, `65` erro (léxico/parse/binding/tipo), `64` uso incorreto,
/// `66` arquivo não encontrado.
int runCheck(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final cli = _readAndParse('check', args, stderrSink);
  if (cli.code != null) return cli.code!;
  final parsed = cli.parsed!;

  final aborted = _abortOnFrontErrors(parsed, stderrSink);
  if (aborted != null) return aborted;

  final res = checkProgram(parsed.program);
  if (args.contains('--dump-types')) stdoutSink.writeln(typeTableDump(res));
  for (final e in res.errors) {
    stderrSink.writeln(e.format());
  }
  return res.hasErrors ? 65 : 0;
}
