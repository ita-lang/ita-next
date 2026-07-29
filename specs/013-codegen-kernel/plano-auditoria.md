# Plano de auditoria da F7 — provar cada afirmação, não confirmar o que já passa

> **Regra única:** cada teste tem de ser capaz de FALHAR. Se um comportamento
> estiver errado, o teste quebra — nada de bypass, nada de asserção complacente.
> Um teste que passa com o código errado não é teste, é decoração.

**Método:** para cada área, listar o que a emissão AFIRMA (na spec, no comentário
do código, ou no commit) e escrever o caso que a nega. Onde o comportamento certo
não é observável por stdout, usar efeito colateral (`print` dentro de `fn`) — é a
única forma de ver ORDEM e CURTO-CIRCUITO.

---

## Lote 1 — Semântica observável (o que nenhum golden de valor pega)

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 1.1 | Argumentos avaliam da ESQUERDA para a DIREITA | `f(a(), b())` com efeito em cada um |
| 1.2 | `&&` curto-circuita: o direito NÃO roda se o esquerdo é `false` | efeito no lado direito |
| 1.3 | `\|\|` curto-circuita: o direito NÃO roda se o esquerdo é `true` | idem |
| 1.4 | `if`-expr avalia SÓ o ramo tomado | efeito nos dois ramos |
| 1.5 | `match` avalia SÓ o braço que casa | efeito em cada braço |
| 1.6 | O subject do `match` avalia UMA vez | (já coberto em `match_option.tu`) |
| 1.7 | `??` avalia o default SÓ quando o esquerdo é vazio | efeito no default |
| 1.8 | Operandos de binário avaliam esquerda→direita | `a() + b()` |

## Lote 2 — Aritmética e as armadilhas de tipo

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 2.1 | `/` de Int é truncada (`~/`), não vira double | (coberto: `arith_int.tu`) |
| 2.2 | `/` de Float é real (`/`) | (coberto: `arith_float.tu`) |
| 2.3 | `/=` segue a mesma regra por tipo | (coberto: `var_assign.tu`) |
| 2.4 | `%` de Int e de Float | valores com resto |
| 2.5 | `-x` usa `unary-`, não `0 - x` | negativo de expressão |
| 2.6 | Precedência preservada: `1 + 2 * 3 == 7` | associatividade e precedência |
| 2.7 | `==` de String compara VALOR, não identidade | duas strings iguais construídas |
| 2.8 | `==` de enum compara variante | (coberto: `enum_simples.tu`) |

## Lote 3 — Variáveis e escopo

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 3.1 | `let` que lê `let` anterior | ordem de inicialização |
| 3.2 | Shadowing em bloco aninhado | mesmo nome, escopos distintos |
| 3.3 | `var` mutado dentro de `if` persiste fora | (o `if`-statement existe?) |
| 3.4 | Param é imutável (F5 barra) | (coberto por teste da F5) |

## Lote 4 — Funções

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 4.1 | Recursão profunda funciona | fatorial/fibonacci com N maior |
| 4.2 | Forward-reference | (coberto: `fn_call.tu`) |
| 4.3 | Label externo ≠ nome interno | (coberto) |
| 4.4 | Default saltável, inclusive do MEIO | (coberto: `default_saltavel.tu`) |
| 4.5 | `Void` não rende valor | fn Void em ExprStmt |
| 4.6 | Argumentos named chegam no param CERTO | dois params de mesmo tipo, valores distintos |

## Lote 5 — Tipos nominais

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 5.1 | `struct` é valor: cópia inobservável | (coberto: `class_ca3.tu`) |
| 5.2 | `class` é referência: mutação compartilhada | (coberto) |
| 5.3 | Campo de struct é `final` no `.dill` | inspeção estrutural |
| 5.4 | Campo `var` de class é mutável | (coberto) |
| 5.5 | `self` lê e chama | (coberto: `metodo_self.tu`) |
| 5.6 | Struct aninhado | (coberto: `struct_valor.tu`) |
| 5.7 | Método com param named | (coberto) |

## Lote 6 — match, todas as famílias

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 6.1 | Option: `.some`/`.none` | (coberto) |
| 6.2 | Escalar: Int/Float/String/Bool | (coberto: `match_escalar.tu`) |
| 6.3 | Range: bordas `..` × `..=` | (coberto) |
| 6.4 | Enum-payload: destrói e rende | (coberto: `enum_payload.tu`) |
| 6.5 | Produto: testa campo e liga | (coberto: `match_produto.tu`) |
| 6.6 | Variantes homônimas em enums distintos | (coberto: `metodo_self.tu`) |
| 6.7 | O braço ERRADO nunca casa | ordem dos braços importa |

## Lote 7 — Result, Option e propagação

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 7.1 | `?` propaga e CORTA o fluxo | (coberto: `result_try.tu`) |
| 7.2 | `??` só avalia o default quando precisa | **Lote 1.7** |
| 7.3 | `!` panica em `nil` | caminho infeliz com exit code |
| 7.4 | `?.` encadeia | (coberto: `optional_chain.tu`) |

## Lote 8 — panic e exit

| # | Afirmação | Como quebrar |
| :-: | :-- | :-- |
| 8.1 | `panic` sai com 255 e mensagem no stderr | (coberto: `panic_exit.tu`) |
| 8.2 | `!` em `nil` também panica | fixture com EXPECT-EXIT |
| 8.3 | stdout ATÉ o panic é preservado | (coberto) |

---

## Status

Preenchido conforme os lotes rodam. **Achado = bug até prova em contrário.**
