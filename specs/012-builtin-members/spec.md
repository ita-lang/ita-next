# Spec 012: Membros de built-in — o CHÃO (`.length`, `[]`, `+`)

> **Tipo:** feature-codegen + decisão-de-linguagem (o chão da 010 §4.6.1 vira produtor real) · **Marco:** `M4 — front-end · destrava a F7`
> **Status:** `clarified` — o único ruling aberto (out-of-bounds de `[]`) foi fechado pelo dono em 2026-07-20 (§0.6/§4.3: **panic** para `List`, **`V?`** para `Map`). Constitution-check W0 (`ita-visionary`): liberado-com-ressalva.
> **Autor / Data:** orquestração (Claude) · 2026-07-20 · **Reserva:** spec 011 §1.3 (não-objetivo 1, "outro produtor") · **PR:** `<a abrir>`

## §0 Metadados

- **Classe da mudança** (Apêndice A):
  - [ ] Nova construção.
  - [x] **Nova regra/fase** — a F5 passa a TIPAR os membros irredutíveis de built-in (hoje `builtin-member-unsupported`) e a F7 a EMITIR o acesso nativo. Nenhum nó novo de AST (`Index`/member-access já existem).
- **Fases tocadas:**
  - [ ] Léxico · [ ] Sintaxe · [x] **Formal/Tipos (§4)** · [x] **SDD/atributos (§5)** · [ ] Fluxo · [x] **Codegen/IR (§7)** · [x] **Runtime (§8)**
- **Princípios do Itá afetados:** **P4** (sem mágica — o chão não pode virar privilégio que o tipo do usuário não alcança); **P6** (zero annotations — o marcador de intrínseco NUNCA é `@decorator`; se um dia existir, é keyword do M5); **P7** (`Result`+`?`+`panic` — o out-of-bounds de `[]` toca isto, §4.3/§0.6); **P9** (zero `node_modules` — os membros vêm de `dart:core`, não de pacote); **Art. III** (Cap 6 é a fronteira: a F7 emite `InstanceGet`/`InstanceInvocation` tipado, a VM entrega o membro).

### §0.5 Constitution check

**A tabela do chão é legítima SSE respeita as 3 condições da doutrina do chão** (spec 010 §4.6.1, ruling `ita-visionary` 2026-07-15): (1) **FECHADA** — um conjunto fixo e pequeno, nunca aberto; (2) **ERRA no desconhecido** — membro fora da tabela é `unknown-member`, jamais `dynamic`/`UnknownType` silencioso (a doença do oracle); (3) **DESTINO `.tu` escrito** — o chão migra para `.tu` no M5 (des-Dartificação). O que **segura a tabela de pé** é o **teste de privilégio de DUAS faces**: o chão só entra se **não nega poder ao tipo do usuário** (o dev escreve `let length: Int` no `MyType` dele — `.length` não é sintaxe-só-do-built-in como o `for`, que fica `for-binder-unsupported` até o M5) **e** não é poder-sobre-o-built-in que só o compilador teria (`.map` hard-coded seria — por isso é biblioteca, M5).

**Escopo do chão = ~3 membros irredutíveis** (os que **têm** de tocar o Dart, spec 010 §3): **`.length`**, **`[]` (índice)**, **`+` (concat)**. Tudo o mais (`.map`, `.filter`, `.fold`, `.slice`, `Map.keys()`) é **BIBLIOTECA** — derivável em `.tu` puro sobre o chão (prova: `stdlib/iter.tu:56` tem `flatMap` em Itá puro) → **M5, fora desta spec** (⚠️ a lista da 011 §1.3 citou `.slice`/`Map.keys()`; a doutrina do chão os reclassifica como biblioteca — nota de reconciliação em §10).

**§0.5-W0 — veredicto do `ita-visionary` (2026-07-20): LIBERADO-COM-RESSALVA.** Nenhum conflito aberto, nenhum princípio permanente ferido. As 3 condições são honradas (a FECHADA "tem dentes" — não readmite `.slice`); P4/P6/P7/Art. II/Art. III honrados; o out-of-bounds é ruling do dono legítimo (§0.6). ⚠️ **Ressalva (a face 1 do privilégio, refino da JUSTIFICATIVA — não do escopo):** o teste absolve `.length` porque o dev escreve `let length: Int` no `MyType` dele (o built-in não ganha sintaxe-privilégio como o `for`). Mas `[]` e `+` **não são campos — são operadores**, cuja rota-de-cura para o tipo do usuário é `OperatorDecl` (diferido a `012+`, ruling §12-4), não um campo. Logo o chão de `[]`/`+` é legítimo **por ruling do dono + cura diferida**, não "não-privilegiado como `.length`". O escopo não muda; a razão fica honesta.

### §0.6 Ruling do dono — o out-of-bounds de `[]` `[✅ DONO 2026-07-20]`

`xs[i]` fora dos limites → **panic** (semântica A: o `[]` nativo do Dart, `RangeError`→panic não-capturável, exit≠0); `m[k]` com chave ausente → **`V?`** (`nil` nativo). Assinaturas: `xs[i] : E`, `m[k] : V?`. Era a única decisão aberta da spec — fechada. Detalhe em §4.3.

## §1 Motivação e resumo

O front-end tipa e prova a sanidade de um programa, mas **não consegue ler o tamanho de uma lista nem acessar um elemento**: `xs.length` e `xs[i]` morrem na F5 com `builtin-member-unsupported` (`check.dart:1818`) — a lacuna DECLARADA (nunca `unknown-member`, que **mentiria**: o membro existe no Dart, nós é que não o modelávamos). Sem o chão, `List` é um tipo que a linguagem sabe nomear e não sabe usar. E a F7 (spec 013 §7.4e) deixou o **`match` sobre `List` GATED por esta spec** — a decisão de comprimento (`.length`) e o bind de elemento (`[]`) são exatamente estes membros.

**Antes → Depois** (exemplo mínimo em `.tu`):

```tu
// antes — a F5 recusa o chão
fn soma(xs: List<Int>) -> Int {
  let n = xs.length      // ✗ builtin-member-unsupported
  let primeiro = xs[0]   // ✗ builtin-member-unsupported
  return n
}
```

```tu
// depois — o chão tipa e a F7 emite o acesso nativo (dart:core)
fn soma(xs: List<Int>) -> Int {
  let n = xs.length      // ✓ xs.length : Int
  let primeiro = xs[0]   // ✓ xs[0] : Int  (out-of-bounds: §4.3, ruling do dono)
  return primeiro + n
}
```

**Não-objetivos:**
- **`.map`/`.filter`/`.fold`/`.slice`/`Map.keys()`** — BIBLIOTECA (deriváveis do chão), destino **M5** (`extension List`/`extension Map` em `.tu`; exige que `List` tenha declaração — Norte do Art. II).
- **Trait `Iterator` e o binder do `for`** — `for-binder-unsupported` (ruling §12-D) até o M5; `for` é sintaxe-só-do-built-in (privilégio) — NÃO é o chão.
- **`xs[i] = v` (index-SET)** — mutação de container. `List` é imutável por default; a forma mutável (`MutList`) e o index-set são decisão separada (§10).
- **Overload / `OperatorDecl`** — `012+` (ruling §12-4: o Itá não tem overload de método).

---

## §4 Especificação formal (tipos e regras) ⭐ — `[cap 6.3, 6.5]`

### 4.1 A tabela do chão — FECHADA

O chão é uma **tabela de tipos fixa e pequena**, indexada por `(tipo-built-in, membro)`, produzida por esta spec e **consumida pela resolução de membro da F5** (spec 011 §4.7 — o sítio `_member` que hoje emite `builtin-member-unsupported`). Ela **erra no desconhecido**: um membro fora da tabela sobre um built-in é `unknown-member` (não mais `builtin-member-unsupported` — a lacuna some quando a tabela existe).

| tipo | membro | assinatura | fundamento |
| :-- | :-- | :-- | :-- |
| `List<E>` | `.length` | `Int` | `[cap 6.3.6]` seleção de campo `record(t)→Int` |
| `List<E>` | `[i]` (índice) | `(i: Int) → E` | `[cap 6.5.1]` acesso a elemento `array(s,t)→t` |
| `List<E>` | `+` (concat) | `(ys: List<E>) → List<E>` | `[cap 6.5.2]` operador homogêneo |
| `String` | `.length` | `Int` | idem `List.length` |
| `String` | `[i]` (índice) | `(i: Int) → String` | Dart `String[i]` é `String` de 1 code-unit (não há `Char` no Itá) |
| `Map<K,V>` | `.length` | `Int` | idem |

> **`Map<K,V>[k]` (índice de Map)** — a rigor entra no chão (`[]` é irredutível), **mas** o Dart devolve `V?` (nullable, ausência = `null`), o que casa com o `T?` nativo do Itá (spec 009 §4.6). Assinatura proposta: `(k: K) → V?`. Marcado como **assumption** (§10) — o idioma `if let x = m[k]` é itaiano; sem risco de identidade.

### 4.2 Equivalência de tipos

Por **nome** (`List`/`String`/`Map` são `BuiltinType` — spec 009 §4.1). O type-arg `E`/`K`/`V` vem por construção da nº1 (`exprTypes` do receptor), como em qualquer `record(t)` — a F5 **não re-tipa** o container.

### 4.3 Regras de tipo — `[cap 6.5.1]`

```
     Γ ⊢ xs ⇒ List<E>                          Γ ⊢ xs ⇒ List<E>     Γ ⊢ i ⇐ Int
     ─────────────────────                     ──────────────────────────────────
     Γ ⊢ xs.length ⇒ Int                       Γ ⊢ xs[i] ⇒ E


     Γ ⊢ xs ⇒ List<E>     Γ ⊢ ys ⇐ List<E>
     ─────────────────────────────────────
     Γ ⊢ xs + ys ⇒ List<E>
```

- `.length` é **síntese** pura (não depende do uso). `[i]` **checa** `i ⇐ Int` (contextual, spec 010) e sintetiza `E`. `+` checa o operando direito contra `List<E>` (homogêneo; heterogêneo é `type-mismatch`, não coerção — P4/§4.5 zero coerção).
- **Out-of-bounds `[✅ DONO 2026-07-20: panic]`** — `xs[i]` com `i ∉ [0, length)` faz **panic** (semântica A): a F7 emite o `[]` **nativo** do Dart, cujo `RangeError` sobe como `Throw` não-capturável (P7, zero try/catch) → o isolate morre, exit≠0 (spec 013 §7.4f). É o mais "chão" (custo zero, toca o Dart direto), e o Itá já tem `panic`; o idioma seguro é checar `xs.length`/`if let` antes. A assinatura fica LIMPA: **`xs[i] : E`** (não `E?`). ⚠️ **Um `[]`, uma política, duas faces (pela natureza do container):** a **ausência em `Map<K,V>[k]`** (§4.1) devolve **`V?`** (`nil` nativo do Dart, casando com o `T?` do Itá; idioma `if let v = m[k]`). Não são duas políticas — é a diferença entre sequência densa (índice fora = erro do programa → panic) e mapa esparso (chave ausente = resultado legítimo → `nil`).

### 4.6 Erros de tipo detectados

- Membro **fora da tabela** sobre built-in → `unknown-member` com span do `.membro` (substitui `builtin-member-unsupported` — a lacuna some).
- `xs[i]` com `i` não-`Int` → `type-mismatch` (span do índice).
- `xs + ys` com `ys` não-`List<E>` → `no-operator-for-types` (span do `+`).
- `.length`/`[]`/`+` sobre tipo **sem** o membro no chão (ex.: `Int.length`) → `unknown-member`.

## §5 SDD / Tradução dirigida por sintaxe — `[cap 5.1, 5.4]`

- **5.1 Atributos** — o tipo do membro é **sintetizado** do receptor + a tabela do chão:

  | PRODUÇÃO | REGRAS SEMÂNTICAS |
  | :-- | :-- |
  | `E → E₁ . length` | `E.type = ground(E₁.type, 'length') = Int` |
  | `E → E₁ [ E₂ ]` | `E₂.type ⇐ Int; E.type = ground_index(E₁.type)` |
  | `E → E₁ + E₂` | `E₂.type ⇐ E₁.type; E.type = E₁.type` (quando `E₁.type` é `List`/`String`) |

- **5.2 Classe da SDD** — **L-atribuída**, um walk (o modelo do Itá): o tipo do receptor (`E₁.type`) é atributo já computado quando o membro/índice é resolvido; sem ciclo. O consumo é no `_member`/`_index` da F5 (spec 011 §4.7), **fechando** o `builtin-member-unsupported`.
- **5.3 Ações** — nenhuma inserção em tabela de símbolos do usuário: o chão é uma tabela **estática do compilador** (destino `.tu` no M5, §10). Zero efeito colateral novo.

## §7 Código intermediário e geração — `[cap 6.2, 8.1]`

### 7.1 Nós Kernel afetados

O acesso ao chão baixa para os nós nativos de `dart:core` (o `interfaceTarget` vem da tabela — o análogo da nº3 da F7 para o built-in), **exatamente a mesma via do `Ops(+)`** da spec 013 §7.5 (`InstanceInvocation` sobre o operador de `dart:core`, `interfaceTarget` tipado).

### 7.2 Gabarito de código — `[cap 8.1.3]`

| construção | nó Kernel emitido |
| :-- | :-- |
| `xs.length` | `InstanceGet(xs, Name('length'), interfaceTarget = dart:core::List::length)` → `int` |
| `xs[i]` | `InstanceInvocation(xs, Name('[]'), Arguments([i]), interfaceTarget = List::[])` |
| `xs + ys` | `InstanceInvocation(xs, Name('+'), Arguments([ys]), interfaceTarget = List::+)` |
| `s.length` (String) | `InstanceGet(s, Name('length'), String::length)` |
| `m.length` (Map) | `InstanceGet(m, Name('length'), Map::length)` |

- O `interfaceTarget` (non-nullable no Kernel) é resolvido do `vm_platform.dill` via `LibraryIndex` (o mesmo mecanismo do `print`, spec 013 §2). **Zero `dynamic`** (ADR-0013): todo acesso é tipado.
- **Out-of-bounds (semântica A, se ratificada):** o `[]` nativo já faz `throw RangeError` — a F7 **não emite guarda**; o throw sobe como `panic` (P7, spec 013 §7.4f), exit≠0.

### 7.3 Comportamento por alvo

| Alvo | Comportamento esperado | Observação |
| :-- | :-- | :-- |
| **VM** (JIT) | `[1,2,3].length` → `3`; `[1,2,3][0]` → `1`; `[1]+[2]` → `[1, 2]` | referência (oracle) |
| **AOT** (`dart compile exe`) | empata a VM byte-a-byte | membros de `dart:core` são idênticos |
| **JS** (`dart2js`) | mesmos valores | ⚠️ paridade a CONFERIR: `List.length`/`[]`/`+` são estáveis; **`Int` grande** diverge (2⁶³ vs 2⁵³) mas é ortogonal (spec 001 §divergência) — marcar **MATCH** para os CAs |

## §8 Runtime — premissas sobre a Dart VM — `[cap 7.1]`

- **8.1** A spec **assume** que `List`/`String`/`Map` do Itá baixam para `dart:core::List`/`String`/`Map` nativos (spec 009 §4.1 — são `BuiltinType`, sem classe própria no `.dill`), e que a VM entrega `.length`/`[]`/`+` **de graça** (Grupo B — ADR-0001). A F7 só emite o `InstanceGet`/`InstanceInvocation` **bem-tipado**; unboxing/bounds-check/growable são da VM. Interop `dart:` desta spec: `dart:core::{List,String,Map}::{length,[],+}` — **explícito e enumerado** (Art. IV, como o `print` do §8.2 da 013).

---

## §9 Checklist de completude (Apêndice A)

- [ ] `symbols` — a tabela do chão tem entradas `(tipo, membro)→assinatura` FECHADAS `[A.4]`
- [ ] fase semântica — `check.dart` `_member`/`_index` consultam o chão; `builtin-member-unsupported` some, `unknown-member` cobre o resto
- [ ] `inter` — `Index`/member-access emitem `InstanceInvocation`/`InstanceGet` com `interfaceTarget` de `dart:core` `[A.5–A.7]`
- [ ] **corpus de conformância** cobre `.length`/`[]`/`+` (VM + paridade JS)
- [ ] **benchmark de compile-time** (`itac` AOT) sem regressão
- [x] a decisão de out-of-bounds (§4.3) fechada por ruling do dono (2026-07-20: panic para `List`, `V?` para `Map`)

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** Não — destrava o que hoje é erro (`builtin-member-unsupported`); nenhum programa verde regride.
- **Reconciliação com a 011 §1.3:** a lista de reserva citou `.slice`/`Map.keys()` na 012; a **doutrina do chão** (010 §3 + §4.6) os reclassifica como **BIBLIOTECA** (deriváveis do chão) → **M5**. Esta spec cobre só o irredutível (`.length`/`[]`/`+`). Não é contradição — é o refinamento que a 010 §3 já assentou. Nota: o destino da stdlib-de-compat migrou de "011" para "M5" porque a própria 011 §1.3 diferiu `extension List` ao M5.
- **Assumption `Map<K,V>[k] → V?`** (§4.1): o índice de Map devolve `V?` (nativo do Dart — ausência = `null` = `nil`), casando com o `T?` do Itá (009 §4.6); o idioma é `if let v = m[k]`. Sem risco de identidade — mas a política de ausência de `[]` é fechada JUNTO com o out-of-bounds de List (§4.3, um só ruling).
- **Destino `.tu` (condição 3 da doutrina):** a tabela do chão é débito de bootstrap; migra para `.tu` na des-Dartificação (M5), quando `List`/`String`/`Map` ganharem declaração. Registrado como dívida, não design permanente.
- **`xs[i] = v` (index-set):** fora de escopo — `List` é imutável (P1/P2); a mutação pede `MutList` (stdlib) e o index-set é decisão do M5.
- **Alternativas descartadas:** (i) hard-code aberto silencioso (a doença do oracle — viola condição 2); (ii) `@intrinsic` marcador — viola P6 (zero annotations); (iii) `.map`/`.slice` no chão — viola a doutrina (são biblioteca, deriváveis).

## §11 Critérios de aceite (viram testes de conformância)

- **CA1** — `fn m() { print("${[10, 20, 30].length}") }` ⟶ imprime `3` na VM; paridade JS **MATCH**.
- **CA2** — `fn m() { print("${[10, 20, 30][1]}") }` ⟶ imprime `20`; paridade JS **MATCH**.
- **CA3** — `fn m() { print("${([1, 2] + [3]).length}") }` ⟶ imprime `3`; paridade JS **MATCH**.
- **CA4** — `fn m() { print("${"olá".length}") }` ⟶ imprime `3`; paridade JS **MATCH**.
- **CA5** (erro) — `fn m(xs: List<Int>) -> Int => xs.foo` ⟶ `unknown-member` com span do `.foo` (a lacuna `builtin-member-unsupported` **não** é mais emitida para membro conhecido).
- **CA6** (erro) — `fn m(xs: List<Int>) -> Int => xs["a"]` ⟶ `type-mismatch` com span do índice (`i ⇐ Int` falha).
- **CA7** (erro) — `fn m(xs: List<Int>, ys: List<String>) => xs + ys` ⟶ `no-operator-for-types` (heterogêneo, zero coerção).
- **CA8** (co-verifica a F7) — `match xs { [] => 0, [_, ..r] => 1 }` sobre `List<Int>` ⟶ passa a **emitir `.dill`** (era gated na spec 013 §7.4e); roda na VM. *(depende da F7 existir — marcado como CA de integração, gated até o codegen.)*
- **CA9** (out-of-bounds — ruling §0.6 fechado) — `fn m() { print("${[1][5]}") }` ⟶ **panic** com exit≠0 (o `[]` nativo dispara `RangeError`); paridade JS: exceção não-capturada + exit≠0.
- **CA10** (Map — chave ausente) — `fn m(x: Map<String, Int>) { match x["k"] { .some(v) => print("${v}"), nil => print("vazio") } }` ⟶ imprime `vazio` (ausência = `nil`); `x["k"] : Int?`.

## Definition of Done

- [ ] CA1–CA7 cobertos por casos no corpus e verdes (VM/AOT/JS conforme §7.3), validados via MCP `ita`.
- [ ] Ruling do dono do out-of-bounds (§0.6/§4.3) fechado; CA9 concretizado.
- [ ] Constitution check (§0.5) sem conflito aberto — as 3 condições da doutrina do chão honradas.
- [ ] CI verde (conformance + unit + benchmark de compile-time).
