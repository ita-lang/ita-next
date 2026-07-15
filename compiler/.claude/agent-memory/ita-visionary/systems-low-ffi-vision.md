---
name: systems-low-ffi-vision
description: Diretriz de dono (ADR-0012 §C dec.9, 2026-07-11) — Itá para "systems programming das bordas" com FFI mínimo, quadrante Erlang/Elixir; bitwise = API funcional Bits.*, NÃO operadores.
metadata:
  type: project
---

# Visão: systems programming das bordas, FFI mínimo

**Fato (ADR-0012, decisão §C-9, dono `GabrielAderaldo`, palavra-final 2026-07-11):** o Itá deve
permitir "programação de sistemas com o mínimo de FFI" — drivers de infraestrutura, manipulação de
binários e arquivos binários feitos EM Itá.

**Superfície escolhida pelo dono (a mais itaiana):** bitwise é a **API funcional `Bits.*`**
(`and/or/xor/not/shl/shr/…`), **NÃO operadores**. Manipulação de binários = **binary pattern-matching
estilo Erlang/Elixir** (roadmap, spec própria). Isto **CONFIRMA e ESTENDE** a spec 001 Q2 (não reverte):
Q2 mantinha `~`; a palavra-final desce `~` também a **morto-no-parser** (junto de `& | ^ <<`),
fechando a uniformidade — bitwise é inteiramente `Bits.*` (`Bits.not`), zero operadores. Sem supersede.
`~` segue **tokenizado** (lexer completo, D5), só filtrado pelo parser. `>>` segue `BinaryOp.Compose`,
**nunca** bit-shift.

**Escopo itaiano (guardrail):** quadrante **Erlang/Elixir**, NÃO Rust/Zig.
- SIM: bytes/binários/protocolos/drivers em-linguagem sobre a Dart VM (`typed_data`), binary
  pattern-matching, `Result` p/ erro de I/O binário, `dart:ffi` como escape ENUMERADO e último recurso
  — como Erlang fez telecom (framing binário, drivers) na BEAM e Elixir evita NIFs.
- NÃO: bare-metal, no-GC, ownership/lifetimes/unsafe/ponteiros manuais — fere Art. II (Dart VM = GC,
  permanente) e o catálogo não-fazer. Se o dono quiser, exige emenda de Art. II (Governança).

**Why é itaiano (e por que a escolha funcional é MELHOR que operadores):** reforça o posicionamento
Itá:Dart::Elixir:Erlang (a analogia é sobre RUNTIME, ortogonal ao domínio; "bordas de baixo nível,
FFI mínimo" É a herança Erlang). A API funcional honra P5 (funcional-first) e P4 (sem overload mágico
de `>>`; largura documentada spec 001 Q1/Q3 = Int64 wrap, o oposto de mágica). Operadores C-style
puxariam para o quadrante Rust/Zig e reabririam o conflito de precedência com `>>`. A escolha do dono
também eliminou o `~` órfão que apontei no review da spec 006. Contínuo com o "Norte — independência do
Dart" (interop `dart:` fino/enumerado) e P10.

**How to apply:** aprovar propostas de bytes/binário SE ficam no quadrante-Erlang (VM gerenciada,
`Bits.*`/pattern-matching, `Result`, imutável-por-default, `mut` p/ buffers). RECUSAR/exigir-emenda se
pedem no-GC/unsafe/ownership OU se pedem operadores bitwise C-style (`& | ^ ~ <<` seguem mortos-no-parser
por decisão firme do dono — não re-litigar; ver [[doctrine-ast-representa]]). Largura fixa (Int32/UInt8)
é a PRÓXIMA tensão real (byte/driver quer isso; spec 001 Q1 ADIOU) — gate de maturidade antes de emendar
Art. II.

**Incorporação formal:** por ora diretriz de ADR (correto). Quando amadurecer, emendar como **COROLÁRIO
do "Norte independência do Dart"**, não como pilar concorrente à analogia Elixir:Erlang. Ato de
dono/Governança — não editar constituição por conta.
