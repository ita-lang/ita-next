// ============================================================================
// itac.dart — CLI do FRONT-END (F1–F6) do ita-next.
// ============================================================================
//
// Fase 1 (léxico):  itac tokenize <file.tu>          → dump de tokens
// Fase 2 (sintaxe): itac parse <file.tu> --dump [--spans] → dump S-expr da AST
// Fase 3 (desugar): itac desugar <file.tu> --dump [--spans] → dump S-expr canônica
// Fase 4 (binding): itac resolve <file.tu> --dump [--spans] → dump anotado (alvo+hops)
// Fase 5 (tipos):   itac check <file.tu> [--dump-types]      → tabela de tipos
// Fase 6 (fluxo):   itac flow <file.tu> [--dump-facts]       → side-table nº8
//
// ⚠️ **`build` e `run` NÃO estão aqui, e não é lacuna: é topologia.** Eles
// precisam do `compileToDill`, que mora no pacote `codegen` — e `codegen` já
// depende deste pacote, então a dependência de volta seria circular. O `itac`
// COMPLETO (F1–F7 + `build`/`run`) é `codegen/bin/itac.dart`, e é ele que o
// ADR-0006 quer compilar em AOT para o CI.
//
// Este binário continua existindo porque o front-end é testável e utilizável
// SEM o `pkg/kernel` vendorado (spec 013 §0-A, o pacote isolado): quem mexe na
// F1–F6 não deveria precisar de 8 MB de platform para rodar um `tokenize`.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';

const _usage =
    'comandos: tokenize <file.tu> | parse <file.tu> [--dump] [--spans] | '
    'desugar <file.tu> [--dump] [--spans] | resolve <file.tu> [--dump] [--spans] | '
    'check <file.tu> [--dump-types] | flow <file.tu> [--dump-facts]\n'
    '(`build`/`run` vivem no itac completo: codegen/bin/itac.dart)';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('itac: uso: itac <comando> [args]');
    stderr.writeln(_usage);
    exit(64);
  }

  final code = runFrontEndCommand(args.first, args.sublist(1));
  if (code == null) {
    stderr.writeln('itac: comando desconhecido: ${args.first}');
    stderr.writeln(_usage);
    exit(64);
  }
  exit(code);
}
