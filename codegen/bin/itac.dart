// ============================================================================
// itac.dart — CLI COMPLETO do Itá (F1–F7) via CommandRunner (spec 013 §7.2).
// ============================================================================
//
// Cada `Command.run()` é adaptador FINO sobre a função de fase pura; o `--help`
// sai em runtime (P11 intocado). Subcomandos:
//
//   Herdados (F1–F6, adaptadores sobre `driver.dart`):
//     tokenize | parse | desugar | resolve | check | flow
//   Backend (F7, este pacote):
//     build <f.tu> [-o <out.dill>]   → .tu → .dill (platform auto-descoberto)
//     run   <f.tu>                    → build p/ temp + EXECUTA na VM pinada
//
// Rodar SEMPRE com o dart PINADO (`.dart-sdk/3.12.2`): o `run`/`build` derivam o
// `vm_platform.dill` de `Platform.resolvedExecutable` (o próprio dart que roda
// este `itac`), então o SDK que compila é o mesmo que executa.

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:kernel/kernel.dart' show loadComponentFromBinary;

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_codegen/emit.dart';
import 'package:ita_next_codegen/finalize.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>('itac', 'Compilador da linguagem Itá (.tu → .dill).')
        ..addCommand(TokenizeCommand())
        ..addCommand(ParseCommand())
        ..addCommand(DesugarCommand())
        ..addCommand(ResolveCommand())
        ..addCommand(CheckCommand())
        ..addCommand(FlowCommand())
        ..addCommand(BuildCommand())
        ..addCommand(RunCommand());

  try {
    // `run` devolve o exit code do comando invocado; `--help`/`--version` do
    // CommandRunner curto-circuitam e devolvem `null` (⟹ 0).
    final code = await runner.run(args);
    exit(code ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

// ============================================================================
// Comandos HERDADOS (F1–F6). Adaptador FINO: repassa a CAUDA crua
// (`argResults.arguments`, tudo após o nome do subcomando) à função de fase pura
// do driver e propaga o exit code. As flags declaradas aqui existem SÓ para o
// parser do CommandRunner aceitá-las (senão `--dump` viraria UsageException 64);
// a interpretação real é da própria `run*`, que re-parseia a cauda.
// ============================================================================

abstract class _PhaseCommand extends Command<int> {
  final int Function(List<String>) _phase;
  _PhaseCommand(this._phase);

  @override
  int run() => _phase(argResults!.arguments);
}

class TokenizeCommand extends _PhaseCommand {
  TokenizeCommand() : super(runTokenize);
  @override
  String get name => 'tokenize';
  @override
  String get description => 'Fase 1 — léxico: dump de tokens.';
}

class ParseCommand extends _PhaseCommand {
  ParseCommand() : super(runParse) {
    argParser
      ..addFlag('dump', negatable: false, help: 'Dump S-expression da AST.')
      ..addFlag('spans', negatable: false, help: 'Anexa @off+len aos nós.');
  }
  @override
  String get name => 'parse';
  @override
  String get description => 'Fase 2 — sintaxe: dump S-expr da AST.';
}

class DesugarCommand extends _PhaseCommand {
  DesugarCommand() : super(runDesugar) {
    argParser
      ..addFlag('dump', negatable: false, help: 'Dump S-expr da AST canônica.')
      ..addFlag('spans', negatable: false, help: 'Anexa @off+len aos nós.');
  }
  @override
  String get name => 'desugar';
  @override
  String get description => 'Fase 3 — desugaring: dump S-expr canônica.';
}

class ResolveCommand extends _PhaseCommand {
  ResolveCommand() : super(runResolve) {
    argParser
      ..addFlag('dump', negatable: false, help: 'Dump S-expr anotada (alvo+hops).')
      ..addFlag('spans', negatable: false, help: 'Anexa @off+len aos nós.');
  }
  @override
  String get name => 'resolve';
  @override
  String get description => 'Fase 4 — binding: dump anotado (alvo+hops).';
}

class CheckCommand extends _PhaseCommand {
  CheckCommand() : super(runCheck) {
    argParser.addFlag('dump-types',
        negatable: false, help: 'Imprime a tabela de tipos.');
  }
  @override
  String get name => 'check';
  @override
  String get description => 'Fase 5 — semântica/tipos.';
}

class FlowCommand extends _PhaseCommand {
  FlowCommand() : super(runFlow) {
    argParser.addFlag('dump-facts',
        negatable: false, help: 'Imprime a side-table nº8 (flow facts).');
  }
  @override
  String get name => 'flow';
  @override
  String get description => 'Fase 6 — flow-check.';
}

// ============================================================================
// Comandos de BACKEND (F7). `build` migra a lógica do antigo `build.dart`; `run`
// compila para um `.dill` temporário e o executa na VM pinada.
// ============================================================================

class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser.addOption('output',
        abbr: 'o',
        help: 'Caminho do .dill de saída (default: <basename>.dill).');
  }

  @override
  String get name => 'build';
  @override
  String get description => 'Compila um .tu para Dart Kernel (.dill).';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('itac build: falta <file.tu>');
      return 64;
    }
    final tuPath = rest.first;

    final result = _compileToDill(tuPath);
    if (result.code != null) return result.code!;

    final outPath = argResults!['output'] as String? ?? _defaultOut(tuPath);
    File(outPath).writeAsBytesSync(result.bytes!);
    stderr.writeln('gerado: $outPath (${result.bytes!.length} bytes)');
    return 0;
  }
}

class RunCommand extends Command<int> {
  @override
  String get name => 'run';
  @override
  String get description => 'Compila e EXECUTA um .tu na Dart VM pinada.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('itac run: falta <file.tu>');
      return 64;
    }
    final tuPath = rest.first;

    final result = _compileToDill(tuPath);
    if (result.code != null) return result.code!;

    // Compila para um `.dill` efêmero e o executa com o MESMO dart pinado que
    // roda este `itac` (Platform.resolvedExecutable). `inheritStdio` deixa o
    // `print("olá")` do programa ir direto ao terminal; o exit code devolvido é
    // o DO PROGRAMA (§7.3: 0 normal, panic ⟹ ≠0), não o do compilador.
    final tempDir = Directory.systemTemp.createTempSync('itac_run_');
    try {
      final dillPath = File.fromUri(tempDir.uri.resolve('out.dill')).path;
      File(dillPath).writeAsBytesSync(result.bytes!);
      final proc = await Process.start(
        Platform.resolvedExecutable,
        [dillPath],
        mode: ProcessStartMode.inheritStdio,
      );
      return await proc.exitCode;
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }
}

// ============================================================================
// Pipeline compartilhado build/run: F1→F6 (GATE F6) → emit → finalize.
// ============================================================================

/// Roda o front-end F1→F6 sobre [tuPath], GATEIA a F6 e emite/finaliza o `.dill`.
/// Devolve `bytes` no sucesso, ou um `code` de saída no fracasso:
///   66 arquivo não encontrado · 65 erro de fase (parse/tipos/fluxo) ·
///   70 ICE de codegen (§7.8, nó fora do CA1 vazou como `CodegenIce`).
({int? code, Uint8List? bytes}) _compileToDill(String tuPath) {
  final tu = File(tuPath);
  if (!tu.existsSync()) {
    stderr.writeln('itac: arquivo não encontrado: $tuPath');
    return (code: 66, bytes: null);
  }
  final source = tu.readAsStringSync();

  // F1–F2: parse. Erro léxico/parse aborta — árvore mal-formada envenena o resto.
  final parsed = parseSource(source);
  if (parsed.hasErrors) {
    for (final e in parsed.lexErrors) {
      stderr.writeln(e.format());
    }
    for (final e in parsed.errors) {
      stderr.writeln(e.format());
    }
    return (code: 65, bytes: null);
  }

  // F3–F6: desugar → bind → check → flow. GATE (013 §0.6): `flow == null` ⟹
  // F4/F5 reprovaram; `flow.hasErrors` ⟹ F6 reprovou. Só F5+F6-VERDE emite.
  final res = flowProgram(parsed.program);
  final flow = res.flow;
  if (flow == null) {
    for (final e in res.check.errors) {
      stderr.writeln(e.format());
    }
    return (code: 65, bytes: null);
  }
  if (flow.hasErrors) {
    for (final e in flow.errors) {
      stderr.writeln(e.format());
    }
    return (code: 65, bytes: null);
  }

  // F7: emitir da AST REAL (`res.check`) + finalizar contra o platform
  // AUTO-DESCOBERTO. O `CodegenIce` (nó fora do CA1) sai como UMA linha limpa
  // `ice: <code> @<off>+<len>` (o `toString` do próprio ICE) — sem stack trace.
  try {
    final platform = loadComponentFromBinary(_platformDillPath());
    final emitted = emitProgram(res.check, platform, sourceUri: tu.absolute.uri);
    final bytes = finalizeProgram(
      platform,
      emitted.libs,
      mainMethod: emitted.main,
    );
    return (code: null, bytes: bytes);
  } on CodegenIce catch (ice) {
    stderr.writeln(ice); // "ice: <code> @<off>+<len>"
    return (code: 70, bytes: null);
  }
}

/// Deriva o `vm_platform.dill` do dart PINADO que roda este `itac`:
/// `Platform.resolvedExecutable` = `<sdk>/bin/dart`, logo
/// `<sdk>/lib/_internal/vm_platform.dill`. Nada de arg explícito — o SDK que
/// compila é, por construção, o mesmo que executa.
String _platformDillPath() {
  // `File(dart).parent` = <sdk>/bin ; `.parent` = <sdk> (Directory, com URI
  // de barra final — `resolve` anexa sem comer o último segmento).
  final sdkDir = File(Platform.resolvedExecutable).parent.parent;
  return sdkDir.uri.resolve('lib/_internal/vm_platform.dill').toFilePath();
}

/// Default do `-o`: basename do `.tu` com extensão `.dill`, no diretório atual.
String _defaultOut(String tuPath) {
  final base = tuPath.split(Platform.pathSeparator).last;
  final stem = base.endsWith('.tu') ? base.substring(0, base.length - 3) : base;
  return '$stem.dill';
}
