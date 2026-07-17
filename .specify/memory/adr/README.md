# ADRs — Registro de Decisões Arquiteturais do Itá

> **Architecture Decision Records.** Uma decisão por arquivo, datada e imutável. Quando uma decisão
> muda, **não se edita** o ADR antigo — cria-se um novo que a `supersedes`. É o mecanismo contra
> regressão: a resposta a "por que fizemos assim?" e "isso ainda vale?" mora aqui.

## Hierarquia de decisão

```
constitution.md            ← princípios permanentes (a lei; raramente muda)  [../constitution.md]
  └─ adr/ADR-NNNN-*.md      ← decisões arquiteturais datadas (podem ser superseded)
       └─ specs/<feat>/     ← specs de feature (implementam decisões)  [/speckit-specify]
```

A `constitution.md` é o topo. Os ADRs detalham **por que** cada escolha de arquitetura foi feita.
O `MANIFESTO.md` (em `ita/`) é a narrativa/visão; o `ROADMAP.md` é o cronograma. Em conflito:
**constitution > ADR > MANIFESTO/ROADMAP**.

## Formato

Cada ADR tem: `Status` (`Proposed` | `Accepted` | `Superseded by ADR-NNNN` | `Deprecated`), `Data`,
`Contexto`, `Decisão`, `Consequências`, e `Relacionados`/`Supersedes`.

## Índice

| ADR | Título | Status | Data |
|-----|--------|--------|------|
| [0001](ADR-0001-dart-vm-backend-permanente.md) | **Dart VM como backend permanente (LLVM abandonado)** | Accepted | 2026-07-04 |
| [0002](ADR-0002-extensao-tu.md) | Extensão de arquivo `.tu` (migração `.glu`→`.tu`) | Accepted | 2026-03-26 |
| [0003](ADR-0003-unfork-dart-stable.md) | Un-fork para Dart stable 3.12.2 (SDK pinado, Kernel 130) | Accepted | 2026-07-06 |
| [0004](ADR-0004-fase-semantica-side-table.md) | Fase semântica via side-table (type-checker, rota rustc) | Accepted · **parcialmente superseded pelo [0013]** (só a regra `Unknown→dynamic`) | 2026-07-06 |
| [0005](ADR-0005-alvo-js-dart2js.md) | Alvo JavaScript via `dart2js` (Rota A; Oxc/Deno descartados) | Accepted | 2026-07-08 |
| [0006](ADR-0006-itac-aot-compile-time.md) | `itac` roda AOT — compile-time perto do Go | Accepted | 2026-07-08 |
| [0007](ADR-0007-roadmap-dragon-book.md) | Roadmap guiado pelo Dragon Book (Grupo A implementa / Grupo B herda) | Accepted | 2026-07-04 |
| [0008](ADR-0008-harness-sdd-speckit.md) | Harness SDD (spec-kit adaptado ao compilador) | Accepted | 2026-07-10 |
| [0009](ADR-0009-referencias-reescrita.md) | Referências da reescrita (Dragon Book + Crafting Interpreters) | Accepted | 2026-07-10 |
| [0010](ADR-0010-formatos-artefatos-formais.md) | Formatos dos artefatos formais por fase (EBNF · ASDL · Ott · tree-sitter) | Accepted | 2026-07-10 |
| [0011](ADR-0011-faseamento-horizontal-front-end.md) | Abordagem horizontal + faseamento completo do front-end (7 fases) | Accepted | 2026-07-10 |
| [0012](ADR-0012-rulings-superficie-fase2.md) | **Rulings de dono da superfície Fase 2** (init/conformance/guard-&&/where/operadores tipados/bitwise-roadmap) | Accepted | 2026-07-11 |
| [0013](ADR-0013-inferencia-falha-e-erro.md) | **Falha de inferência é ERRO; `dynamic` não é tipo de superfície** (supersede parcial do 0004) | Accepted | 2026-07-15 |
| [0014](ADR-0014-procedencia-de-ruling-data-nao-e-fonte.md) | **Procedência de ruling: `data não é fonte`** (Art. IV-6; supersede parcial do 0012 — só a *razão* do item 7) | Accepted *(ratificado em 2026-07-16 — [0016])* | 2026-07-15 |
| [0015](ADR-0015-rulings-superficie-conformance-fase5.md) | **Rulings de dono da superfície de conformance (Fase 5)** — trait é FOLHA · o papel vem do KIND | Accepted | 2026-07-15 |
| [0016](ADR-0016-ratificacao-fila-adr-0014.md) | **Ratificação da fila do 0014** — meta-diretriz Swift · init/memberwise (corpo mata, extension preserva) · ordem obrigatória/defaults saltáveis · init não se herda · razão nova do 0012 item 7 | Accepted | 2026-07-16 |
| [0017](ADR-0017-lowering-de-conformance-f7.md) | **Lowering de conformance (F7)** — merge-na-Class local · defaults por stub+static · box de valor na fronteira existencial `any` · Int = decl `.tu` + backing `dart:core` | Accepted *(R1–R3 decididos em 2026-07-16; existencial é MARCADO: `any Ord`)* | 2026-07-16 |
| [0018](ADR-0018-sistema-de-efeitos.md) | **Sistema de efeitos** — débito de roadmap com endereço (inclinação real do dono, verbatim; spec 014 §12-5 sequenciou) | **`proposed`** — stub deliberado, não bloqueia nada | 2026-07-16 |

> **Superseded conhecido:** a visão "Dart VM = bootstrap → futuro backend LLVM/Swift" (MANIFESTO
> pré-2026-07-04) foi **superseded pelo ADR-0001**. Não reintroduzir.

> **Superseded parcial:** a *regra de ouro* `UnknownType → dynamic` do **ADR-0004** foi **revogada pelo
> ADR-0013** (2026-07-15) — no `ita-next`, falha de inferência é `cannot-infer` (erro), e `dynamic` não é
> alcançável da sintaxe. O **restante do ADR-0004 segue em vigor** (side-table `Map.identity`, rota rustc,
> AST imutável). Não reintroduzir `Unknown→dynamic`.

> ✅ **[ADR-0014] foi ratificado em 2026-07-16** (registro do ato: [ADR-0016] §Procedência). O **Art. IV-6**
> (*"`ruling do dono` no código exige ponteiro para artefato; **data não é fonte**"*) está **em vigor**
> (constituição **1.1.0**). O supersede **parcial do ADR-0012** vale: caiu **só a *razão* do item 7**
> (*"bounds inline cobrem a maioria dos casos"*, falsa — a F5 descarta os bounds e emite
> `generic-bounds-unsupported` desde `b72310d`); a razão nova está no **0016 §E**. **A decisão do item 7 —
> adiar associated types — segue em vigor**, e o resto do ADR-0012 está intacto. A **fila do §3 está vazia**:
> entradas 3–4 no [0015], entradas 1, 2, 5, 6 e 7 no [0016].

> **Reuso de número de spec:** o **nº 003** de *spec* foi **reusado** — a spec `003` original (mini-tradutor
> vertical) foi **descartada** pelo [ADR-0011](ADR-0011-faseamento-horizontal-front-end.md) e o número passou a
> ser `specs/003-lexer-scaffold` (Fase 1: Léxico + scaffold). *É numeração de **spec**, não do **ADR-0003**
> (un-fork Dart stable), que segue vigente.*

> **Lacuna de número deliberada:** o **nº 012** de spec está **RESERVADO** para *membros de built-in* — reserva
> normativa feita pela **spec 011 §1.3** (itens 1 e 5). Por isso a spec da **F7 (codegen → Kernel)** é a
> **`specs/013-codegen-kernel`** (2026-07-16, `draft`), criada ANTES da 012. Número de spec é ordem de criação,
> não de fase.
</content>
