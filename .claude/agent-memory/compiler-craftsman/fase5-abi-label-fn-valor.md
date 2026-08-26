---
name: fase5-abi-label-fn-valor
description: Análise técnica (2026-07-29) das 4 opções de ABI de chamada (A eta / B proibir / C `_` na decl / D dupla-ABI marcada) — representação no tipo, impacto na inferência, custo por fase, e o dilema forçado da (D)
metadata:
  type: project
---

# ABI de label × `fn` como valor — a técnica das 4 opções (W1, 2026-07-29)

Contexto: briefing do ADR "label, ABI de chamada e `fn` como valor". Confronto com o
código: `compiler/lib/frontend/semantic/{type,check,collect,unify}.dart` + `codegen/lib/emit.dart`.

## Os 3 fatos que mudam o problema (verificados no código)

1. **O ICE do briefing NÃO é causado pela ABI.** `_emitType` (`emit.dart:1643-1682`) tem arms
   para `Optional`/`Result`/`Named`/`coreTypes` e cai em `ice-codegen-type-<T>` para
   `FunctionType`. Um **closure** no mesmo slot ICEia igual. Somam-se `_ident` (`:1481`,
   ICE em `TopLevelRes` ⟹ `let f = dobro` morre) e `_call` (`:1917`, ICE em `LocalRes` ⟹
   `f(v)` morre). **Ordem superior é 3 buracos da F7, ortogonais à decisão.** Nenhuma das 4
   opções os evita; a (B) só evita 1 programa.
2. **A (D) sem marcador JÁ É o comportamento de hoje, ponta a ponta.** `_matchArgs`
   (`check.dart:1804`) só consulta label quando o call-site o escreve (guarda `arg.label != null`
   nas linhas 1810 e 1826) ⟹ `dobro(5)` **e** `dobro(x: 5)` tipam na mesma decl; e a F7 emite as
   duas pelo slot da nº5 (`emit.dart:1941-1960`). O marcador da (D) só significa algo **se** o
   label virar obrigatório (decisão nº3). Sem isso ele marca o default.
3. **`ParamType.label == null` já É o bit "posicional"** (`type.dart:227-228`), já produzido por
   `FunctionType.positional` (`:345-350`) para anotação (`collect.dart:717`), closure
   (`check.dart:1081`) e chão (`check.dart:1289`); decl sempre dá `label ?? name`
   (`collect.dart:645`, `check.dart:1309`) ⟹ **nunca null**. A (C) **não precisa de campo novo**.

## Representação

- **(C) = QUOCIENTE, não campo novo.** `==` passa a comparar `(other.label == null) == (label == null)`
  (`type.dart:256`) + `hashCode` junto (`:258`). A razão do `==` atual (`:238-243`: "`(x: Int) -> Int`
  não parseia ⟹ o tipo seria inexprimível") é sobre **QUAL** label; o bit **presença** é exprimível
  sob a (C) (`(Int)->Int` = tudo posicional; `fn f(_ x: Int)` é a forma que o produz). Assinatura
  MISTA não precisa de ban: ela simplesmente não tem tipo-função exprimível.
  ⚠️ **`unify.dart:109-118` tem doutrina PRÓPRIA** ("só os TIPOS dos params") — sob (C) tem de mudar
  junto, senão reincide o bug "duas noções de igualdade, uma negando a outra" (achado 2 de
  [[f5-quantifiers-subtyping]]). (Ele também já ignora `quantifiers`, divergindo do `==`.)
- **NÃO usar "dois construtores de FunctionType"**: `positional` é conveniência, não variante;
  virar variante forçaria arm novo em todo switch sobre `Type` (a doença do `default: break`,
  `check.dart:676-680`).
- **(D) só é sã como propriedade da DECLARAÇÃO, não do TIPO.** Se "dual" virar estado de
  `ParamType` que iguala named E positional, `==` deixa de ser transitiva (named ≠ positional,
  mas ambos == dual) ⟹ quebra (i) o contrato `Object.==` do Dart, (ii) `Map<Type,·>`
  (`emit.dart:1682` faz `coreTypes[type]`), (iii) **union-find (Dragon 6.5.5 / Alg. 6.19), que É
  uma estrutura de classes de EQUIVALÊNCIA**. Relação reflexiva+simétrica não-transitiva =
  *tolerância*, não equivalência. Precedente exato: `dynamic` do Dart e `any` do TS — a analogia
  do dono importa justamente a propriedade errada.
- **(D) como "dois tipos" = tipo interseção** (TAPL 15.7 — lacuna do Dragon) ≡ **sobrecarga**
  (Dragon 6.5.3 + **Ex. 6.5.2, que é explicitamente DOIS percursos**) ⟹ mata a "1 walk" da F5.

## Inferência (onde a decisão entra)

| Opção | Sítio | Ambiguidade? |
|---|---|---|
| A | **subsunção** — arm `FunctionType` do `_isSubtype` (`check.dart:2738-2752`, a "costura" que o próprio doc diz ser onde essa mudança entra) + tabela de coerção (nº7 hoje só grava alvo-trait, `:2586-2591`) | tipo não; **identidade de valor sim** (cada travessia = closure nova) |
| B | check + diagnóstico nomeado | não |
| C | `==`/`≤` (e `unify`) | **nenhuma** — o bit vem da decl, nunca é inferido |
| D-decl | **`_matchArgs`** (regra de aplicação, anterior aos 2 modos) | não |
| D-tipo | **síntese** devolve conjunto (Ex. 6.5.2) | **SIM** — `let f = dobro` tem 2 tipos válidos ⟹ honestamente vira `cannot-infer` (ADR-0013) |

## (D) em profundidade — o dilema FORÇADO

`any Ord` (ADR-0017 R2) é marcador **no tipo**: ele **viaja com o valor**. Um marcador de dupla
ABI na **declaração NÃO viaja** — no `f(5)` sobre uma variável ninguém sabe. Logo:
**ou o marcador viaja e o sistema de tipos paga (não-transitividade / interseção / 2 passes),
ou o sistema fica são e o marcador não viaja.** Não há terceira via. Isto é teorema, não gosto.

Sub-achados:
- `let f = dobro` sem anotação: sob D-tipo ⟹ `cannot-infer` (feature "mais permissiva" que **exige
  anotação**); sob D-decl ⟹ tipo posicional (regra do Swift SE-0111, coerente com ADR-0016 §A).
- **As duas ABIs não são equipotentes**: o posicional só corta default do **FIM**
  (`requiredParameterCount`, `emit.dart:1183-1192`) — default do MEIO só é saltável pelo named.
  Uma fn com default no meio não pode ser honestamente dual.
- Emissão: **(D) é a (A) decidida na declaração** (mesmo artefato — forwarder/wrapper), OU custo
  ~zero reescrevendo named→posicional pelo **slot da nº5, que já existe** (`emit.dart:1944`).

## Custo por fase (resumo)

- **F4: ZERO nas quatro** (`_ x` mantém `name = x`; label não é nome).
- **F2**: A=0, B=0, C=1 produção (`grammar.ebnf:213`; token `underscore` já existe —
  `token.dart:136`, `lexer.dart:340-344`) + 3º estado em `Param.label` (`ast.dart:710`, e o
  `ast.asdl` é normativo), D=**glifo novo** (slot livre e barato = modificador de `fnDecl`,
  `grammar.ebnf:207`, que já toma `static`/`override`).
- **F5**: B ⊂ C (a (C) é a (B) + 1 token — **"(B) é mais barata" é FALSO**); A = arm + tabela;
  D-decl = bit carregado-não-equiparado em `ParamType` (mesmo estatuto de `hasDefault` hoje).
- **F7**: baseline igual p/ todas (`_emitType`/`_ident`/`_call`). **(C) é a única com emissão de
  custo ZERO**: assinatura toda-posicional ⟹ `StaticTearOff` (`kernel expressions.dart:1416`)
  basta, sem adaptador — a ABI do tipo = a ABI do Kernel.

## O que cada uma IMPEDE (régua "só afrouxa depois")

- **(B) não fecha porta nenhuma** — é o superset-mínimo; toda outra é aditiva sobre ela.
- **(C)** solda "sem label" a "é valor" num glifo só (o `_` do Swift é só legibilidade); e o
  **memberwise não tem opt-out** (`field ::=` não aceita `_`, `grammar.ebnf:230`;
  `collect.dart:610` dá `label: f.name`) ⟹ sob label obrigatório, `P(1, 2)` fica ilegal **sem saída**.
- **(A)** fecha para sempre a possibilidade de o label-presença significar algo no tipo, e cria
  custo invisível (P4). Tensão máxima com "sem mágica".
- **(D)** fecha "label obrigatório sem exceção"; se o label nunca virar obrigatório, o marcador
  é sintaxe morta que não se remove.

## Bug de doc encontrado
`emit.dart:1959` diz *"Hoje `param-default` é ICE"* — **PODRE**: os 5 sítios emitem
`initializer` via `_constDefault` (`:586`, `:804`, `:927`, `:1096`, `:1213`).
