---
name: systems-low-ffi-vision
description: Diretriz de dono (ADR-0012 C9, 2026-07-11) — Itá para "systems programming das bordas" com FFI mínimo; escopo = quadrante Erlang/Elixir, NÃO Rust/Zig. Reverte spec-001 Q2.
metadata:
  type: project
---

# Visão: systems programming das bordas, FFI mínimo

**Fato (ADR-0012, decisão C9, dono `GabrielAderaldo`, 2026-07-11):** o Itá deve permitir
"programação de sistemas com o mínimo de FFI" — drivers de infraestrutura, manipulação de
binários e arquivos binários feitos EM Itá. Consequência: bitwise vira feature de 1ª classe
(reativar `& | ^ <<`, resolver right-shift); `~` (NOT unário) já era ativo.

**Escopo itaiano (guardrail que plantei):** é o quadrante **Erlang/Elixir**, NÃO Rust/Zig.
- SIM: bytes/binários/protocolos/drivers em-linguagem sobre a Dart VM (`typed_data`: Uint8List,
  ByteData…), FFI (`dart:ffi`) como escape ENUMERADO e último recurso — exatamente como Erlang
  fez telecom (framing binário, drivers de switch) na BEAM e Elixir evita NIFs.
- NÃO: bare-metal, no-GC, ownership/lifetimes/unsafe/ponteiros manuais — isso fere Art. II
  (Dart VM = GC, permanente) e o catálogo não-fazer ([[identity-yield-and-nao-fazer]]). `mut` é
  PERMISSÃO de mutação, não borrow. Se o dono quiser isso, exige emenda de Art. II (Governança).

**Why é itaiano:** REFORÇA (não quebra) o posicionamento Itá:Dart::Elixir:Erlang — a analogia é
sobre RUNTIME (linguagem própria sobre VM madura), ortogonal ao domínio; e o domínio "bordas de
baixo nível, FFI mínimo" É a herança Erlang. É contínuo com o "Norte transversal — independência
do Dart" (interop `dart:` fino/enumerado) e P10 (sem deps nativas difusas). Bitwise com largura
DOCUMENTADA (spec 001 Q1/Q3: Int64 two's-complement, wrap) HONRA P4 (torna o bit-level explícito),
em vez de ferir — desde que shift-right NÃO reuse `>>` (isso seria magia de overload-por-tipo).

**How to apply:** ao revisar propostas de "acesso a bytes/bitwise/driver", aprovar SE ficam no
quadrante-Erlang (VM gerenciada, Result p/ erro de I/O binário, imutável-por-default, `mut` p/
buffers). RECUSAR/exigir-emenda se pedem no-GC/unsafe/ownership. Largura fixa (Int32/UInt8…) é a
PRÓXIMA tensão real (byte/driver quer isso; spec 001 Q1 ADIOU) — gate de maturidade antes de
emendar Art. II.

**Incorporação formal:** por ora é diretriz de ADR (correto). Quando amadurecer, emendar como
COROLÁRIO do "Norte independência do Dart", não como novo pilar que substitua a analogia
Elixir:Erlang. Ato de dono/Governança — não editar constituição por conta.

## Precedente REVERTIDO — spec 001 Q2
Spec `001-int-bitwise-semantics` §0.6 Q2 (dono, 2026-07-10) decidiu "manter SÓ a API `Bits.*`; o
Itá NÃO tem operadores bitwise binários; `& | ^ <<` mortos, `>>` é composição; §Léxico/§Sintaxe
fora de escopo" — e listou "reintroduzir `& | ^`" como alternativa REJEITADA. A C9 (1 dia depois)
INVERTE isso. **Não citar Q2 como doutrina viva.** ADR-0012 deveria registrar o supersede
explicitamente (apontei como correção de fidelidade). `>>` = Compose segue firme (spec 006 enum
`BinaryOp.Compose`) — NÃO pode virar bit-shift.
