---
name: garantias-fantasma
description: Auditoria 2026-07-29 — inventário das garantias inter-fase citadas em comentário (22 reais, 3 fantasmas de dano (c), 5 citações de sítio podres); a raiz é o contrato F5→F7 não carregar DOMÍNIO das side-tables
metadata:
  type: project
---

# Garantias-fantasma entre fases (auditoria do CASO A generalizado)

## O achado-mestre: a nº1 NÃO é total

`type_table.dart:468-471` declara *"**Totalidade** é invariante (§7-4): todo nó de expressão tem
entrada"*. **Falso como universal.** `check.dart:816` (`exprTypes[e] = t`) é total sobre o
**VISITADO**, não sobre a árvore. A F5 não desce em:
`InitDecl` body (`check.dart:293-294`, `:315-316`) · `OperatorDecl` (`:318-319`) · defaults de
payload de enum (`flow.dart:233-235` o documenta).

A F7 **emite** o corpo do `init` (`emit.dart:920-937`, via `_class`→`_initCtor`) ⟹ toda afirmação
"a F5 provou" dentro de `_expr` é falsa nesse caminho. `Map[k]` devolve `null` para "ausente" e
para "não-visitado" — indistinguíveis. Consequência concreta: `self.x = a / b` com `Float` emite
`~/` (`_arithOpFor(div, null)` → `arithOps[div]`, `emit.dart:1660-1663`), sem ICE.

## Os 3 de dano (c) — produzem artefato errado

1. **domínio do `init`** (acima).
2. **`return` nu em fn `-> T`** — `emit.dart:1247-1248` afirma que a nº8/`missing-return` barra.
   Não barra: `check.dart:392-395` só checa `value != null`; `flow.dart:386-388` devolve `false`
   sem olhar o valor; `missing-return` (`flow.dart:315-320`) é "completa normalmente" (JLS §8.4.7),
   que um `return` nu satisfaz. Nem `verifier.dart:1093-1111` nem `type_checker.dart:1224-1236`
   (só entra se `expression != null`) pegam.
3. **default de payload de enum DESCARTADO** — `emit.dart:570-574` lê `p.defaultValue` para
   `isRequired` e **não** passa `initializer`; os outros 4 sítios chamam `_constDefault`
   (`:791`, `:914`, `:1083-1085`, `:1198-1200`). F5 permite saltar (`check.dart:1318`
   `hasDefault`) ⟹ `null` num named non-nullable.

## Citações de SÍTIO podres (o vetor exato do caso A)

`emit.dart:1445`→`check.dart:1629-1634` (real: `1748-1752`) · `check.dart:741`→`resolver.dart:595`
(real: `619`) · `check.dart:1043` e `:1204`→`resolver.dart:203-204` (real: `225-228`) ·
`match_analysis.dart:394`→`check.dart:624-632` (real: `667-675`).
Exatas: `collect.dart:645`, `check.dart:65-68`, `ast.dart:510`, `ast.dart:634`, `scope.dart:45`,
`scope.dart:51-54`, `resolver.dart:71-75`.

## O mecanismo desenhado (não implementado)

`tools/check-guarantees.sh`, irmão-catraca do `check-citations.sh` (que cobre `§âncora` e NÃO cobre
código-de-erro nem `arquivo.dart:N`). Índice = `_err(At)?\('<kebab>'`/`FlowError\(`/`BindingError\(`
→ código↦arquivo↦FASE (por diretório). Regras: **G1** garantia cita código inexistente ·
**G2** código sem fixture/teste negativo · **G3** fase citada ≠ fase do sítio · **G4** `arquivo.dart:N`
sem identificador-âncora em backticks dentro de `[N-3,M+3]` (imune a drift). Escape `GUARANTEE-OK:`.
Fora do grep: **G5** gate de DOMÍNIO (`_expr` abre com `if (!check.exprTypes.containsKey(e)) _ice('untyped-…')`
+ ledger `domain-gaps.baseline`) e **G6** preservação de tipo (versão viável de translation validation).

Fundamento: Dragon **§5.1.1/§5.2.1** (SDD bem-definida / grafo de dependências = "o atributo tem
domínio") e **§1.2/§2.7** (tabela de símbolos como interface entre fases, já citado corretamente em
`type_table.dart:498-503`); Nystrom **§11.4** (o consumidor tem de walkar o MESMO conjunto que o
produtor). **Lacuna declarada:** pré/pós-condição assertada entre fases é *Design by Contract*
(Meyer 1988/1997 cap. 11), fora dos dois livros; *translation validation* (Pnueli TACAS 1998,
Necula PLDI 2000) cobre o EFEITO, não a garantia, e exige semântica formal da fonte que o Itá
não tem — colapsa em G6.

Ver [[fase7-causa-raiz-recomputacao]] (regra 4 = G6), [[fase7-auditoria-emit]], [[f6_flow_check]].
