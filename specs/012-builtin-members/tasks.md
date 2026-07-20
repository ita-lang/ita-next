# Tasks 012: Membros de built-in — o CHÃO (`.length`/`[]`/`+`)

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md) · **Design:** [`design-notes.md`](./design-notes.md) · [`conformance-cases.md`](./conformance-cases.md)
> **Escopo:** `ita-next/compiler`. Fail-first (RED→GREEN→VALIDATE→QUALITY). `[P]` = paralelizável. Validação de comportamento SEMPRE via MCP `ita` — nunca chutar saída.
> **Corte:** **LT-012a (F5) é implementável AGORA** (não depende do pin). **LT-012b (F7/codegen) fica GATED** pelo Gate 2 (pin do SDK, spec 013 §0.6).

---

## LT-012a — F5: o chão TIPADO (`.length`/`[]`/`+`) `[⏳ implementável agora]`

> A F5 passa a tipar os 3 irredutíveis por uma tabela FECHADA + 2 regras locais; o gate `builtin-member-unsupported` é DELETADO (miss → `unknown-member`). Nenhum nó novo de AST. Fundamento: Dragon 6.3.6/6.5.1; doutrina do chão (3 condições). Ver `design-notes.md` Decisões 1–2c, 5.

### Fase RED — casos de conformância que FALHAM hoje
Um por CA de tipo/erro (spec §11). `check_test.dart` grupo "spec 012 — chão".

- [ ] **T001** — CA1 `.length`: `${[10, 20, 30].length}` tipa `Int`. Hoje FALHA (`builtin-member-unsupported`).
- [ ] **T002** `[P]` — CA2 `[]`: `[10, 20, 30][1]` tipa `Int`. Hoje FALHA (`cannot-infer` — o `ast.Index` não está no dispatch; **linchpin** do "antes").
- [ ] **T003** `[P]` — CA3 concat+length: `([1, 2] + [3]).length` tipa `Int`. Hoje FALHA (`no-operator-for-types`/`builtin-member-unsupported`).
- [ ] **T004** `[P]` — CA4 `String.length`: `"olá".length` tipa `Int`. Hoje FALHA.
- [ ] **T005** `[P]` — CA5 erro: `xs.foo` (List) ⟹ `unknown-member` (NÃO `builtin-member-unsupported`). Hoje dá `builtin-member-unsupported`.
- [ ] **T006** `[P]` — CA6 erro: `xs["a"]` ⟹ `type-mismatch` no span do índice. Hoje `cannot-infer`.
- [ ] **T007** `[P]` — CA7 erro: `List<Int> + List<String>` ⟹ `no-operator-for-types`. Hoje `no-operator-for-types`/`cannot-infer` (confirmar o "antes").
- [ ] **T008** `[P]` — CA10 (tipo, sem exec): `x["k"]` sobre `Map<String,Int>` tipa `Int?` (`optional(V)`). Hoje FALHA.

### Fase GREEN — implementação em `compiler/lib/frontend/semantic/` (ordem do plan §5)
- [ ] **T010** — `check.dart:~51`: `_groundField[(shape, name)]→Type` (`const`, só `.length`→`Int`) + `_groundShape(Type)→{list,map,string}|null`. Critério: unit da tabela (miss → `null`). *(depende de: —)*
- [ ] **T011** — `check.dart:1813` (`_member`): inserir `final g = _groundField(recv, n.name); if (g!=null) return g;` e **DELETAR** o gate `builtin-member-unsupported` (1815-1820). Critério: **T001, T004 passam**; `Int.length`→`unknown-member` (fall-through). *(depende de: T010)*
- [ ] **T012** — `check.dart:1688` (`_binary`): ramo List-concat antes de `_primitiveOps` (`op==add && l is BuiltinType(list)`; `l==r`→`l`; senão `no-operator-for-types`). Critério: **T003, T007 passam**; `String+String` intacto. *(depende de: —)*
- [ ] **T013** — `check.dart:~795` (`_synthInner`): `ast.Index n => _index(n)` + o método (`design-notes.md` Decisão 2b): list→`args[0]`, map→`optional(args[1])`, string→`String`, error/`_`→`ErrorType`+`unknown-member`; **`_synth(n.index)` em TODOS os ramos** (totalidade nº1). Critério: **T002, T006, T008 passam**. *(depende de: —; maior superfície)*
- [ ] **T014** — retirar `builtin-member-unsupported` do registro de diagnósticos (código morto após T011). Critério: `analyze` limpo, sem referência órfã. *(depende de: T011)*

### Fase VALIDATE — comportamento ao vivo (MCP `ita` / `itac check`)
- [ ] **T020** — `itac check` ao vivo: `xs.length:Int`, `xs[i]:E`, `xs+ys:List<E>`, `m[k]:V?`, e os 3 erros (`unknown-member`/`type-mismatch`/`no-operator-for-types`) com span. Nunca assumir a saída (Art. IV-1).

### Fase QUALITY — gate
- [ ] **T030** — `make test` verde (o grupo "spec 012" + zero regressão — nenhum programa verde recusado) + `dart analyze` limpo.

---

## LT-012b — F7: codegen do chão `[🔴 GATED — Gate 2 (pin do SDK), spec 013 §0.6]`

> Design **assentado** (spec §7 + `design-notes.md` Decisões 4–5, confirmados na fonte 3.12.2 pelo `dart-vm-expert`). O GREEN espera o vendor `pkg/kernel` (pin). Emite `InstanceGet`(`get:length`)/`InstanceInvocation`(`[]`,`+`) com `interfaceTarget` de `dart:core` via `LibraryIndex`; `kind=Instance`, `resultType`/`functionType` substituídos; out-of-bounds = `IndexError` intrínseco → panic (sem guarda).

- [ ] **T040** [gated] — RED de execução: CA1-CA4 (valores `3`/`20`/`3`/`3`), CA9 (`[1][5]`→panic exit≠0), CA10 (`x["k"]` ausente→`vazio`) no golden-runner (VM). Falham sem o codegen.
- [ ] **T041** [gated] — GREEN: emissão dos 3 nós em `compiler/lib/frontend/codegen/` (após o esqueleto da F7 existir — LT-F7a). Critério: CA1-CA4 rodam na VM via MCP `ita`.
- [ ] **T042** [gated] — VALIDATE: paridade VM×AOT×JS (MATCH) para CA1-CA4/CA9/CA10; `verifyComponent` verde sobre o `.dill`.
- [ ] **T043** [gated] — **CA8 co-verifica a 013:** `match xs { [] => 0, [_, ..r] => 1 }` passa a EMITIR `.dill` (era gated em 013 §7.4e). Confirma o encaixe 012↔013.

---

## Ordem e gate

1. **LT-012a (F5)** aterrissa JÁ — fecha a lacuna `builtin-member-unsupported`, sem depender do pin.
2. **LT-012b (F7)** entra com o Gate 2 (pin), junto da emissão da F7. O `match` sobre `List` destrava (CA8).
3. Rulings do dono (não bloqueiam LT-012a): nome do diagnóstico do `+` heterogêneo; side-table F5×F7 (recomendação: não).

## Estratégia de implementação
Menor CA primeiro, incremental: **T010 (tabela) → T011 (`.length`, fecha o gate) → T012 (`+`) → T013 (`[]`, o maior) → T014 (limpeza)**. `make test` após cada passo. A F5 é 1 walk L-atribuído (Dragon 5.2.4b) — puro-síntese, nenhum arm de check-mode novo.
