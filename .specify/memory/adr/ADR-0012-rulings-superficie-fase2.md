# ADR-0012 — Rulings de dono da superfície declarativa/expressional (Fase 2)

> **Status:** Accepted
> **Data:** 2026-07-11
> **Supersedes:** — · **Relacionados:** spec `001-int-bitwise-semantics` (Q2 — **confirmada e estendida**, não revertida), ADR-0004 (semântica side-table), ADR-0011 (faseamento front-end), specs `005-decl-surface`, `006-where-typed-ops`, `constitution.md` (Art. I)

## Contexto

Fechando a Fase 2 (Sintaxe → AST), a revisão de identidade do `ita-visionary` (2026-07-11) apontou lacunas de superfície que os 11 princípios já pediam, e um conjunto de **decisões de dono** que precisavam ser cravadas para as estruturas teóricas (`ast.asdl`, `grammar.ebnf`) ficarem completas. Este ADR registra essas decisões — as que já viraram código (specs 005/006) e as de "não-fazer/adiar/roadmap" — para não regredirem nem serem re-litigadas.

## Decisão

### A. Cravadas e implementadas (specs 005/006)

1. **`init` (construtor):** `struct` usa construtor **memberwise sintetizado** (sem `init` explícito — concisão); `class` usa `init` **explícito** quando há estado a validar/normalizar. O parser aceita `InitDecl` nos corpos roteados por `_typeBody` (struct/class/trait/extension/actor/impl; **exclui `enum`**, que tem corpo próprio) e **preserva `pub init`** (P4 — a AST representa, não esconde); a política por-kind e de visibilidade é imposta na Fase 3.
2. **Conformances:** a forma **inline** (`struct P: Trait`, `class D: Super, TraitA`, `extension S: Trait`) **e** o `impl Trait for T` **coexistem** — declaração-de-intenção vs. retrofit externo.
3. **`guard let v = e && cond`:** split no **primeiro `&&`** — `value` é o opcional a desembrulhar (parseado no nível abaixo de `&&`), `condition` é todo o refino restante. `opt && c1 && c2` → `value=opt`, `condition=(c1 && c2)`.
4. **`where { }`:** forma value-first / leitura top-down (P3), como **expressão** (`WhereExpr`, nível 0 da cascata; não-associativa). O parser aceita `let`/`var` bindings (representa); a **pureza** (só-`let`, sem efeitos) e o escopo (só a expressão-valor) são impostos na **Fase 3** — doutrina "representar e deferir". Substitui o bare-block-como-expr recusado (RD-1/Q1) sem criar 2ª via de yield.
5. **Operadores tipados:** `Binary`/`Unary`/`Assign` usam **enums fechados** (`BinaryOp`/`UnaryOp`/`AssignOp`) no lugar de `op:string` — restaura a exaustividade de `switch` (P4/CI 5.2.1) para as fases 3–7. O símbolo (`+`, `??`, `|>`) permanece só como **tag de dump** (goldens preservados).

### B. Não-fazer / adiar

6. **Cast `as` genérico (`x as Int`):** **não adicionar.** Conversões são métodos explícitos (`.toInt()`); downcast via `match`. Coerente com P6 (infere sem anotação) e a `nullity-invariant` (zero coerção implícita). O `as` segue existindo só em `import`.
7. **Associated types em `trait` (`type Item`):** **adiar.** Bounds inline (`T: A + B`, já em `genericParam.bounds`) cobrem a maioria dos casos. Se entrar, é sum/product novo, não retrofit.
8. **`operator` prefix/postfix custom:** **adiar.** Só overloading **infix** do conjunto fixo de símbolos por ora. O campo `fixity` fica na AST (forward-compat); a gramática só habilita infix.

### C. Diretriz de visão — Itá para systems programming com FFI mínimo (roadmap)

9. **Systems programming sem FFI, pela via FUNCIONAL** (decisão de dono 2026-07-11). O Itá deve permitir **programação de sistemas com o mínimo de FFI** — drivers de infraestrutura, manipulação de binários e de arquivos binários feitos **em Itá**. A forma escolhida é a **idiomática/funcional**, NÃO operadores bitwise crus:
   - **Bitwise em `Int` via API `Bits.*`** (métodos `.and/.or/.xor/.shl/.shr/.not`). Isto **confirma e estende a spec 001 Q2** (2026-07-10: "manter só a API `Bits.*` **+ o operador `~`**") — **NÃO a reverte**. A **extensão** sobre a Q2: o `~` (bitwise-NOT), que a Q2 ainda **preservava** como operador, também **desce para morto-no-parser** — fechando a uniformidade: bitwise é inteiramente `Bits.*`, **zero operadores** na superfície. O `~` sai do parser/`UnaryOp`, mas **segue tokenizado** pelo léxico (`Tag: tilde`, §5 mortos — como `& | ^ <<`; "léxico completo, filtrar é fase posterior", D5); o NOT é `Bits.not`. O argumento P4 da spec 001 (evitar a ambiguidade de `>>`) fica preservado.
   - **Manipulação de binários via binary pattern-matching** (estilo Erlang/Elixir: `let <<ver::4, flags::4, resto::binary>> = pacote`). É a ferramenta funcional que sustenta parsing de protocolo / framing / arquivos binários — como o Erlang fez telecom numa VM com GC. **Feature nova → spec própria** (roadmap); casa com o pattern-matching que o Itá já tem.
   - **Posicionamento:** quadrante **Erlang/Elixir** (bordas em-linguagem sobre `typed_data`, `dart:ffi` enumerado e desencorajado), **NÃO** Rust/Zig bare-metal (sem ownership/`unsafe`/no-GC — isso feriria o Art. II, Dart VM = GC permanente). É **corolário do "Norte de independência do Dart"** + P10 (interop nativo mínimo), não um pilar concorrente à analogia Itá:Dart::Elixir:Erlang — que sai *reforçada* (a herança Erlang É "bordas de baixo nível numa VM gerenciada").
   - **Roadmap / gates:** (1) **binary pattern-matching** (spec própria) — a peça central; (2) **larguras fixas** `Int32/UInt8/...` (spec 001 Q1 adiou) = gate de maturidade antes de qualquer emenda ao Art. II. O `>>` **segue sendo `compose`** (`BinaryOp.Compose`), nunca bit-shift; (3) **protocolo iterador Itá-próprio** (trait `Iterator`/`Iterable`, `next() -> Option<T>`, modelo Elixir `Enumerable`) — decidido em 2026-07-12 (Fase 3): o `for` HOJE é retido como `ForInStatement` (a VM Dart itera de graça, Grupo B), mas o contrato de iteração passa a ser um trait Itá na **des-Dartificação (M5)**; migração é localizada no codegen (o nó `for` é ponto único), NÃO fecha a porta.

## Consequências

- As estruturas teóricas (`ast.asdl`, `grammar.ebnf`) da Fase 2 ficam completas e coerentes com a identidade; os débitos de codegen (Fase 7) das specs 005/006 estão registrados nas respectivas specs.
- **Novo corolário do "Norte de independência do Dart"** (decisão C): "systems programming sem FFI, pela via funcional" orienta decisões futuras (binary pattern-matching, larguras fixas, `Bits.*`, interop nativo mínimo). É continuidade daquele Norte + P10 — **não** um pilar concorrente à analogia Itá:Dart::Elixir:Erlang (que sai reforçada). Incorporação formal ao Art. II só quando amadurecer (gate: larguras fixas) — ato de dono/Governança.
- Nenhuma decisão altera princípio permanente (Art. I) — todas foram validadas pelo `ita-visionary` sem conflito aberto.
- A história bitwise fica **rastreada** como débito de roadmap (não implementada nesta rodada).

## Relacionados
- Specs: `specs/005-decl-surface/`, `specs/006-where-typed-ops/`.
- Reviews: `ita-next/compiler/docs/reports/2026-07-10_review-fase2-parser.md` + memórias dos agentes (`ita-visionary`, `dart-vm-expert`).
- Invariante relacionada: `ita-next/compiler/docs/spec/nullity-invariant.md`.
