---
name: f6-flow-check
description: Parecer W1 da spec 014 (F6 flow-check) — syntax-directed à JLS (não CFG/Dragon 9.2), um walk com 3 fatos entrelaçados, Maranget adaptado ao ast.asdl (pat-list por comprimentos), (e) já pago na F4, Assign:Void como economia, pureza where≡globais.
metadata:
  type: project
---

# Spec 014 — F6 (flow-check): o parecer W1 (2026-07-16)

## Decisões técnicas e fontes
- **Definite-return = predicado estrutural `completesNormally`, NÃO CFG.** JLS §14.21 (indução
  estrutural, define reachability e can-complete-normally JUNTOS) + §8.4.7 (erro se corpo PODE
  completar normalmente). Go spec §Terminating statements idem. Dragon **9.2 é otimização-grade**
  (fixpoint/CFG) — só com goto/labels. A F6 inteira é **SDD L-atribuída** (Dragon 5.2.4/5.5);
  `completesNormally` = atributo sintetizado (5.1.1).
- **UM walk, TRÊS fatos entrelaçados:** completesNormally ⊗ DA (JLS §16) ⊗ reachability. Não são
  passes paralelos: DA-após-stmt-que-não-completa = ⊤ (verdade vácua, JLS 16).
- **Simplificações estruturais do Itá (registrar na spec):**
  - Braço de match é EXPRESSÃO (RD-1) ⟹ definite-return **nunca desce em braço**; só o TIPO do
    match importa (Never via join, `check.dart:1468`). O caso Java "all arms return" não existe.
  - §12-7 (let-requires-value na gramática) matou a metade "definitely unassigned" do JLS 16 —
    só `var` entra no domínio DA.
  - **`Assign : Void`** (recomendei; ruling embutido no dedo-F5) ⟹ Assign nunca em posição Bool ⟹
    os conjuntos bivalentes when-true/when-false do JLS 16.1 ficam DESNECESSÁRIOS. Precedente
    Swift/Rust/Go.
- **guard-must-exit = MESMO predicado, novo sítio** (Swift TSPL Early Exit — assinado).
  **while-true**: carve-out SÓ para `BoolLit(true)` sintático (sem const-fold — assinado).
  **Never-reachability**: type-informed via side-table nº1 (precedente Kotlin Nothing — assinado).
  **Closures**: criação = USO de todo `var` capturado (`capture-before-assign`); assign dentro não
  flui pra fora. Precedente C# spec. F4 já dá `crossedFn` (`resolver.dart:119`).
- **Maranget no ast.asdl:** tabela de normalização superfície→construtor. `T?`={some,none};
  Bool finito; Int/String/Float infinitos (Float literal NUNCA conta — assinado); RangePattern tem
  endpoints Int-LITERAIS por construção (`parser.dart:1859`) ⟹ interval-splitting decidível;
  record/struct = produto (assinatura tamanho 1, S expande campos na ordem declarada);
  **pat-list = família List_n + List_{≥k}** — especializar por comprimentos 0..m + representante >m
  (m = maior aridade fixa da coluna). Adaptação assinada; precedente rustc usefulness (slice).
  Fecha com ω OU rest cobrindo [k,∞) + comprimentos <k cobertos.
  Redundância = mesma U (q = linha i vs anteriores NÃO-guarded; guarded pode ser query).
  **Testemunha obrigatória no erro** (a recursão de U a constrói). `wildcard-covers-known-variants`
  sai da mesma especialização.
- **(e) break/continue: JÁ PAGO NA F4** (`resolver.dart:368-371`, reset fn-boundary `:295-297`,
  CI 11.5.1 literal). 014 só re-roteia normativamente (004 §177 → F4) + fixture da fronteira de
  closure (não vi coberta). Parser NÃO: legalidade cruza fronteira de FUNÇÃO (binding, não gramática).
- **Globais:** grafo de deps + Tarjan SCC = F6 (`global-init-cycle` com ciclo nomeado); 3 modelos
  (Go dependency-order / textual / lazy-Dart) — **Go não transplanta limpo: Itá tem top-level stmts
  com efeito, Go não**. Modelo B tem furo (fn chamada lendo global posterior ⟹ exige o mesmo fecho
  transitivo do A). **Acoplamento-chave: pureza de initializer de global ≡ pureza do where** — se
  puro, lazy×eager inobservável ⟹ modelo C quase grátis. Ruling do dono.
- **Pureza where — 4 opções mapeadas, sem decidir:** (1) proibir primitivos sintáticos de efeito
  (Assign/Panic/Await/Emit/Spawn — conjunto FECHADO, sem FFI, print é o único IO) — furo só
  interprocedural; (2) proibir Call — mata o where; (3) ordem topológica-determinística COMO
  semântica (006 §3.6 já diz letrec; Kahn+empate textual já existe, `desugar.dart:507-509`) — zero
  código; (4) sistema de efeitos (Lucassen & Gifford 1988 — lacuna declarada). Natural: 1+3.
  where-cíclico preciso = MESMO módulo SCC dos globais.
- **Arquitetura:** `frontend/analysis/`; entregáveis F7 = **nº8 globalInitOrder** (ou marca lazy) +
  **nº9 flowFacts** (completesNormally por corpo — F7 precisa p/ throw-defensivo de fim-de-corpo,
  Kernel verifier não checa, CFE emite ReachabilityError no caso análogo). **Exaustividade SEM
  side-table** — gate de fase; armazenar = "campo de rota" que a 009 §4.6 recusou (P4).
- **Reparo Assign = DEDO NA F5 dentro da 014** (precedente 013 §7.6 print): não é escopo novo —
  `assign-to-immutable` JÁ consta da 009 §4.8 (dívida), F4 o deferiu (`resolver.dart:465`);
  é pré-condição do DA. `+=` SOBREVIVE ao desugar (`desugar.dart:468-469` preserva op) ⟹ tipar
  como `x = x + e`.
- **Severidade unreachable/braço-morto: mapeado, escolha do dono.** Java=erro (com a cicatriz do
  if-then p/ conditional compilation); modernos=warning. Argumento pró-erro no Itá: sem #if, morto
  nunca é intencional + coerência com exaustividade-é-erro. Severidades podem divergir entre os dois.

## Alternativas rejeitadas
- CFG explícito: custo sem retorno em linguagem estruturada; as NORMAS (JLS/Go) são estruturais.
- Mover break-outside-loop pro parser ou F6: pago na F4, e a fronteira de fn é contexto de binding.
- Side-table "matches exaustivos": informação derivada 2× (P4, precedente 009 §4.6 anti-rota).
- Spec própria pro reparo do Assign: overhead p/ ~1 seção de dívida já prometida na 009.

## Blueprint do flow-walk (2026-07-17) — o que cravei ALÉM do W1
- **`analyzeFlow(CheckResult, resolution)`** — `resolution` é parâmetro porque o `CheckResult`
  NÃO a carrega (`driver.dart:283-299` a descarta — a doença que a 011 matou). Driver:
  `flowProgram` recompõe; **F7 vai precisar do mesmo mapa** (VariableGet) → promover a contrato lá.
- **Comando NOVO `itac flow`** (check intocado): disciplina fase-por-comando + o corpus
  `conformance/check/` tem fns non-Void sem return (`err_try.tu:14`) — dobrar F6 em `check`
  quebraria fixtures da F5 retroativamente. Gate real fica no futuro `itac build`.
- **`bool _stmt(s)` cru** (não record): completes é o único sintetizado puro; DA = estado mutado
  com cópia só em branch (o desenho do javac Flow.java). **⊤ nunca é estado**: braço que não
  completa é NEUTRO do ∩ (omissão/null local); pós-morte o walker PARA — o estado-⊤ nunca vive.
- **Anticascata unreachable = 1 bit** (`_unreachableReported`, recovery à javac): reporta o 1º
  morto, para de walkar o bloco, retorna completes=false (a VERDADE — evita missing-return junto);
  o pai vê o flag em pé e não re-acusa (`{ return; x } y` = 1 erro). Flag limpa quando um stmt
  completa. Morto-dentro-de-morto nunca é walkado.
- **while-true DA: JLS §16.2.10** — `_LoopCtx { sawBreak, breakDAs }` empilhado por loop (zera em
  closure); DA-após-while-true = ∩ breakDAs (deixa verde `var x; while true { x=1; break }; usa(x)`).
  Para while comum colapsa em DA-após-cond (não computa).
- **Closure**: obrigação NA CRIAÇÃO p/ toda ocorrência capturada (spec verbatim — **mais estrita
  que C#**: write-only `{ x = 1 }` também erra; delta anotado, relaxar é compatível). Detector =
  `LocalRes.captured ∧ binder ∈ domínio` (F4 pagou); DA inicial do corpo = DA da criação (C#);
  span do erro = 1º Ident capturador (formato sem payload — apontar o Ident nomeia a var);
  pós-erro os capturados entram no DA (anticascata); restaura DA+loop na saída.
- **Never estendido a LetStmt/EmitStmt** (`let x = panic("TODO")` não completa — Kotlin, mesma
  nº1); **Never aninhado NÃO propaga** (`x = panic(..)` completa — Assign:Void; JLS-fiel,
  recusa documentada). Braço de match/IfExpr com body:Never = vácuo no ∩ do DA.
- **missing-return cobre Closure BlockBody** (`exprTypes[closure].ret`) e **isenta asyncStar**
  (stream rende por emit; fim-de-corpo fecha o stream). `returnType == null` ⟹ Void ⟹ isento.
- **flowFacts nº8**: chave = `FnDecl | InitDecl | Closure` (donos de BlockBody; `=>` fora — vira
  ReturnStatement na F7); valor `bool` cru; total SÓ em programa verde (morto não é walkado).
  Observável: `--dump-facts` → golden `.facts` (fixtures verdes exigem zero erros + dump igual).
- **`self-in-field-default` é sintático**: scan por `SelfExpr` na subárvore do default — completo
  porque a F4 não injeta campos no escopo (self sempre explícito, P4); a F4 RESOLVE self ali
  (`resolver.dart:249-255`) — a proibição é genuinamente F6. Erro por ocorrência.
- **Domínio DA**: só `var`; `let x` sem valor morre no PARSER (`let-requires-value`,
  `parser.dart:700`; `ast.asdl:86`: value==null ⟹ isVar+BindPattern). Chave = nó-binder
  (`Set.identity`), o mesmo domínio de `LocalRes.binder`/nº6. Escopo é GRÁTIS (identidade única
  por decl — entrada vazada é inerte; zero pilha de escopos na F6).
- **Assign:Void colhido**: operando de `&&`/`||` não pode conter Assign (not-bool na F5) ⟹ zero
  cópias de DA em curto-circuito; os únicos merges são if/IfExpr/match.
- **Todos os 13 Stmt sobrevivem ao desugar 1:1** (`desugar.dart:179-229`) — tabela sem N/A;
  açúcar de Expr que nunca chega: coalesce/pipe/compose/if-let/opt-chain/where (where → match
  aninhado, `desugar.dart:576-585`).
- **Lacuna roteada (L3)**: `self` em default de PARÂMETRO resolve na F4 (`resolver.dart:272-288`
  + `:300-302`) e nenhuma spec proíbe — Kernel não tem `this` ali. Irmão órfão do
  `self-in-field-default` → pergunta ao dart-vm-expert + nota de spec do dono.
