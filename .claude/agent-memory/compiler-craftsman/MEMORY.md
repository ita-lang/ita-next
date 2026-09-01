# Memória — compiler-craftsman (Itá / Dragon Book)

## Índice

### Mapa fase → capítulo
- [Mapa fases Dragon Book](fase-capitulo.md) — léxico→codegen (cap 2–6 = Kernel); fronteira em Cap 6→Dart Kernel.

### Fase 2 (Sintaxe → AST, spec 004)
- [Modelagem da AST (ast.asdl) — parecer](fase2-ast-modeling.md) — Zephyr ASDL revisado; blocker de boa-formação + ajustes forward-compat.
- [Decisões de parsing](parsing.md) — cascata de precedência (não Pratt), 8 cantos, recuperação N2; spec 005 (init/traits/guard-cond).

### Fase 4 (Binding / resolução de nomes, spec 008) — IMPLEMENTADA (2026-07-12)
- [Binding](binding.md) — side-table `Map.identity<AstNode,ResolvedName>`=nó-binder+hops+captured; resolve-a-nó (DIVERGE CI—Kernel usa objeto); two-pass módulo (letrec); dump `->L<off>^<hops>[*]`/`->T`/`->S`/`->?`; guard-let=continuação; `binder:Object` (Param não é AstNode).

### Fase 5 (Semântica / Tipos, spec 009) — A/B/D IMPLEMENTADAS (2026-07-15)
- [Tipos](types.md) — Dragon 6.3(collect)→6.5(check); **bidirecional, não HM** (funda em 5.1.1 herdado/sintetizado + Ex 6.5.2); Never/ErrorType≠Unknown; NamedType por nó-decl; exaustividade→F6 (Maranget); nulidade fecha na F5 sem flow; 6.3.4/6.3.5 (leiaute)=Grupo B; 10 armadilhas do oracle.
- [Fatia C — contextual (spec 010)](fase5-fatia-c-contextual.md) — L-atribuída=propriedade da ORDEM dos args (5.2.4b OK / Ex 5.9 é o contraexemplo); ordem de args funda em **5.2.5** (arestas implícitas), não 6.5.5; currying e `**` FORA (sem sintaxe / já pronto); `[]`=checking-only.
- [Membros — spec 011 (review W3)](fase5-spec-011-membros.md) — o que ficou fiel (subst. composta, memo, 1-walk, Ex 5.10) + 4 bloqueantes: `self` em extension=ErrorType mudo, `TopLevelRes`=BindPattern⟹StateError, `_lookup`/`_isSubtype` sem guarda de ciclo, CA73 ausente.
- [Guarda de ciclo no grafo de tipos (W1)](fase5-guarda-ciclo.md) — 2 grafos/2 disciplinas (Fig 2.37 × Fig 6.32); A3 corta a aresta; `sources()` único; kind→ciclo→resto.
- [Instanciação (∀) e subtipagem c/ type-args (W1)](fase5-instanciacao-subtipagem.md) — prefixo ∀ no `FunctionType` mata `_freeParams` (6.5.4/Alg 6.16); `_argsConform` = ponto único da variância E da terminação; S é a saída (Ex. 6.20).
- [ABI de label × `fn` como valor (4 opções, 2026-07-29)](fase5-abi-label-fn-valor.md) — o ICE não é da ABI; (D) sem marcador JÁ é o hoje; dilema forçado: ou o marcador viaja ou o `==` é transitiva.
- [Literal de coleção não-vazio (W1 2026-08-31)](fase5-literal-colecao.md) — `[1,2,3]` = aplicação de `∀α. α×…×α→List<α>` (6.5.1+6.5.4+Alg 6.19), NÃO `_join` nem first-fixes; síntese antes da emissão (gate I3 + `typeArgument`); `let x: Int = []` não erra hoje.
- [O CHÃO — spec 012 (design W1)](fase5-spec-012-chao.md) — `.length`/`[]`/`+` de built-in: **3 sítios** (`_member`/`_index` novo/`_binary`), tabela field-only monomórfica por shape; `Index` hoje=`cannot-infer` (não gate); out-of-bounds=F7; F5 só tipa, nº3 é de user-member; totalidade da nº1 no `_index` (buraco Str-parts).

### Fase 6 (Flow-check, spec 014) — 1º lote IMPLEMENTADO; W3 feito (2026-07-17)
- [F6 — rulings + W3 do flow-walk](f6_flow_check.md) — W3=APROVA C/ EMENDAS: buraco Str-parts da F5 (nº1 não-total⟹crash I2) é O bloqueante; anticascata por sub-região=norma; nº8 parcial (Init/Operator/payload/globais)→ledger; const-eval D-V1 pendente (lote 2).

### Fase 7 (Codegen → Kernel) — spec 013
- [Conformance de traits — lowering](fase7-conformance-lowering.md) — espaço merge/witness/box/mono/orphan c/ precedentes; Kernel sem fat-pointer⟹witness=box; coerência=(tipo,NOME); parecer p/ ADR proposed.
- [LT-F7a — esqueleto executável (W1)](fase7-codegen-skeleton.md) — CodegenVisitor S-atribuído (6.4, subárvore não 3-addr); isFinal=EQUIVALÊNCIA bidirecional (oracle só faz 1 sentido); driver CommandRunner passthrough; PT-BR override `usage`.
- [Debate ordenação LT-F7b × offset 2º (2026-07-26)](fase7-ltf7b-ordering.md) — LT-F7b (promover `resolution` a campo) PRIMEIRO: prereq duro de §7.4, custo assimétrico; offset-2º quer o 1º `let` real antes.
- [Auditoria do `emit.dart` (2026-07-29)](fase7-auditoria-emit.md) — F5 não valida `StructPattern.typeName`; `none/some/ok/err` não são reservados; two-pass só existe p/ `fn` (tipos ICEiam).
- [CAUSA RAIZ da F7 (2026-07-29)](fase7-causa-raiz-recomputacao.md) — os 5 defeitos são UM: a emissão recomputa fato já provado, com chave mais fraca; 5 regras mecânicas + taxonomia de ICE.

### Garantias inter-fase (2026-07-29)
- [Garantias-fantasma](garantias-fantasma.md) — a nº1 NÃO é total (`init`/`operator`/payload não são visitados); 3 fantasmas de dano (c); 5 citações `arquivo.dart:N` podres; desenho do `check-guarantees.sh` (G1–G6).

### Auditoria do front-end (2026-07-17)
- [Auditoria F1→F6](audit-frontend-2026-07.md) — placar por fase (F1–F5 ✅, F6 ⚠️ lote 1 só); ordem CORRETA; **gate F6→F7 = exaustividade Maranget NÃO implementada** (0 no código, só blueprint) trava o `match` da F7.

### Fase 3 (Desugaring / lowering, spec 007) — IMPLEMENTADA (2026-07-12)
- [Desugaring](desugaring.md) — AST→canônica no MESMO hierarquia (não HIR paralelo); reusa MatchExpr; copy-with/currying NÃO são type-agnostic (correção ao ADR-0011). Decisões: if-expr-bool=core, guard-let+for RETIDOS, where=letrec (topo-sort), $0-closure só com $k.
