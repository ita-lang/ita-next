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
   | `let x: String` | não-inicializado | — (ver §Aberto) |

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

## Aberto (decisão de dono — Fase 3)

- **`let x: String` sem init:** legal sintaticamente (GRAMMAR §3). A política
  semântica — exigir atribuição definida antes do uso (*definite assignment*,
  Dragon Book §representação de fluxo), ou proibir de vez em `let` — fica para a
  análise de fluxo da Fase 3. Em nenhum caso o default vira `nil` silencioso.
