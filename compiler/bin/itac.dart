// ============================================================================
// itac.dart — Entry point da CLI do compilador ita-next.
// ============================================================================
//
// Fase 1 (léxico):  itac tokenize <file.tu>          → dump de tokens
// Fase 2 (sintaxe): itac parse <file.tu> --dump [--spans] → dump S-expr da AST
// Fase 3 (desugar): itac desugar <file.tu> --dump [--spans] → dump S-expr canônica
// Fase 4 (binding): itac resolve <file.tu> --dump [--spans] → dump anotado (alvo+hops)
// Fase 5 (tipos):   itac check <file.tu> [--dump-types]      → tabela de tipos
// Fase 6 (fluxo):   itac flow <file.tu> [--dump-facts]       → side-table nº8
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';

const _usage =
    'comandos: tokenize <file.tu> | parse <file.tu> [--dump] [--spans] | '
    'desugar <file.tu> [--dump] [--spans] | resolve <file.tu> [--dump] [--spans] | '
    'check <file.tu> [--dump-types] | flow <file.tu> [--dump-facts]';

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
    case 'desugar':
      exit(runDesugar(rest));
    case 'resolve':
      exit(runResolve(rest));
    case 'check':
      exit(runCheck(rest));
    case 'flow':
      exit(runFlow(rest));
    default:
      stderr.writeln('itac: comando desconhecido: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}
