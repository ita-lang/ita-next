// ============================================================================
// golden_test.dart — o GOLDEN-RUNNER do emitter (spec 013 §7.2, §7.7, §11).
// ============================================================================
//
// Harness próprio (sem `package:test` — ver `kernel-vs-package-test-conflict`).
// Rodar com o dart PINADO:
//
//   ../.dart-sdk/3.12.2/dart-sdk/bin/dart run test/golden_test.dart [--update]
//
// O que ele prova, por fixture de `conformance/codegen/`:
//
//   1. o `.tu` compila pelo MESMO `compileToDill` que o `itac build` usa
//      (lib/compile.dart — uma fonte de verdade, não uma réplica);
//   2. o `.dill` resultante RODA na Dart VM pinada;
//   3. o **stdout** casa byte a byte com o golden `<nome>.out`;
//   4. o **exit code** casa com o esperado (`// EXPECT-EXIT:`, default 0).
//
// Isto é o que os testes de `sanitize`/`finalize` NÃO cobrem: eles verificam a
// higiene e a boa-formação do `.dill` (o verify aceita), não o que o programa
// IMPRIME. Um emitter que troque `~/` por `/`, ou `<` por `<=`, produz `.dill`
// perfeitamente válido — e saída errada. Só a execução pega.
//
// ⚠️ **ALVO: VM (JIT), apenas.** A §7.7 pede os 3 alvos (VM/AOT/JS) no CI; AOT
// (`dart compile exe`) e JS (`dart2js`) são fatias FUTURAS e este runner não os
// roda — nem finge que rodou (o cabeçalho do relatório declara o alvo).
//
// ---------------------------------------------------------------------------
// Fixtures de FRONTEIRA (`// EXPECT-ICE:`)
// ---------------------------------------------------------------------------
// Um fixture pode declarar que a emissão AINDA não sabe baixá-lo, com o
// `ice-codegen-*` que ela devolve (§7.8). Não é decoração: quando a fatia nascer,
// o fixture para de dar ICE e o runner FALHA, cobrando a promoção a CA verde.
// É a fila de trabalho da §7.4, executável.
//
// ---------------------------------------------------------------------------
// `--update`
// ---------------------------------------------------------------------------
// Regrava os `.out` a partir da execução atual. Use só depois de LER a saída
// nova: golden regravado sem olhar é golden que registra o bug.

import 'dart:convert';
import 'dart:io';

import 'package:ita_next_codegen/compile.dart';

int _fails = 0;

void check(bool cond, String label) {
  print('  ${cond ? '✓' : '✗ FAIL:'} $label');
  if (!cond) _fails++;
}

void fail(String label, {String? detail}) {
  print('  ✗ FAIL: $label');
  if (detail != null && detail.isNotEmpty) {
    for (final line in detail.trimRight().split('\n')) {
      print('      $line');
    }
  }
  _fails++;
}

/// Diretivas do header de um fixture (comentários `//` antes do código).
///
///   `// EXPECT-ICE: <code>`  — espera falha de emissão com esse `ice-codegen-*`
///                              (exit 70 do compilador); sem golden `.out`.
///   `// EXPECT-EXIT: <n>`    — exit code esperado do PROGRAMA (default 0).
typedef Directives = ({String? expectIce, int expectExit});

Directives parseDirectives(String source) {
  String? ice;
  var exit = 0;
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (!line.startsWith('//')) continue;
    final body = line.substring(2).trim();
    if (body.startsWith('EXPECT-ICE:')) {
      ice = body.substring('EXPECT-ICE:'.length).trim();
    } else if (body.startsWith('EXPECT-EXIT:')) {
      exit = int.parse(body.substring('EXPECT-EXIT:'.length).trim());
    }
  }
  return (expectIce: ice, expectExit: exit);
}

Future<void> main(List<String> args) async {
  final update = args.contains('--update');
  final root = _conformanceRoot();
  final dir = Directory('$root/codegen');
  if (!dir.existsSync()) {
    throw StateError('corpus não encontrado: ${dir.path}');
  }

  final fixtures = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tu'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // O `vm_platform.dill` (8 MB) é lido UMA vez; cada compilação desserializa um
  // `Component` FRESCO desses bytes — o `finalizeProgram` muta o platform
  // (anexa as libs do programa), logo reusar o mesmo Component acumularia libs
  // de um fixture no seguinte.
  final platformBytes = File(platformDillPath()).readAsBytesSync();

  print('Golden-runner do emitter — ${fixtures.length} fixtures');
  print('  corpus: ${dir.path}');
  print('  alvo:   VM (JIT) — AOT e JS são fatias futuras (§7.7), NÃO rodados');
  print('  dart:   ${Platform.resolvedExecutable}');
  if (update) print('  modo:   --update (regravando os .out)');
  print('');

  final tempDir = Directory.systemTemp.createTempSync('ita_golden_');
  try {
    for (final fixture in fixtures) {
      final name = fixture.uri.pathSegments.last;
      final stem = name.substring(0, name.length - 3);
      final source = fixture.readAsStringSync();
      final directives = parseDirectives(source);
      print('$name:');

      final outcome = compileToDill(fixture.path, platformBytes: platformBytes);

      // ---- fixture de FRONTEIRA: o ICE É o resultado esperado --------------
      final expectIce = directives.expectIce;
      if (expectIce != null) {
        if (outcome.code == null) {
          fail(
            'esperava $expectIce, mas COMPILOU — a fatia nasceu? '
            'promova a fixture a CA verde (crie o .out e remova o EXPECT-ICE)',
          );
        } else if (outcome.code != 70) {
          fail(
            'esperava ICE (70), veio exit ${outcome.code} '
            '(erro de FASE — a fixture parou antes da emissão)',
            detail: outcome.diagnostics.join('\n'),
          );
        } else {
          final got = outcome.diagnostics.join('\n');
          check(got.contains(expectIce),
              'ICE honesto: $expectIce${got.contains(expectIce) ? '' : ' (veio: $got)'}');
        }
        print('');
        continue;
      }

      // ---- fixture VERDE: compila, roda, compara stdout + exit -------------
      if (outcome.code != null) {
        fail(
          'não compilou (exit ${outcome.code})',
          detail: outcome.diagnostics.join('\n'),
        );
        print('');
        continue;
      }

      final dillPath = '${tempDir.path}/$stem.dill';
      File(dillPath).writeAsBytesSync(outcome.bytes!);
      final proc = await Process.run(
        Platform.resolvedExecutable,
        [dillPath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final stdoutText = proc.stdout as String;
      final stderrText = proc.stderr as String;

      final goldenFile = File('$root/codegen/$stem.out');
      if (update || !goldenFile.existsSync()) {
        goldenFile.writeAsStringSync(stdoutText);
        print('  ⟳ golden ${update ? 'regravado' : 'CRIADO'}: $stem.out '
            '(${stdoutText.split('\n').length - 1} linha(s))');
      } else {
        final expected = goldenFile.readAsStringSync();
        if (stdoutText == expected) {
          check(true, 'stdout == $stem.out');
        } else {
          fail('stdout != $stem.out',
              detail: 'esperado:\n${_indent(expected)}\n'
                  'obtido:\n${_indent(stdoutText)}');
        }
      }

      final exitOk = proc.exitCode == directives.expectExit;
      check(exitOk, 'exit ${proc.exitCode} (esperado ${directives.expectExit})');
      if (!exitOk && stderrText.isNotEmpty) {
        for (final line in stderrText.trimRight().split('\n')) {
          print('      $line');
        }
      }
      print('');
    }
  } finally {
    tempDir.deleteSync(recursive: true);
  }

  print(_fails == 0
      ? 'Golden-runner: TODOS OS CHECKS VERDES ✅'
      : 'Golden-runner: $_fails CHECK(S) VERMELHO(S) ❌');
  if (_fails > 0) throw StateError('$_fails checks falharam');
}

/// Indenta um bloco para o relatório de falha. O `trimRight` evita a linha
/// fantasma que o `\n` final de todo stdout produziria no `split`.
String _indent(String text) =>
    text.trimRight().split('\n').map((l) => '        $l').join('\n');

/// Raiz do `conformance/` a partir do cwd (o Makefile roda de `codegen/`).
/// Mesma busca defensiva dos testes do `compiler`.
String _conformanceRoot() {
  for (final candidate in ['../conformance', 'conformance', '../../conformance']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'conformance/ não encontrado a partir de ${Directory.current.path}',
  );
}
