# ADR-0015 — Rulings de dono da superfície de conformance (Fase 5)

- **Status:** Accepted
- **Data:** 2026-07-15
- **Relacionados:** [[ADR-0012]] (mesmo gênero, Fase 2 — este **não** o supersede: são rulings **novos**, sobre superfície que a 005 declarou e a F5 passou a impor) · [[ADR-0011]] (faseamento) · [[ADR-0014]] (é ele quem obriga este arquivo a existir: **data não é fonte**) · spec `005-decl-surface` §3.1c/§3.6 · spec `011-member-resolution`
- **Assentado por:** [[ADR-0014]] §3, entradas **3** e **4** — que saem da fila de ratificação com este ADR.

## Contexto

A Fase 5 passou a **impor** a superfície de conformance que a spec 005 apenas **representava** (*"a AST representa, não valida"*, 005 §42). Ao fazê-lo, dois casos que a gramática admite ficaram sem resposta, e os dois eram **load-bearing**: decidiam diagnóstico que o usuário leva.

O dono decidiu os dois em **2026-07-15**. Este ADR os assenta — e existe **porque** eles estavam a fundar código com um carimbo de data por única fonte, que é exatamente o que o [[ADR-0014]] nomeia. O código citava *"(ruling do dono, 2026-07-15)"*; um `grep` em `specs/`, `.specify/` e `docs/` devolvia **zero**.

> **Procedência:** decisões tomadas em conversa (sessão de 2026-07-15), transcritas aqui **sem interpretação**. Onde a sessão produziu corolários que **não** são do dono, eles estão marcados como tal (§C) — não são cravados por este ADR.

## Decisão

### A. Trait é **FOLHA** — não tem supertrait

**Nenhuma aresta sai de um trait.**

A porta da frente já não o exprimia: `traitDecl ::= "trait" IDENT genericParams? typeBody` (`grammar.ebnf`) **não tem cláusula `:`**, logo `trait X : Y` é inexprimível. Mas as **portas laterais** — `extension X : Y` e `impl Y for X`, com `X` trait — passavam, e a aresta **ficava**: o `_checkTraitConformance` fazia `if (kind == trait_) return`, pulando a checagem e deixando declarado `X ≤ Y` sem conferir nada.

**Ruling:** as laterais fecham. Erro **`trait-supertype`**.

Razão registrada na decisão: *"ou o recurso existe pela porta da frente, ou não existe"* — coerente com a gramática como escrita; fechar a lateral em vez de legitimar por ela o que a porta da frente não oferece.

**Consequência estrutural:** o grafo de traits tem **profundidade 1** ⟹ **só `superclass` pode ciclar**, e é a única aresta que o detector de ciclo corta.

### B. O papel vem do **KIND**, não da posição

**O 1º type após `:` só é superclasse se for `class`.** Sendo trait, é trait — e a classe fica **sem** superclasse.

O parser atribui por **posição** (`parser.dart`: o 1º type após `:` vai para `superclass`, sempre), que é o que ele pode fazer sem lookahead nem tabela de tipos. A posição sozinha **mente**: em `class Pato : Voa` com `Voa` trait, o parser produz `superclass = Voa`, e o kind-check rejeitaria (`superclass-not-a-class`) um programa legítimo. **Consequência: `class` que conforma a trait sem ter superclasse era INEXPRIMÍVEL.**

```
class Pato : Voa            // Voa é trait  → superclass = null, traits = [Voa]
class Dog  : Animal, Barker // Animal é class → superclass = Animal, traits = [Barker]
class X    : Gato, Cao      // 2 classes → erro (só a 1ª pode ser superclasse)
```

Precedente citado na decisão: **Swift**.

**A F2 não muda.** O split do parser é puramente posicional, logo **reversível**: `[superclass, ...traits]` reconstrói a ordem-fonte sem perda. O ruling cabe inteiro na F5 (`_conform`, A2 — onde o span do type ofensor existe).

### C. Corolários — **NÃO são do dono. Assinados.**

Registrados aqui para que ninguém os cite como ruling de dono (a doença do [[ADR-0014]]):

| Corolário | Quem assina | Situação |
| :-- | :-- | :-- |
| **`class-after-trait`** — *"superclasse primeiro ou em lugar nenhum"*: se o 1º é trait, uma `class` depois é erro | `ita-visionary`, 2026-07-15 | Corolário de **B**, não contradição dele: **B** governa a *derivação* (o compilador não infere papel da posição); este governa a *apresentação* (a fonte não contradiz, na posição, o papel que o kind deu). Precedente: Swift — *"Superclass must appear first in the inheritance clause"*. **Contestável.** |
| **`multiple-superclasses`** | derivação do `compiler-craftsman` | Entailment de **B** + ADR-0012 §A-1 (`class` tem uma superclasse). |

> ⚠️ O ganho do `class-after-trait` **não** é *"saber se `D` herda"* — para isso o leitor ainda precisa do kind de `A`. É que os demais **certamente não** são a superclasse ⟹ a busca cai de N arquivos para 1. É a forma do `override`: **aponta, não responde**.

## Consequências

- **Códigos de erro que este ADR funda:** `trait-supertype` (A) · `superclass-not-a-class` e `trait-expected` da 005 §3.6 **passam a realmente disparar** (B) · `class-after-trait` e `multiple-superclasses` (C, assinados).
- **`extension` não planta superclasse por retrofit** — superclasse vem da decl da própria classe e de mais lugar nenhum (entailment de B).
- **A cerca do `_lookup`** (candidato sem corpo não denota, `ruling ita-visionary`) **só é sã como post-filter porque (A) vale**: requisito nunca vem de mais de um nível. **Se (A) for algum dia revogado, aquela cerca tem de virar parâmetro da recursão** — está documentado no ponto (`check.dart`).
- Implementado em `921353a`; a cerca dependente, em `ae7a0d4`.

## Relacionados

Fila remanescente do [[ADR-0014]] §3 — **as 5 que continuam sem artefato**: a meta-diretriz Swift (1), *"`init` em extension preserva o memberwise"* (2), a razão do ADR-0012 item 7 (5), *"ordem obrigatória, defaults saltáveis"* (6), *"`init` não se herda"* (7).
