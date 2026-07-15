# Spec 001: Semântica de largura de `Int` e operações bitwise através dos alvos

> **Tipo:** decisão-de-linguagem · **Marco:** `M4`
> **Status:** `clarified`
> **Autor / Data:** harness SDD (piloto) · 2026-07-10 · **Issue/PR:** — (resíduo de spec do M4; exemplo `bits` MISMATCH em `js_parity`)

## §0 Metadados

- **Classe da mudança** (Apêndice A):
  - [x] **Nova regra/fase** — fixa a semântica do tipo `Int` (largura, overflow) e das operações `Bits.*`; atravessa a fase semântica e o codegen.
  - [ ] Nova construção · [ ] Ambos.
- **Fases tocadas:**
  - [ ] Léxico (§2) · [ ] Sintaxe (§3) — **fora de escopo** (Q2: manter só a API `Bits.*`; nenhum operador novo)
  - [x] Formal/Tipos (§4) · [ ] SDD (§5) · [ ] Fluxo (§6) · [x] Codegen/IR (§7) · [x] Runtime (§8)
- **Princípios do Itá afetados:** **P4 (Sem mágica)** — hoje a largura de `Int` é herdada silenciosamente do Dart, comportamento invisível; esta spec a torna explícita. **Artigo IV** — reconciliação de paridade VM×JS.

### §0.5 Constitution check

| Fonte | Exigência | Como a spec adere |
| :-- | :-- | :-- |
| Princípio 4 (sem mágica) | O código nunca esconde o que acontece | Torna a largura de `Int` e o comportamento de overflow **especificados e documentados**, não herança silenciosa do Dart. **Reforça** o princípio. |
| Princípio 11 (zero codegen build-time) | Nenhuma geração de código em build | Qualquer *lowering* de reconciliação no JS é feito pelo **codegen do compilador** (runtime da compilação), não por `build_runner`/annotation processors. Sem conflito. |
| Artigo II (3 alvos de graça) | Declarar comportamento em VM/AOT/JS | §7.3 declara os três; a decisão fixa como o JS se reconcilia. |
| Artigo IV.4 (conformância no CI) | CA vira caso no corpus + paridade | §11 define os casos; o exemplo `bits` no `js_parity` passa a cobrir o gap. |

**Conflito aberto:** nenhum.

### §0.6 Clarificações resolvidas (2026-07-10 · dono: `GabrielAderaldo`)

- **Q1 — largura/reconciliação:** `Int` é **64-bit signed two's complement canônico em todos os alvos**. No JS a paridade é garantida apenas no **range seguro**; valores ≥ 2³¹ (bitwise) / > 2⁵³ são **divergência documentada**, não emulada (custo JS zero — respeita o objetivo nº1 de perf/build).
- **Q2 — operadores:** **manter só a API `Bits.*`** — o Itá **não tem** operadores bitwise binários (design intencional; `& | ^ <<` mortos no lexer, `>>` é composição). §2 Léxico e §3 Sintaxe **fora de escopo**.
- **Q3 — overflow:** **wrap silencioso** 64-bit two's complement (como a VM), agora **normativo e documentado**. Não-breaking.

## §1 Motivação e resumo

O Itá **herda silenciosamente** o `int` do Dart, cuja representação **difere por alvo**: na Dart VM (JIT/AOT) é **64-bit signed two's complement**; no `dart2js` é um `number` IEEE-754, com operações bitwise **32-bit** e inteiros seguros até 2⁵³. A largura **não é documentada** (`LANGUAGE_SPEC` lista apenas `Int`, sem largura; não há `Int32`/`Int64`). Consequências:

1. **Viola "sem mágica" (P4):** o programador não tem como saber a largura de `Int` — é comportamento invisível herdado da plataforma.
2. **Divergência VM×JS não especificada:** valores ≥ 2³¹ (shifts grandes, overflow) só existem na VM. O exemplo `bits` do corpus **só não expõe** o gap porque foi construído com todos os operandos ≤ `0xFF`; qualquer caso realista diverge (é o `bits` MISMATCH latente do M4).

**Nota de escopo (fato confirmado via MCP `ita`):** o Itá **não possui operadores bitwise binários**. `& | ^ <<` são *terminais mortos no lexer* (tokenizados, nunca consumidos pelo parser) e `>>` é **composição de funções** (`GRAMMAR.md` §4.2). O único operador bitwise é `~` (unário NOT). Todas as operações binárias são a API **`Bits.and/or/xor/not/shl/shr/bit/bits`**. Esta spec, portanto, é sobre a **semântica do tipo `Int` e da API `Bits`** — não sobre operadores.

**Antes → Depois** (o `.tu` que hoje é ambíguo):

```tu
// antes — comportamento não especificado; diverge entre alvos sem aviso
let big = Bits.shl(1, 40)   // VM: 1099511627776 · JS: valor truncado (não garantido)
let ov  = 9223372036854775807 + 1   // VM: -9223372036854775808 (wrap) · JS: ?
```

```tu
// depois — largura e reconciliação FIXADAS por esta spec (conforme decisão Q1/Q3)
let big = Bits.shl(1, 40)   // comportamento idêntico e especificado em VM/AOT/JS
let ov  = 9223372036854775807 + 1   // overflow com semântica definida (wrap | panic)
```

**Não-objetivos:** (a) introduzir aritmética de precisão arbitrária (`BigInt`) como tipo default; (b) redesenhar a API `Bits`; (c) alterar `Float`.

---

## §4 Especificação formal (tipos e regras) ⭐ — `[cap 6.3, 6.5]`

**4.1 Largura de `Int`.** O `Int` do Itá é **64-bit signed two's complement**, canônico em todos os alvos (Q1). VM/AOT o realizam nativamente; o alvo JS garante essa semântica apenas no range seguro (ver §7.3).

**4.2 Tipos das operações** `[cap 6.3.1, 6.5.1]` (síntese; `Bits.*` são funções totais sobre `Int`):

```
      Γ ⊢ e : Int
      ───────────────        (NOT unário; ~x = -x - 1)
      Γ ⊢ ~e : Int

      Γ ⊢ a : Int   Γ ⊢ b : Int
      ─────────────────────────────     op ∈ {and, or, xor, shl, shr}
      Γ ⊢ Bits.op(a, b) : Int

      Γ ⊢ x : Int   Γ ⊢ i : Int              Γ ⊢ x : Int   Γ ⊢ o,c : Int
      ─────────────────────────              ─────────────────────────────
      Γ ⊢ Bits.bit(x, i) : Bool              Γ ⊢ Bits.bits(x, o, c) : Int
```

**4.3 Semântica das operações** (confirmada na VM via MCP `ita`):
- `~0 = -1`, `~1 = -2`, `~255 = -256` (two's complement) — **coincide em 32 e 64-bit**.
- `Bits.shr` é **shift aritmético** (estende o bit de sinal): `Bits.shr(-1,1) = -1`, `Bits.shr(-8,2) = -2`. **Não há shift lógico.**
- `Bits.shl` desloca em 64-bit: `Bits.shl(1,40) = 1099511627776`, `Bits.shl(1,63) = -9223372036854775808` (bit de sinal em pos. 63).

**4.4 Inferência vs síntese.** Síntese pura; sem variáveis de tipo. Zero annotations (P6): `Int` inferido dos literais/operandos.

**4.5 Overflow / coerção.** Overflow de `Int` é **wrap** 64-bit two's complement (Q3): `maxInt64 + 1 = minInt64`, sem erro nem promoção a `BigInt` — comportamento atual da VM, agora **normativo e documentado**. Sem coerção implícita para `Float` em contexto bitwise.

**4.6 Erros detectados.** Literal fora do intervalo de `Int64` é rejeitado no codegen (`error: Undefined: 9223372036854775808`). *(Melhoria possível: erro semântico com span `int-literal-out-of-range` — anotar em §10.)*

## §7 Código intermediário e geração — `[cap 6.2, 8.1]`

**7.1 Emissão.** `Bits.*` faz *lowering* para os operadores nativos do Dart (`& | ^ ~ << >>`) sobre `int`; `~` idem. Alvo = Dart Kernel (`.dill`).

**7.3 Comportamento por alvo** (o cerne da decisão):

| Alvo | Comportamento atual (medido) | Após a decisão |
| :-- | :-- | :-- |
| **VM** (JIT) | `int` 64-bit signed two's complement — **referência/oracle** | inalterado (fixado como canônico) |
| **AOT** (`dart compile exe`) | idêntico à VM | idêntico à VM |
| **JS** (`dart2js`) | `int` IEEE-754; bitwise **32-bit**, seguro até 2⁵³ → **diverge** para valores ≥ 2³¹ | **Best-effort (Q1):** paridade garantida só no range seguro; ≥ 2³¹ é divergência **documentada**, não emulada. Sem *lowering* de reconciliação (custo zero). |

**Paridade VM×JS:** `bits` = MATCH porque nenhum operando excede 2³¹. Casos que expõem o gap (`Bits.shl(1,40)`, `Bits.shl(1,63)`, `maxInt64+1`) são **divergência documentada** (fora do range seguro) — o corpus os marca como tais, **não** como MATCH exigido (Q1: best-effort).

## §8 Runtime — premissas sobre a Dart VM — `[cap 7.1]`

- A spec **assume** que a Dart VM representa `int` como 64-bit signed two's complement (comportamento herdado, não reespecificado — Grupo B). O que esta spec faz é **elevar esse comportamento a garantia de linguagem** e definir como o alvo JS (que não o compartilha) se reconcilia.

---

## §9 Checklist de completude (Apêndice A)

- [ ] `symbols` — registrar a largura de `Int` (64-bit) como propriedade do tipo `[A.4]`.
- [x] fase semântica — regras de tipo de `Bits.*`/`~` já existem; a spec fixa a **semântica** (largura/overflow), não novas regras de tipo.
- [x] `codegen` — **sem** *lowering* de reconciliação no JS (Q1 = best-effort, custo zero); emissão inalterada.
- [ ] **corpus de conformância** — novos casos que expõem o gap (hoje o `bits` não expõe).
- [ ] **paridade** `js_parity/expected.txt` — casos ≥ 2³¹ registrados como divergência documentada.
- [ ] `LANGUAGE_SPEC` / `GRAMMAR.md` — documentar a largura de `Int` = 64-bit e o wrap (hoje ausente). **Entregável principal.**
- [x] Léxico/`parser`/tree-sitter — **fora de escopo** (Q2 = manter só `Bits.*`).

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** **Não.** As decisões (Q1 best-effort, Q3 wrap) apenas **formalizam e documentam** o comportamento atual da VM; VM/AOT inalterados. No JS não há emulação (custo zero) → a saída atual do JS também não muda; o que muda é a **documentação** de que valores ≥ 2³¹ são divergência conhecida.
- **Plano de migração:** nenhum (não-breaking). Apenas documentação nova no `LANGUAGE_SPEC`/`GRAMMAR.md`.
- **Alternativas consideradas:**
  - *Não especificar* (status quo) — rejeitada: viola P4 e mantém o `bits` MISMATCH latente.
  - *`Int` = 53-bit safe (mínimo comum VM∩JS)* — rejeitável: desperdiça a VM 64-bit; surpreende quem vem de Dart.
  - *Reintroduzir operadores `& | ^`* (Q2) — muda a superfície de sintaxe; tratada como pergunta separada.

## §11 Critérios de aceite (viram testes de conformância)

<!-- Cada CA vira caso .tu no corpus + saída esperada; validado via MCP ita. Alguns dependem de Q1/Q3. -->

- **CA1** — `Bits.not(0)` ⟶ imprime `-1` na VM; **paridade JS MATCH** (coincide em 32/64-bit). *(independe das decisões)*
- **CA2** — `Bits.shr(-1, 1)` ⟶ `-1` na VM (shift aritmético). *(independe)*
- **CA3** — `Bits.shl(1, 40)` ⟶ `1099511627776` na VM/AOT; no JS é **divergência documentada** (≥ 2³¹, fora do range seguro) — o corpus marca como tal, não exige MATCH.
- **CA4** — `Bits.shl(1, 63)` ⟶ `-9223372036854775808` na VM (bit de sinal). *(prova 64-bit)*
- **CA5** — `9223372036854775807 + 1` ⟶ `-9223372036854775808` na VM/AOT (wrap 64-bit, Q3), documentado como normativo.
- **CA6** — novo caso no `js_parity` que **exercita** o gap (≥ 2³¹), registrado como **divergência documentada** (não MATCH exigido); e o benchmark de compile-time (`itac` AOT) não regride.

## Definition of Done

- [ ] CAs cobertos por casos no corpus e verdes (VM/AOT; JS conforme Q1), validados via MCP `ita`.
- [ ] Largura de `Int` documentada no `LANGUAGE_SPEC` (fecha P4).
- [ ] Constitution check sem conflito aberto.
- [ ] CI verde (conformance + unit + benchmark de compile-time).
