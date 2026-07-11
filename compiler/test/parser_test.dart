// ============================================================================
// parser_test.dart — Testes da Fase 2 (Sintaxe → AST) do ita-next.
// ============================================================================
//
// Dois blocos:
//  1. Conformância de PARSING: itera `conformance/valid|invalid/*.tu` e confere
//     `itac parse --dump` (via a função pura do driver, sem subprocess) contra
//     os goldens `.ast`; para `invalid/`, confere os erros declarados inline
//     (`// EXPECT: parse-error: … @off+len`) + o `.ast` recuperado, se houver.
//     Só processa arquivos com golden `.ast` OU `// EXPECT: parse-error:` — os
//     fixtures SÓ-léxicos da Fase 1 (com `.tokens`/`.errors`) são ignorados.
//  2. Asserts unitários (T026): shape de `ErrorDecl`, span byte-preciso, e a
//     estrutura que o golden não pega bem.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:test/test.dart';

void main() {
  // --------------------------------------------------------------------------
  // 1. Conformância de parsing.
  // --------------------------------------------------------------------------
  group('conformance/valid — parse --dump == golden .ast', () {
    final dir = Directory('${_conformanceRoot()}/valid');
    for (final tu in _tuFiles(dir)) {
      final astPath = _sibling(tu, '.ast');
      if (!File(astPath).existsSync()) continue; // fixture só-léxico → pula
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(tu.readAsStringSync());
        expect(
          result.errors,
          isEmpty,
          reason: '${tu.path} não deveria ter erro de parse',
        );
        final golden = File(astPath).readAsStringSync().trimRight();
        expect(parseDump(result.program).trimRight(), golden);
      });
    }
  });

  group('conformance/invalid — erros == // EXPECT + resync', () {
    final dir = Directory('${_conformanceRoot()}/invalid');
    for (final tu in _tuFiles(dir)) {
      final src = tu.readAsStringSync();
      final expected = _expectLines(src);
      if (expected.isEmpty) continue; // sem EXPECT de parse → fixture léxico
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(src);
        expect(
          result.errors,
          isNotEmpty,
          reason: '${tu.path} deveria coletar ao menos 1 erro de parse',
        );
        expect(parseErrorDump(result.errors).split('\n'), expected);
        // Se houver `.ast`, confere a árvore RECUPERADA (resync sem cascata).
        final astPath = _sibling(tu, '.ast');
        if (File(astPath).existsSync()) {
          final golden = File(astPath).readAsStringSync().trimRight();
          expect(parseDump(result.program).trimRight(), golden);
        }
      });
    }
  });

  // --------------------------------------------------------------------------
  // 2. Asserts unitários (shape/span — T026).
  // --------------------------------------------------------------------------
  group('CA17 — tipos (shape)', () {
    test('(Int, Int) -> Int é FunctionType não-async', () {
      final p = parseSource('let f: (Int, Int) -> Int = e');
      final let = p.program.body.first as LetStmt;
      final t = let.type as FunctionType;
      expect(t.isAsync, isFalse);
      expect(t.params.length, 2);
      expect((t.ret as NamedType).name, 'Int');
      expect(p.errors, isEmpty);
    });

    test('mut Foo? = mut(optional(Foo)) — mut envolve o optional', () {
      final p = parseSource('let x: mut Foo? = e');
      final let = p.program.body.first as LetStmt;
      final mut = let.type as MutType;
      final opt = mut.inner as OptionalType;
      expect((opt.inner as NamedType).name, 'Foo');
    });
  });

  group('CA15 — generics aninhados (>> split) + span', () {
    test('Map<String, List<Int>> aninha e o >> fecha os dois', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final let = p.program.body.first as LetStmt;
      final map = let.type as NamedType;
      expect(map.name, 'Map');
      expect(map.args.length, 2);
      expect((map.args[0] as NamedType).name, 'String');
      final list = map.args[1] as NamedType;
      expect(list.name, 'List');
      expect((list.args.single as NamedType).name, 'Int');
      expect(p.errors, isEmpty);
    });

    test('span do binding "m" é byte-preciso (offset 4, len 1)', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final let = p.program.body.first as LetStmt;
      final bind = let.target as BindPattern;
      expect(bind.offset, 4);
      expect(bind.length, 1);
    });
  });

  group('CA18 — recuperação N2 (sem cascata)', () {
    test('fn f( { → ErrorDecl enxertado + fn g parseia; erro @6+1', () {
      final p = parseSource('fn f( { }\nfn g() => 1\n');
      expect(p.program.body.length, 2);
      expect(p.program.body[0], isA<ErrorDecl>());
      final g = p.program.body[1] as FnDecl;
      expect(g.name, 'g');
      expect(p.errors.length, 1);
      expect(p.errors.first.code, 'expected-token');
      expect(p.errors.first.offset, 6);
      expect(p.errors.first.length, 1);
    });
  });

  // --------------------------------------------------------------------------
  // Fatia 1 — expressões (shape/assoc + caminhos sem CA dedicado).
  // --------------------------------------------------------------------------
  Expr exprOf(String src) =>
      (parseSource(src).program.body.single as ExprStmt).expr;

  group('CA8 — associatividade', () {
    test('** é direita: a ** b ** c = a ** (b ** c)', () {
      final e = exprOf('a ** b ** c') as Binary;
      expect(e.op, '**');
      expect((e.left as Ident).name, 'a');
      expect((e.right as Binary).op, '**'); // aninha à direita
    });
  });

  group('closure explícito (sem CA — cobre _isClosureStart/_closure)', () {
    test('(x) => x + 1 é Closure com params explícitos', () {
      final p = parseSource('let f = (x) => x + 1');
      final c = (p.program.body.single as LetStmt).value as Closure;
      expect(c.hasExplicitParams, isTrue);
      expect(c.params.single.name, 'x');
      expect(c.returnType, isNull);
      expect(c.body, isA<ExprBody>());
      expect(p.errors, isEmpty);
    });

    test('(x) -> Int => x preserva o returnType', () {
      final p = parseSource('let f = (x) -> Int => x');
      final c = (p.program.body.single as LetStmt).value as Closure;
      expect((c.returnType as NamedType).name, 'Int');
    });
  });

  group('parenOrClosure — grupo/tupla/1-tupla', () {
    test('(a, b) é TupleExpr de 2', () {
      final e = exprOf('(a, b)') as TupleExpr;
      expect(e.elements.length, 2);
    });

    test('(a) é agrupamento (devolve o interno)', () {
      expect(exprOf('(a)'), isA<Ident>());
    });

    test('(a,) 1-tupla → single-element-tuple (M7)', () {
      final p = parseSource('let p = (a,)');
      expect(p.errors.single.code, 'single-element-tuple');
    });
  });

  // --------------------------------------------------------------------------
  // Cluster de correção pós-review (compiler-craftsman B1/A5/A1/A4).
  // --------------------------------------------------------------------------
  group('B1 — recuperação nunca crasha (progresso garantido)', () {
    test('`init` no topo NÃO lança; enxerta ErrorDecl', () {
      final p = parseSource('init'); // kwInit sem case em _declaration
      expect(p.program.body.single, isA<ErrorDecl>());
      expect(p.errors.single.code, 'expected-declaration');
    });

    test('erro no 2º item (após um let válido) resync sem cascata', () {
      final p = parseSource('let x = 1\ninit\n');
      expect(p.program.body.length, 2);
      expect(p.program.body[0], isA<LetStmt>());
      expect(p.program.body[1], isA<ErrorDecl>());
      expect(p.errors.length, 1); // UM erro, sem cascata
    });
  });

  group('A5 — match arms com vírgula OPCIONAL', () {
    test('arms separados sem vírgula parseiam', () {
      final e = exprOf('match x { 1 => a 2 => b }') as MatchExpr;
      expect(e.arms.length, 2);
    });
  });

  group('A1 — supressão de trailing-closure não vaza p/ brackets', () {
    test('trailing-closure aninhada em args de call dentro de cond `if`', () {
      // `inner() { $0 }` está DENTRO de `outer(...)` → não é suprimido pela
      // condição do if; `{ a }`/`{ b }` continuam sendo os blocos do if.
      final p = parseSource(r'if outer(inner() { $0 }) { a } else { b }');
      expect(p.errors, isEmpty);
      expect(p.program.body.single, isA<IfStmt>());
    });
  });

  group('A4 — span do generic interno inclui o `>` (split de `>>`)', () {
    test('List<Int> em Map<String, List<Int>> tem length 9', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final map = (p.program.body.single as LetStmt).type as NamedType;
      final list = map.args[1] as NamedType;
      expect(list.name, 'List');
      expect(list.length, 9); // "List<Int>" — o `>` de fecho entra no span
    });
  });

  // --------------------------------------------------------------------------
  // if-EXPRESSÃO (ruling RD-1, opção A).
  // --------------------------------------------------------------------------
  group('if-expr (RD-1, opção A)', () {
    test('booleana: binding null, subject é o Bool, ramos são expressões', () {
      final e = (parseSource('let x = if a > b => a else b').program.body.single
              as LetStmt)
          .value as IfExpr;
      expect(e.binding, isNull);
      expect((e.subject as Binary).op, '>');
      expect((e.then as Ident).name, 'a');
      expect((e.orElse as Ident).name, 'b');
    });

    test('else-if encadeia como IfExpr no orElse', () {
      final e = (parseSource('let x = if a => 1 else if b => 2 else 3').program
              .body.single as LetStmt)
          .value as IfExpr;
      expect(e.orElse, isA<IfExpr>());
    });

    test('if-let: binding presente, subject é o desembrulhado', () {
      final e = (parseSource('let x = if let u = user => u else nil').program
              .body.single as LetStmt)
          .value as IfExpr;
      expect((e.binding as BindPattern).name, 'u');
      expect((e.subject as Ident).name, 'user');
    });

    test('else é OBRIGATÓRIO no if-expr', () {
      final p = parseSource('let x = if a => 1');
      expect(p.errors, isNotEmpty); // falta o `else`
    });
  });
}

/// Raiz do diretório `conformance/` a partir do cwd do `dart test` (= `compiler/`).
String _conformanceRoot() {
  for (final candidate in ['../conformance', 'conformance', '../../conformance']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'conformance/ não encontrado a partir de ${Directory.current.path}',
  );
}

List<File> _tuFiles(Directory dir) =>
    dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tu')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Troca o sufixo `.tu` do arquivo por [ext] (ex.: `.ast`).
String _sibling(File tu, String ext) =>
    '${tu.path.substring(0, tu.path.length - 3)}$ext';

/// Extrai as linhas `// EXPECT: <erro>` de um fonte, na ordem (só as de parse).
List<String> _expectLines(String src) => src
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('// EXPECT: parse-error:'))
    .map((l) => l.substring('// EXPECT: '.length))
    .toList();
