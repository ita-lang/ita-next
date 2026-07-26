// build.dart — harness B2 (§7.4/§7.6, CA1 mínimo). Lê um `.tu`, roda o
// front-end F1→F6, GATEIA a F6 (só programa F5+F6-verde chega ao emitter),
// emite o `Component` a partir da AST REAL (`emitProgram`) e finaliza o `.dill`
// (`finalizeProgram`). O `itac build`/`run` polido (CommandRunner) é o B3 —
// isto é só o fio para RODAR e ver "olá".
//
// Uso (com o dart PINADO — `.dart-sdk/3.12.2`):
//   dart run bin/build.dart <file.tu> <vm_platform.dill> <out.dill>
//   dart <out.dill>        # a VM pinada imprime "olá"

import 'dart:io';

import 'package:kernel/kernel.dart' show loadComponentFromBinary;

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_codegen/emit.dart';
import 'package:ita_next_codegen/finalize.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'uso: dart run bin/build.dart <file.tu> <vm_platform.dill> <out.dill>',
    );
    exit(64);
  }
  final tuPath = args[0];
  final platformPath = args[1];
  final outPath = args[2];

  final tu = File(tuPath);
  if (!tu.existsSync()) {
    stderr.writeln('build: arquivo não encontrado: $tuPath');
    exit(66);
  }
  final source = tu.readAsStringSync();

  // F1–F2: parse. Erro léxico/parse aborta — árvore mal-formada envenena as
  // fases seguintes (mesma disciplina do driver `itac`).
  final parsed = parseSource(source);
  if (parsed.hasErrors) {
    for (final e in parsed.lexErrors) {
      stderr.writeln(e.format());
    }
    for (final e in parsed.errors) {
      stderr.writeln(e.format());
    }
    exit(65);
  }

  // F3–F6: desugar → bind → check → flow. O GATE: `flow == null` ⟹ F4/F5
  // reprovaram (gate I3 do `flowProgram`); `flow.hasErrors` ⟹ F6 reprovou.
  // Só F5+F6-VERDE chega ao emitter.
  final res = flowProgram(parsed.program);
  final flow = res.flow;
  if (flow == null) {
    for (final e in res.check.errors) {
      stderr.writeln(e.format());
    }
    exit(65);
  }
  if (flow.hasErrors) {
    for (final e in flow.errors) {
      stderr.writeln(e.format());
    }
    exit(65);
  }

  // F7-B2: emitir da AST REAL + finalizar contra o platform. `res.check.program`
  // é o programa DESAÇUCARADO (F3), e `res.check.resolution` é keyada por seus
  // nós — por isso o emitter anda `check.program`, não `parsed.program`.
  final platform = loadComponentFromBinary(platformPath);
  final emitted = emitProgram(res.check, platform, sourceUri: tu.absolute.uri);
  final bytes = finalizeProgram(
    platform,
    emitted.libs,
    mainMethod: emitted.main,
  );
  File(outPath).writeAsBytesSync(bytes);
  stderr.writeln('gerado: $outPath (${bytes.length} bytes)');
}
