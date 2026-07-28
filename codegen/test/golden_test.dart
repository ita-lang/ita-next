// ============================================================================
// golden_test.dart — o GOLDEN-RUNNER do emitter (spec 013 §7.2, §7.7, §11).
// ============================================================================
//
// Harness próprio (sem `package:test` — ver `kernel-vs-package-test-conflict`).
// Rodar pelo Makefile (que resolve o dart do pin):
//
//   make codegen-golden            # verifica
//   make codegen-golden-update     # REGRAVA os .out (leia a saída antes!)
//
// O que ele prova, por fixture de `conformance/codegen/`:
//
//   1. o `.tu` compila pelo MESMO `compileToDill` que o `itac build` usa
//      (lib/compile.dart — uma fonte de verdade, não uma réplica);
//   2. o `.dill` resultante RODA na Dart VM;
//   3. o **stdout** casa byte a byte com o golden `<nome>.out`;
//   4. o **exit code** casa com o esperado (`// EXPECT-EXIT:`, default 0);
//   5. stderr fica VAZIO nos fixtures de saída normal.
//
// Isto é o que os testes de `sanitize`/`finalize` NÃO cobrem: eles verificam a
// higiene e a boa-formação do `.dill` (o verify aceita), não o que o programa
// IMPRIME. Um emitter que troque `~/` por `/`, ou `<` por `<=`, produz `.dill`
// perfeitamente válido — e saída errada. Só a execução pega.
//
// ⚠️ **ALVO: VM (JIT), apenas.** A §7.7 pede os 3 alvos (VM/AOT/JS); AOT
// (`dart compile exe`) e JS (`dart2js`) são fatias FUTURAS e este runner não os
// roda — nem finge que rodou (o cabeçalho declara o alvo, e o nome do job de CI
// carrega o mesmo recorte: declaração que não sobrevive ao tick verde é mentira
// por omissão).
//
// ⚠️ **Camada que falta (declarada, não escondida):** este runner é
// EXTENSIONAL — compara comportamento observável. Ele é cego para invariantes
// que rodam igual e estão errados: `interfaceTarget` nulo (⟹ `DynamicInvocation`
// imprime o mesmo), `isFinal` de local, `dynamic` proibido pelo ADR-0013,
// `staticType` de `ConditionalExpression`, e o `libraryFilter` (CA11 —
// serializar `dart:core` junto roda idêntico, só cresce 8 MB). Os CA10/CA11/CA13
// da §11 são estruturais POR TEXTO NORMATIVO ("inspecionável no dump"). A
// camada intensional é fatia própria.
//
// ---------------------------------------------------------------------------
// Fixtures de FRONTEIRA (`// EXPECT-ICE:`)
// ---------------------------------------------------------------------------
// Um fixture pode declarar que a emissão AINDA não sabe baixá-lo, com o
// `ice-codegen-*` que ela devolve (§7.8). Não é decoração — e não é um `xfail`
// clássico: um xfail fica VERDE quando a feature chega e nunca cobra nada. Este
// fica VERMELHO (o `xpass` do lit/LLVM), cobrando a promoção a CA verde. É a
// fila de trabalho da §7.4, executável.
//
// ---------------------------------------------------------------------------
// `--update`
// ---------------------------------------------------------------------------
// Regrava os `.out` a partir da execução atual. É o ÚNICO caminho que escreve
// golden: um `.out` ausente FALHA (auto-criar seria carimbar como verde uma
// saída que ninguém leu — e no CI o arquivo criado morre com o workspace).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kernel/binary/tag.dart' show Tag;
import 'package:kernel/kernel.dart' show loadComponentFromBytes;

import 'package:ita_next_codegen/compile.dart';
import 'package:ita_next_codegen/invariants.dart';

int _fails = 0;
int _greens = 0; // fixtures verdes que passaram
int _frontiers = 0; // fronteiras (ICE declarado) — TEMPORÁRIAS, a catraca as esvazia
int _negatives = 0; // CAs negativos (erro de usuário esperado) — PERMANENTES

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

/// Asserção de TRÊS pontas do `dart-sdk.pin` — *"os TRÊS têm que vir da MESMA
/// versão stable"* (cabeçalho do pin):
///
///   1. o `dart` que roda isto      (`Platform.version`)        vs `DART_VERSION`
///   2. o `vm_platform.dill` do SDK (bytes 4..7, big-endian)    vs `EXPECTED_KERNEL_FORMAT`
///   3. o `pkg/kernel` VENDORADO    (`Tag.BinaryFormatVersion`) vs o mesmo
///
/// **Por que não é paranoia:** o `.dill` que emitimos sai com **SDK hash NULO** —
/// `tag.dart:264-273` tira `expectedSdkHash` de `String.fromEnvironment('sdk_hash')`
/// e cai no default `'0000000000'`, porque rodamos o `pkg/kernel` do *source*, sem
/// `-Dsdk_hash`; e `isValidSdkHash` (`:275-278`) passa se QUALQUER lado for nulo.
/// Ou seja: a única checagem que detectaria um SDK errado **está desligada** — só
/// o FORMATO é conferido de fato pela VM. Um bump de PATCH com o mesmo formato
/// passaria em silêncio. Estas três linhas são o que sobra.
///
/// A ponta **3** é a que mais quebra num bump real: quem troca a versão do SDK
/// esquece de revendorar o `pkg/kernel`, e o vendor velho emite formato velho.
/// Ler só o `.dill` (o que um `od` no shell alcança) cobriria 1 e 2, não a 3.
///
/// O formato NÃO é hardcodado aqui de propósito: o `main` do SDK já está em 138.
/// A fonte é o `dart-sdk.pin`, sempre.
void checkPin(String root) {
  final pin = <String, String>{};
  for (final line in File('$root/dart-sdk.pin').readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i > 0) pin[t.substring(0, i)] = t.substring(i + 1).trim();
  }
  final wantVersion = pin['DART_VERSION'];
  final wantFormat = int.parse(pin['EXPECTED_KERNEL_FORMAT']!);

  final gotVersion = Platform.version.split(' ').first;
  check(gotVersion == wantVersion,
      'dart $gotVersion == pin $wantVersion${gotVersion == wantVersion ? '' : ' — rode `make pin`, ou DART_CG=<dart $wantVersion>'}');

  // `getUint32` tem `Endian.big` por default, que é o do formato
  // (`kernel_binary.h:167-170` lê com `BigEndianToHost32`).
  final head = File(platformDillPath()).openSync().readSync(8);
  final bd = ByteData.sublistView(head);
  check(bd.getUint32(0) == 0x90ABCDEF, 'vm_platform.dill tem magic de .dill');
  final gotFormat = bd.getUint32(4);
  check(gotFormat == wantFormat, 'vm_platform.dill fmt $gotFormat == pin $wantFormat');
  check(Tag.BinaryFormatVersion == wantFormat,
      'pkg/kernel vendorado fmt ${Tag.BinaryFormatVersion} == pin $wantFormat');
}

/// Diretivas do header de um fixture (linhas `//`).
///
///   `// EXPECT-ICE: <code>`  — espera falha de emissão com esse `ice-codegen-*`
///                              (exit 70 do compilador); sem golden `.out`.
///   `// EXPECT-BUILD-ERROR: <code>` — espera erro de USUÁRIO do driver (exit 65),
///                              ex. `missing-main` (§12-5); sem golden `.out`.
///   `// EXPECT-EXIT: <n>`    — exit code esperado do PROGRAMA (default 0).
///
/// [errors] carrega problemas da PRÓPRIA diretiva. Uma diretiva que o harness
/// não entende NÃO pode ser ignorada em silêncio: `EXPECT-EXITT: 70` cairia no
/// default 0 e o fixture passaria afirmando o que ninguém pediu. O harness
/// aplicaria a si mesmo o oposto de "diagnóstico nunca mente".
typedef Directives = ({
  String? expectIce,
  String? expectBuildError,
  int expectExit,
  List<String> errors,
});

Directives parseDirectives(String source) {
  String? ice;
  String? buildError;
  var exitCode = 0;
  var sawExit = false;
  final errors = <String>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (!line.startsWith('//')) continue;
    final body = line.substring(2).trim();
    if (!body.startsWith('EXPECT')) continue;
    if (body.startsWith('EXPECT-ICE:')) {
      if (ice != null) errors.add('EXPECT-ICE duplicado');
      ice = body.substring('EXPECT-ICE:'.length).trim();
      if (ice.isEmpty) errors.add('EXPECT-ICE sem código');
    } else if (body.startsWith('EXPECT-BUILD-ERROR:')) {
      if (buildError != null) errors.add('EXPECT-BUILD-ERROR duplicado');
      buildError = body.substring('EXPECT-BUILD-ERROR:'.length).trim();
      if (buildError.isEmpty) errors.add('EXPECT-BUILD-ERROR sem código');
    } else if (body.startsWith('EXPECT-EXIT:')) {
      if (sawExit) errors.add('EXPECT-EXIT duplicado');
      sawExit = true;
      final v = int.tryParse(body.substring('EXPECT-EXIT:'.length).trim());
      if (v == null) {
        errors.add('EXPECT-EXIT não-numérico: `$body`');
      } else {
        exitCode = v;
      }
    } else {
      errors.add('diretiva desconhecida: `$body`');
    }
  }
  if (ice != null && buildError != null) {
    errors.add('EXPECT-ICE e EXPECT-BUILD-ERROR no mesmo fixture');
  }
  return (
    expectIce: ice,
    expectBuildError: buildError,
    expectExit: exitCode,
    errors: errors,
  );
}

/// O `toString` do `CodegenIce` é formato fixo (`emit.dart:54`). Extrair o código
/// e comparar por IGUALDADE (não `contains`): um `EXPECT-ICE:` truncado por typo
/// — `ice-codegen-cmp-on-String`, ou pior, `ice-codegen` — casaria com qualquer
/// coisa e o teste passaria afirmando menos do que aparenta.
final _iceLine = RegExp(r'^ice: (\S+) @(\d+)\+(\d+)$');

/// Idem para o diagnóstico do DRIVER (`compile.dart::checkMain`, §12-5).
final _buildErrorLine = RegExp(r'^build-error: (\S+) @(\d+)\+(\d+)$');

Future<void> main(List<String> args) async {
  final update = args.contains('--update');
  final root = _repoRoot();
  final dir = Directory('$root/conformance/codegen');
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
  print('pin (dart ↔ vm_platform.dill ↔ pkg/kernel vendorado):');
  checkPin(root);
  print('');

  final tempDir = Directory.systemTemp.createTempSync('ita_golden_');
  try {
    for (final fixture in fixtures) {
      final name = fixture.uri.pathSegments.last;
      final stem = name.substring(0, name.length - 3);
      final source = fixture.readAsStringSync();
      final directives = parseDirectives(source);
      print('$name:');

      // O harness confere a si mesmo ANTES de conferir o fixture.
      if (directives.errors.isNotEmpty) {
        for (final e in directives.errors) {
          fail('diretiva inválida — $e');
        }
        print('');
        continue;
      }

      final outcome = compileToDill(fixture.path, platformBytes: platformBytes);
      final goldenFile = File('${dir.path}/$stem.out');

      // ---- fixture de FRONTEIRA: o ICE É o resultado esperado --------------
      final expectIce = directives.expectIce;
      if (expectIce != null) {
        // Um `.out` órfão aqui é resíduo de promoção revertida — o fixture não
        // roda, então o golden não pode existir.
        if (goldenFile.existsSync()) {
          fail('golden ÓRFÃO: $stem.out existe num fixture EXPECT-ICE (apague-o)');
        }
        if (outcome.code == null) {
          fail(
            'esperava $expectIce, mas COMPILOU — a fatia nasceu? '
            'promova a fixture a CA verde (rode --update e remova o EXPECT-ICE)',
          );
        } else if (outcome.code != 70) {
          // O furo clássico do xfail: passar pelo motivo errado. Um erro de FASE
          // (65) não é a fronteira da emissão — é a fixture nem chegando lá.
          fail(
            'esperava ICE (70), veio exit ${outcome.code} '
            '(erro de FASE — a fixture parou ANTES da emissão)',
            detail: outcome.diagnostics.join('\n'),
          );
        } else {
          final line = outcome.diagnostics.join('\n');
          final m = _iceLine.firstMatch(line);
          if (m == null) {
            fail('ICE ilegível (o formato do CodegenIce mudou?): $line');
          } else if (m.group(1) != expectIce) {
            fail('ICE ${m.group(1)} ≠ esperado $expectIce');
          } else {
            check(true, 'ICE exato: $expectIce');
            _frontiers++;
          }
        }
        print('');
        continue;
      }

      // ---- fixture de ERRO DE USUÁRIO (§12-5): o driver reprova antes da F7 --
      final expectBuildError = directives.expectBuildError;
      if (expectBuildError != null) {
        if (goldenFile.existsSync()) {
          fail('golden ÓRFÃO: $stem.out num fixture EXPECT-BUILD-ERROR (apague-o)');
        }
        final got = outcome.diagnostics.join('\n');
        if (outcome.code == null) {
          fail('esperava $expectBuildError, mas COMPILOU');
        } else if (outcome.code != 65) {
          // Exit 70 aqui é a REGRESSÃO que este fixture existe para pegar: o erro
          // do usuário voltando a sair como ICE (§7.8 — "a F7 não tem erro de
          // usuário"), com a palavra `ice` na cara de quem só esqueceu o `main`.
          fail('esperava erro de usuário (65), veio exit ${outcome.code}',
              detail: got);
        } else {
          final m = _buildErrorLine.firstMatch(got);
          if (m == null) {
            fail('diagnóstico ilegível (formato mudou?): $got');
          } else if (m.group(1) != expectBuildError) {
            fail('erro ${m.group(1)} ≠ esperado $expectBuildError');
          } else {
            check(true, 'erro de usuário exato: $expectBuildError');
            _negatives++;
          }
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

      // ---- camada INTENSIONAL: o que roda igual e está errado --------------
      // Roda ANTES da execução: se o `.dill` viola o ADR-0013 ou o CA11, o
      // stdout casar com o golden não redime nada.
      final structural = [
        ...checkInvariants(outcome.libs!),
        ...checkSerializedLibraries(loadComponentFromBytes(outcome.bytes!)),
      ];
      if (structural.isEmpty) {
        check(true, 'invariantes (zero dynamic · targets ligados · CA11)');
      } else {
        for (final v in structural) {
          fail('invariante violado — $v');
        }
      }

      final dillPath = '${tempDir.path}/$stem.dill';
      File(dillPath).writeAsBytesSync(outcome.bytes!);

      // `Process.start` + timeout (não `Process.run`): quando a §7.4-e trouxer
      // `while`/`for`, um lowering errado penduraria o job até o timeout do
      // runner de CI. "Travou" tem de ser uma falha NOMEADA, não um job morto.
      final proc = await Process.start(Platform.resolvedExecutable, [dillPath]);
      final outF = proc.stdout.transform(utf8.decoder).join();
      final errF = proc.stderr.transform(utf8.decoder).join();
      int exitCode;
      try {
        exitCode = await proc.exitCode.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
        fail('TRAVOU: o programa não terminou em 15 s (loop que não fecha?)');
        print('');
        continue;
      }
      final stdoutText = await outF;
      final stderrText = await errF;

      var stdoutOk = false;
      if (update) {
        goldenFile.writeAsStringSync(stdoutText);
        print('  ⟳ golden regravado: $stem.out '
            '(${stdoutText.split('\n').length - 1} linha(s))');
      } else if (!goldenFile.existsSync()) {
        // NUNCA auto-criar: seria carimbar de verde uma saída que ninguém leu —
        // exatamente o que o `--update` existe para tornar deliberado. No CI o
        // arquivo criado ainda morreria com o workspace.
        fail('golden AUSENTE: $stem.out — rode `make codegen-golden-update` e LEIA a saída',
            detail: stdoutText);
      } else {
        final expected = goldenFile.readAsStringSync();
        if (stdoutText == expected) {
          check(true, 'stdout == $stem.out');
          stdoutOk = true;
        } else {
          fail('stdout != $stem.out',
              detail: 'esperado:\n${_indent(expected)}\n'
                  'obtido:\n${_indent(stdoutText)}');
        }
      }

      final exitOk = exitCode == directives.expectExit;
      check(exitOk, 'exit $exitCode (esperado ${directives.expectExit})');
      if (!exitOk && stderrText.isNotEmpty) {
        for (final line in stderrText.trimRight().split('\n')) {
          print('      $line');
        }
      }

      // Saída normal não escreve em stderr. (O slot `.err` chega com o CA9 —
      // `panic` grava mensagem + span no stderr e sai ≠ 0.)
      if (directives.expectExit == 0) {
        check(stderrText.isEmpty,
            'stderr vazio${stderrText.isEmpty ? '' : ' (veio: ${stderrText.trim()})'}');
      }
      if (stdoutOk && exitOk) _greens++;
      print('');
    }
  } finally {
    tempDir.deleteSync(recursive: true);
  }

  // O total tem de ser honesto no lugar onde o leitor olha: um fixture de
  // FRONTEIRA contribui um ✓, mas não prova emissão nenhuma — prova que a
  // lacuna segue declarada. Somá-los num "todos verdes" afirmaria mais do que o
  // corpus provou.
  final fronteiras =
      _frontiers == 1 ? '1 fronteira declarada' : '$_frontiers fronteiras declaradas';
  print(_fails == 0
      ? 'Golden-runner: $_greens verdes · $_negatives negativos · $fronteiras ✅'
      : 'Golden-runner: $_fails CHECK(S) VERMELHO(S) ❌');
  if (_fails > 0) throw StateError('$_fails checks falharam');
}

/// Indenta um bloco para o relatório de falha. O `trimRight` evita a linha
/// fantasma que o `\n` final de todo stdout produziria no `split`.
String _indent(String text) =>
    text.trimRight().split('\n').map((l) => '        $l').join('\n');

/// Raiz do repo: o diretório que contém o `dart-sdk.pin`. Âncora normativa —
/// sondar `conformance/` acharia o diretório errado num checkout aninhado, e o
/// pin é justamente o arquivo que este runner precisa ler.
String _repoRoot() {
  for (final candidate in ['..', '.', '../..']) {
    if (File('$candidate/dart-sdk.pin').existsSync()) return candidate;
  }
  throw StateError(
    'dart-sdk.pin não encontrado a partir de ${Directory.current.path}',
  );
}
