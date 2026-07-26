---
name: verify-target-parity
description: O que verifyComponent lê do Target além de verification; furo de paridade NoneTarget vs VmTarget (tearoff lowering)
metadata:
  type: reference
---

# ItaVerifyTarget (extends NoneTarget) vs VmTarget no que o verify LÊ (3.12.2)

`verifyComponent(target, stage, component, skipPlatform)` (`verifier.dart:65`). O `VerifyingVisitor` lê do `target`:
- `target.verification` (offset/field allowances) — base `Target.verification => const Verification()` (`targets.dart:586`); `NoneTarget` NÃO sobrescreve. Se o `VmTarget` também mantém o default → idêntico. **NÃO verificável no vendor** (vm.dart não vendorado) — declarar lacuna.
- `target.isConstructorTearOffLoweringEnabled` / `isFactoryTearOffLoweringEnabled` / `isTypedefTearOffLoweringEnabled` / `isRedirectingFactoryTearOffLoweringEnabled` (1943-1988): reclamam de tearoff NÃO-lowered.
  - `NoneTarget.enabledConstructorTearOffLowerings => ConstructorTearOffLowering.none` (`targets.dart:639`) → as 4 flags = FALSE.
  - `VmTarget` HABILITA lowering de tearoff (a VM exige lowered). **DIVERGE**: o ItaVerifyTarget é MAIS PERMISSIVO — não pega ConstructorTearOff/TypedefTearOff/RedirectingFactoryTarget crus. Furo de paridade se o codegen emitir tearoff.
- `target.supportsFileUriExpression` (2053): NoneTarget=false (base 433); VmTarget também false → equivalente. Itá não emite.
- `target.constantsBackend` (222/225): NoneTarget=NoneConstantsBackend (675); difere de VmConstantsBackend em keepLocals/alwaysInlineConstants — inerte sem nós const.

**Stage**: `afterModularTransformations` = "final stage of a normal compilation" (`verifier.dart:32-35`); `afterConst=true` (annotations devem ser ConstantExpression etc.). Pode ASSUMIR que transformações modulares (mixin apply etc.) já rodaram — reavaliar quando async/mixin/const entrarem. `skipPlatform:true` inerte (component sem libs de plataforma).
