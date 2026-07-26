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
