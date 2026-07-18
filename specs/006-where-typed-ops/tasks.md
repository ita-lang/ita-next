# Tasks 006: where-expr + operadores tipados (preparação Fase 3)

> **Status:** ✅ **IMPLEMENTADA** — débito de bookkeeping fechado na auditoria de 2026-07-17. Evidência: `WhereExpr` (`ast.dart:562`, `parser.dart:971`, `ast_printer.dart:298`), enums `BinaryOp`/`UnaryOp`/`AssignOp` com exaustividade coberta em `parser_test.dart` (grupo "spec 006 — operadores tipados: exaustividade (CA5)"), goldens `expr_where`/`where_binding_needs_value`, dump 001–005 byte-idêntico, `make test` 790 verde. Marcação retroativa.
>
> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler`. Sem codegen.
> **Invariante crítica:** o dump NÃO muda — todos os goldens 001–005 permanecem byte-idênticos (a migração de operadores é invisível ao S-expr).
> **Regras:** `ast.dart` à mão (P11); **sem git durante subagente ativo**.

## Parte 1 — `where`-expr

- [x] T001 `ast.asdl` — `expr += WhereExpr(expr value, stmt* bindings)`.
- [x] T002 `ast.dart` — `WhereExpr extends Expr`.
- [x] T003 `ast_printer.dart` — `(where VALUE binding…)` (bindings via `_stmt`).
- [x] T004 `parser.dart` — nível 0: `_expression() => _where()`; `_where()` = `_assignment()` + `( "where" "{" (letStmt)+ "}" )?`; só aceita `let`/`var` no bloco (senão `parse-error: where-binding-not-let`). Um `where` por expr (2º `where` = erro).
- [x] T005 `grammar.ebnf` — `expression ::= whereExpr`; `whereExpr` no §10.

## Parte 2 — operadores tipados (enum fechado)

- [x] T006 `ast.asdl` — `binaryOp`/`unaryOp`/`assignOp` sums; `Binary`/`Unary`/`Assign` passam a usar o enum.
- [x] T007 `ast.dart` — enums `BinaryOp`/`UnaryOp`/`AssignOp`; campos `op` tipados. Helper `symbol` (enum→String) OU tabela no printer.
- [x] T008 `ast_printer.dart` — mapear enum→símbolo (dump idêntico). **Nenhum símbolo cru na AST.**
- [x] T009 `parser.dart` — converter `Tag`→variante do enum em CADA ponto que hoje passa string a `Binary`/`Unary`/`Assign` (cascata + `_unary` + `_assignment`). Um helper `_binaryOpFor(Tag)` centraliza.

## Conformância + testes + gate

- [x] T010 `conformance/valid/expr_where.tu` (CA1), `.tu` sem where p/ CA2 (reusar existente), `conformance/invalid/where_binding_not_let.tu` (CA3, `// EXPECT`).
- [x] T011 `parser_test.dart` — `WhereExpr` shape; `where` sem binding-let → erro; **exaustividade** (constrói cada variante de `BinaryOp`/`UnaryOp`/`AssignOp`; um `switch` sem `default` compila).
- [x] T012 `dart analyze` limpo + `make test` verde + **diff dos goldens 001–005 = vazio** (dump preservado).
