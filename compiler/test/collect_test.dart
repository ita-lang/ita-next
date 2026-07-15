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
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/collect.dart';
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

    test('a A3 CORTA a aresta — o grafo sai daqui acíclico', () {
      // O corte é o que permite `_implementationAbove`/`_isSubtype`/`_lookup`
      // serem a Fig. 2.37 (sem `visited`). Sem ele, a guarda voltaria a cada um.
      final r = check('class A : B { x: Int }\nclass B : A { y: Int }');
      expect(infoOf(r, 'A').superclass, isNull);
      expect(infoOf(r, 'B').superclass, isNull);
    });

    test('`class C<T> : C<List<T>>` termina — o corte é por DECL, não por TIPO', () {
      // Recursão expansiva (Kennedy & Pierce 2007, lacuna do Dragon): infinitos
      // TIPOS sobre finitas DECLS. Um `visited` de tipos NÃO pararia este walk.
      final r = check('class C<T> : C<List<T>> { v: T }');
      expect(r.errors.map((e) => e.code), ['inheritance-cycle']);
      expect(infoOf(r, 'C').superclass, isNull);
    });

    test('detecção é ordem-INDEPENDENTE (5.2.5): as DUAS arestas são reportadas', () {
      // `u → v` está em ciclo sse `v` alcança `u` — computado sobre o grafo
      // ORIGINAL. Cortar "a primeira que fecha o laço" faria o diagnóstico
      // depender da ordem das declarações.
      final baixo = check('class A : B { x: Int }\nclass B : A { y: Int }');
      final cima = check('class B : A { y: Int }\nclass A : B { x: Int }');
      expect(baixo.errors.length, 2);
      expect(cima.errors.map((e) => e.code), baixo.errors.map((e) => e.code));
    });

    test('erros saem em ordem-FONTE, não de descoberta (A2 × A3)', () {
      // `duplicate-field` é A3 e `unknown-type` é A2 — mas o usuário lê o
      // arquivo de cima para baixo.
      final r = check('struct D { a: Int, a: Int }\nstruct S { x: NaoExiste }');
      expect(r.errors.map((e) => e.code), ['duplicate-field', 'unknown-type']);
    });
  });

  group('papel por KIND, não por posição (ruling do dono 2026-07-15)', () {
    test('`class Pato : Voa` (só trait) é LEGAL e NÃO tem superclasse', () {
      // O parser põe o 1º type em `superclass` SEMPRE (posição, `parser.dart:349`)
      // ⟹ o kind-check acusaria `superclass-not-a-class` num programa legítimo, e
      // `class` que conforma a trait sem herdar era **INEXPRIMÍVEL**.
      final r = check('trait Voa { }\nclass Pato : Voa { n: String }');
      expect(r.errors, isEmpty);
      expect(infoOf(r, 'Pato').superclass, isNull);
      expect(infoOf(r, 'Pato').traits.single.toString(), 'Voa');
    });

    test('`class Dog : Animal, Barker` — o kind separa os papéis', () {
      final r = check(
        'class Animal { n: String }\ntrait Barker { }\n'
        'class Dog : Animal, Barker { r: String }',
      );
      expect(r.errors, isEmpty);
      expect(infoOf(r, 'Dog').superclass.toString(), 'Animal');
      expect(infoOf(r, 'Dog').traits.single.toString(), 'Barker');
    });

    test('duas classes → multiple-superclasses', () {
      expect(
        check('class Gato { }\nclass Cao { }\nclass X : Gato, Cao { }')
            .errors
            .map((e) => e.code),
        ['multiple-superclasses'],
      );
    });

    test('superclasse primeiro ou em lugar nenhum → class-after-trait', () {
      expect(
        check('trait Barker { }\nclass Animal { }\nclass Dog : Barker, Animal { }')
            .errors
            .map((e) => e.code),
        ['class-after-trait'],
      );
    });

    test('`class C : AlgumStruct` → superclass-not-a-class', () {
      expect(
        check('struct S { }\nclass C : S { }').errors.map((e) => e.code),
        ['superclass-not-a-class'],
      );
    });

    test('`struct` não herda (P2: subtipagem de valor é slicing) → trait-expected', () {
      expect(
        check('class C { }\nstruct S : C { }').errors.map((e) => e.code),
        ['trait-expected'],
      );
    });

    test('`struct S : S` morre no kind — a aresta nem chega a formar ciclo', () {
      expect(
        check('struct S : S { }').errors.map((e) => e.code),
        ['trait-expected'],
      );
    });
  });

  group('trait é FOLHA (ruling do dono 2026-07-15)', () {
    test('`extension X : Y` com X trait → trait-supertype', () {
      // A porta da frente não exprime supertrait (`traitDecl` não tem cláusula
      // `:`); as laterais entravam e a aresta FICAVA, sem ninguém a checar.
      expect(
        check('trait X { }\ntrait Y { }\nextension X : Y { }')
            .errors
            .map((e) => e.code),
        ['trait-supertype'],
      );
    });

    test('`impl Y for X` com X trait → trait-supertype', () {
      expect(
        check('trait X { }\ntrait Y { }\nimpl Y for X { }')
            .errors
            .map((e) => e.code),
        ['trait-supertype'],
      );
    });

    test('`extension` NÃO planta superclasse por retrofit', () {
      // Superclasse vem da decl da própria classe e de mais lugar nenhum.
      final r = check('class Animal { }\nclass Dog { }\nextension Dog : Animal { }');
      expect(r.errors.map((e) => e.code), ['trait-expected']);
      expect(infoOf(r, 'Dog').superclass, isNull);
    });

    test('`extension Dog : Barker` (trait de verdade) segue legal', () {
      final r = check('trait Barker { }\nclass Dog { }\nextension Dog : Barker { }');
      expect(r.errors, isEmpty);
      expect(infoOf(r, 'Dog').traits.single.toString(), 'Barker');
    });
  });

  group('contrato F5 → F7 (§7) — as tabelas SAEM da fase', () {
    // O `CheckResult` servia a DOIS papéis: saída do `runCollector` (a entrada
    // que o `Checker` consome) e saída do `checkTypes`. Por isso tinha só os
    // campos da ENTRADA — `exprTypes`/`resolvedMembers`/`binderTypes` viviam no
    // `Checker`, **descartado** no fim do `checkTypes`. A F5 computava o contrato
    // da F7 e o jogava fora. Partir em `CollectResult` × `CheckResult` mata a
    // CLASSE do bug: nenhum campo novo do checker tem para onde vazar.
    test('nº1 `exprTypes` — a F7 não tipa o Kernel sem ela (ADR-0007)', () {
      final r = check('fn f() { let x = 1 + 2 }');
      expect(r.exprTypes, isNotEmpty);
      expect(r.exprTypes.values, everyElement(isNot(isA<ErrorType>())));
    });

    test('nº6 `binderTypes` — `VariableDeclaration.type` é non-nullable', () {
      // Sem ela a F7 só teria `dynamic` para pôr ali, e o ADR-0013 o proíbe.
      final r = check('fn f(a: Int) { let x = a }');
      expect(r.binderTypes.values, contains(const IntType()));
    });

    test('nº3 `resolvedMembers` — sem ela o Kernel cai em `DynamicGet`', () {
      final r = check('struct S { v: Int }\nfn f(s: S) { let x = s.v }');
      expect(r.errors, isEmpty);
      expect(r.resolvedMembers, isNotEmpty);
    });

    test('nº4 `annotations` — o alvo do `extension` entra (era por string)', () {
      // O `_contribute` resolve o alvo por NOME (`declNamed`), fora do `_resolve`
      // ⟹ o `TypeNode` do alvo ficava fora da tabela e a F7 refaria a resolução
      // por string — o que a tabela existe para não acontecer.
      final r = check('struct S { v: Int }\nextension S { fn dobro() -> Int => 2 }');
      expect(r.errors, isEmpty);
      final alvo = r.annotations.values.whereType<NamedType>();
      expect(alvo.map((t) => t.toString()), contains('S'));
    });

    test('nº5 `resolvedCalls` — slot, typeArgs e a assinatura substituída', () {
      final r = check('fn soma(a: Int, b: Int) -> Int => a\nfn f() -> Int => soma(a: 1, b: 2)');
      expect(r.errors, isEmpty);
      final rc = r.resolvedCalls.values.single;
      expect(rc.slot, [0, 1]);
      expect(rc.typeArgs, isEmpty); // fn não-genérica
      expect(rc.signature.ret, const IntType());
    });

    test('nº5 — o `slot` casa por LABEL, e salta o default DO MEIO', () {
      // `Arg.label` é nullable ⟹ arg→param não é recuperável sem re-rodar o
      // `_matchArgs`. E o Itá permite saltar o param do meio (Swift), coisa que o
      // Dart não tem posicionalmente ⟹ o slot CRU é o que serve às duas lowerings.
      final r = check(
        'fn f(a: Int, b: Int = 2, c: Int) -> Int => a\n'
        'fn g() -> Int => f(a: 1, c: 3)',
      );
      expect(r.errors, isEmpty);
      expect(r.resolvedCalls.values.single.slot, [0, 2]); // saltou o 1
    });

    test('⚠️ nº5 — `typeArgs` sai na ordem DECLARADA, não na de aparição', () {
      // `fn fold<B, A>(xs: List<A>, init: B)`: declarada `[B, A]`, aparição
      // `[A, B]`. A ordem é SEMÂNTICA e ninguém a checa — o
      // `Substitution.fromPairs` do Kernel casa posicionalmente ⟹ ordem errada =
      // **tipo trocado em silêncio**, com a aridade batendo. O verifier não faz
      // type-checking (`verifier.dart:127-129`) e a VM nem o roda.
      final r = check(
        'fn fold<B, A>(xs: A, zero: B) -> B => zero\n'
        'fn g() -> String => fold(xs: 1, zero: "a")',
      );
      expect(r.errors, isEmpty);
      // Declarado `<B, A>`; no walk da assinatura o `A` aparece PRIMEIRO (param 0).
      // `[B, A]` = `[String, Int]` — na ordem de aparição seria `[Int, String]`.
      expect(
        r.resolvedCalls.values.single.typeArgs,
        [const StringType(), const IntType()],
      );
    });

    test('nº3 `origin` — o `extension` que contribuiu, não a decl do tipo', () {
      // `MethodInfo.origin` já existia e o `_lookup` o DESCARTAVA (passava
      // `m.decl`): furo de propagação. É o nó, não um enum — o enum não diria QUAL
      // extension, que é do que a F7 precisa.
      final r = check(
        'struct S { v: Int }\n'
        'extension S { fn dobro() -> Int => 2 }\n'
        'fn f(s: S) -> Int => s.dobro()',
      );
      expect(r.errors, isEmpty);
      final m = r.resolvedMembers.values.single;
      expect(m.origin, isA<ast.ExtensionDecl>());
    });

    test('nº3 `origin` — membro próprio aponta a decl do próprio tipo', () {
      final r = check('struct S { v: Int }\nfn f(s: S) -> Int => s.v');
      expect(r.errors, isEmpty);
      expect(r.resolvedMembers.values.single.origin, isA<ast.StructDecl>());
    });

    test('a fatia A entrega `CollectResult` — que NÃO tem as tabelas do checker', () {
      // O tipo da entrada não pode carregar os campos da saída: é o que deixava
      // os dois papéis colados.
      expect(collectTypes(parseSource('struct S { v: Int }').program),
          isA<CollectResult>());
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
