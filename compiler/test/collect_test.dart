// ============================================================================
// collect_test.dart — Fatia A da Fase 5: Collect (spec 009 §5.4-A).
// ============================================================================
//
// Dois blocos:
//  1. Conformância: itera `conformance/check/*.tu`, roda a função pura do driver
//     e compara com o golden `.types` (ou os `// EXPECT-CHECK:` inline).
//  2. Asserts unitários por regra.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:test/test.dart';

void main() {
  CheckResult check(String src) => checkProgram(parseSource(src).program);
  TypeInfo infoOf(CheckResult r, String name) =>
      r.types.of(r.types.declNamed(name)!)!;
  Type fieldType(CheckResult r, String type, String field) =>
      infoOf(r, type).fields!.firstWhere((f) => f.name == field).type;

  // --------------------------------------------------------------------------
  // 1. Conformância
  // --------------------------------------------------------------------------
  group('conformance/check — dump == golden .types', () {
    final dir = Directory('${_conformanceRoot()}/check');
    for (final tu in _tuFiles(dir)) {
      final goldenPath = '${tu.path.substring(0, tu.path.length - 3)}.types';
      if (!File(goldenPath).existsSync()) continue;
      test(tu.uri.pathSegments.last, () {
        final src = tu.readAsStringSync();
        final parsed = parseSource(src);
        expect(parsed.hasErrors, isFalse, reason: '${tu.path}: parse limpo');
        final res = checkProgram(parsed.program);
        expect(res.errors, isEmpty, reason: '${tu.path}: sem erro de tipo');
        expect(
          typeTableDump(res).trimRight(),
          File(goldenPath).readAsStringSync().trimRight(),
        );
      });
    }
  });

  group('conformance/check — erros == // EXPECT-CHECK', () {
    final dir = Directory('${_conformanceRoot()}/check');
    for (final tu in _tuFiles(dir)) {
      final src = tu.readAsStringSync();
      final expected = _expectLines(src);
      if (expected.isEmpty) continue;
      test(tu.uri.pathSegments.last, () {
        final res = check(src);
        // Ordem-FONTE (o `collect` ordena por offset) — é a ordem que o usuário lê.
        expect(res.errors.map((e) => e.code).toList(), expected);
      });
    }
  });

  // --------------------------------------------------------------------------
  // 2. Unit por regra
  // --------------------------------------------------------------------------
  group('A1/A2 — cabeças e assinaturas', () {
    test('two-pass: tipo cita outro declarado DEPOIS (letrec — 6.5.1)', () {
      // Sem A1 plantar as cabeças primeiro, `Point` não existiria ao resolver
      // `Caixa`. É a mesma razão do letrec de módulo da F4.
      final r = check('struct Caixa { p: Point }\nstruct Point { x: Int }');
      expect(r.errors, isEmpty);
      expect(fieldType(r, 'Caixa', 'p'), isA<NamedType>());
    });

    test('tipo RECURSIVO resolve (o grafo tem ciclos — 6.3.1 nota 3)', () {
      final r = check('struct No { v: Int, prox: No? }');
      expect(r.errors, isEmpty);
      expect(fieldType(r, 'No', 'prox'), isA<OptionalType>());
    });

    test('generic param vira TypeParamType (a var LIGADA do 6.5.4), não TypeVar', () {
      // `TypeVar` é a variável NOVA que a unificação cria (fatia D); `T` é a
      // LIGADA, que tem nome e foi declarada.
      final r = check('enum Opt<T> { Some(v: T), None }');
      final payload = infoOf(r, 'Opt').variants!.first.payload.single;
      expect(payload, isA<TypeParamType>());
      expect(payload.toString(), 'T'); // o nome que o usuário escreveu
      expect(payload, isNot(isA<TypeVar>()));
    });

    test('kind carrega valor vs referência (P2)', () {
      final r = check('struct S { x: Int }\nclass C { y: Int }');
      expect(infoOf(r, 'S').kind, TypeKind.struct_);
      expect(infoOf(r, 'C').kind, TypeKind.class_);
    });

    test('Σ do enum é entregue para a F6 (contrato §4.7)', () {
      final r = check('enum E { A(v: Int), B }');
      final sigma = infoOf(r, 'E').variants!.map((v) => v.name).toList();
      expect(sigma, ['A', 'B']);
      expect(infoOf(r, 'E').variants!.first.payload.single, const IntType());
    });

    test('superclasse entra na TypeInfo (a relação ≤ do §4.2b)', () {
      final r = check('class Animal { n: String }\nclass Dog : Animal { r: String }');
      expect(infoOf(r, 'Dog').superclass, isA<NamedType>());
      expect(infoOf(r, 'Animal').superclass, isNull);
    });
  });

  group('§4.6 — `Option<T>` ≡ `T?` (ruling do dono 2026-07-12)', () {
    test('Option<Int> e Int? são o MESMO tipo (CA29)', () {
      final r = check('struct S { a: Option<Int>, b: Int? }');
      expect(fieldType(r, 'S', 'a'), fieldType(r, 'S', 'b'));
      expect(fieldType(r, 'S', 'a'), optional(const IntType()));
    });

    test('o alias resolve em A2 — a nulidade NÃO depende de genéricos', () {
      // `Option<X>` → `OptionalType(X)` é reescrita de uma linha, não
      // instanciação genérica: por isso CA29 cabe na fatia A.
      final r = check('struct S { a: Option<String> }');
      expect(r.errors, isEmpty);
      expect(fieldType(r, 'S', 'a'), optional(const StringType()));
    });

    test('Option com aridade errada → generic-arity-mismatch', () {
      expect(
        check('struct S { a: Option<Int, String> }').errors.map((e) => e.code),
        ['generic-arity-mismatch'],
      );
    });
  });

  group('§4.6 — `redundant-optional` é de ANOTAÇÃO (não de Type)', () {
    // Se morasse no smart constructor `optional()`, dispararia em
    // `compact<String?>` — programa LEGAL (a substituição é silenciosa, CA28b).
    for (final forma in ['Option<Option<Int>>', 'Option<Int>?', 'Option<Int?>']) {
      test('`$forma` → redundant-optional (todas são o mesmo tipo)', () {
        final r = check('struct S { v: $forma }');
        expect(r.errors.map((e) => e.code), ['redundant-optional']);
        expect(fieldType(r, 'S', 'v'), optional(const IntType())); // Int?
      });
    }

    for (final forma in ['Int?', 'Option<Int>']) {
      test('`$forma` (um nível só) passa limpo', () {
        final r = check('struct S { v: $forma }');
        expect(r.errors, isEmpty);
        expect(fieldType(r, 'S', 'v'), optional(const IntType()));
      });
    }

    test('`T??` é INEXPRIMÍVEL — o lexer casa `??` como um token (coalesce)', () {
      // O CA28a original citava `String??`; esse programa morre no PARSER.
      final p = parseSource('struct S { v: Int?? }');
      expect(p.errors, isNotEmpty);
      expect(p.errors.first.code, 'expected-token');
    });
  });

  group('§4.1 — `mut` NÃO é tipo (não tem imagem em DartType)', () {
    test('`mut Int` → Int + flag no campo', () {
      final r = check('struct S { var m: mut Int }');
      expect(fieldType(r, 'S', 'm'), const IntType()); // sem MutType
      expect(infoOf(r, 'S').fields!.single.isMutable, isTrue);
    });
  });

  group('A3 — boa-formação', () {
    test('duplicate-field (6.3.6: "os nomes dos campos devem ser distintos")', () {
      expect(
        check('struct S { a: Int, a: String }').errors.map((e) => e.code),
        ['duplicate-field'],
      );
    });

    test('unknown-type (a F4 não resolve namespace de TIPO — contrato 008 §5.4)', () {
      expect(
        check('struct S { x: NaoExiste }').errors.map((e) => e.code),
        ['unknown-type'],
      );
    });

    test('generic-arity-mismatch em user-type', () {
      expect(
        check('struct Box<T> { v: T }\nstruct S { b: Box<Int, Int> }')
            .errors
            .map((e) => e.code),
        ['generic-arity-mismatch'],
      );
    });

    test('inheritance-cycle: sem isso, todo walk sobre `≤` entra em laço', () {
      final r = check('class A : B { x: Int }\nclass B : A { y: Int }');
      expect(r.errors.map((e) => e.code), ['inheritance-cycle', 'inheritance-cycle']);
    });

    test('herança legítima (sem ciclo) não acusa', () {
      expect(
        check('class A { x: Int }\nclass B : A { y: Int }').errors,
        isEmpty,
      );
    });

    test('erros saem em ordem-FONTE, não de descoberta (A2 × A3)', () {
      // `duplicate-field` é A3 e `unknown-type` é A2 — mas o usuário lê o
      // arquivo de cima para baixo.
      final r = check('struct D { a: Int, a: Int }\nstruct S { x: NaoExiste }');
      expect(r.errors.map((e) => e.code), ['duplicate-field', 'unknown-type']);
    });
  });

  test('a F5 consome a F4 e não re-resolve (contrato ADR-0011)', () {
    // Nome não-resolvido aborta antes de tipar — tipar sobre binding quebrado é
    // cascata.
    final r = check('fn f() { let x = bogus }');
    expect(r.errors.map((e) => e.code), ['unresolved-before-check']);
  });
}

String _conformanceRoot() {
  for (final c in ['../conformance', 'conformance', '../../conformance']) {
    if (Directory(c).existsSync()) return c;
  }
  throw StateError('conformance/ não encontrado a partir de ${Directory.current}');
}

Iterable<File> _tuFiles(Directory dir) => !dir.existsSync()
    ? const <File>[]
    : (dir.listSync()..sort((a, b) => a.path.compareTo(b.path)))
          .whereType<File>()
          .where((f) => f.path.endsWith('.tu'));

List<String> _expectLines(String src) => src
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('// EXPECT-CHECK:'))
    .map((l) => l.substring('// EXPECT-CHECK: '.length))
    .toList();
