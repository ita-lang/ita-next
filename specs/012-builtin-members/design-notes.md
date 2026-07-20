# Design notes 012 — Membros de built-in (o CHÃO)

> **Fase 0 do `/speckit-plan`.** As decisões de design, com `Rationale` (capítulo + princípio) e `Alternatives rejected`. W1: `compiler-craftsman` (F5) + `dart-vm-expert` (codegen), 2026-07-20. Comportamento observável ainda se valida via MCP `ita`.

## Achados de FATO (verificados no código — corrigem o "antes")

1. **`.length`** (`ast.Member`) morre em `check.dart:1815-1820` com `builtin-member-unsupported` (`String` por `_isPrimitive`; `List`/`Map` por `BuiltinType`). A spec §1 está correta aqui.
2. **`xs[i]`** (`ast.Index`) **NÃO está no dispatch `_synthInner`** → hoje cai em `_ => _cannotInfer(e)`. Ou seja, `xs[0]` é hoje **`cannot-infer`, não `builtin-member-unsupported`**. ⚠️ A spec §1 estava imprecisa para `[]` — **corrigido** (o exemplo "antes" já reflete `cannot-infer`). O conserto é o mesmo (novo `_index`).
3. **`xs + ys`**: `_binary` consulta `_primitiveOps[add]` (`check.dart:51`), que **já tem** a row `String+String`. Logo `String+String` **já funciona**; o único delta de `+` é `List+List`.

## Decisão 1 — Estrutura da tabela do chão (F5)

- **Decision.** A tabela realiza-se como **três artefatos, não um Map monolítico**: (a) `_groundField[(shape, name)] → Type` estático/`const`, só para os **field-like** (`.length` → `Int`), com `_groundShape(Type) → {list, map, string} | null`; (b) regra local em `_index` para `[]`; (c) regra local em `_binary` para `+`. Miss → **`ErrorType` absorvente** + `unknown-member` (nunca `UnknownType`/`dynamic`).
- **Rationale.** Precedente: o `Ops(sym)` = `_primitiveOps` (spec 009 §4.9). `.length` é constante (`Int`, independe de `E`) ⟹ tabela; `[]`/`+` têm **retorno paramétrico** (`E`/`V?`/`List<E>`, função de `recv.args`) ⟹ regra local que lê `recv.args`, como `_primitiveOps` já trata operador dentro de `_binary`. `record(t)` do Dragon **6.3.6**. As 3 condições ficam checáveis: FECHADA (`const`, sem `.add`), erra-no-desconhecido (miss→`unknown-member`), destino-M5 (ao lado do `_primitiveOps`, mesmo débito de migração `.tu`).
- **Alternatives rejected.** `Map<(shape,member), FunctionType>` com prefixo ∀ e `substitute`: exigiria um `owner: AstNode` para cada `TypeParamType` — built-in **não tem nó-decl** (o mesmo buraco da Decisão 3). Over-engineering para 6 entradas fechadas. Fica como o caminho do M5 se o chão crescer/virar `.tu`.

## Decisão 2a — `xs.length` (F5)

- **Decision.** Em `_member`, após `if (recv is ErrorType) return recv;` (1813): `final g = _groundField(recv, n.name); if (g != null) return g;` e **DELETAR** o gate `builtin-member-unsupported` (1815-1820). O miss cai naturalmente em `_lookup → null → unknown-member` (`_isPrimitive`/`BuiltinType` nunca são `NamedType`).
- **Rationale.** Síntese pura (Dragon **6.5.1**) sobre `record(t)` (6.3.6); `.length` não depende do uso. Deletar o gate (em vez de trocar o erro) **remove o special-case**: `Int.length`/`xs.foo` (CA5) ganham `unknown-member` de graça pelo fall-through. O mais barato e honesto.
- **Alternatives rejected.** Manter o gate e trocar o erro → conserva ramo que só duplica o `_lookup`.

## Decisão 2b — `xs[i]` (F5, novo `_index`)

- **Decision.** `ast.Index n => _index(n)` no `_synthInner` (~795) + o método: `list` → `_check(index, Int); return args[0]` (`E`); `map` → `_check(index, args[0]); return optional(args[1])` (`V?`); `string` → `_check(index, Int); return String`; `error` → `_synth(index); return ErrorType`; `_` → `_synth(index); _err('unknown-member', n); return ErrorType`.
- **Rationale.** Acesso a elemento (Dragon **6.5.1**: `array(s,t)→t`). Checa `i ⇐ Int` (constante ⟹ trivialmente L-atribuído, 5.2.4b). Map → **`V?` via `optional()`** (smart constructor `type.dart:212`, invariante `T??=T?`) — ruling do dono §0.6. **`_synth(n.index)` em TODOS os ramos** = totalidade da nº1 (spec 009 §7-4) — é a classe do buraco Str-parts que crashou a F6 (`a1f9d0f`).
- **Alternatives rejected.** Não tipar o `index` no ramo error → viola totalidade da nº1. `index-unsupported` próprio → a spec §4.6 manda `unknown-member`; span no `[` (`n.opOffset`).

## Decisão 2c — `xs + ys` (F5, concat de List)

- **Decision.** Em `_binary`, ANTES de `_primitiveOps[n.op]` (1688): `if (op==add && l is BuiltinType && l.kind==list) { if (l==r) return l; _err('no-operator-for-types', n); return ErrorType; }`.
- **Rationale.** Homogêneo, **zero coerção** (Dragon 6.5.2 por negação — o Itá recusa widening, §4.5). `==` estrutural de `BuiltinType` (`type.dart:167`) dá homogeneidade exata. Fica fora de `_primitiveOps` (retorno paramétrico); `String+String` continua na tabela (não dispara aqui — `StringType` não é `BuiltinType`).
- **Alternatives rejected.** `_check(right, l)` literal → daria `type-mismatch`, mas o §4.6/CA7 pedem `no-operator-for-types`. (Nome do diagnóstico é ruling do dono — ver Pendências.)

## Decisão 3 — A fronteira F5/F7 (o que NÃO é da F5)

- **Decision.** A F5 **só tipa**: `xs[i]:E`, `m[k]:V?`, `xs.length:Int`, `xs+ys:List<E>`. **Nenhuma guarda de bounds**, **NÃO** popular a nº3 (`resolvedMembers`). O out-of-bounds é panic em runtime (F7/VM).
- **Rationale.** Fronteira Cap 6 = Art. III. `ResolvedMember` exige `decl: AstNode` — built-in **não tem nó-decl**; forjar fura o invariante (nº3 é de user-member). A F7 re-deriva do TIPO (`exprTypes[receiver]`) + nome, a mesma via do `Ops(+)` (013 §7.5) — não é mágica. Recomendo **não** criar side-table (ruling do dono, ver Pendências).

## Decisão 4 (codegen) — `interfaceTarget` via `LibraryIndex` + higiene de campo

- **Decision.** Resolver via `LibraryIndex(component, ['dart:core']).getMember(container, name)` sobre o `vm_platform.dill` pinado (a via do `print`, 013 §7.6): `xs.length` → `getMember('List','get:length')` (**prefixo `get:` obrigatório** para getter) → `InstanceGet(kind: Instance, receiver, Name('length'), interfaceTarget, resultType: int)`. `xs[i]` → `getMember('List','[]')` → `InstanceInvocation(kind: Instance, receiver, Name('[]'), Arguments([i]), interfaceTarget, functionType: (int)→E)`. `xs+ys` → `getMember('List','+')` → `InstanceInvocation(..., functionType: (List<E>)→List<E>)`.
- **Rationale (fonte VM 3.12.2).** `library_index.dart`: `getterPrefix='get:'`, `getMember(lib, container, member)`; nome de operador em Kernel É o símbolo (`[]`,`+`). `expressions.dart`: `InstanceGet`/`InstanceInvocation` têm `kind` + `resultType`/`functionType` **`required`** (blindagem — não compila sem; ver `kernel-raw-api-field-hygiene`), mas o *valor* de `functionType`/`resultType` **substituído** pode vir errado em silêncio (o verifier não faz type-checking, `verifier.dart:127-129`). `kind = InstanceAccessKind.Instance` (receptor non-nullable interface-type). Confirmado: `List<E> operator +(List<E>)` **EXISTE** em `dart:core@3.12.2` (`list.dart:~603`).
- **Sub-nota — `Map[k]`:** o `functionType` emitido é **`(Object?)→V?`** (a assinatura REAL de `dart:core`: `V? operator [](Object? key)`), não `(K)→V?`. A F5 tipa `k ⇐ K` (narrowing legítimo, mais estrito); `K <: Object?` ⟹ o argumento passa. A superfície do Itá é `(k: K)→V?` (§4.1); o Kernel usa `Object?`.
- **Alternatives rejected.** `resultType=DynamicType` (ADR-0013 proíbe; perde unboxing). `Reference` à mão (reabre higiene de nome canônico).

## Decisão 5 (codegen) — Out-of-bounds = `IndexError` intrínseco; F7 sem guarda

- **Decision.** `xs[i]` fora dos limites faz **panic**, e a F7 **não emite guarda** — o `[]` nativo já checa. Precisão: o erro é **`IndexError`** (não `RangeError` literal). `Map[k]` ausente devolve `null`=`nil` (sem throw).
- **Rationale (fonte VM 3.12.2).** `_GrowableList.operator []` é `external` + `@pragma("vm:recognized")` — bounds-check **intrínseco da VM (Grupo B)**. `errors.dart`: `class IndexError extends ArgumentError implements RangeError`, subtipo de **`Error`**. Zero try/catch (P7) ⟹ nada captura → isolate morre, exit≠0 = panic (013 §7.4f). A distinção `Error`×`Exception` não muda o desfecho.
- **Alternatives rejected.** F7 emitir `if (i >= xs.length) panic` → dupla checagem, custo AOT, viola "o mais chão".

## §7.3 — Comportamento por alvo (MATCH)

| Alvo | `.length`/`[]`/`+` | out-of-bounds | veredicto |
| :-- | :-- | :-- | :-- |
| **VM** (JIT) | referência (oracle) | `IndexError` intrínseco → panic | — |
| **AOT** | empata byte-a-byte (`dart:core` idêntico) | idem | **MATCH** |
| **JS** (dart2js) | `List.+`/`String`/`Map[]` existem; bounds-check sobre `JSArray` também lança `IndexError` | exceção + exit≠0 | **MATCH** (divergência só numérica Int 2⁶³×2⁵³, ortogonal) |

## Riscos/armadilhas (o que a doutrina exige e é fácil furar)

1. Miss vazar `UnknownType` → usar `ErrorType` absorvente (condição 2, a doença do oracle).
2. `_isPrimitive` cobre Int/Float/Bool/String; **só String** tem membro-chão → `_groundShape` retorna `null` p/ Int/Float/Bool (`Int.length`→`unknown-member`).
3. Type-arg ausente (`args` vazio) → `ErrorType`, não crash (cercas `when args.isNotEmpty`/`length==2`).
4. Map-index **tem** de passar por `optional(V)` — nunca `OptionalType._` cru (senão `T??`, sem imagem no Kernel).
5. Totalidade da nº1: `_synth(n.index)` em todos os ramos do `_index`.
6. `+` heterogêneo → `no-operator-for-types` (não `type-mismatch`).
7. `builtin-member-unsupported` vira **código morto** após remover o sítio → retirar do registro de diagnósticos.

## Pendências a escalar ao dono (design-only não decide)

- **Nome do diagnóstico:** `+` heterogêneo (`no-operator-for-types` vs `type-mismatch`) e `[]` em não-indexável (`unknown-member` vs `index-unsupported`). Recomendação: os da spec. Ruling de identidade de diagnóstico.
- **Contrato F5×F7:** popular ou não uma side-table de resolução de membro-built-in. Recomendação: **não** (re-derivável do tipo; a nº3 é de user-member).
