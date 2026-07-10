// ============================================================================
// lexer_test.dart — Testes do léxico do ita-next (Fase 1).
// ============================================================================
//
// Dois blocos:
//  1. Asserts diretos de tokenização (tags, lexemas, literais, spans, erros) —
//     cobrindo CA1–CA16 e CA9a–CA9f + as bordas de D4/D6. (O `test_lexer.dart`
//     do `ita/` NÃO tinha asserts.)
//  2. Conformância: itera sobre `conformance/valid|invalid/*.tu`, roda o dump
//     via a função do driver (sem subprocess) e compara com os goldens
//     `.tokens`/`.errors`.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/lexer/token.dart';
import 'package:test/test.dart';

TokenizeResult run(String src) => tokenizeSource(src);
List<Tag> tagsOf(String src) => run(src).tokens.map((t) => t.tag).toList();
List<String> lexemesOf(String src) =>
    run(src).tokens.map((t) => t.lexeme).toList();
List<String> errorCodes(String src) =>
    run(src).errors.map((e) => e.code).toList();

void main() {
  // --------------------------------------------------------------------------
  group('CA1 — keywords + identificadores', () {
    test('let x = fn', () {
      expect(tagsOf('let x = fn'), [
        Tag.kwLet,
        Tag.identifier,
        Tag.eq,
        Tag.kwFn,
        Tag.eof,
      ]);
      expect(lexemesOf('let x = fn'), ['let', 'x', '=', 'fn', '']);
    });

    test('todas as 40 keywords vivas mapeiam para kw*', () {
      expect(keywords.length, 40);
      expect(tagsOf('static init override precedence').take(4), [
        Tag.kwStatic,
        Tag.kwInit,
        Tag.kwOverride,
        Tag.kwPrecedence,
      ]);
    });
  });

  group('CA1b — contextuais tokenizam como identifier (D1)', () {
    test('from all race', () {
      expect(tagsOf('from all race'), [
        Tag.identifier,
        Tag.identifier,
        Tag.identifier,
        Tag.eof,
      ]);
    });
    test('left right (contextuais de operator)', () {
      expect(tagsOf('left right'), [Tag.identifier, Tag.identifier, Tag.eof]);
    });
  });

  group('CA2 — INT nas 3 bases + separador `_` consertado (D4)', () {
    test('42 0xFF 0b1010 1_000 — quatro intLiteral', () {
      expect(tagsOf('42 0xFF 0b1010 1_000'), [
        Tag.intLiteral,
        Tag.intLiteral,
        Tag.intLiteral,
        Tag.intLiteral,
        Tag.eof,
      ]);
    });

    test('literais pré-computados (radix; `_` removido)', () {
      final toks = run('42 0xFF 0b1010 1_000').tokens;
      expect(toks[0].literal, 42);
      expect(toks[1].literal, 0xFF); // 255
      expect(toks[2].literal, 10); // 0b1010
      expect(toks[3].literal, 1000); // 1_000
    });

    test(
      'DIVERGÊNCIA vs ita/: `1_000` é UM token (o ita/ daria `1`+`_000`)',
      () {
        final toks = run('1_000').tokens;
        expect(toks.length, 2); // intLiteral + eof
        expect(toks[0].tag, Tag.intLiteral);
        expect(toks[0].lexeme, '1_000');
        expect(toks[0].literal, 1000);
      },
    );

    test('`_` entre dígitos em hex/bin/float', () {
      expect(run('0xFF_FF').tokens[0].literal, 0xFFFF);
      expect(run('0b1010_0101').tokens[0].literal, 0xA5);
      expect(run('3.141_59').tokens[0].literal, closeTo(3.14159, 1e-9));
    });
  });

  group('CA3 — FLOAT (expoente só no ramo com ponto — D6)', () {
    test('3.14 2.0e10', () {
      expect(tagsOf('3.14 2.0e10'), [
        Tag.floatLiteral,
        Tag.floatLiteral,
        Tag.eof,
      ]);
      final toks = run('3.14 2.0e10').tokens;
      expect(toks[0].literal, closeTo(3.14, 1e-9));
      expect(toks[1].literal, closeTo(2.0e10, 1e-3));
    });

    test('CA3b — `1.` NÃO é float: intLiteral + dot', () {
      expect(tagsOf('1.'), [Tag.intLiteral, Tag.dot, Tag.eof]);
      expect(run('1.').tokens[0].literal, 1);
    });

    test('D6 — `1e10` sem ponto NÃO é float', () {
      expect(tagsOf('1e10'), [Tag.intLiteral, Tag.identifier, Tag.eof]);
    });

    test('D6 — `.5` NÃO é float: dot + intLiteral', () {
      expect(tagsOf('.5'), [Tag.dot, Tag.intLiteral, Tag.eof]);
    });
  });

  group('CA4 — STRING com interpolação (literal = List de partes)', () {
    test('"hi \${name}!"', () {
      final toks = run(r'"hi ${name}!"').tokens;
      expect(toks[0].tag, Tag.stringLiteral);
      expect(toks[0].literal, [
        'hi ',
        ['expr', 'name'],
        '!',
      ]);
    });

    test('escapes \\n \\t são resolvidos no texto', () {
      final lit = run(r'"a\nb"').tokens[0].literal as List;
      expect(lit, ['a\nb']);
    });
  });

  group('CA5 — MULTILINE_STRING (cru; `\${}` não interpola — D6)', () {
    test('""" a / b """ preserva o conteúdo cru', () {
      final toks = run('"""a\nb"""').tokens;
      expect(toks[0].tag, Tag.multilineString);
      expect(toks[0].literal, 'a\nb');
    });

    test('`\${x}` dentro de multiline NÃO interpola (fica literal)', () {
      final toks = run(r'"""x ${y} z"""').tokens;
      expect(toks[0].tag, Tag.multilineString);
      expect(toks[0].literal, r'x ${y} z');
    });
  });

  group('CA6 — comentário de bloco aninhado (depth)', () {
    test('/* a /* b */ c */ z → só identifier z', () {
      final r = run('/* a /* b */ c */ z');
      expect(r.tokens.map((t) => t.tag), [Tag.identifier, Tag.eof]);
      expect(r.tokens.first.lexeme, 'z');
      expect(r.comments.length, 1);
      expect(r.comments.first.isBlock, isTrue);
      expect(r.errors, isEmpty);
    });
  });

  group('CA7 — maximal munch (mais longo primeiro)', () {
    test('>> > <= < ..= .. != !', () {
      expect(tagsOf('>> > <= < ..= .. != !'), [
        Tag.gtGt,
        Tag.gt,
        Tag.ltEq,
        Tag.lt,
        Tag.dotDotEq,
        Tag.dotDot,
        Tag.bangEq,
        Tag.bang,
        Tag.eof,
      ]);
    });

    test('setas e compostos: -> -= == => ?. ?? |> **', () {
      expect(tagsOf('-> -= == => ?. ?? |> **'), [
        Tag.arrow,
        Tag.minusEq,
        Tag.eqEq,
        Tag.fatArrow,
        Tag.questionDot,
        Tag.questionQuestion,
        Tag.pipeGt,
        Tag.starStar,
        Tag.eof,
      ]);
    });
  });

  group('CA8 — terminais "mortos" são tokenizados (D5)', () {
    test('& | ^ << → amp pipe caret ltLt (não erro)', () {
      final r = run('& | ^ <<');
      expect(r.tokens.map((t) => t.tag), [
        Tag.amp,
        Tag.pipe,
        Tag.caret,
        Tag.ltLt,
        Tag.eof,
      ]);
      expect(r.errors, isEmpty);
    });
    test('# e ~ também tokenizam (hash, tilde)', () {
      expect(tagsOf('# ~'), [Tag.hash, Tag.tilde, Tag.eof]);
    });
  });

  group('CA11 — keyword viva de declaração', () {
    test('static fn f()', () {
      expect(tagsOf('static fn f()'), [
        Tag.kwStatic,
        Tag.kwFn,
        Tag.identifier,
        Tag.lparen,
        Tag.rparen,
        Tag.eof,
      ]);
    });
  });

  group('CA12/CA13/CA14/CA15/CA16 — bordas', () {
    test('CA12 — comentário de linha `//` é ignorado', () {
      final r = run('// oi\nx');
      expect(r.tokens.map((t) => t.tag), [Tag.identifier, Tag.eof]);
      expect(r.tokens.first.line, 2);
      expect(r.comments.length, 1);
      expect(r.comments.first.isBlock, isFalse);
    });

    test('CA13 — string vazia `""` → literal []', () {
      final toks = run('""').tokens;
      expect(toks[0].tag, Tag.stringLiteral);
      expect(toks[0].literal, isEmpty);
    });

    test('CA14 — `_` sozinho → underscore; `_x` → identifier', () {
      expect(tagsOf('_ _x'), [Tag.underscore, Tag.identifier, Tag.eof]);
      expect(run('_ _x').tokens[1].lexeme, '_x');
      // `_1` (sufixo) também é identifier (§2.1a)
      expect(tagsOf('_1'), [Tag.identifier, Tag.eof]);
    });

    test('CA15 — `\$0 \$1` → identifier (closure shorthand)', () {
      final r = run(r'$0 $1');
      expect(r.tokens.map((t) => t.tag), [
        Tag.identifier,
        Tag.identifier,
        Tag.eof,
      ]);
      expect(r.tokens.map((t) => t.lexeme).take(2), [r'$0', r'$1']);
    });

    test('CA16 — quebra de linha NÃO é token; incrementa line', () {
      final toks = run('a\nb').tokens;
      expect(toks[0].line, 1);
      expect(toks[0].col, 1);
      expect(toks[1].line, 2);
      expect(toks[1].col, 1);
      // nenhum token de newline emitido
      expect(toks.map((t) => t.tag), [Tag.identifier, Tag.identifier, Tag.eof]);
    });
  });

  group('D2 — spans reais (offset + length)', () {
    test('offsets e comprimentos batem com o fonte', () {
      final toks = run('let x').tokens;
      expect(toks[0].offset, 0);
      expect(toks[0].length, 3); // "let"
      expect(toks[1].offset, 4);
      expect(toks[1].length, 1); // "x"
    });
  });

  group('CA9 — erros léxicos EN kebab-case, NÃO-ABORTANTES (D3)', () {
    test('CA9a — `@` proibido, segue tokenizando', () {
      final r = run('let x @ y');
      expect(r.errors.map((e) => e.code), ['lex-annotation-unsupported']);
      expect(r.errors.first.line, 1);
      expect(r.errors.first.col, 7);
      // resync: `y` ainda é tokenizado
      expect(
        r.tokens.any((t) => t.tag == Tag.identifier && t.lexeme == 'y'),
        isTrue,
      );
    });

    test('CA9b — string não terminada', () {
      final r = run('"abc');
      expect(r.errors.map((e) => e.code), ['lex-unterminated-string']);
      expect(r.errors.first.col, 1);
    });

    test('CA9c — comentário de bloco não terminado', () {
      final r = run('/* aberto');
      expect(r.errors.map((e) => e.code), ['lex-unterminated-block-comment']);
    });

    test('CA9d — caractere inesperado (coleta, não aborta)', () {
      final r = run('let ~x = §');
      expect(r.errors.map((e) => e.code), ['lex-unexpected-char']);
      expect(r.errors.first.detail, '§');
      expect(r.errors.first.col, 10);
      // `~` é tilde (token válido), não erro
      expect(r.tokens.any((t) => t.tag == Tag.tilde), isTrue);
    });

    test('CA9e — números mal-formados NÃO crasham (coleta 4)', () {
      final r = run('0x\n0b\n2.0e\n1__0');
      expect(
        r.errors.map((e) => e.code),
        List.filled(4, 'lex-malformed-number'),
      );
      expect(r.errors.map((e) => e.line), [1, 2, 3, 4]);
    });

    test('CA9e — bordas do separador `_`: `1_` e `0xFF_` são malformed', () {
      expect(errorCodes('1_'), ['lex-malformed-number']);
      expect(errorCodes('0xFF_'), ['lex-malformed-number']);
      expect(errorCodes('0b'), ['lex-malformed-number']);
      expect(errorCodes('2.0e'), ['lex-malformed-number']);
    });

    test('CA9f — multiline não terminada', () {
      final r = run('"""abc');
      expect(r.errors.map((e) => e.code), [
        'lex-unterminated-multiline-string',
      ]);
    });

    test('coleta MÚLTIPLOS erros num só passe', () {
      final r = run('@ @ §');
      expect(r.errors.length, 3);
    });
  });

  // --------------------------------------------------------------------------
  // Revisão W3 — correções B1/B2/B4/R1 (bugs dos 3 especialistas).
  // --------------------------------------------------------------------------
  group('W3/B1 — int fora do Int64 NÃO crasha (lex-integer-overflow)', () {
    test('decimal > 2^63-1 → invalid + erro, sem crash', () {
      final r = run('99999999999999999999');
      expect(r.errors.map((e) => e.code), ['lex-integer-overflow']);
      expect(r.tokens.map((t) => t.tag), [Tag.invalid, Tag.eof]);
    });

    test('hex unsigned-64 (0xFFFFFFFFFFFFFFFF) também é overflow', () {
      final r = run('0xFFFFFFFFFFFFFFFF');
      expect(r.errors.map((e) => e.code), ['lex-integer-overflow']);
      expect(r.tokens.first.tag, Tag.invalid);
    });

    test('hex de 65 bits (0x1FFFFFFFFFFFFFFFF) é overflow', () {
      expect(errorCodes('0x1FFFFFFFFFFFFFFFF'), ['lex-integer-overflow']);
    });

    test('binário de 65 bits é overflow', () {
      final bin = '0b1${'0' * 64}'; // 2^64
      expect(errorCodes(bin), ['lex-integer-overflow']);
    });

    test('Int64 max (9223372036854775807) segue intLiteral válido', () {
      final r = run('9223372036854775807');
      expect(r.errors, isEmpty);
      expect(r.tokens.first.tag, Tag.intLiteral);
      expect(r.tokens.first.literal, 9223372036854775807);
    });

    test('overflow é NÃO-ABORTANTE: segue tokenizando', () {
      final r = run('99999999999999999999 + x');
      expect(r.errors.map((e) => e.code), ['lex-integer-overflow']);
      expect(r.tokens.map((t) => t.tag), [
        Tag.invalid,
        Tag.plus,
        Tag.identifier,
        Tag.eof,
      ]);
    });
  });

  group('W3/B2 — `\\n` engolido incrementa a linha', () {
    test('newline dentro de \${…} → token seguinte na linha certa', () {
      final r = run('"x \${a\nb} y"\nz');
      final z = r.tokens.firstWhere((t) => t.lexeme == 'z');
      expect(z.line, 3); // \n do ${…} + \n físico contam
      expect(z.col, 1);
      expect(r.errors, isEmpty);
    });

    test('`\\`+newline conta a linha (além de ser escape inválido, R1)', () {
      final r = run('"a\\\nb"\nc');
      final c = r.tokens.firstWhere((t) => t.lexeme == 'c');
      expect(c.line, 3);
    });
  });

  group('W3/B4 — sem segmento vazio espúrio na interpolação', () {
    test(r'"${x}" → [[expr, x]] (sem "" na frente)', () {
      final lit = run(r'"${x}"').tokens[0].literal as List;
      expect(lit, [
        ['expr', 'x'],
      ]);
    });

    test(r'"${a}${b}" → duas interpolações, nada entre elas', () {
      final lit = run(r'"${a}${b}"').tokens[0].literal as List;
      expect(lit, [
        ['expr', 'a'],
        ['expr', 'b'],
      ]);
    });
  });

  group('W3/R1 — escape desconhecido é ERRO (lex-invalid-escape)', () {
    test(r'"a\zb" → lex-invalid-escape no span do \z, com resync', () {
      final r = run(r'"a\zb"');
      expect(r.errors.map((e) => e.code), ['lex-invalid-escape']);
      expect(r.errors.first.line, 1);
      expect(r.errors.first.col, 3); // posição do `\`
      // resync: a string ainda é produzida, char cru mantido (azb)
      expect(r.tokens.first.tag, Tag.stringLiteral);
      expect(r.tokens.first.literal, ['azb']);
    });

    test('escapes válidos NÃO geram erro', () {
      final r = run(r'"a\nb\t\\\"\0\r"');
      expect(r.errors, isEmpty);
      expect(r.tokens.first.tag, Tag.stringLiteral);
    });
  });

  // --------------------------------------------------------------------------
  // Conformância — goldens de tokenização (valid) e de erro (invalid).
  // --------------------------------------------------------------------------
  group('conformance/valid — dump == golden .tokens', () {
    final dir = Directory('${_conformanceRoot()}/valid');
    for (final tu in _tuFiles(dir)) {
      final tokensPath = '${tu.path.substring(0, tu.path.length - 3)}.tokens';
      if (!File(tokensPath).existsSync()) continue; // fixture só-parsing → pula
      final name = tu.uri.pathSegments.last;
      test(name, () {
        final src = tu.readAsStringSync();
        final r = tokenizeSource(src);
        expect(r.errors, isEmpty, reason: '$name não deveria ter erros');
        final golden = File(tokensPath).readAsStringSync().trimRight();
        expect(tokenDump(r.tokens).trimRight(), golden);
      });
    }
  });

  group('conformance/invalid — erros == golden .errors + resync', () {
    final dir = Directory('${_conformanceRoot()}/invalid');
    for (final tu in _tuFiles(dir)) {
      final base = tu.path.substring(0, tu.path.length - 3);
      if (!File('$base.errors').existsSync()) continue; // fixture só-parsing → pula
      final name = tu.uri.pathSegments.last;
      test(name, () {
        final src = tu.readAsStringSync();
        final r = tokenizeSource(src);
        expect(
          r.errors,
          isNotEmpty,
          reason: '$name deveria coletar ao menos 1 erro',
        );
        final goldenErrors = File(
          '$base.errors',
        ).readAsStringSync().trimRight();
        expect(errorDump(r.errors).trimRight(), goldenErrors);
        // resync: o stream de tokens (com Tag.invalid) também é golden.
        final goldenTokens = File(
          '$base.tokens',
        ).readAsStringSync().trimRight();
        expect(tokenDump(r.tokens).trimRight(), goldenTokens);
      });
    }
  });
}

/// Raiz do diretório `conformance/` a partir do cwd do `dart test`
/// (= raiz do pacote, `compiler/`).
String _conformanceRoot() {
  for (final candidate in [
    '../conformance',
    'conformance',
    '../../conformance',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'conformance/ não encontrado a partir de ${Directory.current.path}',
  );
}

List<File> _tuFiles(Directory dir) =>
    dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tu'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
