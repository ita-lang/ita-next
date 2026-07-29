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
/// relinca o seu próprio platform no load (Grupo B), então o `.dill` sai mínimo
/// (CA11/§7.1). As referências externas a `dart:core` entram no `.dill` pelo
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
}) {
  final programSet = Set<Library>.identity()..addAll(programLibs);

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
