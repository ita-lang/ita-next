# Design notes — Spec 001 (Int width & bitwise)

> Phase 0 do `/speckit-plan`. Registra as decisões de design resolvidas (as clarificações §0.6 da spec) com rationale e alternativas. Nenhum `NEEDS CLARIFICATION` remanescente.

## Decisão Q1 — largura de `Int` e reconciliação VM×JS

- **Decision:** `Int` é **64-bit signed two's complement**, canônico em todos os alvos. No alvo JS a paridade é garantida **apenas no range seguro** (< 2³¹ para bitwise, ≤ 2⁵³ para inteiros); valores fora disso são **divergência documentada**, **sem emulação**.
- **Rationale:** honra o **Princípio 4 (sem mágica)** — a largura deixa de ser herança invisível do Dart — sem violar o **objetivo nº1 (build/pipeline rápidos, Artigo II)**: emular 64-bit no JS (BigInt/lowering) custaria perf e tamanho no alvo secundário. Alinha ao modelo Itá:Dart::Elixir:Erlang (o `int` da VM é 64-bit; o JS é o alvo que "não alcança"). `[cap 6.3.1]` (largura é atributo do tipo).
- **Alternatives considered:**
  - *Emular 64-bit no JS* — rejeitada: custo de perf/tamanho/complexidade de codegen num alvo secundário (test oracle).
  - *`Int` = 53-bit safe (interseção VM∩JS)* — rejeitada: desperdiça a VM 64-bit e surpreende quem vem de Dart.
  - *Tipos de largura fixa (`Int32`/`Int64`)* — adiada: amplia a superfície de tipos; nova spec se necessário.

## Decisão Q2 — operadores bitwise

- **Decision:** manter **só a API `Bits.*`** (`and/or/xor/not/shl/shr/bit/bits`) + o operador **`~`** (unário). O Itá **não tem** operadores bitwise binários. §2 Léxico e §3 Sintaxe **fora de escopo**.
- **Rationale:** é o design **já intencional** — `& | ^ <<` são terminais mortos no lexer e `>>` é composição de funções (`GRAMMAR.md` §4.2); o exemplo `bits` documenta "operadores C-style revertidos para métodos nomeados, sem precedência ambígua". Reintroduzir operadores criaria conflito de precedência com `>>` e ambiguidade — contra o **Princípio 4**. `[cap 4.3.2]` (desambiguação).
- **Alternatives considered:**
  - *Reintroduzir `& | ^` + shifts* — rejeitada: tocaria léxico/sintaxe, exigiria novo símbolo para shift-right (pois `>>` é compose) e reconciliação de `GRAMMAR.md`+tree-sitter, sem ganho de ergonomia claro.

## Decisão Q3 — semântica de overflow

- **Decision:** overflow de `Int` é **wrap** 64-bit two's complement (`maxInt64 + 1 = minInt64`), sem erro nem promoção a `BigInt` — comportamento atual da VM, agora **normativo e documentado**.
- **Rationale:** **não-breaking** (formaliza a VM); comportamento familiar de linguagens de sistema (C, Rust em release, Dart). Documentar fecha o **Princípio 4** sem custo. `[cap 6.5.2]` (o modelo numérico é decisão de spec).
- **Alternatives considered:**
  - *`panic` (checked overflow)* — rejeitada por ora: **breaking** na VM, incomum para o tipo inteiro default, custo de checagem em runtime. Poderia voltar como modo opt-in em spec futura.

## Abordagem por fase tocada

- **Semântica/Tipos `[cap 6.5]`:** as regras de tipo de `Bits.*`/`~` já existem e estão corretas; **nada a mudar no type-checker**. A decisão é sobre a *semântica de valor* (largura/wrap), documentada, não sobre novas regras de tipo. Opcional: erro `int-literal-out-of-range` (hoje o codegen rejeita com `Undefined: <literal>`; um erro semântico com span é melhoria de qualidade).
- **Codegen `[cap 8.1]`:** **emissão inalterada** — `Bits.*` já faz lowering para os operadores nativos do Dart, cujo comportamento (64-bit na VM, 32-bit no JS) é exatamente o que a spec fixa. Q1 = best-effort → **sem** lowering de reconciliação.
- **Runtime `[cap 7.1]`:** apenas **assume** o `int` 64-bit da Dart VM (Grupo B); não reespecifica a VM.
