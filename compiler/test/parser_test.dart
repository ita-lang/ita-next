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
