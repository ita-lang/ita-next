// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// bench.dart — o guard de compile-time do ADR-0006.
//
// *"Guard de regressão no CI: benchmark de compile-time que **falha se a mediana
// > 0,5s/arquivo** — barreira contra volta ao JIT ou codegen O(n²)."*
//
// Compile-time é a métrica nº1 do Itá, com norte escrito: *"perto do Go"*. Um
// número impresso sem limiar não é guard — é decoração que ninguém lê depois da
// segunda semana. Este arquivo tem limiar e sai ≠ 0.
//
// **Mede o binário AOT, não o JIT.** É a regra operacional do ADR: *"nunca
// depender do JIT para medir ou iterar"*. Medido nesta máquina (M2, 2026-08-06):
// AOT 0,08–0,15 s por arquivo contra 1,69–2,08 s em `dart run` — ~20×. Medir o
// JIT reprovaria o guard todo dia por um custo que a entrega não paga.
//
// Uso:  dart run tool/bench.dart [--limiar-ms=500] [--repeticoes=3]

import 'dart:io';

const _limiarPadraoMs = 500;

void main(List<String> args) {
  final limiarMs = _intArg(args, '--limiar-ms=') ?? _limiarPadraoMs;
  final repeticoes = _intArg(args, '--repeticoes=') ?? 3;

  final raiz = _raizDoRepo();
  // O WRAPPER, não o binário cru: é ele que exporta `ITA_DART_SDK`, e é ele que
  // o dev e o CI invocam. Medir `build/itac` direto exigiria remontar o caminho
  // do SDK aqui — e no CI esse caminho é outro (`.dart-sdk/` não existe lá).
  // Duas fontes para a mesma coisa é como uma delas fica para trás.
  final itac = File('$raiz/bin/itac');
  if (!itac.existsSync()) {
    // Falha NOMEADA com o comando que conserta. Cair no JIT aqui seria pior que
    // não medir: o número sairia ~20× maior e o guard viraria ruído permanente.
    stderr.writeln('bench: `build/itac` não existe — rode `make itac-aot`.');
    stderr.writeln('       (o ADR-0006 mede o AOT; o JIT não é comparável)');
    exit(1);
  }

  final fixtures = Directory('$raiz/conformance/codegen')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tu'))
      .where((f) => !f.readAsStringSync().contains('EXPECT-'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (fixtures.isEmpty) {
    stderr.writeln('bench: nenhum fixture compilável no corpus — nada medido');
    exit(1);
  }

  final tmp = Directory.systemTemp.createTempSync('ita_bench_');
  final medianas = <int>[];
  try {
    for (final f in fixtures) {
      final amostras = <int>[];
      for (var i = 0; i < repeticoes; i++) {
        final relogio = Stopwatch()..start();
        final p = Process.runSync(
          itac.path,
          ['build', f.path, '-o', '${tmp.path}/saida.dill'],
        );
        relogio.stop();
        if (p.exitCode != 0) {
          stderr.writeln('bench: `${_nome(f)}` não compilou (exit ${p.exitCode})');
          stderr.writeln(p.stderr);
          exit(1);
        }
        amostras.add(relogio.elapsedMilliseconds);
      }
      medianas.add(_mediana(amostras));
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }

  // A MEDIANA das medianas: o limiar do ADR é "por arquivo", e a média deixaria
  // um outlier de I/O (o primeiro build, frio) mascarar o corpo da distribuição.
  final mediana = _mediana(medianas);
  final pior = medianas.reduce((a, b) => a > b ? a : b);
  final piorNome = _nome(fixtures[medianas.indexOf(pior)]);

  stdout.writeln('bench (AOT, ${fixtures.length} arquivos × $repeticoes):');
  stdout.writeln('  mediana: ${mediana} ms/arquivo   (limiar: $limiarMs ms)');
  stdout.writeln('  pior:    ${pior} ms  — $piorNome');

  if (mediana > limiarMs) {
    stderr.writeln('');
    stderr.writeln('bench: REGRESSÃO — mediana ${mediana} ms > $limiarMs ms.');
    stderr.writeln('       O ADR-0006 chama isto de "barreira contra volta ao '
        'JIT ou codegen O(n²)".');
    exit(1);
  }
  stdout.writeln('  ✅ dentro do limiar do ADR-0006');
}

int _mediana(List<int> xs) {
  final ordenado = [...xs]..sort();
  final meio = ordenado.length ~/ 2;
  return ordenado.length.isOdd
      ? ordenado[meio]
      : ((ordenado[meio - 1] + ordenado[meio]) / 2).round();
}

int? _intArg(List<String> args, String prefixo) {
  final a = args.where((x) => x.startsWith(prefixo)).lastOrNull;
  if (a == null) return null;
  final v = int.tryParse(a.substring(prefixo.length));
  if (v == null || v <= 0) {
    stderr.writeln('bench: `$a` não é um inteiro positivo');
    exit(64);
  }
  return v;
}

String _nome(File f) => f.uri.pathSegments.last;

/// A raiz é o diretório com o `dart-sdk.pin` — a mesma âncora normativa que o
/// golden-runner usa, e não `conformance/`, que existe em mais de um nível.
String _raizDoRepo() {
  for (final c in ['..', '.', '../..']) {
    if (File('$c/dart-sdk.pin').existsSync()) return c;
  }
  throw StateError('dart-sdk.pin não encontrado a partir de ${Directory.current.path}');
}
