---
name: parity-js
description: Riscos de paridade VM×JS (ADR-0005) para o codegen do Itá — isolate/spawn e Int/Float.
metadata:
  type: reference
---

# Paridade VM (JIT/AOT) × JS (dart2js) — ADR-0005

## `spawn` / isolates — RISCO DE PARIDADE ALTO
- `spawn` NÃO é primitivo do Kernel/VM. Isolate nasce por CHAMADA de biblioteca:
  `dart:isolate` `Isolate.spawn(entryPoint, message)` / `Isolate.spawnUri`.
  Fonte: `https://mrale.ph/dartvm/` (isolates comunicam só por portas; sem estado
  mutável compartilhado; entry point = função designada que recebe msg por porta).
- Restrições que o nó `Spawn(operand)` precisa carregar/derivar no codegen:
  `Isolate.spawn` exige **entryPoint** = função top-level/estática (não closure que
  captura estado) + **message** SENDABLE. Um `operand` arbitrário sub-especifica.
- **Paridade:** `dart:isolate`/`Isolate.spawn` **não existe no dart2js/JS**. Web usa
  web workers (modelo diferente). Feature que dependa de `spawn` NÃO roda em JS →
  §8 deve declarar a dependência e marcar o alvo JS como não suportado (ou lowering
  alternativo). Sinalizar cedo (W0/W2).

## Int/Float — o único ponto que a MODELAGEM da AST precisa preservar
- `IntLit`≠`FloatLit` na AST (M4) → `IntLiteral`/`DoubleLiteral` no Kernel. Correto.
- Em `dart2js`, `int` e `double` são o MESMO `number` (double IEEE-754). Inteiros
  exatos só até 2^53; entre 2^53 e 2^63 (válidos na VM) perdem precisão em JS.
  A divergência resolve-se no codegen/runtime, mas só EXISTE se a AST preservar qual
  literal era Int e qual era Float — por isso M4 é obrigatório. A AST em si roda no
  compilador (VM nativa) → `IntLit.value` (Dart int 64-bit) guarda exato; sem perda
  na modelagem.
