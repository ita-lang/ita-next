// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
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
    show loadComponentFromBinary, loadComponentFromBytes, writeComponentToBytes;

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

import 'emit.dart';
import 'finalize.dart';
import 'sanitize.dart' show RelatorioSaneamento;

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
  /// Quantas vezes cada passe de saneamento alterou algo. Passe com 0 é
  /// vacuoso sobre este programa — ver `RelatorioSaneamento`.
  RelatorioSaneamento? saneamento,
  // O Component COMPLETO (platform + programa, pós-`finalizeProgram`, que o
  // muta anexando as libs). Sai daqui porque o `checkTypeConsistency` precisa
  // da `ClassHierarchy` para resolver `dart:core` — as `libs` sozinhas não
  // bastam. `null` quando a compilação parou antes da emissão.
  k.Component? component,
  /// **CA11** — os sítios de travessia existencial e o nó que a emissão pôs em
  /// cada um. A F5 grava ONDE (side-table nº7); isto grava O QUÊ, e o
  /// `checkExistentialZeroNode` cobra que não haja nada além da própria
  /// expressão. Sem propagar até aqui, o CA11 só teria a régua GLOBAL do CA10 —
  /// que vê wrapper enquanto classe e não vê cast nem helper.
  Map<ast.Expr, Travessia>? travessias,
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
  final k.Component platform;
  final ({
    List<k.Library> libs,
    k.Procedure main,
    Map<ast.Expr, Travessia> travessias,
  }) emitted;
  try {
    platform = platformBytes != null
        ? loadComponentFromBytes(platformBytes)
        : loadComponentFromBinary(platformDillPath());
    emitted = emitProgram(res.check, platform, sourceUri: tu.absolute.uri);
  } on CodegenIce catch (ice) {
    return _failed(70, ['$ice']);
  }

  // A finalização (saneamento → **verify** → serialização) é separada da emissão
  // DE PROPÓSITO: quando o `verifyComponent` reprova, as `libs` seguem
  // devolvidas. Sem isso, uma árvore mal-formada estourava como exceção crua e o
  // chamador **perdia o acesso ao Component** — justo quando ele é mais útil,
  // porque é aí que os invariantes estruturais dizem O QUE está errado, em vez
  // do "Incorrect parent pointer" do verify.
  try {
    final finalizado = finalizeProgram(
      platform,
      emitted.libs,
      mainMethod: emitted.main,
      // A MESMA URI que o `emitProgram` pôs no `fileUri` das libs, e o MESMO
      // texto que a F1 leu — as duas pontas do `lineStarts` (offsets em code
      // units) vêm daqui, então nada as pode dessincronizar.
      sources: {tu.absolute.uri: source},
    );
    // As `libs` saem PÓS-finalize: já saneadas e verificadas, que é o estado
    // sobre o qual os invariantes têm de valer (sanear depois de inspecionar
    // testaria uma árvore que não é a que foi serializada).
    return (
      code: null,
      bytes: finalizado.bytes,
      diagnostics: const [],
      libs: emitted.libs,
      travessias: emitted.travessias,
      check: res.check,
      saneamento: finalizado.saneamento,
      component: platform,
    );
  } catch (e) {
    // 71 = boa-formação (gate CA12), distinto do 70 (ICE de emissão): o emitter
    // achou que sabia baixar o nó, e a árvore saiu inválida mesmo assim.
    return (
      code: 71,
      bytes: null,
      diagnostics: ['verify: ${e.toString().split('\n').first}'],
      libs: emitted.libs,
      travessias: emitted.travessias,
      check: res.check,
      saneamento: null,
      component: platform,
    );
  }
}

/// O `.dill` **completo** (platform + programa) — o artefato que o alvo **AOT**
/// exige, e que o de produção deliberadamente NÃO é.
///
/// O `.dill` do `itac build` é mínimo: o `libraryFilter` (`finalize.dart:148`)
/// deixa o platform fora da serialização porque **a VM relinca o seu próprio**
/// no load. A premissa é a **spec 013 §8.1** — *"carregamento de `.dill` formato
/// 130 casado com o `vm_platform.dill` do pin"*. ⚠️ O filtro é **derivação**
/// dela, não texto normativo: a **spec 013 §7.1** especifica só *"serialização
/// via `BinaryPrinter`; formato 130"* e não decide o CONTEÚDO do arquivo. Quem
/// escolhe é este código; quem cobra é o `checkSerializedLibraries`.
///
/// O pipeline AOT não relinca — o `gen_kernel` do `dart compile exe` recebe o
/// arquivo e espera achar lá dentro tudo o que ele referencia. Sobre o `.dill`
/// mínimo ele morre assim (SDK 3.12.2, medido):
///
/// ```
/// Reference to dart:core::@methods::print is not bound to an AST node.
/// ```
///
/// Ou seja: **os dois artefatos são legítimos e diferentes**, e o alvo escolhe.
/// Emitir o completo em produção somaria os 7,9 MB do `vm_platform.dill` e o
/// `checkSerializedLibraries` acusaria; emitir só o mínimo deixa o AOT
/// inalcançável — e o alvo está escrito no texto normativo de **sete** CAs da
/// **spec 013 §11**. O molde é o CA1, *"⟶ stdout `olá, 2`, exit 0 — **3
/// alvos**"*, repetido por CA2/4/5/7/8; os três são *"golden-runner VM×AOT×JS no
/// CI"* (**spec 013 §9**), e o sétimo é o CA9: *"VM + AOT; JS: exceção
/// não-capturada, exit ≠ 0"*.
///
/// [component] é o `CompileOutcome.component` — o platform JÁ mutado pelo
/// `finalizeProgram` (libs anexadas, `mainMethod` fixado, canonical names
/// computados, verify passado). Nada aqui re-saneia nem re-verifica: só troca o
/// filtro de serialização.
Uint8List serializeFullComponent(k.Component component) =>
    writeComponentToBytes(component);

CompileOutcome _failed(int code, List<String> diagnostics) => (
      code: code,
      bytes: null,
      diagnostics: diagnostics,
      libs: null,
      travessias: null,
      check: null,
      saneamento: null,
      component: null,
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

/// O diretório do SDK Dart pinado, ou `null` se não houver um localizável.
///
/// **A premissa antiga — *"o SDK que compila é, por construção, o mesmo que
/// executa"* — vale no JIT e MORRE no AOT**, que é o modo que o ADR-0006 exige
/// (*"o `itac` de dev e de CI é o binário AOT, não JIT"*). Sob AOT o
/// `Platform.resolvedExecutable` é o **próprio `itac`**, e `<itac>/../lib/…` não
/// tem platform nenhum. O ADR já registra o mesmo tropeço no repo anterior:
/// *"Fix necessário: `ITA_COMPILER_LIB=compiler/lib` (sob AOT, `Platform.script`
/// aponta pro binário, não achava `toml`)"*.
///
/// A ordem é: **`$ITA_DART_SDK`** → o SDK do executável atual (o caso JIT) →
/// `null`. E o teste de "é um SDK" é o `vm_platform.dill` EXISTIR ali: checar só
/// o nome do diretório aceitaria um `ITA_DART_SDK` apontando para o lugar
/// errado, e o erro apareceria como um `.dill` corrompido três passos adiante.
///
/// [env] e [executavel] existem para o teste: `Platform.environment` é imutável
/// no processo, e sem injeção a única forma de cobrir os três caminhos seria
/// fabricar subprocessos — que é como uma régua deixa de ser rodada.
String? dartSdkDir({Map<String, String>? env, String? executavel}) {
  final ambiente = env ?? Platform.environment;
  final declarado = ambiente['ITA_DART_SDK'];
  if (declarado != null && declarado.isNotEmpty) {
    // Declarado e errado é ERRO, não fallback silencioso: quem setou a variável
    // quis aquele SDK, e cair no do processo escondeu a divergência de versão
    // que o `dart-sdk.pin` existe para impedir.
    return _ehSdk(declarado) ? declarado : null;
  }
  final doProcesso = File(Platform.resolvedExecutable).parent.parent.path;
  final candidato = executavel == null
      ? doProcesso
      : File(executavel).parent.parent.path;
  return _ehSdk(candidato) ? candidato : null;
}

bool _ehSdk(String dir) =>
    File(_platformDillEm(dir)).existsSync();

String _platformDillEm(String sdkDir) =>
    Directory(sdkDir).uri.resolve('lib/_internal/vm_platform.dill').toFilePath();

/// O `vm_platform.dill` do SDK pinado. Lança com mensagem ACIONÁVEL quando não
/// há SDK — a alternativa era um `FileSystemException` sobre um caminho colado
/// de dois pedaços, que não diz o que fazer.
String platformDillPath() {
  final sdk = dartSdkDir();
  if (sdk == null) {
    throw StateError(
      'itac: não achei o SDK Dart pinado.\n'
      '  Rodando AOT? o binário não carrega o platform junto — aponte o SDK:\n'
      '    ITA_DART_SDK=<repo>/.dart-sdk/<versão>/dart-sdk itac ...\n'
      '  (executável atual: ${Platform.resolvedExecutable})',
    );
  }
  return _platformDillEm(sdk);
}

/// O `dart` do SDK pinado — quem EXECUTA o `.dill` no `itac run`.
///
/// Sob JIT é o próprio `Platform.resolvedExecutable`; sob AOT seria o binário
/// `itac`, que não sabe rodar um `.dill`. Derivar do [dartSdkDir] é o que
/// mantém as duas pontas no MESMO SDK, que é a régua do `dart-sdk.pin`.
String dartExecutablePath() {
  final sdk = dartSdkDir();
  if (sdk == null) {
    throw StateError('itac: não achei o SDK Dart pinado (veja `itac build`)');
  }
  return Directory(sdk).uri.resolve('bin/dart').toFilePath();
}
