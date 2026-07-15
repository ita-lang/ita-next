# Tasks 008: Fase 4 — Binding / resolução de nomes

> **Spec:** [`spec.md`](./spec.md) · **Formal:** `compiler/docs/spec/binding.md` · **Escopo:** `ita-next/compiler`.
> **Regras:** resolver à mão (P11); AST imutável (side-table `Map.identity`, ADR-0004); **sem git durante subagente ativo**.

## Infra
- [ ] T001 `compiler/lib/frontend/binding/scope.dart` — pilha de escopos encadeada (`Scope(parent)`, `declare`/`define`/`lookup`); `ResolvedName` (`LocalRes`/`TopLevelRes`/`SelfRes`).
- [ ] T002 `compiler/lib/frontend/binding/resolver.dart` — resolver visitor 1-walk sobre a AST canônica; `Map.identity<Expr, ResolvedName>` de saída; split declare/define; two-pass no módulo (letrec) + single-pass léxico nos blocos; context-flags (loop/fn/method).
- [ ] T003 `driver/driver.dart` + `bin/itac.dart` — `itac resolve <f.tu> --dump [--spans]` (parse→desugar→bind); função pura `resolveProgram`/`resolveDump` testável; `AstDumper` modo `--resolve` (anota `Ident`/`SelfExpr` com alvo+hops).

## Resolução (§5.3)
- [ ] T004 Escopos: `Block`/`FnDecl`/`Closure`/`InitDecl`/`MatchExpr`-arm/`ForStmt`; `Param`s e binders de pattern (destructuring liga múltiplos); `LetStmt` split declare/define.
- [ ] T005 `GuardLetStmt` = escopo de continuação; `SelfExpr`→`SelfRes` (self sintético do método); gensyms como binders ordinários.
- [ ] T006 Módulo letrec: declare-all (`fn`/tipos/globais) → resolve corpos (forward-ref/recursão mútua).

## Erros (§5.5)
- [ ] T007 `unresolved-name`, `read-in-own-initializer`, `duplicate-declaration`, `self-outside-method`, `break/continue-outside-loop`, `return/emit-outside-fn` (span + kebab-case).

## Conformância + testes + gate
- [ ] T008 `conformance/resolve/*.tu` → `.resolve` (CA1-3,7,8,10-12) + `.errors` (CA4-6,8,9) — orquestrador gera ao vivo.
- [ ] T009 `resolver_test.dart` — unit por regra; hops corretos; captura sinalizada; contrato F4↔F5 (não resolve `.field`).
- [ ] T010 `dart analyze` limpo + `make test` verde + goldens 001–007 inalterados.
