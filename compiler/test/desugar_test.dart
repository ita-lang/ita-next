// ============================================================================
// desugar_test.dart — Testes da Fase 3 (Desugaring / lowering) do ita-next.
// ============================================================================
//
// Três blocos (espelho do parser_test da Fase 2):
//  1. Conformância: itera `conformance/desugar/*.tu` e confere `desugar --dump`
//     (via a função pura do driver, sem subprocess) contra os goldens `.desugar`
//     — gerados AO VIVO pelo orquestrador. Só processa arquivos COM golden.
//  2. Invariantes globais sobre TODO fixture: idempotência (CA10), span dentro
//     do range do fonte (CA11) e assertion de core (§5.4 — nenhum açúcar sobra).
//  3. Asserts unitários por regra §5.2 (shape estrutural + os 3 shapes CONFIRMADOS
//     ao vivo em exact-dump: `??`/`>>`/`|>`).
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/desugar/core_check.dart';
import 'package:ita_next_compiler/frontend/desugar/desugar.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:test/test.dart';

void main() {
  // --------------------------------------------------------------------------
  // 1. Conformância de desugaring (goldens gerados ao vivo).
  // --------------------------------------------------------------------------
  group('conformance/desugar — desugar --dump == golden .desugar', () {
    final dir = Directory('${_conformanceRoot()}/desugar');
    for (final tu in _tuFiles(dir)) {
      final goldenPath = _sibling(tu, '.desugar');
      if (!File(goldenPath).existsSync()) continue; // golden ainda não gerado
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(tu.readAsStringSync());
        expect(
          result.errors,
          isEmpty,
          reason: '${tu.path}: fixture de desugar deve parsear limpo',
        );
        final golden = File(goldenPath).readAsStringSync().trimRight();
        expect(desugarDump(result.program).trimRight(), golden);
      });
    }
  });

  // --------------------------------------------------------------------------
  // 2. Invariantes globais sobre CADA fixture de desugar.
  // --------------------------------------------------------------------------
  group('invariantes globais — todo fixture conformance/desugar', () {
    final dir = Directory('${_conformanceRoot()}/desugar');
    for (final tu in _tuFiles(dir)) {
      final src = tu.readAsStringSync();
      final name = tu.uri.pathSegments.last;

      test('$name — parseia limpo', () {
        expect(parseSource(src).errors, isEmpty);
      });

      test('$name — CA10 idempotência: desugar∘desugar == desugar', () {
        final p = parseSource(src).program;
        final once = desugarProgram(p);
        expect(desugarDump(once), desugarDump(p));
      });

      test('$name — §5.4 assertion: nenhum açúcar sobrevive', () {
        final canonical = desugarProgram(parseSource(src).program);
        expect(
          findResidualSugar(canonical),
          isEmpty,
          reason: 'açúcar residual em $name',
        );
        expect(() => assertCoreForm(canonical), returnsNormally);
      });
    }
  });

  // --------------------------------------------------------------------------
  // 3. Asserts unitários por regra §5.2.
  // --------------------------------------------------------------------------

  // Açúcar em posição de EXPRESSÃO no topo → ExprStmt.
  Expr desugarExpr(String src) {
    final p = desugarProgram(parseSource(src).program);
    return (p.body.single as ExprStmt).expr;
  }

  // O valor de um `let x = <expr>` no topo, já desaçucarado.
  Expr desugarLetValue(String src) {
    final p = desugarProgram(parseSource(src).program);
    return (p.body.single as LetStmt).value!;
  }

  bool inRange(AstNode n, String src) =>
      n.offset >= 0 && n.offset + n.length <= src.length;

  group('CA1 — a ?? b → match .some/.none', () {
    const src = 'a ?? b';

    test('shape estrutural + span herdado do açúcar', () {
      final original = (parseSource(src).program.body.single as ExprStmt).expr
          as Binary;
      final m = desugarExpr(src) as MatchExpr;
      // span do match sintetizado == span do `??` fonte (CA11).
      expect(m.offset, original.offset);
      expect(m.length, original.length);
      expect(inRange(m, src), isTrue);

      expect((m.scrutinee as Ident).name, 'a');
      expect(m.arms.length, 2);
      final some = m.arms[0].pattern as EnumPattern;
      expect(some.variant, 'some');
      final bind = some.subpatterns.single as BindPattern;
      expect(bind.name, startsWith(r'$x'));
      expect(inRange(bind, src), isTrue);
      expect((m.arms[0].body as Ident).name, bind.name); // .some($x) => $x
      expect((m.arms[1].pattern as EnumPattern).variant, 'none');
      expect((m.arms[1].body as Ident).name, 'b'); // .none => b
    });

    test('exact-dump (shape CONFIRMADO ao vivo)', () {
      expect(
        desugarDump(parseSource(src).program),
        '(expr-stmt (match (id a) (arm (pat-enum "some" (bind "\$x0")) '
            '(id \$x0)) (arm (pat-enum "none") (id b))))',
      );
    });
  });

  group('CA2 — a?.b → match, .some faz .b, .none propaga .none', () {
    test('shape', () {
      final m = desugarExpr('a?.b') as MatchExpr;
      expect((m.scrutinee as Ident).name, 'a');
      final someBody = m.arms[0].body as Member;
      expect(someBody.name, 'b'); // $x.b
      expect((someBody.receiver as Ident).name, startsWith(r'$x'));
      expect((m.arms[1].body as EnumShorthand).variant, 'none'); // .none
    });

    test('cadeia a?.b?.c aninha (matches encadeados; sem opt-chain residual)', () {
      final canonical = desugarProgram(parseSource('a?.b?.c').program);
      expect(findResidualSugar(canonical), isEmpty);
      final outer = (canonical.body.single as ExprStmt).expr as MatchExpr;
      // o scrutinee do match externo é o match interno (a?.b já desaçucarado).
      expect(outer.scrutinee, isA<MatchExpr>());
    });
  });

  group('CA3 — a! → match com .none => panic', () {
    test('shape', () {
      final m = desugarExpr('a!') as MatchExpr;
      expect((m.arms[0].body as Ident).name, startsWith(r'$x'));
      final panic = m.arms[1].body as Panic;
      final msg = (panic.operand as Str).parts.single as StrLit;
      expect(msg.value, 'force-unwrap on none');
    });
  });

  group(r'CA4 — f >> g → ($c) => g(f($c))', () {
    const src = 'f >> g';

    test('shape estrutural', () {
      final c = desugarExpr(src) as Closure;
      expect(c.hasExplicitParams, isTrue);
      final param = c.params.single;
      expect(param.name, startsWith(r'$c'));
      final call = (c.body as ExprBody).e as Call; // g(f($c))
      expect((call.callee as Ident).name, 'g');
      final inner = call.args.single.value as Call; // f($c)
      expect((inner.callee as Ident).name, 'f');
      expect((inner.args.single.value as Ident).name, param.name);
    });

    test('exact-dump (shape CONFIRMADO ao vivo)', () {
      expect(
        desugarDump(parseSource(src).program),
        '(expr-stmt (closure (params (param "\$c0")) '
            '(call (id g) (call (id f) (id \$c0)))))',
      );
    });
  });

  group('CA5 — x |> f(a) → f(x, a) (x 1º posicional)', () {
    const src = 'x |> f(a)';

    test('shape estrutural', () {
      final call = desugarExpr(src) as Call;
      expect((call.callee as Ident).name, 'f');
      expect(call.args.length, 2);
      expect((call.args[0].value as Ident).name, 'x'); // injetado na frente
      expect((call.args[1].value as Ident).name, 'a');
    });

    test('exact-dump (shape CONFIRMADO ao vivo)', () {
      expect(
        desugarDump(parseSource(src).program),
        '(expr-stmt (call (id f) (id x) (id a)))',
      );
    });

    test('x |> f (rhs não-Call) → f(x)', () {
      final call = desugarExpr('x |> f') as Call;
      expect((call.callee as Ident).name, 'f');
      expect(call.args.single.value, isA<Ident>());
      expect((call.args.single.value as Ident).name, 'x');
    });
  });

  group('CA6 — if let P = e => t else f → match .some(P)/.none', () {
    test('shape', () {
      final m = desugarLetValue('let r = if let u = user => u else fb')
          as MatchExpr;
      expect((m.scrutinee as Ident).name, 'user');
      final some = m.arms[0].pattern as EnumPattern;
      expect(some.variant, 'some');
      expect((some.subpatterns.single as BindPattern).name, 'u'); // P direto
      expect((m.arms[0].body as Ident).name, 'u');
      expect((m.arms[1].pattern as EnumPattern).variant, 'none');
      expect((m.arms[1].body as Ident).name, 'fb');
    });

    test('if-expr BOOLEANO (sem binding) PERMANECE core (não vira match)', () {
      final e = desugarLetValue('let m = if a => 1 else 2');
      expect(e, isA<IfExpr>());
      expect((e as IfExpr).binding, isNull);
    });
  });

  group('CA7 — for RETIDO como core (baixa p/ ForInStatement do Kernel)', () {
    // Ruling do dono 2026-07-12 (Opção 1): a VM itera de graça (Grupo B); Dragon
    // 6.1 (não lowerar além do que o backend oferece). `for` NÃO desaçucara — só o
    // INTERIOR (iterable/body) é reescrito recursivamente. Entra nos retidos.
    test('for sync permanece ForStmt; target/iterable/body preservados', () {
      final p = desugarProgram(parseSource('for x in xs { f(x) }').program);
      expect(p.body.single, isA<ForStmt>());
      final forStmt = p.body.single as ForStmt;
      expect(forStmt.isAwait, isFalse);
      expect((forStmt.target as BindPattern).name, 'x');
      expect((forStmt.iterable as Ident).name, 'xs');
      expect(forStmt.body.stmts.single, isA<ExprStmt>());
    });

    test('for await preserva isAwait (permanece ForStmt)', () {
      final p = desugarProgram(
        parseSource('for await x in xs { f(x) }').program,
      );
      expect((p.body.single as ForStmt).isAwait, isTrue);
    });

    test('o CORPO desaçucara: ?? no corpo vira match, mas o for fica', () {
      final p = desugarProgram(parseSource('for x in xs { a ?? b }').program);
      final forStmt = p.body.single as ForStmt;
      final bodyExpr = (forStmt.body.stmts.single as ExprStmt).expr;
      expect(bodyExpr, isA<MatchExpr>()); // o ?? do corpo desaçucarou
    });

    test('o ITERABLE desaçucara: ?? no iterável vira match, for fica', () {
      final p = desugarProgram(parseSource('for x in a ?? b { f(x) }').program);
      expect((p.body.single as ForStmt).iterable, isA<MatchExpr>());
    });

    test('for NÃO é açúcar residual (assertion de core passa)', () {
      final p = desugarProgram(parseSource('for x in xs { a ?? b }').program);
      expect(findResidualSugar(p), isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // Açúcar DENTRO de pattern — o vetor é a STRING interpolada de um
  // LiteralPattern (`match x { "${a ?? b}" => … }`). Duas metades: o desugar
  // desce em patterns E o core_check acusa se algo escapar (antes: nenhum dos
  // dois, então o `??` sobrevivia na pattern e o check aprovava em silêncio).
  // --------------------------------------------------------------------------
  group('açúcar em pattern — desugar desce e core_check acusa', () {
    // A pattern do 1º arm de um `match` no topo, já desaçucarada.
    Pattern armPattern(String src) {
      final p = desugarProgram(parseSource(src).program);
      final m = (p.body.single as LetStmt).value! as MatchExpr;
      return m.arms.first.pattern;
    }

    Expr interpOf(Pattern p) {
      final str = (p as LiteralPattern).literal as Str;
      return (str.parts.single as StrInterp).expr;
    }

    test('match arm: `"\${a ?? b}"` → o ?? na pattern vira match', () {
      final pat = armPattern('let r = match x {\n "\${a ?? b}" => 1\n _ => 2\n}');
      expect(interpOf(pat), isA<MatchExpr>());
    });

    test('pattern ANINHADA (.some([n, "\${p |> f}"])) também desce', () {
      final pat = armPattern(
        'let r = match x {\n .some([n, "\${p |> f}"]) => 1\n _ => 2\n}',
      );
      final list = (pat as EnumPattern).subpatterns.single as ListPattern;
      expect(interpOf(list.elements[1]), isA<Call>()); // p |> f → f(p)
    });

    test('target de let/for/guard-let também desce', () {
      final p = desugarProgram(
        parseSource('let "\${a ?? b}" = x\nfor "\${c ?? d}" in xs { g() }')
            .program,
      );
      expect(interpOf((p.body[0] as LetStmt).target), isA<MatchExpr>());
      expect(interpOf((p.body[1] as ForStmt).target), isA<MatchExpr>());
    });

    test('core_check ACUSA açúcar que sobreviva na pattern', () {
      // AST na mão: o desugar já corrige, então a única forma de provar que o
      // check pega o resíduo é construí-lo. `match x { "${a ?? b}" => 1 }` com
      // o `??` intacto na pattern — exatamente o que passava em silêncio.
      final sugar = Binary(
        BinaryOp.coalesce,
        Ident('a', 0, 1),
        Ident('b', 0, 1),
        0,
        1,
      );
      final residual = Program([
        ExprStmt(
          MatchExpr(
            Ident('x', 0, 1),
            [
              MatchArm(
                LiteralPattern(Str([StrInterp(sugar)], 0, 1), 0, 1),
                null,
                IntLit(1, 0, 1),
              ),
            ],
            0,
            1,
          ),
          0,
          1,
        ),
      ], 0, 1);
      expect(findResidualSugar(residual).map((r) => r.kind), ['??']);
      expect(() => assertCoreForm(residual), throwsStateError);
    });
  });

  group('CA8 — V where { let x = e } → match/let-in (sem where)', () {
    test('single binding: match e { x => V }', () {
      final m = desugarLetValue('let s = doubled where { let doubled = n * 2 }')
          as MatchExpr;
      expect((m.scrutinee as Binary).op, BinaryOp.mul); // n * 2
      expect((m.arms.single.pattern as BindPattern).name, 'doubled');
      expect((m.arms.single.body as Ident).name, 'doubled'); // V
    });

    test('multi binding ordena por DEPENDÊNCIA (letrec §3.6), NÃO ordem-fonte', () {
      // CA1: `total` (forward-ref) referencia `a`/`b` definidos DEPOIS. A ordem de
      // aninhamento tem de ligar `a`/`b` ANTES de avaliar `a + b` → a,b OUTER, total
      // INNER. (Antes: aninhava em ordem-fonte e avaliava a+b com a/b não ligados.)
      final m =
          desugarLetValue(
                'let r = total where { let total = a + b\n let a = 1\n let b = 2 }',
              )
              as MatchExpr;
      // outer = a (sem deps; empate desfeito em ordem-fonte → a antes de b).
      expect((m.arms.single.pattern as BindPattern).name, 'a');
      expect((m.scrutinee as IntLit).value, 1);
      final lvl2 = m.arms.single.body as MatchExpr;
      expect((lvl2.arms.single.pattern as BindPattern).name, 'b');
      expect((lvl2.scrutinee as IntLit).value, 2);
      final lvl3 = lvl2.arms.single.body as MatchExpr;
      expect((lvl3.arms.single.pattern as BindPattern).name, 'total');
      expect((lvl3.scrutinee as Binary).op, BinaryOp.add); // a + b AVALIADO por último
      expect((lvl3.arms.single.body as Ident).name, 'total'); // V no fundo
    });

    test('bindings independentes preservam ordem-fonte (nesting determinístico)', () {
      final m =
          desugarLetValue('let r = x where { let x = 1\n let y = 2 }')
              as MatchExpr;
      expect((m.arms.single.pattern as BindPattern).name, 'x'); // 1º na fonte
      expect(
        ((m.arms.single.body as MatchExpr).arms.single.pattern as BindPattern)
            .name,
        'y',
      );
    });
  });

  group('CA9 — retenção: Try / copy-with / ** NÃO expandem', () {
    test('e? permanece Try', () {
      expect(desugarLetValue('let r = e?'), isA<Try>());
    });
    test('p.{ x: 1 } permanece CopyWith', () {
      expect(desugarLetValue('let c = p.{ x: 1 }'), isA<CopyWith>());
    });
    test('a ** b permanece Binary.pow', () {
      final e = desugarLetValue('let q = a ** b') as Binary;
      expect(e.op, BinaryOp.pow);
    });
    test('guard let permanece GuardLetStmt (RD-1: early-return não cabe em => expr)', () {
      final p = desugarProgram(parseSource('guard let v = o else { return }').program);
      expect(p.body.single, isA<GuardLetStmt>());
      expect(findResidualSugar(p), isEmpty); // guard-let NÃO é açúcar da Fase 3
    });
  });

  group(r'$0-closure — aridade por scan sintático', () {
    test(r'{ $0 * 2 } → params explícitos [$0]', () {
      final p = desugarProgram(parseSource('let g = xs.map { \$0 * 2 }').program);
      final call = (p.body.single as LetStmt).value as Call;
      final closure = call.args.single.value as Closure;
      expect(closure.hasExplicitParams, isTrue);
      expect(closure.params.single.name, r'$0');
    });

    test(r'{ $0 + $1 } → aridade 2 [$0, $1]', () {
      final p = desugarProgram(
        parseSource('let h = xs.reduce { \$0 + \$1 }').program,
      );
      final call = (p.body.single as LetStmt).value as Call;
      final closure = call.args.single.value as Closure;
      expect(closure.params.map((e) => e.name).toList(), [r'$0', r'$1']);
    });

    test(r'closure implícita SEM $k mantém-se implícita (aridade contextual, Fase 5)', () {
      final p = desugarProgram(parseSource('let g = xs.each { f() }').program);
      final call = (p.body.single as LetStmt).value as Call;
      final closure = call.args.single.value as Closure;
      expect(closure.hasExplicitParams, isFalse);
    });

    test(r'$k em closure aninhada NÃO conta para a externa', () {
      // externa usa `$0`; interna usa `$0` também, mas isolado.
      final p = desugarProgram(
        parseSource('let g = a.map { b.map { \$0 } }').program,
      );
      final outer =
          ((p.body.single as LetStmt).value as Call).args.single.value
              as Closure;
      // A externa NÃO tem `$k` próprio (só dentro da interna) → permanece implícita.
      expect(outer.hasExplicitParams, isFalse);
    });

    // ORDEM do scan: no body BRUTO, antes do desugar. O `>>` embrulha em closure
    // sintética; se o scan rodasse depois, o `$k` cairia atrás dessa fronteira
    // (onde o scan para) → aridade 0 e `$0` unbound.
    Closure closureOf(String src) =>
        ((desugarProgram(parseSource(src).program).body.single as LetStmt).value
                as Call)
            .args
            .single
            .value
            as Closure;

    test(r'{ $0 >> f } → aridade 1 (o >> não esconde o $0 do scan)', () {
      final c = closureOf('let a = xs.map { \$0 >> f }');
      expect(c.hasExplicitParams, isTrue);
      expect(c.params.map((e) => e.name).toList(), [r'$0']);
    });

    test(r'{ f >> $0 } → aridade 1 (o $k do lado direito também conta)', () {
      final c = closureOf('let b = xs.map { f >> \$0 }');
      expect(c.params.map((e) => e.name).toList(), [r'$0']);
    });

    test(r'{ ($0 >> f)($1) } → aridade 2 (dentro e fora do compose)', () {
      final c = closureOf('let c = xs.map { (\$0 >> f)(\$1) }');
      expect(c.params.map((e) => e.name).toList(), [r'$0', r'$1']);
    });

    test(r'$k dentro de pattern interpolada conta para a aridade', () {
      final c = closureOf(
        'let d = xs.map { match y {\n "\${\$0}" => 1\n _ => 2\n} }',
      );
      expect(c.params.map((e) => e.name).toList(), [r'$0']);
    });

    // Grafia canônica: o param sintético é nomeado pelo decimal (`$1`), então o
    // USO precisa normalizar junto — senão `{ $01 }` declara `$1` e usa `$01`.
    // Mesma normalização que o léxico faz em `01`/`007` (intLiteral 1/7).
    test(r'{ $01 } normaliza o uso p/ $1 (declara e usa o MESMO nome)', () {
      final c = closureOf('let a = xs.map { \$01 * 2 }');
      expect(c.params.map((e) => e.name).toList(), [r'$0', r'$1']);
      final body = (c.body as ExprBody).e;
      expect(((body as Binary).left as Ident).name, r'$1'); // não `$01`
    });

    test(r'{ $01 + $1 } → grafias misturadas caem no MESMO param', () {
      final c = closureOf('let b = xs.map { \$01 + \$1 }');
      expect(c.params.map((e) => e.name).toList(), [r'$0', r'$1']);
      final body = (c.body as ExprBody).e as Binary;
      expect((body.left as Ident).name, r'$1');
      expect((body.right as Ident).name, r'$1'); // o mesmo param dos dois lados
    });

    test(r'gensym ($x0) NÃO é tocado pela normalização', () {
      // `$`+letra não é shorthand — _dollarIndex devolve null e o nome fica.
      final m = desugarExpr('a ?? b') as MatchExpr;
      final bind = (m.arms[0].pattern as EnumPattern).subpatterns.single
          as BindPattern;
      expect(bind.name, startsWith(r'$x'));
      expect((m.arms[0].body as Ident).name, bind.name);
    });

    test(r'a closure sintética do >> NÃO ganha params do escopo externo', () {
      // `($c) => f($0($c))` tem seu próprio param gensym; o `$0` que ela
      // referencia é o param da closure EXTERNA (capturado), não dela.
      final outer = closureOf('let a = xs.map { \$0 >> f }');
      final inner = (outer.body as ExprBody).e as Closure;
      expect(inner.params.single.name, startsWith(r'$c'));
    });

    // --- corpo de closure: bloco de 1 ExprStmt → ExprBody -------------------
    // Ruling do dono 2026-07-15. EXISTE para preservar RD-1, não para furá-lo:
    // a gramática só dá `trailingClosure ::= block`, então `{ $0 * 2 }` nasce
    // bloco e, por RD-1, não renderia — a closure daria Void e o idioma
    // `.map { … }` (ruling §12-1 da spec 010) não significaria nada. A saída é
    // tornar o `=>` EXPLÍCITO no desugar, visível em `itac desugar --dump` (P4).
    test(r'{ $0 * 2 } rende: corpo vira ExprBody (o => passa a existir)', () {
      final c = closureOf('let a = xs.map { \$0 * 2 }');
      expect(c.body, isA<ExprBody>());
      expect((c.body as ExprBody).e, isA<Binary>());
    });

    test('bloco MULTI-statement continua bloco — não há o que render', () {
      final c = closureOf('let a = xs.each { g()\n h() }');
      expect(c.body, isA<BlockBody>());
    });

    test('bloco de 1 stmt NÃO-expressão continua bloco', () {
      final c = closureOf('let a = xs.each { let z = 1 }');
      expect(c.body, isA<BlockBody>());
    });

    test('corpo de FN não é tocado — RD-1 intacto onde importa', () {
      // O escopo da regra é deliberadamente estreito: só CLOSURE. Senão
      // `fn f() -> Int { 5 }` passaria a render, e RD-1 cairia justo no caso
      // que ele governa.
      final p = desugarProgram(parseSource('fn f() -> Int { 5 }').program);
      expect((p.body.single as FnDecl).body, isA<BlockBody>());
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

/// Troca o sufixo `.tu` do arquivo por [ext] (ex.: `.desugar`).
String _sibling(File tu, String ext) =>
    '${tu.path.substring(0, tu.path.length - 3)}$ext';
