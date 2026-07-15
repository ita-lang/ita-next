# Memória — compiler-craftsman (Itá / ita-next)

Índice. Detalhe nos arquivos-tema; aqui só ponteiros de uma linha.

## Semântica / Tipos (Dragon Book cap 6)
- [Spec 011 — dispatch + membros de extension/impl](dispatch_members.md) — tabela do ALVO (6.3.6); dispatch não mata o 1-walk (overload sim); `for` não precisa de `Iterator`; corte 011/012/013.

## Parsing / Sintaxe (Dragon Book cap 4–5, CI cap 6)
- [Spec 006 — where-expr + operadores tipados](parsing_where_typed_ops.md) — WhereExpr nível 0; op:string→enum fechado; símbolo no printer; divergência `~`; códigos where-*.
- [Inventário dump Tag→enum→símbolo](dump_preservation_inventory.md) — tabela que garante S-expr byte-idêntico após migração de operadores.
