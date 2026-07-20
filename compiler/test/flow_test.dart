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
    test('Regime 1: `_` fecha coluna não-modelada (List) ⟹ verde', () {
      // A 3a modelou struct; List segue não-modelada até a 3b. O `_` decide
      // sem descer na estrutura (o corte moveu-se, o Regime 1 continua).
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { [1, 2] => 0, _ => 1 }'),
        isEmpty,
      );
    });
    test('Regime 2: Int só-literais (Σ∞) ⟹ Fatia 2 DECIDE `1 não coberto`', () {
      // F2: o átomo Int vira intervalo [0,0]; a testemunha do gap é CONCRETA
      // (`maxHi+1`), não mais `_`. É a promoção do interval-splitting.
      expect(codes('fn m(n: Int) -> Int => match n { 0 => 1 }'),
          contains('match-not-exhaustive'));
      expect(
          detailOf('fn m(n: Int) -> Int => match n { 0 => 1 }'), '1 não coberto');
    });
    test('Composição 3a+3b: produto com campo List (ambos modelados) ⟹ verde', () {
      // A recursão desce da struct no campo List, e a 3b o exaure (`[] + [_,..r]`).
      // Prova que produto e List compõem sem mascarar nem falsa-acusar.
      expect(
        codes('struct Wrap { xs: List<Int> }\n'
            'fn m(w: Wrap) -> Int => '
            'match w { Wrap { xs: [] } => 0, Wrap { xs: [_, ..r] } => 1 }'),
        isEmpty,
      );
    });
    test('Regime 3: a lacuna ESTREITOU — resta só `class` (unsupported)', () {
      // Produto/List DECIDEM; 2-rest morre na F5 (ruling (a)). O ÚNICO
      // `match-exhaustiveness-unsupported` remanescente é `class` sem um `_`
      // (ruling (e) do dono, ainda pendente).
      expect(
        codes('class Foo { x: Int }\n'
            'fn m(f: Foo) -> Int => match f { Foo { x: a } => 0 }'),
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

    // --- FATIA 2 (interval-splitting de Range — Maranget §3.2, testemunha
    //     CONCRETA). Blueprint §F2. Range vira intervalo [lo,hi] em BigInt;
    //     Int é ℤ ilimitado ⟹ só `_` exaure, mas o gap ganha valor concreto. ---
    test('F2/A: range não-exaustivo ⟹ testemunha CONCRETA `10 não coberto`', () {
      expect(codes('fn m(n: Int) -> Int => match n { 0..=9 => 1 }'),
          contains('match-not-exhaustive'));
      expect(detailOf('fn m(n: Int) -> Int => match n { 0..=9 => 1 }'),
          '10 não coberto');
    });
    test('F2/B: `_` fecha o range ⟹ verde (Regime 1)', () {
      expect(codes('fn m(n: Int) -> Int => match n { 0..=9 => 1, _ => 2 }'),
          isEmpty);
    });
    test('F2/C: range vazio invertido `9..=3` ⟹ morto por vacuidade', () {
      expect(codes('fn m(n: Int) -> Int => match n { 9..=3 => 1, _ => 2 }'),
          contains('unreachable-match-arm'));
    });
    test('F2/C\': range exclusivo vazio `5..5` ⟹ morto por vacuidade', () {
      expect(codes('fn m(n: Int) -> Int => match n { 5..5 => 1, _ => 2 }'),
          contains('unreachable-match-arm'));
    });
    test('F2/D: literal contido em range anterior `5 ⊂ 0..=9` ⟹ unreachable', () {
      expect(
        codes('fn m(n: Int) -> Int => match n { 0..=9 => 1, 5 => 2, _ => 3 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('F2/E: sobreposição PARCIAL `5..=15` sobre `0..=9` ⟹ verde', () {
      expect(
        codes('fn m(n: Int) -> Int => '
            'match n { 0..=9 => 1, 5..=15 => 2, _ => 3 }'),
        isEmpty,
      );
    });
    test('F2/F: range aninhado `.ok(0..=9)` ⟹ `.ok(10) não coberto`', () {
      expect(
        codes('fn m(r: Result<Int, String>) -> Int => '
            'match r { .ok(0..=9) => 1, .err(e) => 2 }'),
        contains('match-not-exhaustive'),
      );
      expect(
        detailOf('fn m(r: Result<Int, String>) -> Int => '
            'match r { .ok(0..=9) => 1, .err(e) => 2 }'),
        '.ok(10) não coberto',
      );
    });
    test('F2/G: regressão de precisão `.ok(0)` ⟹ `.ok(1) não coberto`', () {
      expect(
        detailOf('fn m(r: Result<Int, String>) -> Int => '
            'match r { .ok(0) => 1, .err(e) => 2 }'),
        '.ok(1) não coberto',
      );
    });
    test('F2/H: dois ranges disjuntos + `_` ⟹ verde, nenhum morto', () {
      expect(
        codes('fn m(n: Int) -> Int => '
            'match n { 0..=9 => 1, 10..=19 => 2, _ => 3 }'),
        isEmpty,
      );
    });
    test('F2/I: range totalmente contido `3..=6 ⊂ 0..=9` ⟹ unreachable', () {
      expect(
        codes('fn m(n: Int) -> Int => '
            'match n { 0..=9 => 1, 3..=6 => 2, _ => 3 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('F2/J: furo INTERIOR ⟹ testemunha é o furo (`6`), não `maxHi+1`', () {
      // Exercita `_gapValue` em regime não-trivial: [0,5]∪[10,15] deixa 6..9
      // descoberto; a testemunha honesta é o furo `6`, não `16`.
      expect(
        detailOf('fn m(n: Int) -> Int => match n { 0..=5 => 1, 10..=15 => 2 }'),
        '6 não coberto',
      );
    });
    test('F2/K: redundância por UNIÃO ⟹ `2..=8 ⊂ 0..=5 ∪ 4..=10`', () {
      // Nenhum range anterior sozinho contém [2,8]; a UNIÃO contém. O
      // interval-splitting decide (cada elementar recursa coberto).
      expect(
        codes('fn m(n: Int) -> Int => '
            'match n { 0..=5 => 1, 4..=10 => 2, 2..=8 => 3, _ => 4 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('F2/C-detail: range vazio ENSINA o porquê no `detail` (P4)', () {
      expect(
        detailOf('fn m(n: Int) -> Int => match n { 9..=3 => 1, _ => 2 }'),
        'range vazio (início > fim)',
      );
    });

    // --- FATIA 3a (PRODUTO — struct/record). Um tipo-produto é Σ de UM
    //     construtor (Maranget §3.1); RIDA o motor selado. Campo omitido = ω
    //     (ruling do dono 2026-07-19). Blueprint §F3. ---
    const point = 'struct Point { x: Int, y: Int }\n';
    test('P1: destructure total `Point{x,y}` (sem `_`) ⟹ verde (era unsupported)',
        () {
      expect(
        codes('${point}fn m(p: Point) -> Int => match p { Point { x: a, y: b } => 0 }'),
        isEmpty,
      );
    });
    test('P2: campo escalar parcial `Point{x: 0}` ⟹ testemunha CONCRETA', () {
      expect(
        codes('${point}fn m(p: Point) -> Int => match p { Point { x: 0, y: b } => 0 }'),
        contains('match-not-exhaustive'),
      );
      expect(
        detailOf('${point}fn m(p: Point) -> Int => match p { Point { x: 0, y: b } => 0 }'),
        'Point{x: 1, y: 0} não coberto',
      );
    });
    test('P3: `_` após destructure total ⟹ unreachable (produto já exaure)', () {
      expect(
        codes('${point}fn m(p: Point) -> Int => '
            'match p { Point { x: a, y: b } => 0, _ => 1 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('P4: produto ANINHADO em `.ok` ⟹ `.ok(Point{x: 1, y: 0}) não coberto`', () {
      expect(
        detailOf('${point}fn m(r: Result<Point, String>) -> Int => '
            'match r { .ok(Point { x: 0, y: b }) => 0, .err(e) => 1 }'),
        '.ok(Point{x: 1, y: 0}) não coberto',
      );
    });
    test('P5: braço de produto dominado por campo ⟹ unreachable', () {
      expect(
        codes('${point}fn m(p: Point) -> Int => '
            'match p { Point { x: 0, y: b } => 0, Point { x: 0, y: c } => 1, _ => 2 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('P6: campo OMITIDO conta como ω `Point{x: a}` ⟹ verde', () {
      expect(
        codes('${point}fn m(p: Point) -> Int => match p { Point { x: a } => 0 }'),
        isEmpty,
      );
    });

    // --- FATIA 3b (LIST — split por comprimento, rustc `Slice::split`). List é
    //     SEALED-like: o `..resto` torna o rabo ALCANÇÁVEL ⟹ `[] + [_,..]` é
    //     exaustivo de VERDADE (verde real, não unsupported). Blueprint §F3. ---
    test('L1: `[] + [_, ..r]` cobre toda List ⟹ verde (era unsupported!)', () {
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { [] => 0, [_, ..r] => 1 }'),
        isEmpty,
      );
    });
    test('L2: só `[]` ⟹ testemunha de comprimento maior `[0] não coberto`', () {
      expect(codes('fn m(xs: List<Int>) -> Int => match xs { [] => 0 }'),
          contains('match-not-exhaustive'));
      expect(detailOf('fn m(xs: List<Int>) -> Int => match xs { [] => 0 }'),
          '[0] não coberto');
    });
    test('L3: `[] + [x] + [x, y, ..r]` particiona 0/1/≥2 ⟹ verde', () {
      expect(
        codes('fn m(xs: List<Int>) -> Int => '
            'match xs { [] => 0, [x] => 1, [x, y, ..r] => 2 }'),
        isEmpty,
      );
    });
    test('L4: `[x, ..r]` não cobre a vazia ⟹ `[] não coberto`', () {
      expect(
        detailOf('fn m(xs: List<Int>) -> Int => match xs { [x, ..r] => 0 }'),
        '[] não coberto',
      );
    });
    test('L5: rest puro `[..]` cobre tudo ⟹ verde', () {
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { [..] => 0 }'),
        isEmpty,
      );
    });
    test('L6: redundância de List DEFERE (3b-ii) — abstém, não falsa-acusa', () {
      // `[x]` é dominado por `[_, ..r]`, mas o lint de redundância de List defere;
      // o importante: NÃO falsa-acusa e o match (exaustivo) fica verde.
      expect(
        codes('fn m(xs: List<Int>) -> Int => '
            'match xs { [_, ..r] => 0, [x] => 1, [] => 2 }'),
        isEmpty,
      );
    });
    test('L7: exaustividade do ELEMENTO dentro da List ⟹ `[false] não coberto`', () {
      expect(
        detailOf('fn m(xs: List<Bool>) -> Int => '
            'match xs { [] => 0, [true] => 1, [_, _, ..r] => 2 }'),
        '[false] não coberto',
      );
    });
    test('L8: 2-rest `[..a, ..b]` em MATCH ⟹ F5 barra (duplicate-rest-pattern)', () {
      // Ruling (a) do dono 2026-07-19: 2-rest é MALFORMADO (divisão indefinida),
      // não lacuna de análise — morre na F5, não chega à F6 (nem vira unsupported).
      final r = flow('fn m(xs: List<Int>) -> Int => match xs { [..a, ..b] => 0 }');
      expect(r.flow, isNull, reason: 'a F5 rejeita 2-rest');
      expect(
          r.check.errors.map((e) => e.code), contains('duplicate-rest-pattern'));
    });
    test('L9: 2-rest em `let` destructuring ⟹ F5 barra também (as DUAS portas)', () {
      // A porta B (irrefutável, sem F6): o furo do code-review. A F5 fecha as
      // duas — `match` e `let`/`var` — com a mesma regra.
      final r = flow('fn m(xs: List<Int>) -> Int { let [..a, ..b] = xs\n'
          '  return 0 }');
      expect(r.flow, isNull, reason: 'a F5 rejeita 2-rest em let também');
      expect(
          r.check.errors.map((e) => e.code), contains('duplicate-rest-pattern'));
    });

    // --- FATIA 3c (STRING). A exaustividade já é Fatia 1 (Σ∞, testemunha `_`);
    //     a 3c dá REDUNDÂNCIA exata de String CONSTANTE + a F5 bane a interpolada
    //     (ruling do dono 2026-07-19: pattern com valor de runtime é guard). ---
    test('S1: String literal duplicada ⟹ unreachable (chave de igualdade real)', () {
      expect(
        codes('fn m(s: String) -> Int => match s { "a" => 0, "a" => 1, _ => 2 }'),
        contains('unreachable-match-arm'),
      );
    });
    test('S2: Strings DISTINTAS não são redundantes ⟹ verde', () {
      expect(
        codes('fn m(s: String) -> Int => match s { "a" => 0, "b" => 1, _ => 2 }'),
        isEmpty,
      );
    });
    test('S3: Str INTERPOLADA em pattern ⟹ banida na F5 (não chega à F6)', () {
      final r = flow('fn m(s: String) -> Int => '
          'match s { "a\${s}b" => 0, _ => 1 }');
      expect(r.flow, isNull, reason: 'a F5 barra o pattern interpolado');
      expect(r.check.errors.map((e) => e.code),
          contains('interpolated-string-pattern'));
    });

    // --- Achados do W3 adversarial (2026-07-19) aplicados. ---
    test('W3🔴: campo DUPLICADO `Point{x: 0, x: 1}` ⟹ F5 barra (soundness)', () {
      // Sem o gate, `_subPatternsProd` resolveria first-wins em silêncio ⟹
      // falso-verde de exaustividade. A F5 rejeita como faz p/ `unknown-field`.
      final r = flow('${point}fn m(p: Point) -> Int => '
          'match p { Point { x: 0, x: 1, y: b } => 0 }');
      expect(r.flow, isNull, reason: 'a F5 barra o campo duplicado');
      expect(
          r.check.errors.map((e) => e.code), contains('duplicate-field-pattern'));
    });
    test('W3🟡: testemunha do rabo com fixos > aridade ⟹ comprimento > L honesto',
        () {
      // maxPre+maxSuf=1 < L=3; a testemunha tem de ter comprimento > L (senão
      // colide com um comprimento fixo já coberto). `tailArity = max(L+1, …)`.
      expect(
        detailOf('fn m(xs: List<Int>) -> Int => match xs { '
            '[] => 0, [_] => 1, [_, _] => 2, [_, _, _] => 3, [1, ..r] => 4 }'),
        '[2, 0, 0, 0] não coberto',
      );
    });
    // Débito de teste do W3 (verificação 2026-07-19): o ramo `_specializeTail`
    // com SUFIXO (`[.., y]`) não era exercitado (L1-L9 são prefixo-puro).
    test('L10: SUFIXO após `..` — `[.., 9]` num gap ⟹ testemunha honesta', () {
      expect(
        detailOf('fn m(xs: List<Int>) -> Int => '
            'match xs { [] => 0, [_] => 1, [.., 9] => 2 }'),
        '[0, 10] não coberto', // comprimento 2 > L=1, não termina em 9
      );
    });
    test('L11: prefixo E sufixo `[a, b, ..r] + [..s, y, z]` exaure ⟹ verde', () {
      // maxPre=2, maxSuf=2, tailArity=4; o `[a, b, ..r]` (prefixo ω) cobre todo
      // comprimento ≥2, e `[] + [_]` os menores. Exercita `maxPre+maxSuf > L`.
      expect(
        codes('fn m(xs: List<Int>) -> Int => match xs { '
            '[] => 0, [_] => 1, [a, b, ..r] => 2, [..s, y, z] => 3 }'),
        isEmpty,
      );
    });
    // Achado do code-review final (2026-07-19): literal escalar contra `T?`.
    test('review🔴: literal contra `Int?` ⟹ F5 barra (não vaza `_HInt` no Option)',
        () {
      // `0` passava por `Int <: Int?` e virava braço MORTO silencioso na F6
      // (coluna Option selada, testemunha imprecisa `.some(_)`). A F5 agora exige
      // `.some(0)`/`nil` (§4.6) — espelha a Cerca 2 de list e o range exato.
      final r = flow('fn m(x: Int?) -> Int => '
          'match x { .some(v) => 1, 0 => 2, .none => 3 }');
      expect(r.flow, isNull, reason: 'a F5 barra o literal contra T?');
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
