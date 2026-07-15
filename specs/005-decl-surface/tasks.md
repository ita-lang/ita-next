# Tasks 005: Completar a superfície declarativa (Fase 2)

> **Spec:** [`spec.md`](./spec.md) · **Escopo:** `ita-next/compiler` (parser + AST + gramática + conformância). Sem codegen.
> **Ordem:** modelagem (ASDL→ast.dart→printer) → parser → gramática → conformância/testes → gate.
> **Regras:** `ast.dart` à mão a partir do `ast.asdl` (P11, zero codegen); dump determinístico; **sem git durante subagente ativo**; comportamento observável = `itac parse --dump` (não chutar).

## Modelagem

- [ ] T001 `ast.asdl` — `decl += InitDecl(param* params, block body)` (com `attributes`); `GuardLetStmt += expr? condition`; `StructDecl += type* traits`; `ExtensionDecl += type* traits`; `ClassDecl += type* traits` (já tem `superclass`).
- [ ] T002 `ast.dart` — materializar à mão: classe `InitDecl extends Decl`; campo `Expr? condition` em `GuardLetStmt`; `List<TypeNode> traits` em `StructDecl`/`ClassDecl`/`ExtensionDecl`. Manter construtores/ordem consistentes.
- [ ] T003 `ast_printer.dart` — dump: `(init (params …) (block …))`; guard-let com `(cond …)` quando `condition != null`; `(traits (type …)…)` quando não-vazio (após `:pub`/nome/generics, antes dos membros).

## Parser

- [ ] T004 `parser.dart` — `_initDecl()` (despacho por `Tag.kwInit` em `_member`); `_guardStmt` captura `&& expression` opcional após o `value` do guard-let; `_conformances()` helper (`: type ( , type )*`) chamado em `_structDecl`/`_classDecl`/`_extensionDecl` (class: 1º = superclasse, resto = traits). Confirmar que `async`/`stream` em membro já funciona (só documentar).

## Gramática

- [ ] T005 `grammar.ebnf` §8 — reconciliar: `member` com `initDecl` + `("async"|"stream")?`; `initDecl` nova produção; `structDecl`/`classDecl`/`extensionDecl` com `( ":" type ("," type)* )?`; `enumMember` com `("async"|"stream")?`; remover `(DEFER)` de conformance e de `assoc` no `operatorDecl`.

## Conformância + testes (§11)

- [ ] T006 `conformance/valid/` — CA1 `decl_init.tu`; CA3 `decl_struct_conformance.tu`; CA4 `decl_class_super_trait.tu`; CA5 `decl_extension_conformance.tu`; CA6 `decl_member_async.tu`; CA2/CA7 `stmt_guard_let_cond.tu` (com e sem `&&`) — cada um com `.ast` conferido ao vivo.
- [ ] T007 `parser_test.dart` — unit: `InitDecl` shape; `GuardLetStmt.condition` presente/ausente; `traits` em struct/class/extension; class distingue superclasse de trait.

## Gate

- [ ] T008 `dart analyze` limpo + `make test` verde. Atualizar rodapé de débito do `ast.asdl` (fechar as 4 lacunas da revisão).
