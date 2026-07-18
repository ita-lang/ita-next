---
name: list-pattern-typing
description: W1 da LT-F6a (spec 014, dedo F5) — RATIFICO tipar ListPattern/RestPattern via t.args[0] (Dragon 6.5.1 array-access ≠ 6.3.6 member-lookup=M5); pattern-type-mismatch taxonomia; Literal/Range type-check é F5 (pré-condição I5/I2 do Maranget); nil não sintetiza.
metadata:
  type: project
---

# LT-F6a — tipar list/rest-patterns + `pattern-type-mismatch` (W1, 2026-07-17)

## A tese RATIFICADA (a distinção Dragon que mata o comentário `check.dart:542`)
- **Recuperar `E` de `List<E>` = Dragon 6.5.1 acesso-a-array** (`array(s,t) → t`): inspeção da
  EXPRESSÃO de tipo (6.3.1), casa o construtor, lê `t.args[0]`. **Zero tabela de símbolos.**
- **Resolver `.length`/`.map` = Dragon 6.3.6** (`record(t)`, lookup por NOME) — é o **chão M5**
  (`List`/`Map` sem `.tu`). Sítio real da reserva 012 = **`_member` (`check.dart:1700-1701`)**,
  intocado.
- O `:542` diz "elemento de List é membro de built-in": 1ª metade certa (`t.args[0]`), 2ª FALSA
  (elemento = argumento do construtor, não membro). **Prova pelo precedente:** `_bindEnumPattern`
  JÁ destrutura `Result` por `t.args[i]` (`check.dart:579`) e `Option` por `t.inner` (`:555`) — se
  isso fosse "membro de built-in", o P7 inteiro violaria a 012. **List pisa no mesmo chão. F5 AGORA.**

## Regra de tipo (herdado 5.1.1 — `t` desce; modo check bidirecional 008 §5.4)
- `t=BuiltinType(list,[E])`: elemento não-rest liga `E` (HOMOGÊNEO — ≠ enum/result que é `args[i]`
  posicional heterogêneo, SEM `substFor`); `..resto` nomeado liga `resto:List<E>` (reusa o objeto
  `t`); `..` sem nome nada (F4 só declara nomeado, `resolver.dart:563`).
- `t=ErrorType`: silêncio. Outro `t`: `pattern-type-mismatch`.
- **`List<E>?` (`OptionalType(list)`)**: `[a]` contra ele = **mismatch, NÃO auto-unwrap** (espelha
  `member-on-optional` `:1692`; invariante de nulidade). `[]` contra List: OK (comprimento-0 Maranget).
  Aninhamento `[[a],[b]]`: grátis (`_bindPattern` já recursivo). List INVARIANTE (zero widening).

## `pattern-type-mismatch` — taxonomia (NÃO existe hoje; criar)
Erro de USUÁRIO (forma incompatível com o tipo): (1) List/Rest contra não-List; (2) LiteralPattern
com `typeof(lit) ⋬ t` (subtipo via `_isSubtype`, NÃO igualdade — `3` casa `any Ord`; zero coerção ⟹
Int em coluna Float = mismatch); (3) RangePattern (sempre Int) contra `t` sem `Int ≤ t`.
- **Distinção de `pattern-arity-mismatch`** (`:576,600`): arity pressupõe construtor CASA, conta
  subpatterns; type-mismatch é um nível acima (construtor não pertence). **List NUNCA gera arity**
  (comprimento variável → é (in)exaustividade da F6).
- **FRONTEIRA lacuna≠usuário** (doutrina widen/max dispatch-members item 4; D5 walks_sources): lacuna
  NOSSA ≠ `pattern-type-mismatch`. Shorthand `P{x,y}` fica `pattern-binder-unsupported` (D4, `:644`);
  interpolated-string = ruling. `ErrorType` nos binders APÓS diagnóstico (anti-cascata).

## Literal/Range ganham type-check na F5 (é F5, PROVA via Maranget)
- Maranget assume matriz bem-tipada (I5 "nunca re-tipa"); incompat lá = StateError I2 (interno, não
  usuário). Logo a F5 tem de rejeitar `match 3 {"s"=>…}` ANTES. É juízo de tipo (6.5), não
  exaustividade. Muda `:537-540` de `break` mudo → `_isSubtype(_synth(lit),t)`.
- **⚠️ `nil` NÃO sintetiza** (`_synth(NilLit)=_cannotInfer` `:670`): special-case `NilLit` casa sse
  `t is OptionalType`. F5 só checa COMPATIBILIDADE; exaustividade de literal fica F6.

## Onde mexer (`check.dart`) + fatiamento
- `_bindPattern` `:544-546`: `ListPattern`→novo `_bindListPattern(n,t)` (espelha `_bindEnumPattern`,
  trata rest inline); `RestPattern` top-level→**backstop `throw`** (inalcançável: `GRAMMAR.md:255-262`
  só admite `..` como `patElem` dentro de `[...]`; contrato=throw, D5).
- Chaves JÁ pagas pela F4: elementos `resolver.dart:576-579`, rest nomeado `:562-563` (nó=chave);
  nº6 já prevê RestPattern (`type_table.dart:478`); leitor `_ident` `:899`. Zero trabalho F4/AST.
- **2 dedos, A→B:** A=list/rest (desbloqueia CA9, cria o código); B=literal/range (I5/I2 escalar,
  reusa o código). NÃO empacotar o 3º dedo (duplicate-rest/interpolated).

## PARE e leve ao dono (não bloqueia A+B)
- **duplicate-rest + rest-no-meio**: parser aceita `[a,..r,b]` e `[..a,..b]` (`parser.dart:1794-1804`
  cru). Modelo F6 (rustc prefixo+sufixo) exige ≤1 rest. (a) rest-no-meio legal? = identidade; (b)
  2-rests ilegal, qual código/fase? parser (forma pura, meu voto) vs F5. É o 3º dedo — ruling de fatia.
- **interpolated-string-pattern** (`"a${x}b"`): banir vs relaxar-a-guard = ruling. NÃO é type-mismatch.
- (menor) escrutínio `dynamic` chegando a `_bindListPattern`: política consistente com enum.

## W3 (revisão adversarial, 2026-07-17) — VEREDITO 🟢 sólido, 2 co-requisitos 🟡
- **`t.args[0]` (`check.dart:586`) é seguro GLOBALMENTE**: só 4 sítios constroem `BuiltinType`
  (`collect.dart:827`, `type.dart:495` substitute, `unify.dart:68` resolve, ctor `type.dart:164`);
  os 3 primeiros preservam/forçam aridade — `collect.dart:812` retorna `ErrorType` se `List` cru.
  Logo TODO `BuiltinType(list)` tem exatamente 1 arg. `[]` vazio ainda lê `t.args[0]` (inócuo).
- **List-literal como escrutínio NÃO estoura**: `ListExpr ∉ _synthInner` (`check.dart:738-765`) → cai
  em `_cannotInfer` → `ErrorType` → Cerca 1. `match [1,2] {…}` dá `cannot-infer` (fatia C/D), nunca crash.
- **`throw StateError` (`:565`) genuinamente inalcançável**: `RestPattern` só nasce em
  `parser.dart:1798`, DENTRO de `[...]`; `..` top-level → `throw ParseError('expected-pattern')`
  (`:1906`); e `_bindListPattern` trata rest INLINE (nunca chama `_bindPattern` nele).
- **Range endpoints são `IntLit` por construção** (`parser.dart:1854-1868`, `_consume(intLiteral)`) ⟹
  `lo`/`hi` sempre `IntType`; única variável em `_checkRangePattern` é `t`. `x..y` com vars nem parseia.
- **Aninhamento honesto**: `[[a]]`/`List<Int>` → mismatch no `[a]` INTERNO (span certo), `a` fica sem
  tipo→ErrorType absorvente (anticascata, sem 2º erro). `List<Bogus>` (arg=ErrorType) propaga por Cerca 1
  de cada sub-método. `[..r,..s]`/`[a,..r,b]`: liga todos, zero erro inventado, zero crash (ruling-dono intacto).
- **🟡 co-requisito 1 — `flow.dart:836-837` comentário ESTALE**: diz "List/Rest são
  `pattern-binder-unsupported` na F5" — o diff destravou isso. `_domainBinder` ListPattern (`:841`) é
  no-op ≠ `_mutableBinder` (check.dart:218-223, DENTRO do diff). INERTE (todo DA gated por
  `_domain.contains` `:661,689`; list-binder sempre atribuído no bind) mas o diff devia ter atualizado.
- **🟡 co-requisito 2 — interpolated-string-pattern silenciosamente checado**: `_checkLiteralPattern`
  faz `_synth(Str)` sem distinguir interp; `"a${x}b"` sinta `x`, `_str` devolve `String` (mascara erro
  interno) → aceito como literal constante. Fora da fatia B (design roteou "banir vs relaxar" ao dono),
  mas o diff DE-FACTO escolheu "relaxar+checar". Armadilha p/ F6 lote 2: a Str-Sig assume literal CONSTANTE.
- **Inerte (tentei quebrar, aguentou)**: `exprTypes[NilLit-in-pattern]` NÃO é gravado (`:603-607` retorna
  antes do `_synth`) — assimetria vs não-nil. Zero consumidor: `flow._matchExpr` não desce em pattern
  (`:865` "Patterns ficam de fora"), `_typeOf` (falha-alta) nunca é chamado em literal de pattern.
