---
name: desugaring
description: Decisões técnicas da Fase 3 (Desugaring/lowering, spec 007) do Itá — modelo AST→canônica, catálogo de açúcar, fronteiras type-agnostic
metadata:
  type: project
---

# Desugaring — Itá Fase 3 (spec 007, ADR-0011)

Fase 3 = passo separado AST→AST canônica (modelo rustc AST→HIR), type-agnostic, ANTES de
binding (Fase 4). Fundamentação: Dragon 5.3 (SDD sobre a árvore de sintaxe, não sobre a
parse-tree) + 6.1 (variantes de árvore) + CI 9.5.1 (desugar `for`→`while` DENTRO do parser —
o Itá diverge: passo próprio).

## Decisão-mãe (modelo de dados)
- **NÃO** materializar um HIR paralelo inteiro (P11: nós à mão dobram; printer/visitor duplicados).
- **SIM** um único hierarquia `sealed` (a `ast.dart`), com **subconjunto CORE** = alvo do desugar,
  e invariante "nós-açúcar não sobrevivem à Fase 3" checada por **assertion pass** (não estático —
  trade-off aceito; Dragon 5.3 abençoa "walk na MESMA árvore com outra SDD").
- **Reusar `MatchExpr` (bind irrefutável) como let-in/condicional canônico** → `??`, `?.`, `!`,
  `where` NÃO precisam de nó novo. Só `?` (try, early-return) excede a expr-AST → manter nó `Try`
  canônico baixado no codegen (Fase 7), OU adicionar 1 nó block-expr. Recomendado: manter `Try`.
- **Side-table (ADR-0004) indexa os nós CANÔNICOS** (ordem 3→4→5): binding/typeck rodam sobre a
  árvore já desaçucarada. Consistente — nunca se tipa um `Try`/`where`, tipa-se o alvo.

## CORREÇÃO ao ADR-0011 (achado do relatório)
O ADR diz que `?,|>,>>,where,copy-with,currying,$0` são TODOS type-agnostic. **Falso p/ 2:**
- **copy-with** (`p.{x:1}`): expansão precisa enumerar os campos do struct → `_typeFields[type]`
  no oracle (`_compileCopyWith`, codegen.dart:10724). **Type-DEPENDENTE** → Fase 5/7. Fase 3 só
  normaliza p/ nó canônico `CopyWith`, não expande.
- **currying**/aplicação parcial: detectar sub-aplicação precisa da **aridade do callee**
  (`totalParams` no oracle `_buildCurriedClosure`, codegen.dart:11474) → binding+assinatura.
  **NÃO é Fase 3.** Mover expansão p/ pós-binding (Fase 4/5).
- **`|>`**: rewrite estrutural (`x|>f(a)`→`Call(f,[x,a])`) É type-agnostic; o dispatch
  static-vs-dynamic do oracle (`_functions.containsKey`) é concern de CODEGEN, não do desugar.

## Type-agnostic (ficam na Fase 3)
`|>`→`Call` (insere x como 1º arg); `>>`→`Closure((x)=>g(f(x)))`; `where`→match-bind irrefutável;
`$0`→scan do corpo p/ maxIndex+1 → `Closure` com params explícitos (aridade SINTÁTICA; contexto=Fase5);
`if let`→`match`; `for`→`while`+protocolo-iterador (CI 9.5.1); `?.`/`!`/`??`→match-sobre-nil/Option.
`?` (try)→match+early-return (nó `Try` retido até codegen).

## NÃO-Fase-3 (fronteiras)
`**` fica `Binary.pow` (alvo `pow` int/float = type-directed, Fase 5/7); resolução de nome=Fase 4;
exaustividade do match gerado=Fase 6 (Maranget); pureza dos `let` do `where`=Fase 6.

## Armadilhas
- **Spans/DWARF**: todo nó sintetizado propaga `offset+length`+`opOffset` do açúcar-fonte (a AST já
  carrega isso p/ `fileOffset` do Kernel). Desugar que zera span quebra stack-trace AOT.
- **Higiene**: `>>`(`x`), `for`(`_it`), `?.`/`!`(temp) introduzem binders ANTES do binding (Fase 4)
  → gensym em namespace reservado p/ não capturar. Livros NÃO cobrem — externo (Kohlbecker 1986).
- **Idempotência/passo único**: saídas são só nós core → 1 walk bottom-up (post-order, Dragon 5.2)
  basta, sem ponto-fixo. Rodar 2× = no-op (bom teste).
- **`??`/`?.` runtime-type-test vs P4 (sem mágica)**: desugar Option-unwrap embute teste de tipo
  em runtime — tensão com "sem mágica". Ruling do `ita-visionary` pendente.

## Observável (Q4)
`itac desugar --dump` reusa o `AstDumper` (S-expr, CI 5.4). Diff vs `parse --dump`: some `(where`,
`(|>`, `(try`, `(>>`; aparece `(match`, `(call`, `(closure (params "$0"))`, `(while`. Corpus
`.desugar` + oracle (padrão Fases 1-2).

## IMPLEMENTADO (2026-07-12) — decisões cravadas no código
Arquivos: `compiler/lib/frontend/desugar/desugar.dart` (transformer post-order),
`.../core_check.dart` (assertion pass `findResidualSugar`/`assertCoreForm`), driver
`desugarDump`/`runDesugar`, `itac desugar <f> --dump [--spans]`. Testes: `test/desugar_test.dart`;
fixtures `conformance/desugar/*.tu` (goldens `.desugar` gerados ao vivo pelo orquestrador).
- **Gensym**: contador POR TAG (`$x`,`$c`,`$it`), reset por passe → 1º de cada = `$…0` (CA1/CA4).
  `_dollarIndex` só casa `$`+dígitos (`$c0` tem letra → não é shorthand). Idempotente (passe 2 não
  acha açúcar → 0 gensym → dump idêntico).
- **if-expr BOOLEANO = CORE** (não vira match): mapeia 1:1 p/ `ConditionalExpression` do Kernel;
  reduzir a `match {true=>,false=>}` forçaria a máquina de decisão da Fase 6 sobre ternário trivial
  (net-negativo, P4). SÓ o if-let (`IfExpr.binding != null`) desaçucara.
- **guard-let RETIDO** (NÃO lowerado, apesar do catálogo §5.2/T004): early-return no else + binding-
  na-continuação são STATEMENTS, não cabem em `=> expr` — MESMO blocker do `Try` (RD-1, block-expr
  rejeitado). Sem CA e fora da lista do assertion → retenção é consistente. **Precisa ruling dono/spec**
  (o único item do catálogo não honrado — declarado como lacuna, não inventei lowering incorreto).
- **where = LETREC, ordenação TOPOLÓGICA** (spec 006 §3.6: ordem de avaliação = dependência, não
  textual; CA1 usa forward-ref `total` antes de `a`/`b`). BUG pego pelo coordenador (2026-07-12): a
  1ª versão aninhava em ordem-FONTE → avaliava `a+b` antes de ligar `a`/`b`. Fix: dependência
  SINTÁTICA (cabe na Fase 3 sem binding) = análise de **vars livres** (`_freeRefs`, respeita shadowing
  léxico: params de closure, patterns de arm/if-let/for, lets de bloco em ordem; DESCE em closures =
  captura) ∩ nomes-do-where; Kahn topo-sort, empate em ordem-fonte (determinístico). Só sombreia por
  binders CERTOS → over-approxima quando incerto (no máx. ciclo falso, NUNCA ordem errada). Usa NOMES
  do usuário (sem gensym/substituição — renomear exigiria Fase 4). Ciclo entre bindings (inválido pela
  spec): resto travado cai em ordem-fonte; diagnóstico preciso de where-cíclico é pós-binding (precisa
  escopos reais). 1-binding e bindings independentes = inalterados. Tipo do bind dropado (Fase 5).
- **$0-closure**: só reescreve implícita COM ≥1 `$k` (aridade = maxIdx+1, scan sintático que PARA em
  closure aninhada). Sem `$k` → permanece implícita (aridade é contextual, ex.: `map { g() }` exige 1
  arg mas usa 0 — forçar arity-0 seria errado; Fase 5 resolve). Param `$k` herda span da 1ª ocorrência.
- **opt-chain aninhado** vira matches ANINHADOS (não "achatado 1×"): correção-preservada (single-
  optional mantido); flatten é otimização deferida.
- **`for` RETIDO como core** (ruling dono 2026-07-12, Opção 1 — reverte o for→while inicial): o Dart
  Kernel tem `ForInStatement` nativo → a VM itera de graça (Grupo B); Dragon 6.1 (não lowerar além do
  que o backend oferece; CI 9.5.1 só lowera por falta de primitivo no tree-walker). `for` (sync E async,
  `isAwait` preservado) vira pass-through no desugar (só desce em iterable/body); codegen (Fase 7) emite
  `ForInStatement`. Protocolo Itá-próprio (trait `Iterator.next()->Option<T>` + ponte Iterable-Dart) = débito
  de roadmap (rejeitado agora: aditivo em 3 camadas + reintroduz blocker RD-1 no `.none=>break`). `for.desugar`
  ≈ `for.ast` (`(for (bind "x") (id xs) (block …))`; corpo/iterável internos desaçucaram).
- **Retidos SEM flag no assertion**: `Try`, `CopyWith`, `Binary.pow`, if-expr booleano, `GuardLetStmt`,
  `ForStmt` (sync/async). Assertion acusa: `??`/`|>`/`>>`, `OptChain`, `ForceUnwrap`, `WhereExpr`, if-let.
