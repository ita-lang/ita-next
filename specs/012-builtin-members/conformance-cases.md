# Conformance cases 012 — Membros de built-in (o CHÃO)

> **Fase 1 do `/speckit-plan`.** Um caso `.tu` por CA da spec §11 → saída/erro esperado, por alvo. Validação ao vivo via MCP `ita`. Legenda de estado: **[F5-now]** = validável já (só typing); **[F7-pin]** = espera o pin do SDK (execução/emissão).

## Casos de TIPO (F5 — validáveis agora via `itac check`)

### CA1 — `List.length` [F5-now → valor em F7-pin]
```tu
fn m() { print("${[10, 20, 30].length}") }
```
- F5: `[10,20,30].length : Int` (sem erro). F7 (pin): imprime `3`. VM oracle · AOT empata · JS **MATCH**.

### CA2 — `List` índice [F5-now → valor em F7-pin]
```tu
fn m() { print("${[10, 20, 30][1]}") }
```
- F5: `[...][1] : Int`. F7: imprime `20`. **MATCH**.

### CA3 — `List` concat + length [F5-now → valor em F7-pin]
```tu
fn m() { print("${([1, 2] + [3]).length}") }
```
- F5: `[1,2] + [3] : List<Int>`; `.length : Int`. F7: imprime `3`. **MATCH**.

### CA4 — `String.length` [F5-now → valor em F7-pin]
```tu
fn m() { print("${"olá".length}") }
```
- F5: `"olá".length : Int`. F7: imprime `3`. **MATCH**.

### CA5 (erro) — membro desconhecido de built-in [F5-now]
```tu
fn m(xs: List<Int>) -> Int => xs.foo
```
- F5: **`unknown-member`** com span do `.foo`. ⚠️ O `builtin-member-unsupported` **não** é mais emitido (some — código morto). Corpus: `conformance/check/` (erro).

### CA6 (erro) — índice não-`Int` [F5-now]
```tu
fn m(xs: List<Int>) -> Int => xs["a"]
```
- F5: **`type-mismatch`** com span do índice (`i ⇐ Int` falha). Nota: o "antes" (sem a 012) é `cannot-infer` (o `ast.Index` não estava no dispatch), não `builtin-member-unsupported`.

### CA7 (erro) — concat heterogêneo [F5-now]
```tu
fn m(xs: List<Int>, ys: List<String>) => xs + ys
```
- F5: **`no-operator-for-types`** com span do `+` (zero coerção; `List<Int> ≠ List<String>`).

## Casos de EXECUÇÃO / RUNTIME (F7 — esperam o pin)

### CA8 (integração — destrava o `match` sobre `List`) [F7-pin]
```tu
fn m(xs: List<Int>) -> Int => match xs { [] => 0, [_, ..r] => 1 }
```
- Hoje: a F6 modela, mas a F7 dava `gated` (013 §7.4e — precisa de `.length`/`[]`). Com a 012: a F5 tipa `xs.length`/`xs[i]` ⟹ o gabarito de `match`-sobre-`List` **emite `.dill`** e roda na VM. Co-verifica 012 ↔ 013.

### CA9 (out-of-bounds → panic) [F7-pin]
```tu
fn m() { print("${[1][5]}") }
```
- F7/VM: **panic** com exit≠0 (o `[]` nativo dispara `IndexError`, intrínseco). JS: exceção não-capturada + exit≠0. **MATCH**. (Ruling do dono §0.6: semântica A.)

### CA10 (Map — chave ausente → `nil`) [F7-pin]
```tu
fn m(x: Map<String, Int>) {
  match x["k"] { .some(v) => print("${v}"), nil => print("vazio") }
}
```
- F5: `x["k"] : Int?` (o `Map[k]→V?` do ruling). F7/VM: imprime `vazio` (ausência = `nil`, sem throw). **MATCH**.

## Cobertura no corpus + unit

- **Corpus:** `conformance/check/` para os erros (CA5-CA7, `// EXPECT-CHECK`); `conformance/run/` (ou o golden-runner) para CA1-CA4/CA8-CA10 (pós-pin).
- **Unit:** `compiler/test/check_test.dart` grupo "spec 012 chão" — as assinaturas (`.length:Int`, `xs[i]:E`, `Map[k]:V?`, `xs+ys:List<E>`) e os 3 erros. O linchpin do "antes" (`xs[i]` = `cannot-infer`) ancora que a 012 o converte, não o inventa.
- **Regressão:** confirmar que nenhum programa verde regride (o `builtin-member-unsupported` só é REMOVIDO, nunca adiciona recusa).
