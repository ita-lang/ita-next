# Tasks 012: Membros de built-in — o CHÃO (`.length`/`[]`/`+`)

> **Plan:** [`plan.md`](./plan.md) · **Spec:** [`spec.md`](./spec.md) · **Design:** [`design-notes.md`](./design-notes.md) · [`conformance-cases.md`](./conformance-cases.md)
> **Escopo:** `ita-next/compiler`. Fail-first (RED→GREEN→VALIDATE→QUALITY). `[P]` = paralelizável. Validação de comportamento SEMPRE via MCP `ita` — nunca chutar saída.
> **Corte:** **LT-012a (F5) é implementável AGORA** (não depende do pin). ~~**LT-012b (F7/codegen) fica GATED** pelo Gate 2 (pin do SDK, spec 013 §0.6).~~ **Gate 2 caiu** — o SDK está materializado em `.dart-sdk/3.12.2/` e o `pkg/kernel` vendorado em `third_party/dart/3.12.2/`; a LT-012b foi implementada em 2026-08-31.

---

## LT-012a — F5: o chão TIPADO (`.length`/`[]`/`+`) `[⏳ implementável agora]`

> A F5 passa a tipar os 3 irredutíveis por uma tabela FECHADA + 2 regras locais; o gate `builtin-member-unsupported` é DELETADO (miss → `unknown-member`). Nenhum nó novo de AST. Fundamento: Dragon 6.3.6/6.5.1; doutrina do chão (3 condições). Ver `design-notes.md` Decisões 1–2c, 5.

### Fase RED — casos de conformância que FALHAM hoje
Um por CA de tipo/erro (spec §11). `check_test.dart` grupo "spec 012 — chão".

- [ ] **T001** — CA1 `.length`: `${[10, 20, 30].length}` tipa `Int`. Hoje FALHA (`builtin-member-unsupported`). — ⚠️ `[ ]` mantido: a forma literal-nu descrita NÃO tipa hoje — o list-literal nu dá `cannot-infer` (depende da fatia C, spec 010). Chão validado só com **receptor tipado**: `fn f(xs: List<Int>) => xs.length : Int` (exit 0). Test unit CA1 usa a forma tipada e passa.
- [ ] **T002** `[P]` — CA2 `[]`: `[10, 20, 30][1]` tipa `Int`. Hoje FALHA (`cannot-infer` — o `ast.Index` não está no dispatch; **linchpin** do "antes"). — ⚠️ `[ ]` mantido: literal-nu dá `cannot-infer` no list-literal (fatia C). `ast.Index` JÁ está no dispatch (`_index`); validado com receptor tipado `xs[0] : Int` (exit 0). Test unit CA2 usa a forma tipada e passa.
- [ ] **T003** `[P]` — CA3 concat+length: `([1, 2] + [3]).length` tipa `Int`. Hoje FALHA (`no-operator-for-types`/`builtin-member-unsupported`). — ⚠️ `[ ]` mantido: literal-nu dá `cannot-infer` nos list-literals (fatia C). Validado com receptor tipado `(xs + ys).length : Int` (exit 0). Test unit CA3 usa a forma tipada e passa.
- [x] **T004** `[P]` — CA4 `String.length`: `"olá".length` tipa `Int`. Hoje FALHA.
- [x] **T005** `[P]` — CA5 erro: `xs.foo` (List) ⟹ `unknown-member` (NÃO `builtin-member-unsupported`). Hoje dá `builtin-member-unsupported`.
- [x] **T006** `[P]` — CA6 erro: `xs["a"]` ⟹ `type-mismatch` no span do índice. Hoje `cannot-infer`.
- [x] **T007** `[P]` — CA7 erro: `List<Int> + List<String>` ⟹ `no-operator-for-types`. Hoje `no-operator-for-types`/`cannot-infer` (confirmar o "antes").
- [x] **T008** `[P]` — CA10 (tipo, sem exec): `x["k"]` sobre `Map<String,Int>` tipa `Int?` (`optional(V)`). Hoje FALHA.

### Fase GREEN — implementação em `compiler/lib/frontend/semantic/` (ordem do plan §5)
- [x] **T010** — `check.dart:~51`: `_groundField[(shape, name)]→Type` (`const`, só `.length`→`Int`) + `_groundShape(Type)→{list,map,string}|null`. Critério: unit da tabela (miss → `null`). *(depende de: —)*
- [x] **T011** — `check.dart:1813` (`_member`): inserir `final g = _groundField(recv, n.name); if (g!=null) return g;` e **DELETAR** o gate `builtin-member-unsupported` (1815-1820). Critério: **T001, T004 passam**; `Int.length`→`unknown-member` (fall-through). *(depende de: T010)*
- [x] **T012** — `check.dart:1688` (`_binary`): ramo List-concat antes de `_primitiveOps` (`op==add && l is BuiltinType(list)`; `l==r`→`l`; senão `no-operator-for-types`). Critério: **T003, T007 passam**; `String+String` intacto. *(depende de: —)*
- [x] **T013** — `check.dart:~795` (`_synthInner`): `ast.Index n => _index(n)` + o método (`design-notes.md` Decisão 2b): list→`args[0]`, map→`optional(args[1])`, string→`String`, error/`_`→`ErrorType`+`unknown-member`; **`_synth(n.index)` em TODOS os ramos** (totalidade nº1). Critério: **T002, T006, T008 passam**. *(depende de: —; maior superfície)*
- [x] **T014** — retirar `builtin-member-unsupported` do registro de diagnósticos (código morto após T011). Critério: `analyze` limpo, sem referência órfã. *(depende de: T011)*

### Fase VALIDATE — comportamento ao vivo (MCP `ita` / `itac check`)
- [x] **T020** — `itac check` ao vivo: `xs.length:Int`, `xs[i]:E`, `xs+ys:List<E>`, `m[k]:V?`, e os 3 erros (`unknown-member`/`type-mismatch`/`no-operator-for-types`) com span. Nunca assumir a saída (Art. IV-1).

### Fase QUALITY — gate
- [x] **T030** — `make test` verde (o grupo "spec 012" + zero regressão — nenhum programa verde recusado) + `dart analyze` limpo.

---

## LT-012b — F7: codegen do chão `[🟢 T040–T042 fechados 2026-08-31 · T043 ABERTO, por outro motivo]`

> Design **assentado** (spec §7 + `design-notes.md` Decisões 4–5, confirmados na fonte 3.12.2 pelo `dart-vm-expert`). Emite `InstanceGet`(`get:length`)/`InstanceInvocation`(`[]`,`+`) com `interfaceTarget` de `dart:core`; `kind=Instance`, `resultType`/`functionType` **substituídos** via `Substitution.fromInterfaceType`; `ListLiteral`/`MapLiteral` com `isConst: false`; out-of-bounds = `RangeError` intrínseco → panic (sem guarda).

- [x] **T040** — RED de execução, em `conformance/codegen/chao_*.tu`. Os `.out` foram escritos **antes** de a emissão existir, a partir de um oráculo Dart independente rodado no pin 3.12.2 — não do nosso emitter.
  - ⚠️ **A letra dos CA1/CA2/CA3/CA9 não chega à F7**, medido: com receptor literal-nu (`[10,20,30].length`) o programa para na F5 com `cannot-infer`, exit 65 — erro de FASE, não fronteira da emissão. Os fixtures usam receptor tipado, e o corte está preso executavelmente por `chao_literal_nu.tu` (`EXPECT-ERROR: cannot-infer`), que fica VERMELHO quando a decisão do literal nu sair, em qualquer direção. Ver o item 4 de "Ordem e gate".
  - O runner ganhou a diretiva `// EXPECT-STDERR: <substring>`, exigida com `EXPECT-EXIT` ≠ 0: sem ela o CA9 ficaria verde sobre qualquer morte de isolate — um `interfaceTarget` de classe errada dá `NoSuchMethodError` e também sai 255. `panic_exit.tu` ganhou a sua junto.
- [x] **T041** — GREEN em `codegen/lib/emit.dart` (não em `compiler/lib/frontend/codegen/`, que não existe — o codegen é o pacote isolado, spec 013 §0-A): `ListExpr`→`ListLiteral`, `MapExpr`→`MapLiteral`, `Member(length)`→`InstanceGet`, `Index`→`InstanceInvocation`, `Binary(add)` de List/String→`InstanceInvocation` da classe do receptor.
  - 🔴 **Achado no caminho: o `+` de `String` estava quebrado, e só em AOT.** `_arithTarget` escolhia o alvo pela TAG SINTÁTICA do operador, então `"a" + "b"` gravava `interfaceTarget = num::+` e `functionType = String Function(num)`. JIT e JS imprimiam certo; o AOT morria com *"Attempt to execute code removed by Dart AOT compiler (TFA)"*. Fixture `chao_string_concat.tu`.
  - 🔴 **E a primeira correção dele cobriu só 1 dos 3 sítios** — achado pela revisão adversarial em contexto limpo, não pelos gates. A decisão do alvo do `+` estava escrita em `_binary`, `_assign` (`s += "x"`) e `_assignMember` (`c.s += "x"`); corrigir o primeiro deixou os outros dois em silêncio, e esta linha chegou a declarar que "a classe fechou". Não tinha fechado: `var s: String = "a"; s += "b"` é programa legal (`_primitiveOps` da F5 admite `(String,String)→String`, `check.dart:55`) e seguia morrendo em AOT. A cura virou **um sítio só** (`_arithAlvo`), chamado pelos três — a régua já existia no corpus para o `div`, escrita em `var_assign.tu:13-15`: *"a armadilha `~/` (Int) × `/` (Float) não pode ser fechada numa forma e reaberta na outra"*. Fixtures `chao_string_compound.tu` (metamórfico: `a + b` e `c += b` no mesmo programa) e `chao_string_compound_campo.tu`.
  - 🔴 **ICE sobre programa LEGAL:** `let xs: List<Int>? = [1, 2]` passava a F5 (exit 0) e dava `ice-codegen-list-literal-typed-OptionalType`. A F5 grava o esperado INTEIRO, com o `?` (`check.dart:2848`), e declara a legalidade no próprio docstring (`:2801-2802`, *"`T?` desembrulha para validar e descer … é legal (subsunção `T ≤ T?`)"*) — o emitter lia sem desembrulhar. Fixture `chao_literal_opcional.tu`. É violação da R6 e o formato mais caro deste repo: a decisão estava escrita na fase anterior, e a seguinte não a leu.
  - O `.length` do chão caía em `ice-codegen-member-unresolved` — ICE que nomeia estado do emissor sobre um acesso que a F5 **resolveu**, por outra tabela: ela não popula a nº3 para o chão (`check.dart:2411-2412`).
- [x] **T042** — VALIDATE: os 10 fixtures `chao_*` rodam nos **três** alvos (VM × AOT × JS), stdout byte a byte, `verifyComponent` + os 8 invariantes verdes. Além dos CAs da §11, três casos que a spec não pede: `chao_membro_usuario.tu` (`struct` com campo `length` convivendo com o chão — o desvio por tipo não sequestra o campo do usuário), `chao_aninhado.tu` (`Map<String,List<Int>>` × `List<Map<String,Int>>` — onde a substituição deixa de ser trivial), `chao_receptor_efeito.tu` (receptor efeituoso avaliado **uma** vez — R3, o invariante que nenhum golden de valor puro enxerga).
- [ ] **T043** — **CA8 NÃO destravou, e a previsão desta linha estava errada.** Medido em 2026-08-31: `fn conta(xs: List<Int>) -> Int => match xs { [] => 0, [_, ..r] => 1 }` dá `ice-codegen-match-on-BuiltinType`. O bloqueio nunca foi a emissão de `List` — é o **lowering de list-pattern** no `_matchExpr`, que não sabe baixar `[]` nem `[_, ..r]`. Fatia própria, com nome e sítio (R10: o branco se preenche com código nosso). O encaixe 012↔013 que este item prometia verificar segue **não verificado**.

---

## Ordem e gate

1. **LT-012a (F5)** aterrissa JÁ — fecha a lacuna `builtin-member-unsupported`, sem depender do pin.
2. ~~**LT-012b (F7)** entra com o Gate 2 (pin), junto da emissão da F7. O `match` sobre `List` destrava (CA8).~~
   **Metade certa, metade errada — medido em 2026-08-31.** A LT-012b entrou (o Gate 2 já tinha caído: SDK
   e vendor materializados). Mas o `match` sobre `List` **não destravou**: ele nunca dependia da emissão de
   `List`, e sim do lowering de list-pattern no `_matchExpr` — `ice-codegen-match-on-BuiltinType`. Ver T043.
3. Rulings do dono: nome do diagnóstico do `+` heterogêneo (pendente); side-table F5×F7 (recomendação: não, pendente); **✅ reconciliação da 011 §4.7 (W3-D) RESOLVIDA (2026-07-20, dono delegou):** não-chão de built-in → `unknown-member` — `.map`/`.filter` são BIBLIOTECA (`.tu`, M5), não lacuna do COMPILADOR; `builtin-member-unsupported` mentiria sobre a natureza. Assentado na spec §4.6.
4. ~~**Dependência conhecida (W3-A):** os CAs com LITERAIS (`[1,2,3].length`) só tipam quando a **fatia C** (contextual typing, spec 010) inferir o receptor; o chão funciona sobre receptor TIPADO hoje. O codegen (LT-012b) não assume literal-nu até a fatia C.~~
   **✅ RESOLVIDO em 2026-08-31 — e metade da leitura estava errada.** A frase acima vale para o
   literal **nu** (`let xs = [1,2,3]`, sem esperado), e ali segue verdadeira: é `cannot-infer` por
   política (009 §4.3), não por fatia faltando. Mas ela foi **aplicada a casos que não cobre** — sob
   `let` anotado, argumento de parâmetro tipado e retorno anotado, o esperado existe e a 009 §4.3
   manda o literal CHECAR (*"`[Cachorro()]` contra esperado `List<Animal>` desce elemento a
   elemento"* — o exemplo do texto é não-vazio). Medido antes do conserto: **nenhuma das três formas
   tipava**, o que tornava impossível construir uma `List`/`Map` com conteúdo em Itá — e deixava os
   CA1–CA3/CA9/CA10 desta spec **inexecutáveis**, não "dependentes".
   Fatia implementada na **[errata da 010 §4.1](../010-contextual-typing/spec.md)** (é regra de
   tipagem, não do chão), com catraca em `check_test.dart`, grupo *"errata 010 §4.1"* — 13 casos,
   incluindo o que trava a metade **sem** esperado, que continua `cannot-infer` até ruling do dono.

## Estratégia de implementação
Menor CA primeiro, incremental: **T010 (tabela) → T011 (`.length`, fecha o gate) → T012 (`+`) → T013 (`[]`, o maior) → T014 (limpeza)**. `make test` após cada passo. A F5 é 1 walk L-atribuído (Dragon 5.2.4b) — puro-síntese, nenhum arm de check-mode novo.
