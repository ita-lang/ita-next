# Plan 012: Membros de built-in — o CHÃO (`.length`/`[]`/`+`)

> **Spec:** [`spec.md`](./spec.md) · **Status:** `ready` · **Marco:** `M4 — front-end · destrava a F7`
> **Design:** [`design-notes.md`](./design-notes.md) · [`conformance-cases.md`](./conformance-cases.md) · W1: `compiler-craftsman` + `dart-vm-expert` (2026-07-20)

## 1. Resumo técnico

A F5 passa a **tipar** os 3 membros irredutíveis do chão (`.length`/`[]`/`+`) por uma tabela FECHADA + duas regras locais, deletando o gate `builtin-member-unsupported`; miss vira `unknown-member`. A F7 **emite** o acesso nativo de `dart:core` (`InstanceGet`/`InstanceInvocation` com `interfaceTarget` tipado, via `LibraryIndex`). Resultado observável: `xs.length`/`xs[i]`/`xs + ys` compilam e rodam; o `match` sobre `List` (013 §7.4e) destrava. **Corte:** a **F5 é implementável AGORA**; a **F7 fica gated pelo pin do SDK** (Gate 2 da 013 §0.6, adiado) — o design está fundado na tag 3.12.2, que é a mesma do pin.

## 2. Fases do compilador tocadas (ancoradas na spec)

| Fase | Arquivo(s) `compiler/lib/…` | Mudança | Ref. spec | Estado |
| :-- | :-- | :-- | :-- | :-- |
| Semântica/Tipos | `frontend/semantic/check.dart` | `_groundField`+`_groundShape` (`~51`); `_member` consulta o chão e **deleta** o gate `builtin-member-unsupported` (`1815-1820`); novo `_index` no `_synthInner` (`~795`); ramo List-concat em `_binary` (`1688`) | §4, §5 | **agora** |
| Semântica/Tipos | `frontend/semantic/type.dart` | uso de `optional()` (`212`) p/ `Map[k]→V?`; `BuiltinKind`/`==` estrutural (existentes) | §4.1/§4.3 | **agora** |
| (diagnósticos) | registro de erros | retirar `builtin-member-unsupported` (código morto); garantir `unknown-member`/`no-operator-for-types` | §4.6 | **agora** |
| Codegen | `frontend/codegen/` (hoje vazio) | `InstanceGet`(`get:length`)/`InstanceInvocation`(`[]`,`+`) com `interfaceTarget` de `dart:core` via `LibraryIndex`; `kind=Instance`, `resultType`/`functionType` substituídos | §7 | **gated (pin)** |

## 3. Estratégia por alvo (codegen — gated pelo pin)

- **VM (JIT/AOT):** os membros vêm de `dart:core` (Grupo B, ADR-0001); a F7 só emite o nó bem-tipado. Out-of-bounds = `IndexError` intrínseco → panic (sem guarda emitida). AOT empata a VM byte-a-byte.
- **JS (dart2js):** `List.+`/`String[]`/`Map[]` existem na `dart:core` compartilhada; bounds-check sobre `JSArray` também lança `IndexError`. Paridade **MATCH** (a única divergência é numérica — `Int` 2⁶³×2⁵³ — ortogonal a esta spec).

## 4. Plano de teste (o gate)

- **Corpus de conformância:** CA1–CA10 (ver [`conformance-cases.md`](./conformance-cases.md)) — `.tu` novos. Os de **tipo** (CA1-CA7) validam na F5 **agora**; os de **execução/erro-runtime** (CA8-CA10) esperam a F7 (pin).
- **Testes unitários:** `compiler/test/check_test.dart` — grupo "spec 012 chão": `.length:Int`, `xs[i]:E`, `Map[k]:V?`, `xs+ys:List<E>`, e os erros (`unknown-member`, `type-mismatch`, `no-operator-for-types`). O "antes" de `xs[i]` é `cannot-infer` (não `builtin-member-unsupported` — achado do W1).
- **Validação ao vivo:** MCP `ita` / `itac check` — o typing na F5; `itac run` (pós-pin) para CA1-CA4/CA9/CA10.
- **Paridade VM×JS:** golden-runner (pós-pin); MATCH marcado.
- **CI:** conformance + unit + benchmark de compile-time (`itac` AOT) sem regressão.

## 5. Ordem de ataque e dependências

1. **`_groundField`+`_groundShape`** (tabela isolada) — depende de: — .
2. **`.length`** (`_member`: consulta + delete do gate) — depende de: 1. *(menor; fecha o gate)*
3. **`xs + ys`** (ramo List-concat em `_binary`) — depende de: — . *(1 ramo)*
4. **`xs[i]`** (`_index` novo no `_synthInner`) — depende de: — . *(maior superfície; exige a totalidade da nº1)*
5. **Retirar `builtin-member-unsupported`** do registro (código morto) — depende de: 2.
6. **[gated] Codegen** dos 3 nós — depende de: 1-4 **e** do **pin do SDK** (Gate 2 da 013).

Rodar `make test` após cada passo. Passos 1-5 são a F5 (agora); 6 espera o pin.

## 6. Riscos técnicos e mitigações

| Risco | Mitigação |
| :-- | :-- |
| Miss no chão vazar `UnknownType` (a doença do oracle) | `ErrorType` absorvente + `unknown-member` (condição 2 da doutrina) |
| `_isPrimitive` cobre Int/Float/Bool, mas só String tem chão | `_groundShape` → `null` p/ Int/Float/Bool (`Int.length`→`unknown-member`) |
| `Map[k]` produzir `T??` | passar por `optional()` (smart constructor), nunca `OptionalType._` |
| Totalidade da nº1 no `_index` (crash da F6, à la Str-parts) | `_synth(n.index)` em TODOS os ramos |
| `functionType`/`resultType` substituído errado (silêncio — verifier não type-check) | teste estrutural sobre o dump (pós-pin) + golden-runner |

## 7. Constitution Check (pós-design)

Sem conflito — **W0 `ita-visionary`: liberado-com-ressalva** (§0.5 da spec). O design honra as 3 condições (a tabela é `const`/FECHADA; miss→`unknown-member`; destino `.tu` M5), **P4** (o `.dill` diz a verdade — `InstanceGet`/`InstanceInvocation` tipado, zero `dynamic`), **P6** (nenhum marcador de intrínseco; se um dia, keyword do M5), **P7** (out-of-bounds→panic, ruling do dono), **Art. III** (Cap 6 é a fronteira). Pendências ao dono (não bloqueiam): nome do diagnóstico do `+` heterogêneo; popular ou não a side-table F5×F7 (recomendação: não).

## Ordem no roadmap

**F5 (passos 1-5) pode aterrissar já** — não depende do pin, e fecha uma lacuna real (`builtin-member-unsupported`). **A F7 (passo 6)** entra quando o Gate 2 (pin) for rodado, junto com o resto da emissão. O `match` sobre `List` destrava exatamente aí.
