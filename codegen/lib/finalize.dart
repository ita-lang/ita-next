// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// Pipeline de finalização do `.dill` — LT-F7a (spec 013 §7.1, "Pipeline de
// finalização"). Ordem OBRIGATÓRIA:
//
//   construir Component → [sanitizeComponent] (2 visitors de higiene)
//     → computeCanonicalNames → verifyComponent(ItaVerifyTarget) [gate CA12]
//     → BinaryPrinter (.dill fmt 130)
//
// O saneamento roda ANTES do verify e da serialização; o verify é o NOSSO gate
// de sanidade (a VM não o roda), e NÃO type-checa (verifier.dart:128-129).

import 'dart:typed_data';

import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_to_binary.dart' show BinaryPrinter, BytesSink;
import 'package:kernel/target/targets.dart';
import 'package:kernel/verifier.dart';

import 'sanitize.dart';

/// Target mínimo para o `verifyComponent`. O verifier exige um [Target], mas NÃO
/// o `VmTarget` — que puxaria `pkg/front_end` inteiro (dezenas de MB) e não
/// sobrescreve `verification`, logo é byte-idêntico ao `NoneTarget` no que o
/// verify lê (spec 013 §8.3, decisão do dono 2026-07-20). Vendor +0 MB.
class ItaVerifyTarget extends NoneTarget {
  ItaVerifyTarget() : super(TargetFlags());
}

/// Offsets de início de linha de [source], no formato que o `Source` do Kernel
/// espera (o primeiro elemento é sempre `0`).
///
/// ⚠️ **Conta em code units da `String`, NÃO em bytes do arquivo** — e a
/// diferença é observável. O `fileOffset` de todo nó vem da F1/F3, que indexam a
/// `String` Dart (UTF-16); a VM localiza a linha procurando o offset nesta
/// lista. Computar sobre `readAsBytesSync()` desloca cada linha por um byte a
/// cada caractere não-ASCII acima dela, e o stack trace passa a apontar uma
/// linha ERRADA — silenciosamente, porque o número existe e parece plausível.
///
/// Medido em 2026-07-29 (`panic_exit.tu`): com lineStarts em bytes, o trace do
/// AOT acusava a linha **22**; o `panic` está na **24**. As duas linhas de
/// diferença são os acentos dos comentários acima — que todo fixture desta casa
/// tem, porque a doutrina é escrever o porquê em português no próprio fixture.
List<int> computeLineStarts(String source) {
  final starts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0a) starts.add(i + 1);
  }
  return starts;
}

/// Saneia, verifica e serializa [component]; devolve os bytes do `.dill`
/// (formato 130). Lança se o `verifyComponent` reprovar — que, para entrada
/// F5+F6-verde, é ICE de codegen (§7.8), nunca erro de usuário.
Uint8List finalizeComponent(Component component) {
  sanitizeComponent(component); // higiene de campo ANTES de tudo
  component.computeCanonicalNames();
  verifyComponent(
    ItaVerifyTarget(),
    VerificationStage.afterModularTransformations,
    component,
    skipPlatform: true,
  );
  return writeComponentToBytes(component);
}

/// Finaliza um PROGRAMA que referencia o platform. Todo programa real referencia
/// `dart:core`; o `verifyComponent` só resolve essa referência externa se o
/// membro-alvo (`print`, ...) estiver PRESENTE no Component verificado — o passe
/// `declareMember` que marca `seenByVerifier` percorre TODAS as libs do
/// Component, incondicionalmente (`verifier.dart:416-434`), e o `skipPlatform`
/// só pula a verificação dos CORPOS do platform (`visitLibrary`,
/// `verifier.dart:456-462`), não a declaração dos seus membros. Sem o platform
/// presente, a referência a `print` cai em "Dangling reference"
/// (`defaultMemberReference`, `verifier.dart:1465`).
///
/// Por isso o [platform] (carregado de `vm_platform.dill`) vira a BASE do
/// Component: as [programLibs] são ANEXADAS a ele. Só o PROGRAMA é saneado (o
/// platform já vem correto do `.dill`) e só o PROGRAMA é serializado — a VM
/// relinca o seu próprio platform no load (Grupo B), então o `.dill` sai mínimo.
/// A premissa é a **spec 013 §8.1**, *"casado com o `vm_platform.dill` do pin"*;
/// o filtro (`libraryFilter`, abaixo) é derivação dela, e quem o cobra é o
/// `checkSerializedLibraries`. **Não é o CA11** — o ledger registra o
/// mis-rótulo. As referências externas a `dart:core` entram no `.dill` pelo
/// link table por canonical name (`checkCanonicalName`, `ast_to_binary.dart:1049`),
/// sem carregar o corpo do platform.
///
/// ⚠️ [platform] é MUTADO (recebe as libs do programa e o `mainMethod`; o verify
/// também alterna `seenByVerifier` nos membros durante a passada). Como
/// `loadComponentFromBinary` devolve um Component fresco e não-compartilhado a
/// cada chamada, isto é seguro — mas NÃO reutilize o mesmo [platform] carregado
/// para dois programas: recarregue por programa (as libs se acumulariam).
({Uint8List bytes, RelatorioSaneamento saneamento}) finalizeProgram(
  Component platform,
  List<Library> programLibs, {
  Procedure? mainMethod,
  required Map<Uri, String> sources,
}) {
  final programSet = Set<Library>.identity()..addAll(programLibs);

  // 0. A `Source` de cada lib do programa. Obrigatória, e o parâmetro é
  //    `required` de propósito: um caller que não tenha a fonte à mão precisa
  //    DIZER isso (`sources: const {}`), não esquecer em silêncio — o custo do
  //    esquecimento aparece só no alvo AOT, num FATAL do gerador de DWARF
  //    (`checkSourcesRegistered` em `invariants.dart` conta a história inteira).
  //
  //    `emptySource`: guardamos `lineStarts` e a URI, **não os bytes do
  //    programa**. Medido — o AOT e a linha do stack trace precisam só disto; os
  //    bytes só serviriam para uma ferramenta querer reimprimir o trecho, e
  //    embuti-los cresce o `.dill` pelo tamanho da fonte (`match_produto.tu`:
  //    1928 → 4256 bytes). O `.dill` mínimo tem quem o cobre (o
  //    `checkSerializedLibraries`); a fonte do usuário dentro do artefato não.
  for (final lib in programLibs) {
    final text = sources[lib.fileUri];
    if (text == null) continue; // o invariante acusa — aqui não se inventa fonte
    platform.uriToSource[lib.fileUri] = Source.emptySource(
      computeLineStarts(text),
      lib.importUri,
      lib.fileUri,
    );
  }

  // 1. Anexar as libs do programa ao Component base e (re)adotá-las: `adoptChildren`
  //    seta o `parent` das novas libs (idempotente p/ as do platform, cujos
  //    canonical names já têm `parent == root`). Os canonical names do programa
  //    são bindados no passo 3.
  platform.libraries.addAll(programLibs);
  platform.adoptChildren();
  if (mainMethod != null) {
    platform.setMainMethodAndMode(mainMethod.reference, true);
  }

  // 2. Sanear SÓ o programa — nunca o platform (corromperia libs válidas).
  final saneamento = sanitizeLibraries(programLibs);

  // 3. Canonical names no Component completo (idempotente p/ o platform via a
  //    flag `dirty`), depois o gate do verify (CA12): resolve as refs ao platform
  //    SEM verificar o corpo dele.
  platform.computeCanonicalNames();
  verifyComponent(
    ItaVerifyTarget(),
    VerificationStage.afterModularTransformations,
    platform,
    skipPlatform: true,
  );

  // 4. Serializar SÓ as libs do programa (filtro retornando `true` = INCLUIR —
  //    `writeLibraries`, `ast_to_binary.dart:820`).
  final sink = BytesSink();
  BinaryPrinter(
    sink,
    libraryFilter: (library) => programSet.contains(library),
  ).writeComponentFile(platform);
  return (bytes: sink.builder.toBytes(), saneamento: saneamento);
}
