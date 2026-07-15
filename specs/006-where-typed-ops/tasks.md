# Tasks 006: where-expr + operadores tipados (preparação Fase 3)

> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler`. Sem codegen.
> **Invariante crítica:** o dump NÃO muda — todos os goldens 001–005 permanecem byte-idênticos (a migração de operadores é invisível ao S-expr).
> **Regras:** `ast.dart` à mão (P11); **sem git durante subagente ativo**.

## Parte 1 — `where`-expr

- [ ] T001 `ast.asdl` — `expr += WhereExpr(expr value, stmt* bindings)`.
- [ ] T002 `ast.dart` — `WhereExpr extends Expr`.
- [ ] T003 `ast_printer.dart` — `(where VALUE binding…)` (bindings via `_stmt`).
- [ ] T004 `parser.dart` — nível 0: `_expression() => _where()`; `_where()` = `_assignment()` + `( "where" "{" (letStmt)+ "}" )?`; só aceita `let`/`var` no bloco (senão `parse-error: where-binding-not-let`). Um `where` por expr (2º `where` = erro).
- [ ] T005 `grammar.ebnf` — `expression ::= whereExpr`; `whereExpr` no §10.

## Parte 2 — operadores tipados (enum fechado)

- [ ] T006 `ast.asdl` — `binaryOp`/`unaryOp`/`assignOp` sums; `Binary`/`Unary`/`Assign` passam a usar o enum.
- [ ] T007 `ast.dart` — enums `BinaryOp`/`UnaryOp`/`AssignOp`; campos `op` tipados. Helper `symbol` (enum→String) OU tabela no printer.
- [ ] T008 `ast_printer.dart` — mapear enum→símbolo (dump idêntico). **Nenhum símbolo cru na AST.**
- [ ] T009 `parser.dart` — converter `Tag`→variante do enum em CADA ponto que hoje passa string a `Binary`/`Unary`/`Assign` (cascata + `_unary` + `_assignment`). Um helper `_binaryOpFor(Tag)` centraliza.

## Conformância + testes + gate

- [ ] T010 `conformance/valid/expr_where.tu` (CA1), `.tu` sem where p/ CA2 (reusar existente), `conformance/invalid/where_binding_not_let.tu` (CA3, `// EXPECT`).
- [ ] T011 `parser_test.dart` — `WhereExpr` shape; `where` sem binding-let → erro; **exaustividade** (constrói cada variante de `BinaryOp`/`UnaryOp`/`AssignOp`; um `switch` sem `default` compila).
- [ ] T012 `dart analyze` limpo + `make test` verde + **diff dos goldens 001–005 = vazio** (dump preservado).
