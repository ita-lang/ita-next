// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// driver_build.dart — `itac build` e `itac run`, as duas pontas que faltavam
// entre o compilador e quem o usa.
//
// Até 2026-08-06 o `compileToDill` só era alcançável por TESTE: o `itac` parava
// no `flow` (F6), e o único caminho até um `.dill` era rodar o golden-runner. O
// compilador sabia emitir para os três alvos e não expunha isso a ninguém.
//
// As duas funções seguem o contrato das fases (`runCheck`/`runTokenize`/…): **um
// `int` de exit code e sinks injetáveis**, nunca `exit()` lá dentro. É o que a
// §9 pede ao listar *"`itac build`/`run` no driver (funções puras testáveis,
// como `tokenize`/`parse`/`check`)"* — e é o que permite ao teste ler a saída em
// vez de conferir que "o processo não morreu".
//
// Os códigos de saída são os do `CompileOutcome` (§7.2), e são contrato: o
// golden-runner os lê como CLASSIFICAÇÃO da falha, não como "deu ruim".
//   64 uso incorreto · 66 arquivo não encontrado · 65 erro de FASE
//   70 ICE de codegen (§7.8) · 71 boa-formação (gate CA12)

import 'dart:io';

import 'compile.dart';

/// `itac build <file.tu> [-o <saída>] [--emit=vm|aot]`
///
/// **`--emit` existe porque os dois artefatos são legítimos e diferentes**, e o
/// alvo é quem escolhe (o achado de 2026-08-06, medido nos dois sentidos):
///
///   - `vm` (default) — o `.dill` MÍNIMO, sem o platform. É o de produção: a VM
///     relinca o seu próprio no load, e o `dart compile js` também. ~450 bytes
///     para o hello-world.
///   - `aot` — o `.dill` COMPLETO, com o platform embutido (~8 MB). É o que o
///     `dart compile exe` exige: o `gen_kernel` não relinca nada, e sobre o
///     mínimo morre em `Reference to dart:core::@methods::print is not bound to
///     an AST node`.
///
/// Sem esta flag o AOT ficaria inalcançável pela CLI — o compilador saberia
/// produzir o artefato e não teria como entregá-lo.
int runBuild(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  String? tuPath;
  String? saida;
  var emit = 'vm';
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-o') {
      if (i + 1 >= args.length) {
        stderrSink.writeln('itac build: `-o` sem caminho');
        return 64;
      }
      saida = args[++i];
    } else if (a.startsWith('--emit=')) {
      emit = a.substring('--emit='.length);
      if (emit != 'vm' && emit != 'aot') {
        // Valor desconhecido é ERRO, não silêncio: `--emit=aotr` cairia no
        // default `vm` e gravaria o `.dill` que o AOT recusa — a falha
        // apareceria três passos adiante, no `gen_kernel`, sem dizer por quê.
        stderrSink.writeln('itac build: `--emit=$emit` desconhecido (vm | aot)');
        return 64;
      }
    } else if (a.startsWith('-')) {
      stderrSink.writeln('itac build: opção desconhecida: $a');
      return 64;
    } else if (tuPath == null) {
      tuPath = a;
    } else {
      stderrSink.writeln('itac build: mais de um arquivo de entrada');
      return 64;
    }
  }
  if (tuPath == null) {
    stderrSink.writeln('itac build: uso: itac build <file.tu> [-o <saída>] '
        '[--emit=vm|aot]');
    return 64;
  }

  final outcome = compileToDill(tuPath);
  if (outcome.code != null) {
    for (final d in outcome.diagnostics) {
      stderrSink.writeln(d);
    }
    return outcome.code!;
  }

  final destino = saida ?? _trocarExtensao(tuPath, '.dill');
  final bytes = emit == 'aot'
      ? serializeFullComponent(outcome.component!)
      : outcome.bytes!;
  try {
    File(destino).writeAsBytesSync(bytes);
  } on FileSystemException catch (e) {
    stderrSink.writeln('itac build: não consegui gravar `$destino`: ${e.message}');
    return 73; // EX_CANTCREAT
  }
  stdoutSink.writeln('$destino (${bytes.length} bytes, --emit=$emit)');
  return 0;
}

/// `itac run <file.tu>` — build + executa, e o exit code É o do programa.
///
/// ⚠️ **O `.dill` vai para um temporário e é apagado.** `run` não é `build` com
/// um passo a mais: quem quer o artefato pede `build`. Deixar um `.dill` ao lado
/// do fonte faria `run` sujar o diretório do usuário, e um `.dill` velho ali é
/// pior que nenhum — ele parece atual.
///
/// O executável é o [Platform.resolvedExecutable], o mesmo dart que roda este
/// processo e de onde o `platformDillPath()` já deriva o platform: *"o SDK que
/// compila é, por construção, o mesmo que executa"*. Quando o `itac` virar o
/// binário AOT do ADR-0006, `resolvedExecutable` passa a ser o próprio `itac` e
/// esta linha precisa de um dart de verdade — a lacuna está declarada aqui e no
/// §9, e o sintoma aparece ANTES, no `compileToDill`, que não acharia o
/// `vm_platform.dill`.
int runRun(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.length != 1 || positional.length != args.length) {
    stderrSink.writeln('itac run: uso: itac run <file.tu>');
    return 64;
  }

  final outcome = compileToDill(positional.first);
  if (outcome.code != null) {
    for (final d in outcome.diagnostics) {
      stderrSink.writeln(d);
    }
    return outcome.code!;
  }

  final tmp = Directory.systemTemp.createTempSync('itac_run_');
  try {
    final dill = '${tmp.path}/programa.dill';
    File(dill).writeAsBytesSync(outcome.bytes!);
    // `runSync`: a saída chega ao fim, não em streaming. Para a fatia atual
    // (programas que terminam em milissegundos) a diferença não é observável;
    // quando houver programa longo ou interativo, isto vira `Process.start` com
    // `inheritStdio` e a assinatura passa a ser assíncrona.
    final p = Process.runSync(Platform.resolvedExecutable, [dill]);
    if ((p.stdout as String).isNotEmpty) stdoutSink.write(p.stdout);
    if ((p.stderr as String).isNotEmpty) stderrSink.write(p.stderr);
    return p.exitCode;
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// `caminho/x.tu` → `caminho/x.dill`. Sem extensão conhecida, apenas anexa.
String _trocarExtensao(String caminho, String nova) =>
    caminho.endsWith('.tu')
        ? '${caminho.substring(0, caminho.length - 3)}$nova'
        : '$caminho$nova';
