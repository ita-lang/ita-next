// compile.dart — o pipeline `.tu` → `.dill` COMPARTILHADO (spec 013 §7.2).
//
// Extraído do `bin/itac.dart` (B3) para haver UMA fonte de verdade entre a CLI e
// o **golden-runner** (§7.7): o corpus tem de exercitar o MESMO caminho que o
// `itac build`/`run`, não uma réplica que diverge em silêncio na primeira fatia
// nova (P4 — o teste que testa outra coisa é mágica escondida).
//
// A função NÃO escreve em stderr: devolve os diagnósticos ao chamador — a CLI os
// imprime, o runner os COMPARA (um ICE esperado é golden, não ruído). O I/O é só
// a leitura do `.tu` e do `vm_platform.dill`.

import 'dart:io';
import 'dart:typed_data';

import 'package:kernel/kernel.dart'
    show loadComponentFromBinary, loadComponentFromBytes;

import 'package:ita_next_compiler/driver/driver.dart';

import 'emit.dart';
import 'finalize.dart';

/// Saída de [compileToDill]. `code == null` ⟺ sucesso (e então `bytes != null`).
///
/// Os códigos são os da CLI (§7.2), e o golden-runner os lê como classificação
/// da falha — por isso são parte do contrato, não detalhe do `main`:
///   - **66** arquivo não encontrado;
///   - **65** erro de FASE (léxico/parse/tipos/fluxo) — a F7 nem roda (§0.6);
///   - **70** **ICE de codegen** (§7.8): nó que a emissão ainda não sabe baixar.
///     Não é erro de usuário — é a fronteira honesta da fatia atual.
typedef CompileOutcome = ({
  int? code,
  Uint8List? bytes,
  List<String> diagnostics,
});

/// Roda F1→F6 sobre [tuPath], GATEIA a F6 e emite/finaliza o `.dill`.
///
/// [platformBytes] são os bytes CRUS do `vm_platform.dill` (não um `Component`)
/// — de propósito: o [finalizeProgram] **muta** o platform (anexa as libs do
/// programa), logo cada compilação precisa de um `Component` FRESCO. Passar os
/// bytes deixa o chamador ler o arquivo de 8 MB uma única vez e ainda assim
/// desserializar um Component novo por programa, que é o que a docstring do
/// `finalizeProgram` exige. Ausente ⟹ carrega do [platformDillPath].
CompileOutcome compileToDill(String tuPath, {Uint8List? platformBytes}) {
  final tu = File(tuPath);
  if (!tu.existsSync()) {
    return (
      code: 66,
      bytes: null,
      diagnostics: ['itac: arquivo não encontrado: $tuPath'],
    );
  }
  final source = tu.readAsStringSync();

  // F1–F2: parse. Erro léxico/parse aborta — árvore mal-formada envenena o resto.
  final parsed = parseSource(source);
  if (parsed.hasErrors) {
    return (
      code: 65,
      bytes: null,
      diagnostics: [
        for (final e in parsed.lexErrors) e.format(),
        for (final e in parsed.errors) e.format(),
      ],
    );
  }

  // F3–F6: desugar → bind → check → flow. GATE (013 §0.6): `flow == null` ⟹
  // F4/F5 reprovaram; `flow.hasErrors` ⟹ F6 reprovou. Só F5+F6-VERDE emite.
  final res = flowProgram(parsed.program);
  final flow = res.flow;
  if (flow == null) {
    return (
      code: 65,
      bytes: null,
      diagnostics: [for (final e in res.check.errors) e.format()],
    );
  }
  if (flow.hasErrors) {
    return (
      code: 65,
      bytes: null,
      diagnostics: [for (final e in flow.errors) e.format()],
    );
  }

  // F7: emitir da AST REAL (`res.check`) + finalizar contra o platform. O
  // `CodegenIce` sai como UMA linha limpa `ice: <code> @<off>+<len>` (o
  // `toString` do próprio ICE) — sem stack trace.
  try {
    final platform = platformBytes != null
        ? loadComponentFromBytes(platformBytes)
        : loadComponentFromBinary(platformDillPath());
    final emitted = emitProgram(res.check, platform, sourceUri: tu.absolute.uri);
    final bytes = finalizeProgram(
      platform,
      emitted.libs,
      mainMethod: emitted.main,
    );
    return (code: null, bytes: bytes, diagnostics: const []);
  } on CodegenIce catch (ice) {
    return (code: 70, bytes: null, diagnostics: ['$ice']);
  }
}

/// Deriva o `vm_platform.dill` do dart PINADO que roda este processo:
/// `Platform.resolvedExecutable` = `<sdk>/bin/dart`, logo
/// `<sdk>/lib/_internal/vm_platform.dill`. Nada de arg explícito — o SDK que
/// compila é, por construção, o mesmo que executa.
String platformDillPath() {
  // `File(dart).parent` = <sdk>/bin ; `.parent` = <sdk> (Directory, com URI
  // de barra final — `resolve` anexa sem comer o último segmento).
  final sdkDir = File(Platform.resolvedExecutable).parent.parent;
  return sdkDir.uri.resolve('lib/_internal/vm_platform.dill').toFilePath();
}
