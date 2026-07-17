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
