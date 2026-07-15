# Spec 002: Reescrita do compilador Itá do zero (ÉPICO — Dragon Book)

> **Tipo:** épico (spec-mãe) · **Marco:** `Reescrita` (novo eixo)
> **Status:** `clarified`
> **Autor / Data:** dono + harness SDD · 2026-07-10 · **Escopo:** `ita-next/` (o `ita/` NÃO é tocado)

## §0 Metadados

- **Classe da mudança:** **ÉPICO** — esta spec **não implementa** nenhuma fase; ela define a arquitetura,
  o faseamento e os invariantes. Cada fase vira **uma sub-spec futura** via `/speckit-specify`.
- **Fases do compilador (as 7, via sub-specs):** Léxico (Cap 3) · Sintaxe (Cap 4) · Desugaring ·
  Binding · Semântica (Cap 6) · Análises · Codegen → Kernel (Cap 6). Nenhuma é implementada aqui.
- **Princípios/decisões que regem:** os **11 princípios permanentes** + **ADR-0001…0011**.

### §0.5 Constitution check

| Fonte | Exigência | Como o épico adere |
| :-- | :-- | :-- |
| **ADR-0001** | Alvo é sempre Dart Kernel → Dart VM; LLVM abandonado | O `ita-next` compila para `.dill` → Dart VM. **Nenhuma fase reabre LLVM.** |
| **ADR-0002** | `.tu` é o único dialeto | O `ita-next` lê/escreve `.tu`; sem `.glu`. |
| **ADR-0003** | SDK stable pinado (Kernel 130) | A toolchain (`dart-sdk.pin`, vendor `pkg/kernel`) entra na Fase 1, reaproveitada do `ita/`. |
| **ADR-0004** | Semântica via side-table | A Fase 4 (Cap 6) usa side-table `Map<AstNode,ResolvedType>`, AST imutável. |
| **ADR-0005** | Alvo JS via `dart2js` | O `driver` nasce com `itac build --target=js` (requisito herdado do spike). |
| **ADR-0006** | `itac` AOT, compile-time ~Go | O benchmark de compile-time entra no CI desde a Fase 1. |
| **ADR-0007** | Grupo A implementa (caps 2–6) / Grupo B a VM herda (7–12) | O épico só implementa o Grupo A; runtime/GC/isolates são herdados (sem `runtime/` próprio). |
| Princípios 1–11 | imutável, zero annotations, Result, zero codegen build-time… | A linguagem-alvo é idêntica à do `ita/`; só a **implementação** é reescrita. |

**Conflito aberto:** nenhum. **A linguagem não muda** — muda a implementação do compilador.

## §1 Motivação e resumo

O compilador atual (`ita/`) **funciona** (M0–M2, semântica, codegen, paridade JS), mas cresceu por
acreção e a auditoria de 2026-07-10 revelou débitos estruturais: `codegen.dart` é um **monolito de
11.750 linhas numa única classe**, os 4 testes de internals estavam **órfãos** (não rodavam no CI),
`examples/` mistura corpus-golden com demos, e `runtime/` carregava **28M de peso morto**. Reescrever
**do zero, seguindo a pedagogia do Dragon Book** (fase a fase, cada uma com fronteiras limpas), produz um
compilador que nasce **correto, segmentado e testado** — e serve de referência canônica de "como o Itá é
feito".

**Antes → Depois** (arquitetura, não `.tu` — a *linguagem* é a mesma):

```
ANTES (ita/)                         DEPOIS (ita-next/)
compiler/lib/                        compiler/lib/
  codegen/codegen.dart  (11.7k L,      frontend/lexer     (Fase 1, Cap 3)
    1 classe, tudo dentro)             frontend/parser    (Fase 2, Cap 4)
  semantic/ (ok)                       frontend/desugar   (Fase 3 ★)
  ...                                  frontend/binding   (Fase 4 ★)
                                       frontend/semantic  (Fase 5, side-table, Cap 6)
                                       frontend/analysis  (Fase 6 ★)
test/ (4 Dart órfãos)                  codegen/           (Fase 7 → Kernel, Cap 6, fatiado)
examples/ (corpus+demos)              driver/            (itac, --target=js nativo)
runtime/ (28M morto)                 test/ (roda no CI dia 1) · conformance/ ⊥ examples/
```

**Não-objetivos:**
- **Não tocar o `ita/`** — ele permanece intacto como **oracle** de validação.
- **Não mudar a linguagem** — sintaxe/semântica são as de `GRAMMAR.md`/`LANGUAGE_SPEC.md`/ADRs. Isto é uma
  reescrita de **implementação**, não um redesign de linguagem.
- **Não reabrir LLVM** (ADR-0001). Não reintroduzir `runtime/` embedder.

---

## §A Arquitetura-alvo do `ita-next/`

Layout segmentado pela sequência do livro, com os aprendizados da auditoria embutidos:

```
ita-next/
├── dart-sdk.pin · tools/ · third_party/     (toolchain — entra na Fase 1, ADR-0003)
├── compiler/
│   ├── lib/
│   │   ├── frontend/
│   │   │   ├── lexer/      Fase 1 — texto → tokens
│   │   │   ├── parser/     Fase 2 — tokens → AST bruta
│   │   │   ├── desugar/    Fase 3 — AST canônica (mata o açúcar)
│   │   │   ├── binding/    Fase 4 — resolução de nomes / escopo
│   │   │   ├── semantic/   Fase 5 — símbolos + tipos, side-table (ADR-0004)
│   │   │   └── analysis/   Fase 6 — flow (definite-return…) + exaustividade de match
│   │   ├── codegen/        Fase 7 — AST-canônica-tipada → Dart Kernel (.dill) — FATIADO por responsabilidade
│   │   └── driver/         itac CLI (run/build/check/fmt/tokenize/parse; --target=js desde o design)
│   ├── test/               unit por fase — RODA no CI desde o dia 1
│   └── docs/spec/          GRAMMAR.md, LANGUAGE_SPEC.md (herdados/reconciliados)
├── conformance/            corpus golden (valid/invalid + goldens) — SEPARADO de examples/
└── examples/               demos/showcase (sem golden)
```

Invariantes de arquitetura: (a) `codegen` **nunca** vira classe única monolítica; (b) todo teste **roda no
CI**; (c) `conformance/` (golden) e `examples/` (demos) são diretórios distintos; (d) **sem `runtime/`**.

## §B Faseamento (cada fase = uma sub-spec via `/speckit-specify`)

**Abordagem HORIZONTAL (ADR-0011):** cada fase é feita **inteira e documentada por vez** (todos os artefatos do
livro) e validada pelo **output da própria fase** (dump) contra o oracle `ita/` — **sem** mini-tradutor
vertical (o `ita/` já provou o pipeline). Cada fase = uma sub-spec `/speckit`.

| Fase | Sub-spec | Entrega | Valida por |
| :-- | :-- | :-- | :-- |
| **1** | `lexer` (+ scaffold) | **Scaffold + toolchain + CI** (entram aqui) · léxico completo: tokens, defs regulares, keywords, interpolação, posição | `itac tokenize` → tokens |
| **2** | `parser` | Sintaxe: gramática (`grammar.ebnf`), Pratt, recuperação de erro N2 → AST bruta | `itac parse --dump` → AST (S-expr) |
| **3** | `desugar` ★ | AST canônica: reescreve `?`, `\|>`, `>>`, where-block, copy-with, currying, `$0`, decl. de função | dump da AST canônica |
| **4** | `binding` ★ | resolução de nomes/escopo (Resolver); erros `let`/redeclaração/uso-na-init | side-table nome→decl + testes |
| **5** | `semantic` | tabela de símbolos + type-check + inferência (zero annotations); side-table (ADR-0004) | `itac check` → tipos/erros |
| **6** | `analysis` ★ | flow (definite-return, unreachable, use-before-assign, break-em-loop) + **exaustividade de `match`** | `itac check` → erros de fluxo/exaustividade |
| **7** | `codegen` | AST-canônica-tipada → Dart Kernel; fatiado; alvos VM/AOT/JS | `itac run`/`.dill` → VM (end-to-end) |
| *(8)* | *`ir-3-addr`* | *IR de três endereços própria — **adiada** (ADR-0011); só quando otimização exigir* | — |

★ = fases que o núcleo simplista esquecia (ADR-0011). **Grupo B (não implementar):** backpatching, frames,
registradores, GC, JIT/AOT — herdados da Dart VM. Cada sub-spec segue `specify → clarify → plan → tasks →
implement`, validada contra o oracle antes da próxima.

### §B.1 Artefatos formais e seus formatos por fase (ADR-0007 · ADR-0009 · ADR-0010)

Cada fase **entrega um artefato canônico** (o que o Dragon Book manda produzir), num **formato padronizado e
versionável** (ADR-0010), implementado no estilo do **Crafting Interpreters** (ADR-0009):

| Fase | Artefato canônico (Dragon Book / CI) | Formato de formalização (ADR-0010) | Ref. impl. (CI) |
| :-- | :-- | :-- | :-- |
| **1 Léxico** | definições regulares / spec de tokens | **W3C EBNF** (`.ebnf`, seção lexical) — *só-spec* | `scanning.md` |
| **2 Sintaxe** | gramática → **AST** | **W3C EBNF** `grammar.ebnf` + **tree-sitter** `grammar.js` + **railroad**; AST em **ASDL** `ast.asdl` | `parsing-expressions`, `representing-code`, `appendix-ii` |
| **3 Desugaring** ★ | regras de reescrita (açúcar → núcleo) | tabela de reescrita documentada (*só-spec*); AST canônica no `ast.asdl` | `control-flow` §9.5.1, `functions` |
| **4 Binding** ★ | regras de escopo / resolução de nomes | doc de regras de escopo (*só-spec*); side-table nome→decl | `resolving-and-binding` (cap. 11) |
| **5 Semântica** | tabela de símbolos + regras de tipo | **Ott** `types.ott` (→ LaTeX; opcional Coq) — *só-spec* | `resolving-and-binding` |
| **6 Análises** ★ | regras de flow + exaustividade de `match` | **Ott**/doc formal (regras de fluxo); casos de erro no corpus | `control-flow`, `resolving-and-binding` §11.5 |
| **7 Codegen** | emissão Dart Kernel | **`.dill`** + **dump textual** `*.kernel.txt` (golden); princípios ADR-0009 | — |
| **Conformance** | corpus + goldens | **tree-sitter** `test/corpus/*.txt` + **`*.expected`** | — |

**Grupo B (não produz artefato):** Runtime (Cap 7) e Otimização (Caps 9–12) são herdados da Dart VM (ADR-0007).
**Guard (ADR-0010):** todos os formatos acima são *só-spec* ou geração-por-script-do-dev; nenhum acopla
gerador ao build do `itac` (Princípio 11), nem arrasta Python/Node ao compilador (Princípios 8/9).

## §C Estratégia oracle

O **`ita/` é o oracle**. Regra de "pronto" de cada fase:

1. **Goldens:** o `ita-next` reproduz byte-a-byte os `ita/examples/*.expected` que a fase habilita (via MCP
   `ita` no `ita/` para gerar o esperado, e execução do `ita-next` para conferir).
2. **Conformância:** passa o mesmo corpus `valid/`+`invalid/` que o `ita/` passa (`itac check`).
3. **Paridade VM×JS:** quando a fase de codegen chega, o `js_parity` do `ita-next` bate o placar do `ita/`.
4. **Diferença permitida:** só melhorias explícitas (ex.: `codegen` fatiado, erros com melhor span) — nunca
   regressão de comportamento observável.

## §10 Compatibilidade, migração e cutover

- **Durante o épico:** `ita/` e `ita-next/` coexistem; o `ita/` é oracle e não é tocado.
- **Cutover (decisão futura, fora deste épico):** quando o `ita-next` passar **todo** o corpus do `ita/` com
  paridade e o benchmark AOT, decide-se promover `ita-next` → `ita` (e arquivar o antigo). Registrar em ADR
  próprio na hora. Versionamento do `ita-next` (git próprio / repo na org) também é decisão da Fase 1.

## §11 Critérios de aceite do épico (§conformance)

O épico está **pronto** quando o `ita-next` satisfaz, validado via MCP `ita` + CI:

- **CA1** — compila e roda o **corpus de conformância** do `ita/` (`valid/` passa, `invalid/` falha) com as
  mesmas mensagens de erro (EN kebab-case + span).
- **CA2** — reproduz os **goldens** de `examples/*.expected` do `ita/` (byte-a-byte na VM/AOT).
- **CA3** — **paridade VM×JS** ≥ o placar atual do `ita/` (dart2js); `itac build --target=js` funcional.
- **CA4** — `itac` roda **AOT** com compile-time **perto do Go** (benchmark no CI sem regressão — ADR-0006).
- **CA5** — **todos os testes rodam no CI** (unit por fase + conformance + parity + benchmark) verdes.
- **CA6** — `codegen` **não é** uma classe monolítica única; `conformance/` e `examples/` são separados; sem
  `runtime/`.

## Definition of Done (do épico)

- [ ] Todas as sub-specs (Fases 1–7) implementadas e verdes (cada uma com seu `/speckit` completo).
- [ ] CA1–CA6 satisfeitos, validados via MCP `ita` e CI.
- [ ] Constitution check sem conflito; nenhuma menção a LLVM reintroduzida.
- [ ] Decisão de cutover registrada em ADR quando o `ita-next` alcançar paridade total.
