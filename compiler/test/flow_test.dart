// ============================================================================
// flow_test.dart — Fase 6, 1º lote: o flow-walk (spec 014 §2–§3).
// ============================================================================
//
// Três blocos, espelho do `collect_test.dart`:
//  1. Conformância verde: `conformance/flow/*.tu` com golden `.facts` — exige
//     ZERO erros + dump `--dump-facts` byte-igual (a nº8 é o observável).
//  2. Conformância de erro: lista EXATA de `// EXPECT-FLOW:` em ordem-fonte —
//     casos verdes no MEIO dos fixtures são de propósito (falso-positivo
//     neles quebra a lista; o padrão do `err_try.tu`).
//  3. Asserts unitários dos casos-armadilha do blueprint da 014
//     (`specs/014-flow-check/blueprint-flow-walk.md`) §13: as duas formas
//     de região aninhada (§6), `+=` como USO+GEN, merge ∩ com braço-Never,
//     closure aninhada (§5), while-true × loop interno (§7), async/asyncStar
//     no predicado de retorno (§11).
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/analysis/flow.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:test/test.dart';

void main() {
  ({CheckResult check, FlowResult? flow}) flow(String src) {
    final parsed = parseSource(src);
    // Sem isto um erro de parse RECUPERADO (M2) rodaria a F6 sobre árvore com
    // nós de erro e o teste afirmaria sobre o programa errado em silêncio.
    expect(parsed.hasErrors, isFalse, reason: 'parse limpo');
    return flowProgram(parsed.program);
  }

  /// Códigos da F6 de um programa que TEM de passar a F5 (o gate I3): se o
  /// `flow` vier nulo, o teste morre aqui com a razão — não em cascata.
  List<String> codes(String src) {
    final r = flow(src);
    expect(
      r.flow,
      isNotNull,
      reason: 'F5 barrou: ${r.check.errors.map((e) => e.format()).join('; ')}',
    );
    return r.flow!.errors.map((e) => e.code).toList();
  }

  /// Offsets dos erros — os testes de região morta afirmam ONDE, não só o quê.
  List<int> offsets(String src) {
    final r = flow(src);
    expect(r.flow, isNotNull);
    return r.flow!.errors.map((e) => e.offset).toList();
  }

  // --------------------------------------------------------------------------
  // 1. Conformância verde — dump == golden .facts
  // --------------------------------------------------------------------------
  group('conformance/flow — dump == golden .facts', () {
    final dir = Directory('${_conformanceRoot()}/flow');
    for (final tu in _tuFiles(dir)) {
      final goldenPath = '${tu.path.substring(0, tu.path.length - 3)}.facts';
      if (!File(goldenPath).existsSync()) continue;
      test(tu.uri.pathSegments.last, () {
        final src = tu.readAsStringSync();
        final parsed = parseSource(src);
        expect(parsed.hasErrors, isFalse, reason: '${tu.path}: parse limpo');
        final res = flowProgram(parsed.program);
        expect(res.check.errors, isEmpty, reason: '${tu.path}: F5 limpa');
        expect(res.flow!.errors, isEmpty, reason: '${tu.path}: sem erro de fluxo');
        expect(
          flowFactsDump(res.flow!).trimRight(),
          File(goldenPath).readAsStringSync().trimRight(),
        );
      });
    }
  });

  // --------------------------------------------------------------------------
  // 2. Conformância de erro — lista EXATA de // EXPECT-FLOW
  // --------------------------------------------------------------------------
  group('conformance/flow — erros == // EXPECT-FLOW', () {
    final dir = Directory('${_conformanceRoot()}/flow');
    for (final tu in _tuFiles(dir)) {
      final src = tu.readAsStringSync();
      final expected = _expectLines(src);
      if (expected.isEmpty) continue;
      test(tu.uri.pathSegments.last, () {
        // Ordem-FONTE (o `analyzeFlow` ordena por offset) — a ordem que o
        // usuário lê.
        expect(codes(src), expected);
      });
    }
  });

  // --------------------------------------------------------------------------
  // 3. Unit — os casos-armadilha
  // --------------------------------------------------------------------------
  group('§6 — unreachable-code sem cascata (as duas regiões aninhadas)', () {
    test('morto DENTRO de morto: nunca walkado ⟹ UM erro, no `if` inteiro', () {
      const src = 'fn f(c: Bool) -> Int {\n'
          '  return 1\n'
          '  if c {\n'
          '    let junk = 2\n'
          '  }\n'
          '}';
      expect(codes(src), ['unreachable-code']);
      // O span é o do `if` (o primeiro morto) — o junk lá dentro nem existe
      // para o walk; e o corpo que não completa NUNCA soma missing-return.
      expect(offsets(src), [src.indexOf('if c')]);
    });

    test('morte que ATRAVESSA bloco nu: `{ return; x } y` = UMA região, UM erro', () {
      const src = 'fn f() -> Int {\n'
          '  {\n'
          '    return 1\n'
          '    let dentro = 2\n'
          '  }\n'
          '  let fora = 3\n'
          '}';
      expect(codes(src), ['unreachable-code']);
      expect(offsets(src), [src.indexOf('let dentro')]); // no interno, não no `fora`
    });

    test('`if {return} else {return} y`: nenhum flag em pé ⟹ o erro é em y', () {
      const src = 'fn f(c: Bool) -> Int {\n'
          '  if c {\n'
          '    return 1\n'
          '  } else {\n'
          '    return 2\n'
          '  }\n'
          '  let y = 3\n'
          '}';
      expect(codes(src), ['unreachable-code']);
      expect(offsets(src), [src.indexOf('let y')]);
    });

    test('braços são regiões DISTINTAS: morto no then E no else acusam os dois', () {
      // A morte só atravessa bloco NU; fronteira de branch fecha a região —
      // dois pecados, dois spans (é o que mantém `y` acusável no teste acima).
      const src = 'fn f(c: Bool) -> Int {\n'
          '  if c {\n'
          '    return 1\n'
          '    let a = 2\n'
          '  } else {\n'
          '    return 2\n'
          '    let b = 3\n'
          '  }\n'
          '}';
      expect(codes(src), ['unreachable-code', 'unreachable-code']);
    });

    test('região FECHA quando um stmt completa: dois mortos separados = dois erros', () {
      const src = 'fn f(c: Bool) -> Int {\n'
          '  if c {\n'
          '    return 1\n'
          '    let a = 1\n'
          '  }\n'
          '  let vivo = 2\n'
          '  if c {\n'
          '    return 2\n'
          '    let b = 3\n'
          '  }\n'
          '  return 3\n'
          '}';
      expect(codes(src), ['unreachable-code', 'unreachable-code']);
    });
  });

  group('§4 — Never type-informed (a linha da spec §2, por nó)', () {
    test('`let x = panic(…)` encerra — a extensão Kotlin da mesma regra', () {
      expect(
        codes('fn f() -> Int {\n  let x = panic("TODO")\n  let y = 1\n}'),
        ['unreachable-code'],
      );
    });

    test('`emit panic(…)` encerra — EmitStmt tem a mesma regra da nº1', () {
      expect(
        codes('stream fn f() -> Int {\n  emit panic("boom")\n  let y = 1\n}'),
        ['unreachable-code'],
      );
    });

    test('fronteira DELIBERADA (§14-L4): Never ANINHADO não propaga', () {
      // `x = panic(…)` tem tipo(Assign) = Void ⟹ o ExprStmt COMPLETA e a fn
      // acusa missing-return — o falso-positivo benigno documentado (o JLS
      // §14.21 faz igual: throw dentro de expressão não conta).
      expect(
        codes('fn f() -> Int {\n  var x: Int\n  x = panic("boom")\n}'),
        ['missing-return'],
      );
    });
  });

  group('nº1 total em interpolação — regressão do E1 do W3 (2026-07-17)', () {
    // O achado do W3 técnico: a F5 sintetizava `Str → StringType` sem descer
    // nas partes (violando a totalidade da 009 §7-4), e a F6 consulta a nº1
    // DENTRO delas — `${if …}`/`${match …}` em string estouravam StateError
    // em programa VERDE. O fix é o dedo na F5 (check.dart, case Str); aqui
    // fica a regressão pela F6: o pipeline inteiro roda e nada estoura.
    test('`\${if c => 1 else 2}` em string: verde, sem crash', () {
      expect(
        codes('fn f(c: Bool) -> String {\n'
            '  return "a\${if c => 1 else 2}b"\n'
            '}'),
        isEmpty,
      );
    });

    test('`\${match …}` em string: verde, sem crash', () {
      expect(
        codes('fn f(c: Bool) -> String {\n'
            '  return "\${match c { true => 1, false => 2 }}"\n'
            '}'),
        isEmpty,
      );
    });

    test('interpolação LÊ a var: `\${x}` fora do DA é uso', () {
      const src = 'fn f() -> String {\n  var x: Int\n  return "v=\${x}"\n}';
      expect(codes(src), ['use-before-assign']);
    });
  });

  group('§3 — DA: `+=` é USO+GEN (JLS §16.1.8)', () {
    test('`x += 1` sobre var não-atribuído LÊ antes ⟹ use-before-assign', () {
      const src = 'fn f() -> Int {\n  var x: Int\n  x += 1\n  return x\n}';
      expect(codes(src), ['use-before-assign']);
      // UM erro só: o GEN do próprio `+=` paga o uso do `return x`.
      expect(offsets(src), [src.indexOf('x +=')]);
    });

    test('atribuído antes, `+=` passa e continua GEN', () {
      expect(
        codes('fn f() -> Int {\n  var x: Int\n  x = 1\n  x += 2\n  return x\n}'),
        isEmpty,
      );
    });
  });

  group('§3 — merge ∩ com braço-Never = ⊤ (neutro, por omissão)', () {
    test('if-STATEMENT: braço que panica não restringe o ∩', () {
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  var x: Int\n'
            '  if c {\n'
            '    x = 1\n'
            '  } else {\n'
            '    panic("boom")\n'
            '  }\n'
            '  return x\n'
            '}'),
        isEmpty,
      );
    });

    test('match-EXPRESSÃO: braço-Never neutro no ∩ (a forma do §2.2)', () {
      // Braço de match admite Assign (`=> expression`); braço de if-expr NÃO
      // (a gramática corta acima do nível 1) — o match é onde o GEN-em-braço
      // de expressão é exprimível.
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  var x: Int\n'
            '  match c {\n'
            '    true => x = 1,\n'
            '    false => panic("boom"),\n'
            '  }\n'
            '  return x\n'
            '}'),
        isEmpty,
      );
    });

    test('if-EXPRESSÃO: uso dentro de braço é checado contra o DA de entrada', () {
      const src = 'fn f(c: Bool) -> Int {\n'
          '  var x: Int\n'
          '  let r: Int = if c => x else panic("boom")\n'
          '  return r\n'
          '}';
      expect(codes(src), ['use-before-assign']);
      expect(offsets(src), [src.indexOf('x else')]);
    });

    test('contra-prova: braço que completa SEM atribuir derruba o ∩', () {
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  var x: Int\n'
            '  if c {\n'
            '    x = 1\n'
            '  } else {\n'
            '    let outro = 2\n'
            '  }\n'
            '  return x\n'
            '}'),
        ['use-before-assign'],
      );
    });
  });

  group('§5 — closures: obrigação na criação, DA herdado, aninhamento', () {
    test('pre-scan é TRANSITIVO: o Ident profundo conta na criação da EXTERNA', () {
      // A externa erra UMA vez (anticascata: o binder entra na cópia do DA ⟹
      // a criação da interna não re-acusa); o uso de fora segue erro próprio.
      const src = 'fn f() -> Int {\n'
          '  var x: Int\n'
          '  let fora = () => {\n'
          '    let dentro = () => {\n'
          '      x = 1\n'
          '    }\n'
          '    let marca = 1\n'
          '  }\n'
          '  return x\n'
          '}';
      expect(codes(src), ['capture-before-assign', 'use-before-assign']);
      expect(offsets(src), [src.indexOf('x = 1'), src.indexOf('return x') + 7]);
    });

    test('local da closure EXTERNA capturado pela INTERNA: a obrigação é da interna', () {
      const src = 'fn f() -> Void {\n'
          '  let fora = () => {\n'
          '    var y: Int\n'
          '    let dentro = () => {\n'
          '      let z = y\n'
          '    }\n'
          '    y = 2\n'
          '  }\n'
          '}';
      expect(codes(src), ['capture-before-assign']);
      expect(offsets(src), [src.indexOf('= y\n') + 2]);
    });

    test('write-only também é obrigação (delta anotado vs C#, §14-L2)', () {
      expect(
        codes('fn f() -> Void {\n'
            '  var x: Int\n'
            '  let g = () => {\n'
            '    x = 1\n'
            '    let marca = 2\n'
            '  }\n'
            '}'),
        ['capture-before-assign'],
      );
    });

    test('closure de corpo-bloco entra no predicado §11 (closure É fn)', () {
      // Bloco multi-statement (o de 1 expr vira `=>` na F3 — RD-1) que cai do
      // fim com retorno anotado non-Void: o MESMO buraco de soundness da fn.
      expect(
        codes('fn f() -> Void {\n'
            '  let g = () -> Int => {\n'
            '    let a = 1\n'
            '    let b = 2\n'
            '  }\n'
            '}'),
        ['missing-return'],
      );
    });
  });

  group('§7 — while-true: binding do break e fronteiras', () {
    test('break em loop INTERNO não destrava o while-true externo', () {
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  while true {\n'
            '    while c {\n'
            '      break\n'
            '    }\n'
            '  }\n'
            '}'),
        isEmpty, // o while-true segue infinito ⟹ o corpo não cai do fim
      );
    });

    test('break dentro de CLOSURE não destrava o while-true externo (§8 da spec)', () {
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  while true {\n'
            '    let roda = () => {\n'
            '      while c {\n'
            '        break\n'
            '      }\n'
            '      let volta = 1\n'
            '    }\n'
            '  }\n'
            '}'),
        isEmpty,
      );
    });

    test('break maybe-unassigned derruba o ∩ dos snapshots (JLS §16.2.10)', () {
      expect(
        codes('fn f(c: Bool) -> Int {\n'
            '  var x: Int\n'
            '  while true {\n'
            '    if c {\n'
            '      x = 1\n'
            '    }\n'
            '    break\n'
            '  }\n'
            '  return x\n'
            '}'),
        ['use-before-assign'],
      );
    });
  });

  group('§11 — missing-return: async entra, asyncStar isento', () {
    test('`async fn -> Int` que cai do fim ERRA (o Future completaria com null)', () {
      expect(
        codes('async fn f() -> Int {\n  let x = 1\n}'),
        ['missing-return'],
      );
    });

    test('`async fn -> Int` com return em todo caminho passa', () {
      expect(codes('async fn f() -> Int {\n  return 1\n}'), isEmpty);
    });

    test('`stream fn -> Int` é isento: rende por emit, fim-de-corpo fecha o stream', () {
      expect(codes('stream fn f() -> Int {\n  emit 1\n}'), isEmpty);
    });

    test('`-> Never` NÃO é isento (spec §3: vale igual)', () {
      expect(
        codes('fn f() -> Never {\n  let x = 1\n}'),
        ['missing-return'],
      );
    });
  });

  group('nº8 — flowFacts (chave, RD-1, dump)', () {
    test('corpo `=>` NÃO entra; corpo-bloco de fn e de closure entram', () {
      final r = flow('fn seta() -> Int => 1\n'
          'fn bloco() -> Void {\n'
          '  let f = () => {\n'
          '    let a = 1\n'
          '    let b = 2\n'
          '  }\n'
          '}');
      expect(r.flow, isNotNull);
      final dump = flowFactsDump(r.flow!);
      expect(dump, isNot(contains('seta'))); // RD-1: `=>` nunca cai do fim
      expect(dump, contains('fn bloco'));
      expect(dump, contains('closure'));
      expect(dump, contains('completes=true'));
    });

    test('em programa verde o fato acompanha o predicado (CA2 na tabela)', () {
      final r = flow('fn explode() -> Int {\n  panic("x")\n}');
      final entry = r.flow!.completesNormally.entries.single;
      expect(entry.value, isFalse);
    });
  });

  group('driver — gate I3 e a família de exit codes', () {
    test('erro de F5 barra a F6: flow == null, erros da F5 preservados', () {
      final r = flow('fn f() -> Int {\n  return "s"\n}');
      expect(r.flow, isNull);
      expect(r.check.errors.map((e) => e.code), contains('type-mismatch'));
    });

    test('erro de F4 barra antes: unresolved-before-check (espelho do checkProgram)', () {
      final r = flow('fn f() -> Int {\n  return bogus\n}');
      expect(r.flow, isNull);
      expect(r.check.errors.map((e) => e.code), ['unresolved-before-check']);
    });

    test('flowErrorDump: uma linha por erro, formato canônico', () {
      final r = flow('fn f() -> Int {\n  let x = 1\n}');
      expect(flowErrorDump(r.flow!.errors), 'flow-error: missing-return @0+29');
    });

    test('runFlow: 0 verde (com --dump-facts), 65 erro de fluxo, 65 gate F5', () {
      final dir = Directory.systemTemp.createTempSync('ita_flow_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final verde = File('${dir.path}/verde.tu')
        ..writeAsStringSync('fn f() -> Int {\n  return 1\n}');
      final fluxo = File('${dir.path}/fluxo.tu')
        ..writeAsStringSync('fn f() -> Int {\n  let x = 1\n}');
      final tipo = File('${dir.path}/tipo.tu')
        ..writeAsStringSync('fn f() -> Int {\n  return "s"\n}');

      final out = StringBuffer();
      final err = StringBuffer();
      expect(runFlow([verde.path, '--dump-facts'], out: out, err: err), 0);
      expect(out.toString().trim(), 'fn f @0+28 completes=false');
      expect(err.toString(), isEmpty);

      final err2 = StringBuffer();
      expect(runFlow([fluxo.path], out: StringBuffer(), err: err2), 65);
      expect(err2.toString().trim(), 'flow-error: missing-return @0+29');

      final err3 = StringBuffer();
      expect(runFlow([tipo.path], out: StringBuffer(), err: err3), 65);
      expect(err3.toString(), contains('check-error: type-mismatch'));
    });

    test('runFlow: 64 sem arquivo, 66 arquivo inexistente', () {
      expect(runFlow([], out: StringBuffer(), err: StringBuffer()), 64);
      expect(
        runFlow(['/nao/existe.tu'], out: StringBuffer(), err: StringBuffer()),
        66,
      );
    });
  });

  // --------------------------------------------------------------------------
  // 4. LT-F6b — exaustividade + redundância de `match` (Maranget §3.1).
  //    Casos-âncora do blueprint §F1; o corte do §12-11 (ruling do dono) nos
  //    três regimes. `detail` = testemunha em superfície (só em UNIT).
  // --------------------------------------------------------------------------
  group('spec 014 LT-F6b — exaustividade de `match` (Maranget)', () {
    String? detailOf(String src) {
      final r = flow(src);
      expect(r.flow, isNotNull,
          reason: r.check.errors.map((e) => e.format()).join('; '));
      return r.flow!.errors.isEmpty ? null : r.flow!.errors.first.detail;
    }

    // --- tipos FECHADOS: Σ conhecido, Maranget exato + testemunha ---
    test('Bool não-exaustivo ⟹ `false não coberto`', () {
      expect(codes('fn m(b: Bool) -> Int => match b { true => 0 }'),
          contains('match-not-exhaustive'));
      expect(detailOf('fn m(b: Bool) -> Int => match b { true => 0 }'),
          'false não coberto');
    });
    test('Bool exaustivo ⟹ verde', () {
      expect(codes('fn m(b: Bool) -> Int => match b { true => 0, false => 1 }'),
          isEmpty);
    });
    test('Option: falta `.none` ⟹ `.none não coberto`', () {
      expect(detailOf('fn m(o: Int?) -> Int => match o { .some(x) => x }'),
          '.none não coberto');
    });
    test('Option exaustivo — `nil` normaliza p/ none ⟹ verde', () {
      expect(
          codes('fn m(o: Int?) -> Int => match o { .some(x) => x, nil => 0 }'),
          isEmpty);
    });
    test('Result: testemunha ANINHADA `.ok(false) não coberto`', () {
      expect(
        detailOf('fn m(r: Result<Bool, String>) -> Int => '
            'match r { .ok(true) => 0, .err(e) => 1 }'),
        '.ok(false) não coberto',
      );
    });
    test('enum de 3 variantes: falta uma ⟹ `.Blue não coberto`', () {
      expect(
        detailOf('enum Color { Red, Green, Blue }\n'
            'fn m(c: Color) -> Int => match c { .Red => 0, .Green => 1 }'),
        '.Blue não coberto',
      );
    });

    // --- REDUNDÂNCIA (unreachable-match-arm) ---
    test('braço dominado por `_` anterior ⟹ unreachable-match-arm', () {
      expect(
        codes('enum Color { Red, Green, Blue }\n'
            'fn m(c: Color) -> Int => match c { .Red => 0, _ => 1, .Green => 2 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('`nil` após `.none` ⟹ unreachable (nil ≡ none)', () {
      expect(
        codes('fn m(o: Int?) -> Int => '
            'match o { .some(x) => x, .none => 0, nil => 1 }'),
        contains('unreachable-match-arm'),
      );
    });

    // --- os TRÊS regimes do §12-11 (o corte do dono: PEDRA, não mente) ---
    test('Regime 1: `_` fecha Int ⟹ verde (literal nem inspecionado)', () {
      expect(codes('fn m(n: Int) -> Int => match n { 0 => 1, _ => 2 }'), isEmpty);
    });
    test('Regime 1: `_` fecha struct (nem inspecionado) ⟹ verde', () {
      expect(
        codes('struct Point { x: Int, y: Int }\n'
            'fn m(p: Point) -> Int => match p { Point { x: a, y: b } => 0, _ => 1 }'),
        isEmpty,
      );
    });
    test('Regime 2: Int só-literais (Σ∞) ⟹ Fatia 1 DECIDE `_ não coberto`', () {
      expect(codes('fn m(n: Int) -> Int => match n { 0 => 1 }'),
          contains('match-not-exhaustive'));
      expect(
          detailOf('fn m(n: Int) -> Int => match n { 0 => 1 }'), '_ não coberto');
    });
    test('Regime 3: struct num gap ⟹ lacuna declarada (não mente nem chuta)', () {
      expect(
        codes('struct Point { x: Int, y: Int }\n'
            'fn m(p: Point) -> Int => match p { Point { x: a, y: b } => 0 }'),
        contains('match-exhaustiveness-unsupported'),
      );
    });
    test('Regime 3: List num gap ⟹ lacuna declarada (Fatia 3)', () {
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { [] => 0, [_, ..r] => 1 }'),
        contains('match-exhaustiveness-unsupported'),
      );
    });
    test('Regime 3 NÃO dispara quando `_` fecha — não falsa-acusa', () {
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { [] => 0, _ => 1 }'),
        isEmpty,
      );
    });

    // Linchpin (W3): a soundness de `_specialize` em coluna SELADA depende de a F5
    // rejeitar literal mistyped ANTES da F6 (gate I3, driver.dart:375). Se a F5
    // abrisse buraco aqui, a exaustividade ficaria unsound em SILÊNCIO — contra o
    // §12-11. Este teste ancora a dependência: `5` (Int) numa coluna Bool morre
    // na F5 e NUNCA chega ao `_specialize` da F6.
    test('linchpin F5→F6: literal mistyped em coluna selada morre na F5', () {
      final r = flow('fn m(b: Bool) -> Int => match b { 5 => 0, _ => 1 }');
      expect(r.flow, isNull, reason: 'a F5 tem de barrar antes da F6 rodar');
      expect(r.check.errors.map((e) => e.code), contains('pattern-type-mismatch'));
    });
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
    .where((l) => l.startsWith('// EXPECT-FLOW:'))
    .map((l) => l.substring('// EXPECT-FLOW: '.length))
    .toList();
