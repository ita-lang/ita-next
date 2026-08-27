---
name: fase7-conformance-lowering
description: F7 — espaço de técnicas p/ lowering de conformance de traits (merge/witness/box/mono/orphan), coerência whole-program, defaults; parecer p/ ADR proposed (2026-07-16)
metadata:
  type: project
---

# Lowering de conformance (parecer W1, 2026-07-16 — alimenta ADR `proposed`; decisão é do dono)

Problema: trait-é-tipo (subsunção `T ≤ Ord`) ⟹ dispatch existencial; conformance em 3 sítios
(decl, `impl`, `extension`); Kernel = vtable nominal sem retrofit; foreign (Int→`dart:core::int`)
irretrofitável. Traits são FOLHA (ADR-0015 §A); bounds não lidos (ADR-0016 §E).

## Espaço de técnicas (todas type-directed ⟹ **pós-F5, nunca F3** — W&B'89: a tradução é
## definida SOBRE a derivação de tipos; mesmo argumento da minha correção ao ADR-0011)
- **(a) merge-na-Class** (whole-program): F7 funde `impl`/`extension` na `Class` +
  `implementedTypes`. Precedente: CI cap.29 copy-down (closed-world — **fora do acervo capturado**);
  Dart AOT é closed-world. Side-table: `ResolvedMember.origin`/`TypeInfo.traits` — **já existe tudo**.
  Runtime zero (TFA devirtualiza, ~16× do ROADMAP). Falha: foreign + separate compilation.
- **(b) witness/dictionary — 3 sabores DISTINTOS**: Haskell (W&B POPL'89) = dict no ARGUMENTO;
  Rust `dyn` = vtable no PONTEIRO (fat pointer, zero lookup, RFC 0255); Swift = PWT no CONTAINER
  (3 words inline + metadata + PWT, `docs/ABI/TypeLayout.rst`, WWDC16 s.416) + registry p/ casts +
  dict-passing oculto em genérico não-especializado. **No Kernel não há fat pointer/arg oculto ⟹
  witness reifica como objeto = colapsa em (c)**. Exige side-table NOVA: sítios de subsunção —
  e há UM ponto a instrumentar (subsunção centralizada, blocker #1 do meu review da 009).
  Fundamento Dragon: **6.5.2 `widen`** — coerção implícita materializa na IR (analogia assinada minha).
- **(c) box/adapter na fronteira**: `class Ord$Int implements Ord`. Precedente: Swift boxa por
  TAMANHO (>3w, daí `any` SE-0335); Scala 2 implicit-conversion-wrapper; Rust = newtype MANUAL.
  Vaza: identidade, custo escondido (anti-P4), type-test vê o box, `==`-delegação.
- **(d) monomorfização**: NÃO resolve existencial (definicional — o tipo decide em runtime; o
  próprio Rust tem `dyn` por isso). Só cobre genérico bounded, que hoje NEM TEM superfície (bounds
  descartados). Compile-time explosivo = anti-métrica Go (Go 1.18 escolheu stenciling+dicts).
- **(e) orphan/proibir foreign**: Rust RFC 1023+2451 (trait local OU tipo local, cobertura).
  O código JÁ toma a posição extrema provisória: `conformance-on-builtin-unsupported`
  (`collect.dart:388-393`) com a fork M5 aberta (Int→`.tu` própria ⟹ foreign some por construção).

## Coerência (Q2)
Hoje: 6.3.6 `duplicate-member` (namespace único por tipo) + own>default via cadeia Fig.2.37 +
default×default recusado + trait-folha (sem diamante). Unidade = **(tipo, NOME)**, não (tipo,trait)
— mais restritivo que Rust (ruling §12-4). Precedente da especificidade: JVMS §5.4.3.3.
Whole-program ⟹ orphan NÃO é soundness (collect global É a prova); função remanescente = localidade
de culpa + semver (RFC 1105: adicionar impl só é minor POR CAUSA da orphan). Com pacotes .tu fonte:
clash entre deps explode no usuário final (diamante). Evidência empírica da ausência de orphan:
**Swift SE-0364** (conformance retroativa duplicada = comportamento não especificado em runtime).

## Híbrido local=merge + foreign=box (Q3)
**Nenhum grande faz esse corte**: Swift é uniforme-PWT (retroativa funciona em tipo alheio; box por
tamanho, não por origem); Kotlin proíbe tudo (extensions estáticas); Scala desvia (dict no termo).
Combinação original com metades fundadas — assinada minha. Fronteira LIMPA (derivação minha): a
técnica muda por PROPRIEDADE do tipo, nunca por sítio; híbrido é spec-limpo **sse** fronteira
coincide com valor/referência (struct sem identidade ⟹ vazamento de identidade some por construção).

## Defaults (Q4)
Java 8 = VM resolve (JVMS §5.4.3.3/§5.4.6, corpo 1×, zero cópia — exige suporte de VM que a Dart VM
NÃO tem p/ interface). Scala pré-2.12 = `Trait$class` estático + forwarder stubs por conformer
(quebra binária ao adicionar método); 2.12+ = defaults Java 8. Menu real no Kernel: copiar corpo
(self concreto ⟹ TFA especializa; code-size ↑) vs stub-forwarder (1 corpo, self trait-typed) vs
mixin Kernel (`mixedInType` — transformer achata = cópia Grupo B; estado atual → dart-vm-expert).
Separate compilation: as duas quebram IGUAL (lição Scala: só VM-resolve salva). Whole-program AOT
(ADR-0006) ⟹ custo aceito.

## Fontes — o que a casa cobre (Q5)
Dragon: 1.6.5+Ex.1.8 (dispatch = conceito), 6.3.6, 6.3.4, **6.5.2 (materializar coerção)**,
12.2.1 (dispatch virtual SÓ como problema de análise — além da fronteira). NÃO tem: vtable,
interface dispatch, witness, typeclass, coerência. CI: caps.12/13/28/29 (method tables runtime +
copy-down) — **fora do acervo capturado** (que para em compiling-expressions). Externa obrigatória:
W&B'89; PJ/Jones/Meijer'97; RFCs Rust 1023/2451/0255/1105; Swift TypeLayout.rst + WWDC16 + SE-0364;
JVMS §5.4.3.3; Scala 2.12 notes; Go 1.18 design doc + Russ Cox itab.

Ver [[types]] (subsunção ponto único), [[fase5-spec-011-membros]] (origin/duplicate-member),
[[desugaring]] (F3 é type-agnostic ⟹ lowering type-directed é pós-F5).
