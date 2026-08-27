---
name: fase7-causa-raiz-recomputacao
description: F7 — causa raiz dos 5 defeitos de 2026-07-29 é UMA só (a emissão RECOMPUTA fato já provado por fase anterior, com chave mais fraca) + as 5 regras verificáveis mecanicamente que a pegariam
metadata:
  type: project
---

# A causa raiz da F7 é uma só: **recomputação com chave mais fraca**

Investigação de 2026-07-29 (5 perguntas do dono, sem consertar). Os 5 defeitos são instâncias
do MESMO gerador: a F7 **redecide** um fato que uma fase anterior já provou, e a redecisão é
menos precisa que a prova. **A F7 não decide nada — ela TRADUZ.**

| defeito | fato já provado | o que a F7 usou no lugar |
|---|---|---|
| família de `match` por lexema | `resolution` (F4) + nº1/nº3 (F5) | a STRING `.variant`/`.typeName` |
| two-pass só em `fn` | letrec do módulo (`resolver.dart:71-75`, "ordem textual não importa") | a ordem TEXTUAL de `program.body` |
| `f().n += 1` 2× | — (é o desugar) | re-`_expr` da subárvore, em vez de temporário |
| `Int+Int : num` | nº1 `exprTypes` | a assinatura DECLARADA de `num::+` |
| `while` antes de closure | ordem de `tasks.md` §Ordem-e-gate-final | a ordem do payoff visível |

## As 5 regras (todas verificáveis por máquina)

1. **Zero string de origem-usuário em posição de decisão.** Nome de plataforma (`dart:core`) é
   vocabulário FECHADO e externo ⟹ legítimo (é linkedição), e já mora no facade `_resolve*`.
   Detecção: grep-lint em `codegen/lib` + corpus adversarial de HOMONÍMIA (`enum Estado { none }`,
   `enum Resposta { ok }`) + inserção de decl MORTA (pega o flag global `_resultParts != null`).
   Forma forte: `extension type Lexeme(String)` na AST ⟹ vira erro de compilação.
2. **Shell-then-members para TODA decl nomeada, não só `fn`** (letrec/forward-decl; grafo de tipos
   é CÍCLICO por construção). Detecção: teste de PERMUTAÇÃO — todo fixture recompila com
   `program.body` REVERTIDO e tem de dar o mesmo stdout. O teste É a especificação do contrato da F4.
3. **`_expr` é injetiva por nó** (contador `Map.identity`; 2ª chamada = falha). Pega compound
   assignment, e pegará copy-with e `a[i] op= v`. Corolário: `checkNoSharedNodes` e "avaliar uma vez"
   PUXAM EM SENTIDOS OPOSTOS — a única construção que satisfaz os dois é o temporário (`Let`).
4. **Preservação de tipo**: `emitido.getStaticType() == _emitType(check.exprTypes[e])` — IGUAL, não
   subtipo. `checkNoDynamic` (ADR-0013) é o caso degenerado disso; generalizar mata 3 dos 8 bugs.
5. **Nenhuma guarda vacuosa**: passe de saneamento que aplica ZERO vezes no corpus inteiro é falso
   verde (hoje: `LocalFunctionIdAssigner`, porque closure ainda não é emitida).

## Taxonomia de ICE que escondeu o bug nº2

`ice-codegen-type-unemitted-*` LÊ como fronteira honesta e É bug interno. Régua: ICE que nomeia
**estado do emissor** (`unemitted`/`unbound`/`untyped`) é bug NOSSO; ICE que nomeia **construção da
linguagem** (`fn-generic`, `struct-private-field`) é fronteira. `EXPECT-ICE:` tem de RECUSAR a 1ª
família — fixture nunca pode *esperar* um defeito.

## Por que golden+verify eram cegos

Os 8 bugs vivem no ponto cego dos dois: `verifyComponent` = boa-formação (não checa tipo de
initializer, e **não checa alvo de `break`** — grep de `LabeledStatement` no `verifier.dart` = 0);
golden = comportamento em UM input. Os defeitos são RELAÇÕES ENTRE PROGRAMAS (renomear, permutar,
inserir decl morta) ⟹ pedem teste **metamórfico/propriedade**, não mais golden. Lacuna de livro
declarada: Dragon/Nystrom não cobrem teste de compilador — literatura externa (EMI, Le/Afshari/Su
PLDI 2014).

Fontes: Dragon **2.7.2** (papel da tabela: de declarações para usos), **2.7.1** (mesmo lexema,
declarações distintas), **2.8.3** (valor-L × valor-R), **2.8.4** Fig 2.44/2.45 + Ex 2.19 (`lvalue`
hoista `t = 2*k`), **6.3.2/6.3.6** (grafo de tipos cíclico; classe = tabela de campos), **6.4.3/6.4.4**
(`L.addr` calculado 1×), **6.5.2** Fig 6.25 (`max`/`widen` — coerção só onde a linguagem manda),
**7.1-7.4** (tempo de vida > ativação ⟹ closure); Nystrom cap. 11 (side table por IDENTIDADE;
"define o nome ansiosamente, antes do corpo" = letrec).

Ver [[fase7-auditoria-emit]], [[fase7-codegen-skeleton]], [[binding]], [[types]].
