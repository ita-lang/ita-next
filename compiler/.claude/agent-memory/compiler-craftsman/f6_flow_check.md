---
name: f6-flow-check
description: Parecer W1 + blueprints da spec 014 (F6): flow-walk (lote 1, EM MAIN) e match analysis Maranget (lote 2, blueprint 2026-07-17) — Sig materializa a tabela §4; 2 dedos na F5 (list-pattern + pattern-type-mismatch) são pré-condição; FlowError ganha detail/isWarning.
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

## Blueprint do match analysis (lote 2, 2026-07-17) — Maranget §4 da spec
- **PRÉ-CONDIÇÃO: 2 dedos na F5** (estatuto do Assign §1; Str-parts do lote 1 é o precedente):
  **A)** tipar list-patterns — `check.dart:544-546` rejeita TODO ListPattern (até `[]`) com
  `pattern-binder-unsupported` ⟹ **CA9 é inalcançável hoje**; dedo = `t.args[0]` do BuiltinType(list)
  + rest→`List<E>` na nº6 (chave JÁ prevê RestPattern — `type_table.dart:477-478`) +
  `duplicate-rest-pattern` (o parser aceita 2 rests, `parser.dart:1794-1804`). **B)**
  `pattern-type-mismatch` p/ literal/range × coluna (dívida 009 §4.8 — `_bindPattern` dá `break` mudo)
  + **`interpolated-string-pattern`** (achado NOVO: pattern-string com `${…}` reparseada,
  `parser.dart:1880/1524` — "literal" não-constante que a tabela §4 não previu; banir, relaxável a
  guard). Pós-dedos, incompatibilidade na matriz = StateError (backstop I2).
- **Módulo:** `analysis/match_analysis.dart`, chamado do `_matchExpr` do walker (`flow.dart:721`) —
  NÃO passe irmão: match em código morto NÃO analisado (anticascata; gate são: morto⟹programa
  vermelho) + match aninhado grátis pela visita recursiva. Retorna `MatchReport{diagnostics,
  deadArms}`; walker PULA braço morto no DA (correto além de anticascata: braço morto não roda ⟹
  fora do ∩ é mais PRECISO).
- **Design-centro: `Sig` selada materializa a tabela §4** — os 3 pontos de variação do U_rec viram
  `split(roots)→(toTest, residue)` + `argTypes(c)`. Enum/Option/Result/Bool = Σ-fechada; Int = átomos
  de interval-splitting (split SEMPRE total; **BigInt** — bordas de i64 wrappam no int do Dart!);
  Str = resíduo-gloss; **Float = linha evapora no D e nunca é query** (não conta, não domina);
  Produto = 1 ctor, campos na ordem declarada, omitido/hasRest→ω; List = `{Len 0..m, LenGe m+1}`
  partição total (m = max aridade fixa/k-rest da coluna; prefixo+sufixo à rustc); `Never` =
  **EmptySig, ω não-útil** (match vazio exaure Never); resto Opaque. Coluna dirigida pelo TIPO
  (nº1 + nº2 + substFor/substitute — I5: a matriz nunca re-tipa).
- **U devolve a testemunha** (`List<Wit>?`, null=não-útil); o resíduo do split É a testemunha-cabeça;
  printer em sintaxe de superfície (`.some(.none)`, `[_, _, ..]`, `P { x: .off, .. }`); texto
  normativo CA3 "`<termo>` não coberto"; Int concreto (`-1`/`10` p/ `0..=9`).
- **Nomes cravados:** `match-not-exhaustive` (span = MatchExpr) e `unreachable-match-arm` (span =
  arm.pattern — MatchArm não é AstNode, como Param). Guard: nem matriz nem query (I6 — DoD "guard
  nunca acusado"; **delta anotado vs JLS §14.11.1**, que ACUSA guarded dominado). Range vazio
  (`5..5`/`9..3` parseiam) ⟹ morto por vacuidade.
- **`FlowError` ganha `detail:String?` + `isWarning:bool`** — format `… — <detail>`, prefixo
  `flow-warning:`; `hasErrors=any(!isWarning)` (espelho CheckResult `type_table.dart:506-507`; delta
  deliberado vs CheckError.format, que não distingue warning). Zero quebra do lote 1: runner casa
  `e.code`, goldens são `.facts`; detail testado em UNIT, não no `// EXPECT-FLOW:`.
- **`wildcard-covers-known-variants` roteado à F6** (a F5 nunca o emitiu — 0 ocorrências em
  check.dart; 009 ganha nota datada): braço ω top-level, unguarded, VIVO, coluna EnumSig de enum
  DECLARADO (só ele — a razão é "adicionar variante"; Bool/T?/Result não ganham variantes);
  engolidas = `{v ∈ Σ | U(rows<i, v(ω…)) útil}`; Bind conta como ω.
- **Achados F5 roteados:** `match x {}` parseia e a F5 fica MUDA (`check.dart:1672` —
  `acc ?? ErrorType` SEM erro; F6 pega por exaustividade); `StructPattern.typeName` IGNORADO
  (`_bindFieldPatterns` usa o TypeInfo do scrutinee). **N/A com evidência:** or-pattern,
  tuple-pattern, literal negativo em pattern (`_pattern`, `parser.dart:1790-1907`, não os tem).
- Blueprint completo VERSIONADO: `specs/014-flow-check/blueprint-match-analysis.md` (2026-07-17).

## Review W3 ADVERSARIAL de `match_analysis.dart` (Fatia 1, 2026-07-17) — VEREDITO: sem 🔴
- **Terminação PROVADA (não só testada):** a recursão de `_useful` segue os PATTERNS finitos, não o
  TIPO. No ramo-Σ-completa só `_specialize` recursa; ω-rows viram ω^arity (folhas), c-rows viram
  subpatterns ESTRITAMENTE menores. Enum recursivo (`enum L{Nil,Cons(Int,L)}`), single-ctor sem base
  (`enum S{Wrap(S)}`) e mútuo A/B TERMINAM — o bind colapsa no `_default` assim que a coluna fica só-ω.
  Medida: (nº colunas)×(profundidade máx de pattern), ambas finitas.
- **§12-11 em profundidade CORRETO:** `Result<Point,E>{.ok(Point{...}),.err(e)}`→unsupported (não
  estoura, não vaza non-exhaustive); `.ok(_)`→verde; `.ok(Point{x:0})` SÓ (err ausente)→`.err(_)`
  (o ramo-INCOMPLETO decide via `_default` SEM tocar Point). `anyUnsupported` NÃO engole: só vira
  verde se NENHUM ctor lançou; testemunha concreta de qualquer ctor vence (retorno em `:371`, sound
  porque `_specialize` isola ctores). Testemunha aninhada certa: `Result<Int?,E>{.ok(.some(0)),.err}`
  →`.ok(.none)`.
- **🟡 declarados (aceitáveis, honestos — NÃO bugs):** (1) produto/list IRREFUTÁVEL sem `_` (ex.:
  `Point{x,y}=>a` sozinho, exaustivo de fato)→unsupported; aresta afiada que o usuário sente, docs
  devem avisar "struct destructure sozinho exige `_` até Fatia 3". (2) `_atomKey` dá Float chave EXATA
  (`f:val`) e PEGA `1.0,1.0` redundante — DIVERGE do texto do blueprint §3.2 ("Float nunca conta");
  sound p/ casos alcançáveis (NaN/-0.0 não parseiam em pattern); reconciliar doc×impl. (3) redundância
  de String NÃO pega (chave `u:offset:len` única por span) — incompletude honesta, nunca falsa-acusa.
  (4) Range ficou `_HStruct` conservador (`0..=9=>a`→unsupported); a PROMOÇÃO a `_HAtom` que o blueprint
  §F1.4 recomendou NÃO foi tomada (daria `non-exhaustive _`, mais informativo) — escolha de escopo.
- **Dependência de contrato EXPLÍCITA (linchpin):** a soundness de `_specialize` p/ coluna selada
  depende de F5 `pattern-type-mismatch` (`check.dart:601-618` literal por `_isSubtype`; `:629` range só
  `Int`; `nil` fora de `Optional`) + gate I3 (`driver.dart:375`). Se F5 abrir buraco, literal mistyped
  numa coluna selada seria DESCARTADO mudo em `_specialize` (`:290`) → exaustividade unsound. Hoje FECHADO.
- **`_classify` total (10 Pattern, sealed switch, analyzer limpo); `_WWild` printer imprime SEMPRE `_`
  (nunca o `.type`)** ⟹ TypeParam não vaza gensym (cerca W0 aguenta). I6/guard: guarded fora da matriz E
  nunca query; `_` unguarded depois de guarded idêntico NÃO é redundante (correto).

## Fatia 1 do match analysis — design cravado (W1, 2026-07-17)
- **Só tipos FECHADOS:** Enum/Option/Result/Bool = `SealedSig`; Never = `EmptySig` (completa por
  vacuidade — `match n: Never {}` exaure); resto = `OpaqueSig`. `_sigOf` é o ÚNICO ponto que sabe a
  família (a tabela §4 em código). Enum via `TypeInfo.variants`+`substFor`/`substitute` (idem
  `check.dart:688-690`); Option via `inner`; Result via `args[0/1]`; Bool fixo.
- **Normalização superfície→construtor mora em `_headCtor`:** `nil` = `LiteralPattern(NilLit)`
  (`parser.dart:1892`) normaliza p/ `none`; `true`/`false` = `LiteralPattern(BoolLit)` NÃO EnumPattern
  (`parser.dart:1884`). ω = Wildcard|Bind.
- **⚠️ O CORTE MUDOU (spec 014 §12-11, ruling do dono 2026-07-17): lacuna = ERRO honesto, NUNCA
  silêncio.** O bail-silencioso ("false NEGATIVE OK") que eu tinha atribuído ao dono está MORTO — o dono
  NUNCA aceitou false-negative; verbatim: *"não pode mentir para o dev… tem que ser uma PEDRA"*. Código
  novo: **`match-exhaustiveness-unsupported`** (ERRO, span=MatchExpr; família `for-binder-unsupported`).
- **Corte revisado = classificação de cabeça `_Head` de 4 vias** (`_HWild`/`_HCtor` selado/`_HAtom`
  literal escalar/`_HStruct` Range·List·Struct·Record). **A chave anti-falsa-acusação:** `_default(D)`
  só pergunta "é ω?" ⟹ **um `_`/ω SEMPRE fecha a coluna e dá veredito sem tocar estrutura**. 3 regimes:
  (1) `_`/ω fecha (`w==null` antes do teste de struct) ⟹ VERDE mesmo com struct/list/range —
  `match n {0=>a,_=>b}` e `match p {Point{x,y}=>a,_=>b}` = VERDE; (2) coluna escalar infinita
  (Int/Str/Float) só-literais ⟹ Maranget §3.2 decide, testemunha `_` — `match n:Int {0=>a}` =
  `non-exhaustive` `_` (**Fatia 1 DECIDE, não defere** — resposta ao coordenador: U genérico já dá a
  testemunha); (3) gap + `_columnHasStruct` ⟹ `throw _MatchUnsupported` ⟹ erro honesto —
  `match p {Point{x:0}=>a}`, `match xs {[]=>a,[_,..]=>b}` = unsupported (List/produto → fatia 3).
- **Testemunha concreta VENCE unsupported** no ramo-Σ-completa (não-exaustividade definitiva > "não
  sei"). **Redundância** que bate em struct/átomo-vs-range ABSTÉM aquele braço (não mente sobre
  exaustividade — é incompletude do lint; o braço redundante ainda roda). Drivers com `try` SEPARADOS.
- **Range = togglável:** classifiquei `_HStruct` (defere, seguindo "Range defere" do coordenador), MAS
  a rigor é promovível a `_HAtom` já na Fatia 1 (Int infinito ⟹ range gap-preserving ⟹ `non-exhaustive`
  `_` honesto); só a REDUNDÂNCIA-de-range precisa de intervalo (fatia 2). Recomendei a promoção; decisão
  do coordenador.
- **`U` devolve `List<_Wit>?`** (null=inútil; `[]`=base útil); testemunha-cabeça: ramo-Σ-completa via
  `_rebuild(c,w)`, ramo-incompleta via `_missing(sig,present)` (ctor fora de Σ) ou `_WWild` (Σ=∅).
  Caso base `width==0`: útil ⟺ 0 linhas.
- **Integração walker:** `analyzeMatch(n, _typeOf(scrutinee), _check.types)` — NÃO recebe exprTypes
  (I5, sub-colunas vêm dos argTypes do ctor). Walker PULA `report.deadArms` no ∩ do DA (`continue`
  antes de `_expr(arm.body)` — mais preciso que anticascata: morto não roda). Anticascata de código
  morto é estrutural/grátis (match morto nunca chega a `_matchExpr`).
- **MUDOU desde o blueprint:** os 2 dedos da LT-F6a (A: tipar list/rest-pattern; B: `pattern-type-mismatch`)
  JÁ estão em `main` (`check.dart:560-632`: `_bindListPattern`/`_checkLiteralPattern`/`_checkRangePattern`).
  ⟹ NÃO são mais pré-condição pendente. Para a FATIA 1 não há pré-condição F5 (enum/Option/Result/Bool
  sempre foram tipados por `_bindEnumPattern`). Débito F5 restante (`interpolated-string-pattern`,
  `check.dart:609-618`) é concern da FATIA 3 (String).
