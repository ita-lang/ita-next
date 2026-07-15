---
name: dump-preservation-inventory
description: Tabela Tag→enum→símbolo que garante o dump S-expr byte-idêntico após a migração op:string→enum (spec 006). Referência para futuras migrações.
metadata:
  type: reference
---

# Inventário Tag → enum → símbolo (dump preservado — spec 006)

A migração `op:string`→enum é invisível ao S-expr se e só se este round-trip é identidade. Fonte da tag no dump = `ast_printer` (`_binarySym`/`_unarySym`/`_assignSym`). Conversão Tag→enum = `parser` (`_binaryOpFor`/`_assignOpFor` + variantes diretas nos níveis mono-op).

## Binary (17)
`pipeGt→pipe→|>` · `gtGt→compose→>>` · `questionQuestion→coalesce→??` · `pipePipe→or→||` · `ampAmp→and→&&` · `eqEq→eq→==` · `bangEq→ne→!=` · `lt→lt→<` · `gt→gt→>` · `ltEq→le→<=` · `gtEq→ge→>=` · `plus→add→+` · `minus→sub→-` · `star→mul→*` · `slash→div→/` · `percent→mod→%` · `starStar→pow→**`
(mono-op via variante direta: `??`→coalesce, `||`→or, `&&`→and, `**`→pow)

## Unary (3)
`bang→not→!` · `minus→neg→neg` · `tilde→bitNot→~`

## Assign (5)
`eq→assign→=` · `plusEq→addAssign→+=` · `minusEq→subAssign→-=` · `starEq→mulAssign→*=` · `slashEq→divAssign→/=`

## Nós que NÃO migraram (dump próprio, não op:string)
`RangeExpr` (`..`/`..=` via `inclusive:bool`), `Await`/`Spawn`/`Panic` (nós próprios). `~` não aparece em nenhum golden `.ast` (só fixture léxico `unexpected_char`).
