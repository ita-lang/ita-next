---
name: kernel-field-mutability
description: O verifier do Kernel gateia a relação isFinal/hasSetter de Field; regra exata e arestas (3.12.2)
metadata:
  type: reference
---

# Field: isFinal ⟺ sem setter é GATEADO pelo verifier (3.12.2)

`verifier.dart` `visitField` (744-768):
```
isImmutable = isLate ? (isFinal && initializer != null) : (isFinal || isConst);
if (isImmutable == hasSetter) → ERRO
```
Ou seja o verifier EXIGE `isImmutable ⟺ !hasSetter`. Não é só VM-side; o `verifyComponent` reprova.

- `Field.hasSetter => setterReference != null` (`members.dart:485`). `Field.mutable` cria setterRef; `Field.immutable` não.
- O pass de saneamento (sanitize.dart) que alinha `isFinal` a `setterReference` (bidirecional) casa com isso p/ campos NÃO-late e NÃO-const.

**Arestas que o pass simples de isFinal NÃO cobre:**
- `isConst`: isImmutable fica true mesmo com isFinal=false → const+setter continua erro; flip de isFinal não resolve.
- `isLate`: isImmutable = isFinal && initializer!=null. `late final` sem initializer e sem setter → verifier quer hasSetter (mutável) → pass não conserta.
- P2 (`class` com `var`): o pass CONFIA no setterReference. Se o codegen emitir `Field.immutable` p/ um `var`, o pass silenciosamente crava FINAL. A garantia de P2 vive no codegen escolher `Field.mutable`, não no pass.

Outros checks de Field: top-level deve ser static (730-735); const deve ser static (737-742).
