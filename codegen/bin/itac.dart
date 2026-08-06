// ============================================================================
// itac.dart — a CLI COMPLETA do ita-next: F1–F7.
// ============================================================================
//
// Front-end (F1–F6), delegado ao `runFrontEndCommand` do pacote `compiler`:
//   itac tokenize | parse | desugar | resolve | check | flow  <file.tu>
//
// Codegen (F7), daqui:
//   itac build <file.tu> [-o <saída>] [--emit=vm|aot]   → grava o `.dill`
//   itac run   <file.tu>                                → build + executa
//
// **Por que este binário existe além de `compiler/bin/itac.dart`:** `build`
// precisa do `compileToDill`, que mora neste pacote, e este pacote já depende do
// `compiler` — a dependência de volta seria circular. Os seis comandos de fase
// NÃO estão duplicados aqui: vêm de `runFrontEndCommand`, uma fonte só, senão o
// dia em que uma fase nova nascesse um dos dois `switch` ficaria para trás em
// silêncio (R13).
//
// É este o binário que o ADR-0006 quer em AOT para o CI.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';

import 'package:ita_next_codegen/driver_build.dart';

String get _usage => '''
comandos:
  front-end (F1–F6): ${frontEndCommands.join(" | ")}  <file.tu>
  build <file.tu> [-o <saída>] [--emit=vm|aot]   grava o `.dill`
  run   <file.tu>                                build + executa (exit = o do programa)

`--emit=vm` (default) é o `.dill` MÍNIMO — o que a VM e o `dart compile js`
querem, porque relincam o platform deles. `--emit=aot` embute o platform (~8 MB):
é o que o `dart compile exe` exige.''';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('itac: uso: itac <comando> [args]');
    stderr.writeln(_usage);
    exit(64);
  }

  final command = args.first;
  final rest = args.sublist(1);

  final fase = runFrontEndCommand(command, rest);
  if (fase != null) exit(fase);

  switch (command) {
    case 'build':
      exit(runBuild(rest));
    case 'run':
      exit(runRun(rest));
    default:
      stderr.writeln('itac: comando desconhecido: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}
