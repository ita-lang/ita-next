---
paths:
  - "codegen/**"
---

# R2 · R3 — como a árvore é construída

Os dois invariantes de construção que nenhum golden de stdout percebe: a ordem em que as
declarações nascem (R2) e o número de vezes que uma subexpressão é emitida (R3).

## R2 — Shell antes de membro, para TODO o grafo de tipos

Toda entidade nomeada que outra possa mencionar nasce em duas fases: **shell registrado na
tabela** → membros. Vale para `struct`/`enum`/`class`/`trait`, não só para `fn` — o grafo de
declarações de módulo é **cíclico por construção** (`struct No { prox: No? }` não tem ordem
topológica), e a F4 já provou que *"ordem textual não importa"*.

**Sinal:** compilar cada fixture **duas vezes**, com `program.body` revertido na segunda.
Stdout idêntico, zero ICE. Um `ice-*-unemitted-*` sobre programa legal é **bug nosso**, não fronteira.

## R3 — `_expr` nunca roda duas vezes sobre o mesmo nó

Toda subexpressão-fonte que apareça mais de uma vez na árvore emitida tem de aparecer como
**leitura de um temporário**. `checkNoSharedNodes` (um nó, um pai) e "avaliar uma vez" puxam em
sentidos opostos; **o temporário é a única construção que satisfaz os dois** — re-emitir a
subárvore satisfaz o invariante e **cria** dupla execução.

Atinge: `obj.f op= v`, `a[i] op= v`, `??=`, `++`, e sobretudo o **copy-with `p.{x:1}`**, que
leria o receptor uma vez **por campo não-mencionado**.

**Sinal:** assert de fase — contador `Map.identity<ast.Expr,int>` na entrada de `_expr`; segunda
chamada sobre o mesmo nó falha. Fixtures de valor-L usam receptor **com efeito**
(`fn f() -> Caixa { print("[efeito]"); … }`) — golden de valor puro não percebe.
