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
      // Em `class` — struct não admite campo mutável (spec 013 §12-1, abaixo).
      final r = check('class S { var m: mut Int }');
      expect(fieldType(r, 'S', 'm'), const IntType()); // sem MutType
      expect(infoOf(r, 'S').fields!.single.isMutable, isTrue);
    });
  });

  group('spec 013 §12-1 — struct é imutável SEMPRE (ruling do dono 2026-07-16)', () {
    // A F7 representa struct por referência no Kernel; a cópia-valor só é
    // inobservável POR imutabilidade (P2). Campo mutável = sharing observável
    // = referência sem glifo. Mutação pede `class` ou copy-with.
    test('campo `var` em struct → mut-field-on-struct', () {
      expect(
        check('struct S { var m: Int }').errors.map((e) => e.code),
        ['mut-field-on-struct'],
      );
    });

    test('o glifo no TIPO também cai: `m: mut Int` em struct', () {
      expect(
        check('struct S { m: mut Int }').errors.map((e) => e.code),
        ['mut-field-on-struct'],
      );
    });

    test('`class` segue aceitando `var`/`mut` — mutação é da REFERÊNCIA (P2)', () {
      final r = check('class C { var m: mut Int }');
      expect(r.errors, isEmpty);
      expect(infoOf(r, 'C').fields!.single.isMutable, isTrue);
    });

    test('struct com campos imutáveis segue limpo (o memberwise não muda)', () {
      final r = check('struct P { x: Int, y: Int = 2 }');
      expect(r.errors, isEmpty);
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

  group('`generic-bounds-unsupported` — lacuna declarada, não falsa acusação', () {
    test('⚠️ `fn f<T: Ord>` erra no BOUND (antes acusava o `cmp`)', () {
      // O bound é representado (parser, AST, dump) e **sem força**: a F5 o
      // descarta. Antes o único erro era `unknown-member` no `cmp` — o compilador
      // acusando o usuário de um membro inexistente quando a verdade é "não lemos
      // o teu bound". Mesma taxonomia do `extension-on-builtin-unsupported`:
      // *"lacuna do COMPILADOR, não erro do usuário"*.
      final r = check(
        'trait Ord { fn cmp(o: Int) -> Int }\n'
        'fn f<T: Ord>(x: T) -> Int => x.cmp(o: 1)',
      );
      // **UMA linha, e é a verdadeira.** O `unknown-member` no `cmp` saía como
      // cascata — 2ª mentira sobre o mesmo fato, e a que culpa o usuário. É a
      // mesma família do `builtin-member-unsupported` (*"`xs.length` existe — nós
      // é que não o modelamos"*): o `cmp` **existe** no bound. Reportada na decl,
      // que é onde se conserta; no uso, `ErrorType` absorvente (ADR-0013 §4).
      expect(r.errors.map((e) => e.code), ['generic-bounds-unsupported']);
    });

    test('…e `T` SEM bound segue dando `unknown-member` — ali é HONESTO', () {
      // A contra-prova, e é o que mantém a supressão estreita: um `T` nu não tem
      // membro nenhum, e acusar é a verdade. É o **bound declarado** que muda o
      // fato — não o `T`.
      expect(
        check('fn f<T>(x: T) -> Int => x.foo()').errors.map((e) => e.code),
        ['unknown-member'],
      );
    });

    test('bound em TIPO também erra (`struct Caixa<T: Ord>`)', () {
      expect(
        check('trait Ord { fn cmp(o: Int) -> Int }\nstruct Caixa<T: Ord> { v: T }')
            .errors
            .map((e) => e.code),
        ['generic-bounds-unsupported'],
      );
    });

    test('multi-bound erra UMA vez por bound', () {
      // `A + B` não tem imagem no Kernel (`TypeParameter.bound` é singular), mas o
      // check é Grupo A: ser mais restrito que o alvo é seguro. Abrir mão do `+` é
      // decisão do dono — o ADR-0012 §B-7 adiou associated types **porque** os
      // bounds cobririam, e essa premissa está falsa hoje.
      expect(
        check(
          'trait A { fn a() -> Int }\ntrait B { fn b() -> Int }\n'
          'fn f<T: A + B>(x: T) -> Int => 1',
        ).errors.map((e) => e.code),
        ['generic-bounds-unsupported', 'generic-bounds-unsupported'],
      );
    });

    test('generic SEM bound segue limpo — é o bound que erra, não o generic', () {
      expect(check('fn ident<T>(x: T) -> T => x').errors, isEmpty);
    });
  });

  group('diamante insatisfazível — o erro é da CLASSE', () {
    test('⚠️ `D : A, T` com `f` incompatível ⟶ erro na DECL (era silêncio)', () {
      // `D ≤ A` pede `f: () -> String`; `D ≤ T` pede `f: () -> Int`. **Nenhum
      // `D.f` serve** ⟹ a classe é insatisfazível, e o erro nasce aqui **mesmo que
      // `D` não declare `f`**. Antes compilava: o `_checkTraitConformance` pula o
      // que tem default, e o `_checkOverride` só roda no que `D` declara ⟹
      // `fn g(a: A) -> String => a.f()` + `g(d)` tipava e rodava errado.
      expect(
        check(
          'trait T { fn f() -> Int => 1 }\n'
          'class A { fn f() -> String => "a" }\n'
          'class D : A, T { w: Int }',
        ).errors.map((e) => e.code),
        ['inherited-signature-conflict'],
      );
    });

    test('…e erra mesmo quando `D` DECLARA `f` — não é problema do `override`', () {
      // Antes isto dava `override-signature-mismatch`: o `_implementationAbove`
      // faz DFS e pegava `A.f` (superclasse primeiro) ⟹ o código do erro MENTIA,
      // mandando o usuário consertar o inconsertável. Nenhum `f` conserta.
      expect(
        check(
          'trait T { fn f() -> Int => 1 }\n'
          'class A { fn f() -> String => "a" }\n'
          'class D : A, T { w: Int\n  override fn f() -> Int => 2 }',
        ).errors.map((e) => e.code),
        contains('inherited-signature-conflict'),
      );
    });

    test('assinaturas COMPATÍVEIS nas duas fontes não acusam', () {
      // Contra-prova: é o conflito que erra, não o diamante. Com a mesma
      // assinatura, qualquer escolha do `_implementationAbove` dá a mesma resposta
      // ⟹ a precedência que ele inventa vira **inobservável**.
      final r = check(
        'trait T { fn f() -> Int => 1 }\n'
        'class A { fn f() -> Int => 2 }\n'
        'class D : A, T { w: Int\n  override fn f() -> Int => 3 }',
      );
      expect(r.errors, isEmpty);
    });

    // ── As âncoras da cerca do `_offeredBy` ────────────────────────────────
    // ⚠️ **O `_offeredBy` NÃO filtra `body != null`, e isso é LOAD-BEARING.** Ele
    // pergunta *"que OBRIGAÇÕES esta aresta impõe?"* — e **requisito É obrigação**.
    // Os outros dois walks (`_lookup`, `_implementationAbove`) filtram corpo porque
    // perguntam *"que corpo roda?"*. Se o `_offeredBy` filtrar, esta cerca fica cega
    // a tudo que envolve requisito, e caem **dois** rulings que a citam
    // nominalmente: o `hits.first` do `_lookup` e o "pega o primeiro" do
    // `_implementationAbove` — os dois só são sãos porque ela roda antes.
    //
    // Os testes acima usam **default** (tem corpo) ⟹ **sobrevivem** à mutação. Sem
    // os três abaixo, a cerca pendia de um único teste, e no outro arquivo.
    // Verificados por mutação: pondo `if (m.decl.body == null) continue` no
    // `_offeredBy`, os três ficam vermelhos.

    test('âncora 1 — REQUISITO × implementação: sigs incompatíveis conflitam', () {
      // `X` exige `f: () -> Int` (sem corpo); `A` provê `f: () -> String`.
      // `D ≤ X` pede Int, `D ≤ A` dá String ⟹ nenhum `D.f` serve.
      expect(
        check(
          'trait X { fn f() -> Int }\n'
          'class A { fn f() -> String => "a" }\n'
          'class D : A, X { w: Int }',
        ).errors.map((e) => e.code),
        contains('inherited-signature-conflict'),
      );
    });

    test('âncora 2 — REQUISITO × REQUISITO: dois traits, sigs incompatíveis', () {
      // Nenhum dos dois tem corpo. A classe é insatisfazível **antes** de qualquer
      // implementação existir — não há `f` que satisfaça `X` e `Y` ao mesmo tempo.
      expect(
        check(
          'trait X { fn f() -> Int }\n'
          'trait Y { fn f() -> String }\n'
          'struct S : X, Y { z: Int }',
        ).errors.map((e) => e.code),
        contains('inherited-signature-conflict'),
      );
    });

    test('âncora 3 — requisito herdado pela SUPERCLASSE × requisito direto', () {
      // O requisito de `X` chega em `D` **através de `A`** ⟹ a cerca tem de compor
      // a subst ao descer, não só olhar o nível 1.
      expect(
        check(
          'trait X { fn f() -> Int }\n'
          'trait Y { fn f() -> String }\n'
          'class A : X { }\n'
          'class D : A, Y { w: Int }',
        ).errors.map((e) => e.code),
        contains('inherited-signature-conflict'),
      );
    });

    test('override legítimo na cadeia não é conflito (mais-interno vence, 1.6.4)', () {
      // `B` sobrepõe `A.f` com a mesma assinatura; `D : B` vê UMA oferta, não duas.
      final r = check(
        'class A { fn f() -> Int => 1 }\n'
        'class B : A { override fn f() -> Int => 2 }\n'
        'class D : B { w: Int }',
      );
      expect(r.errors, isEmpty);
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

  group('R2 — o existencial é MARCADO: `any` (ADR-0017 §6; grammar.ebnf §11)', () {
    const voa =
        'trait Voa { fn voa() -> Int }\n'
        'struct Pato : Voa { fn voa() -> Int => 1 }\n';

    test('trait NU em posição de tipo → existential-requires-any', () {
      // O glifo da fronteira do box (ADR-0017 §3) é obrigatório: `fn f(v: Voa)`
      // deixou de denotar; a mensagem aponta o conserto (`any Voa`).
      final r = check('${voa}fn f(v: Voa) -> Int => 1');
      expect(r.errors.map((e) => e.code), ['existential-requires-any']);
    });

    test('trait nu como TYPE-ARG idem: `List<Voa>` exige `List<any Voa>`', () {
      final r = check('${voa}fn f(xs: List<Voa>) -> Int => 1');
      expect(r.errors.map((e) => e.code), ['existential-requires-any']);
    });

    test('`any` sobre não-trait → any-on-non-trait (não há fronteira sem trait)', () {
      expect(
        check('${voa}fn f(p: any Pato) -> Int => 1').errors.map((e) => e.code),
        ['any-on-non-trait'],
      );
      expect(
        check('fn f(x: any Int) -> Int => 1').errors.map((e) => e.code),
        ['any-on-non-trait'],
      );
    });

    test('`any Desconhecido` → só unknown-type, sem cascata', () {
      final r = check('fn f(x: any Bogus) -> Int => 1');
      expect(r.errors.map((e) => e.code), ['unknown-type']);
    });

    test('`any` na CLÁUSULA de conformance → any-in-conformance', () {
      // Na cláusula o trait é REFERÊNCIA (quem eu conformo), não tipo (o que
      // um slot aceita) — o `any` não tem o que marcar lá.
      final r = check('trait Voa { }\nstruct Pato : any Voa { }');
      expect(r.errors.map((e) => e.code), ['any-in-conformance']);
    });

    test('a cláusula segue NUA: `struct Pato : Voa` continua legal', () {
      final r = check(voa);
      expect(r.errors, isEmpty);
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

    test('⚠️ INVARIANTE — num programa sem erros, `exprTypes` não tem `TypeVar`', () {
      // Mata a FAMÍLIA, não a instância: varre a tabela inteira. A instância era o
      // `_closureAgainst`, que grava `exprTypes[closure] = expected` **antes** de o
      // corpo resolver as vars ⟹ `mapa(xs: nums) { $0 + 1 }` **sem anotação** no
      // `let` (que é o que desliga o R0) deixava `(Int) -> α1` vivo na side-table
      // que a F7 lê. Com anotação o R0 fixava tudo antes — por isso passava verde.
      // ADR-0013 #4: *"deve estar resolvido no fim; se sobrou ⟹ cannot-infer"*.
      bool temVar(Type t) => switch (t) {
        TypeVar _ => true,
        OptionalType n => temVar(n.inner),
        NamedType n => n.args.any(temVar),
        BuiltinType n => n.args.any(temVar),
        FunctionType n => n.params.any((p) => temVar(p.type)) || temVar(n.ret),
        TupleType n => n.elements.any(temVar),
        _ => false,
      };
      final r = check(
        'fn mapa<T, U>(xs: List<T>, f: (T) -> U) -> List<U> => []\n'
        'fn m(nums: List<Int>) -> Void { let ys = mapa(xs: nums) { \$0 + 1 } }',
      );
      expect(r.errors, isEmpty);
      expect(r.exprTypes.values.where(temVar), isEmpty);
      expect(r.binderTypes.values.where(temVar), isEmpty);
    });

    test('⚠️ nº5 NÃO é gravada sob erro — a R2 não alimentava o `hadError`', () {
      // `aplica(f: nil)`: `nil` é checking-only ⟹ deferido para a R2, cujo
      // `_check` errava `nil-under-non-optional` **sem marcar `hadError`** ⟹ o call
      // seguia e gravava a tabela nº5, contra o invariante que ela mesma crava
      // ("só no caminho de SUCESSO: registrar sob erro entregaria à F7 um
      // `ResolvedCall` com buraco dentro"). O `_closureAgainst` erra por dentro
      // pelo mesmo caminho.
      // Sem chamada no corpo de `aplica`: a única do programa é a que falha, senão
      // o `f(1)` gravaria a sua — legitimamente — e mascararia o assert.
      final r = check(
        'fn aplica(f: (Int) -> Int) -> Int => 1\n'
        'fn m() -> Void { let x: Int = aplica(f: nil) }',
      );
      expect(r.errors.map((e) => e.code), contains('nil-under-non-optional'));
      expect(r.resolvedCalls, isEmpty);
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

    test('nº7 `coercions` — a travessia para alvo-trait é GRAVADA (ADR-0017 §5)', () {
      // `p` entra num slot `Voa` — a fronteira existencial do ADR-0017 §3. A F5
      // grava o FATO (houve travessia); a F7 decide por FONTE (local ⟹ nada,
      // vtable; built-in ⟹ box de valor). Sem a tabela, a F7 recomputaria
      // tipagem para achar o sítio — o que as side-tables existem para impedir.
      final r = check(
        'trait Voa { fn voa() -> Int }\n'
        'struct Pato : Voa { fn voa() -> Int => 1 }\n'
        'fn f(v: any Voa) -> Int => v.voa()\n'
        'fn g(p: Pato) -> Int => f(v: p)',
      );
      expect(r.errors, isEmpty);
      final c = r.coercions.values.single;
      expect(c.source.toString(), 'Pato');
      expect(c.target.toString(), 'Voa');
    });

    test('nº7 — o alvo INTEIRO é preservado: `Voa?` grava `Voa?`, não `Voa`', () {
      // O `?` não esconde a travessia; a F7 só compõe box + `.some` na ordem
      // certa vendo o alvo como ele é. (Uma volta de unwrap basta: `?` é
      // idempotente — 009 §4.6 — e fonte opcional nunca subsome.)
      final r = check(
        'trait Voa { fn voa() -> Int }\n'
        'struct Pato : Voa { fn voa() -> Int => 1 }\n'
        'fn f(v: any Voa?) -> Int => 1\n'
        'fn g(p: Pato) -> Int => f(v: p)',
      );
      expect(r.errors, isEmpty);
      expect(r.coercions.values.single.target.toString(), 'Voa?');
    });

    test('nº7 — retorno também é sítio: o ponto único cobre TODO fluxo', () {
      // `p` devolvido como `Voa` é a MESMA travessia em outro contexto
      // sintático — e nada além do `_check` precisou de instrumentação (§4.3:
      // a subsunção tem UM ponto; a totalidade da tabela vem disso).
      final r = check(
        'trait Voa { fn voa() -> Int }\n'
        'struct Pato : Voa { fn voa() -> Int => 1 }\n'
        'fn f(p: Pato) -> any Voa => p',
      );
      expect(r.errors, isEmpty);
      expect(r.coercions.values.single.source.toString(), 'Pato');
    });

    test('nº7 — identidade NÃO grava: `Voa` em slot `Voa` não é travessia', () {
      // Dragon 6.5.2 só materializa o `widen` quando o tipo MUDA.
      final r = check(
        'trait Voa { fn voa() -> Int }\n'
        'fn f(v: any Voa) -> Int => v.voa()\n'
        'fn g(v: any Voa) -> Int => f(v: v)',
      );
      expect(r.errors, isEmpty);
      expect(r.coercions, isEmpty);
    });

    test('nº7 — upcast de CLASSE não grava: só alvo-trait pode exigir nó', () {
      // `Dog ≤ Animal` é superclass/`implementedTypes` no Kernel — upcast
      // grátis, tabela sem consumidor (ADR-0017 §1).
      final r = check(
        'class Animal { fn nome() -> Int => 1 }\n'
        'class Dog : Animal { }\n'
        'fn f(a: Animal) -> Int => a.nome()\n'
        'fn g(d: Dog) -> Int => f(a: d)',
      );
      expect(r.errors, isEmpty);
      expect(r.coercions, isEmpty);
    });

    test('nº7 — `T ≤ T?` sem trait não grava: o alvo não pode exigir box', () {
      final r = check('fn f(x: Int?) -> Int => 1\nfn g() -> Int => f(x: 1)');
      expect(r.errors, isEmpty);
      expect(r.coercions, isEmpty);
    });

    test('⚠️ nº7 NÃO grava sob erro — o invariante da nº5 vale igual', () {
      // Registrar sob erro entregaria à F7 um sítio com buraco dentro.
      final r = check(
        'trait Voa { fn voa() -> Int }\n'
        'fn f(v: any Voa) -> Int => 1\n'
        'fn g(x: Int) -> Int => f(v: x)',
      );
      expect(r.errors.map((e) => e.code), contains('type-mismatch'));
      expect(r.coercions, isEmpty);
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
