---
name: kernel-offsets
description: Como offsets de fileOffset/secundários são serializados no .dill e o que o verifier de fato exige (fmt 130 / SDK 3.12.2)
metadata:
  type: reference
---

# Offsets no Kernel binário (.dill fmt 130) — vendor 3.12.2

**`-1` (`TreeNode.noOffset`, `misc.dart:61`) é um offset LEGAL e round-trips.**
- `writeOffset(o)` escreve `o + 1` como UInt30 (`binary/ast_to_binary.dart:1094-1102`); comentário: "File offset ranges from -1 and up".
- `readOffset()` lê `readUInt30() - 1` (`binary/ast_from_binary.dart:4480-4484`).
- Logo `-1` NÃO é malformado no binário; não há base de contrato-Kernel para normalizá-lo.

**O verifier só checa o offset PRIMÁRIO** (`verifier.dart`):
- `checkLocation` (1806-1825): se `name != null && !name.contains("#")` e `fileOffset == noOffset` e `!verification.allowNoFileOffset` → erro "'$name' has no fileOffset". Só nós NOMEADOS.
- `Verification.allowNoFileOffset` (53-56) só libera `Library`. `AsExpression` também exige offset (1849-1864).
- `testLocation` está DESLIGADO (`doTestLocation = false`, 1786). Nenhum offset SECUNDÁRIO é checado.
- Portanto: normalizar `fileOffset` primário `-1→0` em nós nomeados É necessário p/ passar o verify; normalizar secundários NÃO é gateado.

**Enumeração canônica de nós com offset SECUNDÁRIO** = overrides de `fileOffsetsIfMultiple` (base `TreeNode`=null em `misc.dart:75`) + pares de `writeOffset` no writer:
- Class: startFileOffset, fileEndOffset (`declarations.dart:34,39`; writer 1294-1296)
- Constructor: startFileOffset, fileEndOffset (`members.dart:566`; writer 1337-1339)
- Procedure: **fileStartOffset** (assimetria!), fileEndOffset (`members.dart:925`; writer 1408-1410)
- Field (base Member): fileEndOffset (`members.dart:17`; writer 1507-1508)
- FunctionNode: fileEndOffset (`functions.dart:19`; writer 1574-1575)
- Block: fileEndOffset (`statements.dart:91`; writer 2275-2276)
- **AssertStatement**: conditionStartOffset/conditionEndOffset (`statements.dart:233`; writer 2300-2301) — ctor params obrigatórios
- **ForInStatement**: bodyOffset default noOffset (`statements.dart:638`; writer 2375)
- **SwitchCase**: expressionOffsets[] (`statements.dart:958`; writer 2403)
- **VariableDeclaration**: fileEqualsOffset default noOffset (`variables.dart` várias; writer 2489) — emitido em TODO local/param

Typedef/Extension/ExtensionTypeDeclaration/Library: SÓ offset primário (não aparecem em `fileOffsetsIfMultiple`).
