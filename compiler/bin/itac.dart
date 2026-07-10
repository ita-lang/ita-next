// ============================================================================
// itac.dart — Entry point da CLI do compilador ita-next.
// ============================================================================
//
// Fase 1 (léxico): único comando é `tokenize`.
//   itac tokenize <file.tu>   → dump de tokens (uma linha por token)
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('itac: uso: itac <comando> [args]');
    stderr.writeln('comandos: tokenize <file.tu>');
    exit(64);
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case 'tokenize':
      exit(runTokenize(rest));
    default:
      stderr.writeln('itac: comando desconhecido: $command');
      stderr.writeln('comandos: tokenize <file.tu>');
      exit(64);
  }
}
