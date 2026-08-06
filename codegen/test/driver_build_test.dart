// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// driver_build_test.dart — o RED de `itac build` e `itac run`.
//
// Harness próprio (sem `package:test`). Rodar por `make codegen-test`.
//
// O que este arquivo cobra, e por que cada caso existe:
//
//   1. **os códigos de saída são CONTRATO** (§7.2), não "deu ruim": 64 uso, 66
//      arquivo, 65 fase. Um `build` que devolvesse 1 para tudo passaria em
//      qualquer teste que só olhasse `!= 0` — e o golden-runner classifica a
//      falha por esse número;
//   2. **`--emit=vm` e `--emit=aot` produzem artefatos DIFERENTES.** É a única
//      asserção que pega a flag ligada no lugar errado, e a diferença é de três
//      ordens de grandeza (centenas de bytes contra ~8 MB);
//   3. **valor desconhecido de `--emit` REPROVA.** Sem isto, `--emit=aotr` cai
//      no default e grava o `.dill` que o `dart compile exe` recusa — a falha
//      apareceria no `gen_kernel`, três passos adiante, sem dizer por quê;
//   4. **`run` propaga o exit code do PROGRAMA**, não o do compilador — é o que
//      a §7.2 escreve, e o caso do `panic` é o que distingue os dois.

import 'dart:io';

import 'package:ita_next_codegen/driver_build.dart';

import 'harness.dart';

final _corpus = '../conformance/codegen';

void main() {
  final h = Harness('itac build/run');
  print('harness — o botão de vermelho funciona?');
  h.selfTest();
  print('');

  final tmp = Directory.systemTemp.createTempSync('itac_build_test_');
  try {
    print('runBuild — os códigos de saída são contrato (§7.2):');
    {
      final err = StringBuffer();
      h.check(runBuild(const [], err: err) == 64, 'sem arquivo ⟹ 64 (uso)');
      h.check(err.toString().contains('uso:'), 'o diagnóstico ENSINA o uso');

      final err2 = StringBuffer();
      h.check(runBuild(['$_corpus/nao_existe.tu'], err: err2) == 66,
          'arquivo inexistente ⟹ 66');
      h.check(err2.toString().contains('nao_existe.tu'),
          'o diagnóstico nomeia o arquivo que faltou');

      final err3 = StringBuffer();
      h.check(runBuild(['$_corpus/ca1_interp.tu', '-o'], err: err3) == 64,
          '`-o` sem caminho ⟹ 64');

      final err4 = StringBuffer();
      h.check(
          runBuild(['$_corpus/ca1_interp.tu', '--emit=aotr'], err: err4) == 64,
          '`--emit` desconhecido ⟹ 64 (não cai no default em silêncio)');
      h.check(err4.toString().contains('vm | aot'),
          'o diagnóstico lista os valores válidos');

      final err5 = StringBuffer();
      h.check(runBuild(['$_corpus/err_missing_main.tu'], err: err5) == 65,
          'erro de FASE/driver ⟹ 65');
    }

    print('');
    print('runBuild — `--emit` escolhe o ARTEFATO, e eles são diferentes:');
    {
      final vmOut = '${tmp.path}/ca1_vm.dill';
      final out = StringBuffer();
      final code =
          runBuild(['$_corpus/ca1_interp.tu', '-o', vmOut], out: out);
      h.check(code == 0, 'build do CA1 ⟹ 0');
      h.check(File(vmOut).existsSync(), 'o `.dill` foi gravado onde `-o` mandou');
      h.check(out.toString().contains('--emit=vm'),
          'o relatório DIZ qual artefato saiu');

      final aotOut = '${tmp.path}/ca1_aot.dill';
      h.check(
          runBuild(['$_corpus/ca1_interp.tu', '-o', aotOut, '--emit=aot'],
                  out: StringBuffer()) ==
              0,
          'build `--emit=aot` ⟹ 0');

      final vmLen = File(vmOut).lengthSync();
      final aotLen = File(aotOut).lengthSync();
      // A relação é de três ordens de grandeza: o completo embute o platform
      // inteiro. `>` sozinho passaria com 1 byte de diferença.
      h.check(aotLen > vmLen * 100,
          'o `.dill` de AOT embute o platform ($vmLen B → $aotLen B)');
      h.check(vmLen > 0 && vmLen < 100000,
          'o `.dill` de VM é MÍNIMO ($vmLen B) — sem o platform');
    }

    print('');
    print('runBuild — sem `-o`, o destino deriva do fonte:');
    {
      // Copiar para o temp: um `build` que grava ao lado do fonte sujaria o
      // corpus, e o teste passaria a depender de um `.dill` versionado.
      final copia = '${tmp.path}/hello.tu';
      File('$_corpus/ca1_interp.tu').copySync(copia);
      h.check(runBuild([copia], out: StringBuffer()) == 0, 'build sem `-o` ⟹ 0');
      h.check(File('${tmp.path}/hello.dill').existsSync(),
          '`x.tu` ⟹ `x.dill` (a extensão é TROCADA, não anexada)');
    }

    print('');
    print('runRun — o exit code é o do PROGRAMA (§7.2):');
    {
      final out = StringBuffer();
      final code = runRun(['$_corpus/ca1_interp.tu'], out: out);
      h.check(code == 0, 'programa que termina bem ⟹ 0');
      final golden = File('$_corpus/ca1_interp.out').readAsStringSync();
      h.check(out.toString() == golden,
          'o stdout do programa chega ao chamador (== ca1_interp.out)');

      // O caso que separa "exit do compilador" de "exit do programa": aqui o
      // build vai bem (0) e o programa morre. Sem ele, `return 0` fixo passaria.
      final err = StringBuffer();
      final codePanic = runRun(['$_corpus/panic_exit.tu'], err: err);
      h.check(codePanic != 0,
          'programa que dá `panic` ⟹ exit ≠ 0 (veio $codePanic)');
      h.check(err.toString().isNotEmpty, 'o stderr do `panic` chega ao chamador');

      h.check(runRun(const [], err: StringBuffer()) == 64, 'run sem arquivo ⟹ 64');
      h.check(
          runRun(['a.tu', 'b.tu'], err: StringBuffer()) == 64,
          'run com dois arquivos ⟹ 64');
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }

  h.finish();
}
