# Invariante de nulidade — "valor vazio ≠ ausência"

> **Decisão de dono (2026-07-11).** Regra permanente da linguagem. Alinha com o
> princípio 7 do Itá (`Result` + `?` + `panic`, zero-null-surpresa) e com "sem
> mágica — nunca esconde o que acontece".

## A regra

1. **`""`, `0`, `0.0`, `[]`, `{}`, `false` são VALORES reais de sistema.** Uma
   string vazia é uma `String` legítima — *não* é `nil`, *não* é `undefined`,
   *não* é "falsy". O Itá **não** tem coerção truthy/falsy implícita (o oposto de
   JS/TS, onde `""` e `null` colapsam em `false`).
2. **`nil` é ausência INTENCIONAL e explícita.** A única porta para `nil` é um
   tipo opcional `T?`. Um tipo não-opcional (`String`, `Int`, …) **nunca** admite
   `nil` — é isso que "previne valores nulos não intencionais".
3. **Três estados são mutuamente distintos** e o compilador jamais os confunde:

   | Forma | Estado | Tipo exigido |
   |-------|--------|--------------|
   | `let x: String = ""` | valor (string vazia) | `String` |
   | `let x: String? = nil` | ausência intencional | `String?` (opcional) |
   | `var x: String` | não-inicializado (**slot**) | `String` |

   > **Δ 2026-07-15 (ruling do dono — fecha o §Aberto abaixo):** o 3º estado é
   > **`var`**, não `let`. `let` **liga um valor** ⟹ exige `= e`; `var` é **slot
   > mutável** ⟹ pode encher depois. Os três seguem distintos — e agora a **FORMA**
   > diz qual é qual (P1 deixa de ser só semântica).

## Garantido AGORA (Fase 2 — sintático, parser)

O parser já materializa os três estados sem ambiguidade (travado por testes):

- `""` → nó `Str` (com `parts` vazio) — **um valor**, nunca `NilLit`.
- `nil` → nó `NilLit` — distinto de `Str`.
- sem init → `LetStmt.value == null` (graças a D5 / GRAMMAR §3).
- `String` → `NamedType` ≠ `String?` → `OptionalType`.

Cobertura: `conformance/valid/stmt_empty_string_vs_nil.{tu,ast}` +
grupo `nullity — "" é VALOR real…` em `compiler/test/parser_test.dart`.

## A garantir na Fase 3 (semântica — type-checker; AINDA NÃO existe)

O parser **representa**, não valida. Quando o binder/type-checker existir, ele
DEVE, sem exceção:

- [ ] **Rejeitar `nil` sob tipo não-opcional** — `let x: String = nil` é ERRO de
      tipo (ex.: `nil-under-non-optional`). Só `T?` aceita `nil`.
- [ ] **NUNCA emitir warning/lint por valor vazio** — `let x: String = ""` (ou
      `0`, `[]`, `false`) é código idiomático e correto. Zero "possibly empty".
- [ ] **Sem estreitamento implícito por vacuidade** — `if s == ""` compara VALOR;
      não existe `if (s)` testando "vazio-ou-nil" de uma vez (isso é magia falsy).
- [ ] **Fluxo de desembrulho só para `T?`** — `?`, `guard let`, `if let`, `??`
      operam sobre opcionais; aplicá-los a um não-opcional é erro (nada a
      desembrulhar).

## ~~Aberto~~ → **FECHADO (decisão de dono, 2026-07-15)**

- **`let x: String` sem init: PROIBIDO.** `let` exige `= EXPR` — na **GRAMÁTICA**
  (`let-requires-value`, parser), não na semântica. `var x: String` segue legal
  (é slot); *definite assignment* é **Fase 6** (ADR-0011 lista use-before-assign
  lá). **Em nenhum caso o default vira `nil` silencioso** — isto se mantém.

  **Por quê:** proibir **não custa imutabilidade**, porque a linguagem já tem
  **três** caminhos imutáveis — e o argumento anterior ("é a válvula que evita
  cair em `var`") apoiava-se num **erro de categoria**: RD-1 é sobre *blocos*, e
  `if`/`match` são **expressões** (P3).

  | Caso | Caminho itaiano |
  |------|-----------------|
  | condicional | `let x = if c => a else b` / `match` — P3 |
  | vários passos | `let t = v where { let a = … }` — ADR-0012 A4 |
  | pode falhar | `let x = f()?` / `guard let` — P7 |

  O uninit-let seria um **quarto** caminho, e **menos honesto**: o glifo `x = e`
  significaria "inicializar" **ou** "mutar" conforme o fluxo, **sem marca
  sintática** — a mesma doença do flow-narrowing, que esta mesma spec recusa (o
  `guard let` é honesto porque cria um **nome novo**; aqui não há marca).
  E o domínio útil é **vazio**: onde a F6 conseguiria provar (if/else), o
  `if`-expr já resolve; onde seria preciso (loop), a F6 **não** prova — e várias
  atribuições em caminhos diferentes **é** mutação: `var` é a palavra honesta.

  Ver spec `009-semantic-types` §12-7. Fixtures: `conformance/invalid/let_requires_value.tu`
  (ilegal) e `conformance/valid/stmt_let_no_init.tu` (o `var` legal).
