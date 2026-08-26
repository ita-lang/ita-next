---
name: fase5-spec-012-chao
description: Fase 5 / spec 012 (membros de built-in — o CHÃO .length/[]/+) — design W1: 3 sítios distintos, tabela field-only monomórfica, out-of-bounds é F7, correções à prosa da spec
metadata:
  type: project
---

# Spec 012 — o CHÃO (`.length`/`[]`/`+`) — design-notes F5 (W1, 2026-07-20)

Sucede 011 (membro de user-type). Ver [[types]], [[fase5-fatia-c-contextual]], [[fase5-spec-011-membros]].
Doutrina do chão: 3 condições (FECHADA / erra no desconhecido / destino `.tu` M5) — spec 010 §4.6.1.

## Fato de código (verificado, não é a prosa da spec)
- **`.length`** (`ast.Member`) → `_member` (`check.dart:1794`); gate `builtin-member-unsupported` em **1815-1820** (`recv is BuiltinType || _isPrimitive`). `String` cai aqui (é `_isPrimitive`), `List`/`Map` são `BuiltinType`.
- **`xs[i]`** (`ast.Index`) → **NÃO está no dispatch `_synthInner`** (778-805) ⟹ cai no `_ => _cannotInfer`. Hoje `xs[0]` é **`cannot-infer`, NÃO `builtin-member-unsupported`**. A prosa da spec §1 erra nisso; o conserto (novo `_index`) é o mesmo, mas o "antes" do teste difere.
- **`xs + ys`** (`ast.Binary` add) → `_binary` (1674); `_primitiveOps[add]` (51-77) só tem Int/Float/**String** rows. `String+String` JÁ funciona; só `List+List` é novo.

## As 3 decisões-chave
1. **3 sítios, não 1** (nós de AST distintos, disciplinas distintas): `.length`=seleção de campo (6.3.6), `[]`=acesso a elemento (6.5.1), `+`=operador (6.5.2/refuta a coerção). Todas **puro-síntese** (nenhum arm de check-mode; síntese + subsunção basta em `_check`). Só os OPERANDOS sub-checam (`i ⇐ Int`, concat-operando `⇐ List<E>`).
2. **Tabela = só `.length` (field-like), monomórfica por SHAPE.** `_groundField[(shape, name)] → Type` com shape∈{list,map,string}→`Int`. `[]`/`+` NÃO entram na tabela: retorno é função de `recv.args` (paramétrico) ⟹ regras locais em `_index`/`_binary`, exatamente como `_primitiveOps` já trata operador localmente. Rejeitado: esquema ∀-prefixo uniforme (precisa `owner` AstNode falso p/ `TypeParamType`; over-eng p/ 6 entradas fechadas — o precedente `_primitiveOps` escolheu tuplas concretas).
3. **F5 só TIPA; NÃO popula `resolvedMembers` (nº3).** `ResolvedMember.decl` exige `AstNode` que o built-in não tem; forjar nó é desonesto e fura o invariante da nº3 (é de user-member). F7 tem a SUA tabela de alvo `dart:core` (§7.1, "análogo da nº3 p/ built-in"), re-inspecionando `exprTypes[receiver]`+nome. Contrato F5×F7 — escalar ao dono se quiser side-table dedicada (recomendo não).

## Implementação mínima
- `.length`: em `_member`, após guarda `ErrorType` (1813), inserir `final g = _groundField(recv, n.name); if (g != null) return g;` e **DELETAR** o bloco 1815-1820. Built-in/primitivo sem membro-chão cai em `_lookup`→null→`unknown-member` (1838). `builtin-member-unsupported` vira código morto (§4.6: "a lacuna some").
- `_index` novo: synth recv; `list[E]`→`_check(index,Int)`,ret `recv.args[0]`; `map[K,V]`→`_check(index,K)`,ret `optional(recv.args[1])`; `String`→`_check(index,Int)`,ret `String`; senão `unknown-member` (span `[`); `ErrorType`→**synth do index p/ totalidade**, ret ErrorType.
- `_binary`: antes do `final table=` (1688), `if (op==add && l is BuiltinType(list)) { if (l==r) return l; _err('no-operator-for-types',n); return ErrorType; }`.

## Out-of-bounds (§3 = NÃO é F5)
F5 só tipa `xs[i]:E` (E, **não** E?) e `m[k]:V?`. Sem guarda de bounds — o panic é F7/VM (`[]` nativo do Dart → RangeError → panic não-capturável, P7, spec 013 §7.4f). Fronteira Cap 6 (Art. III): F5=6.3/6.5 estático; trap de runtime=7+ (dart-vm-expert). Map=`V?` pq ausência é valor legítimo (nil-nativo, 009 §4.6), não erro de programa.

## Armadilhas (o que a doutrina exige e é fácil errar)
1. Miss no chão → **`ErrorType` absorvente**, NUNCA `UnknownType`/`dynamic` (condição 2; a doença do oracle).
2. `_isPrimitive`=Int/Float/Bool/String; **só String tem membro-chão**. `_groundField` NÃO pode ter row Int/Float/Bool ⟹ `Int.length`=`unknown-member`.
3. `recv.args` vazio num `List`/`Map` (tipo malformado) → `ErrorType`, não crash em `args[0]`. Aridade é garantida por A (`generic-arity-mismatch`), mas defensivo.
4. Map-index usa **`optional(V)`** (smart ctor), nunca `OptionalType._` — idempotência do invariante `T??=T?`.
5. **Totalidade da nº1 (§7-4)**: `_index` tem de dar `exprTypes` ao index MESMO com receptor ErrorType — é a classe exata do buraco Str-parts que crashou a F6 em programa verde ([[f6_flow_check]]).
6. `+` heterogêneo = **`no-operator-for-types`** (CA7/§4.6), NÃO o `type-mismatch` que o `⇐` do §5.1 sugeriria. Igualdade exata + zero coerção, como `_primitiveOps`.

## L-atribuída / 1-walk
Todas L-atribuídas (Dragon 5.2.4b): `E₁.type` é sintetizado do filho já percorrido; `.length`/`[]`/`+` sintetizam só do receptor; `i ⇐ Int` checa contra CONSTANTE, não irmão à direita. Zero ponto-fixo, 1 walk.
