---
name: spec-014-ltf6a-identity-review
description: W0 da LT-F6a (spec 014, co-req F5→F6) — destravar binding de list/rest-pattern. Veredito ✅×2; a reserva 012 é sobre `_member`, NÃO sobre destructuring de type-arg; precedente interno Result/Option; achado: atribuição D4-vs-012 é fabricação-por-classe (Art. IV-6b)
metadata:
  type: project
---

# W0 LT-F6a (2026-07-17) — destravar `_bindPattern` de List/Rest

**Contexto:** `check.dart:544-546` recusa tipar `[a, ..resto]` com `pattern-binder-unsupported`.
A LT-F6a quer remover a recusa, extrair `T` de `List<T>` via `list.args[0]` e ligar `resto : List<T>`;
criar `pattern-type-mismatch` (list-pattern × não-List; literal/range × coluna incompatível). É
co-requisito da F6 (a matriz de Maranget precisa de tipo por coluna — 014/tasks.md:24).

## Q1 (procedência / reserva 012) — ✅ NÃO fura, e não precisa do dono
- **A reserva é do dono** (spec 011 §1.3 não-objetivo 1, status `clarified`), mas o que ela reserva é
  **membro de built-in** enumerado: `.length`, `xs[i]`, `+` de `List`, `.slice`, `Map.keys()` — todas
  operações do sítio **`_member`** (§4.7: *"`xs.length` bate no `_member` sem resposta"*). É o `_member`
  que espera o M5, não o type-arg.
- **Extrair `List<T>.args[0]` é destructuring, NÃO resolução de membro.** Prova interna irrefutável:
  `_bindEnumPattern` (`check.dart:553-580`) **já** faz exatamente isto para DOIS built-ins —
  `Option` (`t.inner`, :555) e `Result` (`t.args[i]`, :579) — e isso **nunca** foi reservado à 012.
  `List` é o 3º genérico built-in; o pattern é `[...]` em vez de `.ok(...)`, mas a operação (ler o
  type-arg) é idêntica. O `T` de `List<T>` já é acessível na F5 (`[]` tipa `List<T>`, 010 §4.1).
- **O comentário `:542-543` ("spec 012 … membro de built-in §1.3-1") NÃO é ruling do dono** — não diz
  *"ruling do dono"*, cita **spec 012 que não tem arquivo** e um §1.3-1 que **não menciona list-pattern**.
  Sob Art. IV-6(a) nem seria atribuição válida ao dono; sob IV-6(b) é **derivação** (classificação do
  craftsman), **contestável por construção** — e o `ita-visionary` a contesta. Foi **fabricação-por-classe**
  (a classe "membro de built-in" esticada sobre destructuring), não fabricação-por-voz-do-dono.
- **Achado corroborante:** o registro tem DUAS atribuições em CONFLITO para a mesma recusa —
  `:542` diz "spec 012 / membro de built-in"; `check.dart:216-217` e `blueprint-flow-walk.md:204` dizem
  **"débito D4"**. Mas D4 (`:610-622`) é o problema do `FieldPattern` sem identidade de AstNode (o
  *shorthand* `P { x, y }`), que **não se aplica** a List/Rest (têm span; `RestPattern`→`VariableDeclaration`,
  spec 008:128). Duas derivações que discordam = prova de que **nenhum ruling do dono** trancava isto.

## Q2 (doutrina do erro) — ✅ respeita P4, com ressalva DURA
- `pattern-type-mismatch` (list-pattern × não-List; literal/range × coluna incompatível) são **erros
  reais do usuário** — honestos. Precedente do sítio: `_bindEnumPattern` já separa certo (`unknown-variant`,
  `pattern-arity-mismatch`, `variant-against-non-enum` = todos user error).
- **Precedente da doutrina:** spec 011 §4.7 (`builtin-member-unsupported` ≠ `unknown-member` porque *"o
  membro existe; nós é que não o modelamos"*) + DoD 011 (*"os dois dizem lacuna do compilador, não erro
  do usuário"*). É a cristalização de P4 pra esta família.
- **Ressalva (a doença do catch-all, 4ª vez):** `pattern-type-mismatch` NÃO pode virar o novo `_ =>`
  absorvente. Cercas: (1) `ErrorType` no escrutínio → **return silencioso** (anti-cascata, igual
  `:561`); (2) sub-caso genuinamente não-modelado mantém código de **lacuna do compilador**, nunca
  acusa; (3) List aninhada é FINE se `_bindPattern` **recursa** (args[0] de `List<List<T>>` é `List<T>`)
  — só vira falsa-acusação se alguém especializar um nível e esquecer de recursar.

## Nota P3 (não superestimar)
Hoje o braço de List **erra honestamente** (`pattern-binder-unsupported` = lacuna, P4-honesto) — NÃO
é buraco silencioso. LT-F6a é **upgrade de recusa-honesta → capacidade**, que destrava "match rende"
(P3) e a exaustividade F6. Não reivindicar "reparo de violação silenciosa" (seria overclaim; lição
"a auditoria fabrica a própria prova").

Ver [[doctrine-citacao-ou-nome]] (fabricação-por-classe é a face que o lint de ponteiro não pega),
[[spec-011-identity-review]] (o corte chão×declaração-de-List), [[doctrine-ast-representa]].
