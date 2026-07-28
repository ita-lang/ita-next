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

import 'package:kernel/ast.dart' as k;
import 'package:kernel/kernel.dart'
    show loadComponentFromBinary, loadComponentFromBytes;

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

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
/// [libs] e [check] são a janela INTENSIONAL: o `.dill` serializado diz o que o
/// programa imprime, mas não o que ele É. Invariantes como "zero `DynamicType`"
/// (ADR-0013) ou "todo `InstanceInvocation` tem `interfaceTarget`" rodam IGUAL
/// quando violados — só a inspeção do `Component` os pega. Expostos aqui, e não
/// num `compileToComponent` paralelo, para não bifurcar o pipeline: a CLI ignora
/// os dois campos, o golden-runner os lê. Um caminho, dois leitores.
typedef CompileOutcome = ({
  int? code,
  Uint8List? bytes,
  List<String> diagnostics,
  List<k.Library>? libs,
  CheckResult? check,
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
    return _failed(66, ['itac: arquivo não encontrado: $tuPath']);
  }
  final source = tu.readAsStringSync();

  // F1–F2: parse. Erro léxico/parse aborta — árvore mal-formada envenena o resto.
  final parsed = parseSource(source);
  if (parsed.hasErrors) {
    return _failed(65, [
      for (final e in parsed.lexErrors) e.format(),
      for (final e in parsed.errors) e.format(),
    ]);
  }

  // F3–F6: desugar → bind → check → flow. GATE (013 §0.6): `flow == null` ⟹
  // F4/F5 reprovaram; `flow.hasErrors` ⟹ F6 reprovou. Só F5+F6-VERDE emite.
  final res = flowProgram(parsed.program);
  final flow = res.flow;
  if (flow == null) {
    return _failed(65, [for (final e in res.check.errors) e.format()]);
  }
  if (flow.hasErrors) {
    return _failed(65, [for (final e in flow.errors) e.format()]);
  }

  // ENTRY-POINT (§7.3 + ruling §12-5): exigir `fn main` é do **DRIVER em modo
  // build**, NÃO da emissão — `itac check` sobre uma biblioteca sem `main` é
  // legítimo, e por isso esta guarda não vive na F5 nem na F7.
  final mainError = checkMain(res.check);
  if (mainError != null) return _failed(65, [mainError]);

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
    // As `libs` saem PÓS-finalize: já saneadas e verificadas, que é o estado
    // sobre o qual os invariantes têm de valer (sanear depois de inspecionar
    // testaria uma árvore que não é a que foi serializada).
    return (
      code: null,
      bytes: bytes,
      diagnostics: const [],
      libs: emitted.libs,
      check: res.check,
    );
  } on CodegenIce catch (ice) {
    return _failed(70, ['$ice']);
  }
}

CompileOutcome _failed(int code, List<String> diagnostics) => (
      code: code,
      bytes: null,
      diagnostics: diagnostics,
      libs: null,
      check: null,
    );

/// Valida o entry-point de um build executável (spec 013 §7.3 + ruling **§12-5**):
/// existe `fn main`, **aridade 0**, sem genéricos, não-`async`, com corpo, e
/// retorno `Void`. Devolve o diagnóstico ou `null` se está tudo certo.
///
/// **Por que aqui e não na emissão.** O §12-5 assentou que isto é validação do
/// DRIVER: `itac check` NÃO exige `main` (uma biblioteca sem entry-point é
/// programa legítimo), só `build`/`run` exigem. E a §7.8 é literal — *"a F7 não
/// tem erro de usuário"*. Sem esta guarda, quem esquece o `main` recebia
/// `ice: ice-codegen-missing-main` na cara: a palavra "ICE" acusa bug INTERNO do
/// compilador, e o dev não escreveu bug nenhum — escreveu uma biblioteca. O
/// `emitMain` mantém os ICEs dele como rede de scaffold; eles voltam a ser o que
/// a §7.8 diz que são (impossibilidade interna), porque agora são inalcançáveis
/// por programa de usuário.
///
/// O código sai com o prefixo `build-error:` — não `check-`/`resolve-`/`flow-`:
/// a fase que reprovou é o DRIVER, e o diagnóstico não mente sobre quem falou.
String? checkMain(CheckResult check) {
  final program = check.program;
  final mains = [
    for (final item in program.body)
      if (item is ast.FnDecl && item.name == 'main') item,
  ];
  if (mains.isEmpty) {
    return 'build-error: missing-main @${program.offset}+${program.length}';
  }
  // `main` duplicado não chega aqui — a F4 o pega como `duplicate-declaration`.
  final main = mains.first;
  final returnType = main.returnType;
  final declared = returnType == null ? null : check.annotations[returnType];
  final bad = main.params.isNotEmpty ||
      main.generics.isNotEmpty ||
      main.asyncMarker != ast.AsyncMarker.sync ||
      main.body == null ||
      (declared != null && declared is! VoidType);
  if (bad) {
    return 'build-error: invalid-main-signature @${main.offset}+${main.length}';
  }
  return null;
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
