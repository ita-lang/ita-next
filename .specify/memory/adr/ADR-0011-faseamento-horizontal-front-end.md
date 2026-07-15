# ADR-0011: Abordagem horizontal + faseamento completo do front-end

- **Status:** Accepted
- **Data:** 2026-07-10
- **Relacionados:** [[ADR-0007]] (Grupo A/B), [[ADR-0008]] (épico 002), [[ADR-0009]] (referências), [[ADR-0010]] (formatos). **Reorienta** o faseamento do épico 002 (que antes começava por um "tradutor em miniatura" vertical).

## Contexto

O plano da reescrita começava por um **tradutor em miniatura (Cap 2, vertical)** — um slice fino tocando
todas as fases — para *provar o pipeline*. Mas o **`ita/` já é essa prova** (a PoC: `.tu → tokens → AST →
.dill → VM`, M0–M4). Re-provar o pipeline é retrabalho. Além disso, um levantamento nos **dois livros**
(Dragon Book + Crafting Interpreters) revelou que o núcleo "léxico → sintaxe → SDD → semântica → codegen"
estava **incompleto e com um erro conceitual**: **SDD não é uma fase** — é a *técnica* (Syntax-Directed
Translation) usada dentro das fases. E faltavam **5 fases** que os livros recomendam.

## Decisão

**1. Abordagem HORIZONTAL (por fase completa), não vertical (mini-tradutor).** Cada fase é feita **inteira e
documentada por vez** — com todos os artefatos formais do livro (ADR-0010) — e **validada pelo output da
própria fase** (`itac tokenize` → tokens; `itac parse --dump` → AST em S-expression; `itac check` → tipos/
erros), tendo o **`ita/` como oracle** e referência de código. Não há mini-tradutor: o pipeline end-to-end já
está provado pela PoC; o valor da reescrita é **completude e organização**, não re-validação.

**2. Faseamento completo do front-end (Grupo A — 7 fases):**

| # | Fase | Entrega | Fundamentação |
| :-- | :-- | :-- | :-- |
| 1 | **Léxico** | tokens (+ o scaffold/toolchain/CI entram aqui) | Dragon 3 · CI `scanning` |
| 2 | **Sintaxe** | parser → AST bruta + recuperação de erro | Dragon 4 · CI `parsing-expressions` |
| 3 | **Desugaring / lowering** ★ | AST canônica: reescreve `?`,`\|>`,`>>`,where,copy-with,currying,`$0` | CI §9.5.1 |
| 4 | **Binding (resolução de nomes)** ★ | liga identificador→declaração; escopo/hops; erro de `let` | CI cap. 11 |
| 5 | **Semântica** | tabela de símbolos + type-check + inferência (zero annotations) | Dragon 6.3/6.5 |
| 6 | **Análises estáticas** ★ | flow-check **semântico** (definite-return, unreachable, use-before-assign) + **exaustividade de `match`** | flow-check = **Grupo A** (≠ data-flow de otimização, Dragon 9 = Grupo B) · exaust.: **Maranget 2007** · CI §11.5 |
| 7 | **Codegen → Dart Kernel** | AST-canônica-tipada → `.dill` | **Cap 6** (código intermediário → Kernel; Cap 8 = código de máquina = Grupo B) |

**3. Adiado:** **IR de três endereços própria** (Dragon 6.2) — só quando otimizações independentes de máquina
justificarem; hoje o alvo Dart Kernel já é uma IR pronta (ADR-0004). A AST-tipada deve ser desenhada podendo
ser baixada para uma IR no futuro.

**4. Grupo B (NÃO implementar — herdado da Dart VM):** backpatching/jumping-code (Dragon 6.6–6.7), switch como
jump-table (6.8), frames/ABI de procedimentos (6.9, cap. 7), alocação de registradores, GC, JIT/AOT.

## Consequências

- As **★ (3, 4, 6)** são as fases que o núcleo simplista esquecia — **MUITO relevantes** para o Itá: desugaring
  (o Itá é quase todo açúcar), binding (closures + escopo léxico + `let` imutável), análises (tudo-é-expressão
  exige definite-return; `match` exaustivo é promessa da linguagem, e os livros **não a dão de graça**).
- O **épico 002 é reorganizado** com estas 7 fases; a **spec 003 (mini-tradutor) é descartada**; o **scaffold +
  toolchain + CI entram na Fase 1 (Léxico)**.
- Cada fase = **uma sub-spec `/speckit`** completa, validada por dump + oracle `ita/`.

### Notas de precisão (citações e contratos)

- **Citações corrigidas (fronteira Grupo A/B):** a Fase 6 faz **flow-check semântico** (definite-return,
  unreachable, use-before-assign) — isso é **Grupo A** e **não** é o *jumping-code/backpatching* do Dragon 6.6
  (Grupo B), nem o *data-flow de otimização* do Dragon Cap 9 (Grupo B). São coisas distintas. A
  **exaustividade de `match`** **não vem dos livros** (o Lox do *Crafting Interpreters* não tem pattern
  matching; o Dragon não a trata) — a fonte é externa: **Maranget, *Warnings for pattern matching* (2007)**. A
  Fase 7 emite **código intermediário (Dragon Cap 6) → Kernel** (Grupo A); **Cap 8 (código de máquina) é
  Grupo B**.
- **Contrato Binding × Semântica:** a **Fase 4 (Binding) produz** apenas a resolução nome→declaração e a
  **profundidade de escopo (hops)**; a **Fase 5 (Semântica) consome** isso e **não reconstrói escopo** — o
  contrato evita duplicar a lógica de resolução entre as duas fases.
- **Desugaring é escolha do Itá:** tratá-lo como **passo separado** (AST → AST canônica, modelo **rustc
  AST→HIR**) é decisão do Itá, **não** prescrição do *Crafting Interpreters* (que desaçucara **dentro do
  parser**). O desugaring é **type-agnostic**: produz o nó canônico, validado só depois (Semântica/Análises).
