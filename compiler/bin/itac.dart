// ============================================================================
// itac.dart — Entry point da CLI do compilador ita-next.
// ============================================================================
//
// Fase 1 (léxico):  itac tokenize <file.tu>          → dump de tokens
// Fase 2 (sintaxe): itac parse <file.tu> --dump [--spans] → dump S-expr da AST
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';

const _usage = 'comandos: tokenize <file.tu> | parse <file.tu> [--dump] [--spans]';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('itac: uso: itac <comando> [args]');
    stderr.writeln(_usage);
    exit(64);
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case 'tokenize':
      exit(runTokenize(rest));
    case 'parse':
      exit(runParse(rest));
    default:
      stderr.writeln('itac: comando desconhecido: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}
