# Spec 014: Fase 6 — Flow-check (fluxo + exaustividade de `match`)

> **Tipo:** feature-fase (análises) · **Marco:** `Fase 6 do ita-next — O gate da F7 (spec 013 §0.6)`
> **Status:** `clarified` — **5 rulings de dono fechados em 2026-07-16** (§12): código morto é **ERRO** nos dois sítios · **`Assign : Void`** · **`guard-must-exit`** · globais pelo **modelo D-V1 do dono** (const-eval; `var` global e stmt top-level BANIDOS) · where por **1+3** com o sistema de efeitos registrado como débito de roadmap. O §12-6 (verificação de lazy na VM) morreu por irrelevância — o modelo C caiu com o D. ⚠️ O modelo D é **desenho do dono** (contraproposta no clarify), não opção do menu — procedência integral no §12.
> **Autor / Data:** orquestração (Claude) · 2026-07-16 · **Fundamentação:** a TÉCNICA é Dragon **cap 5** (SDD **L-atribuída**, uma descida — 5.2.4/5.5); as REGRAS são norma, não livro-texto: **JLS §8.4.7** (missing-return), **§14.21** (reachability/completes-normally, por indução estrutural — sem CFG), **§16** (definite assignment); **Maranget 2007** (*Warnings for pattern matching* — U/S/D + testemunha) dá o `match` inteiro. **Dragon 9.2 (CFG/fixpoint) NÃO é usado** — é otimização-grade, só necessário com goto/labels, que o Itá não tem. Lacunas assinadas (Art. IV-6b): Never-reachability (precedente Kotlin `Nothing`) · guard-must-exit (Swift TSPL "Early Exit") · DA×closures (C# spec) · pat-list por comprimentos (adaptação; precedente rustc usefulness) · init de globais (Go spec) · pureza interprocedural (Lucassen & Gifford 1988 — **fora de alcance, declarada**). Parecer `compiler-craftsman` 2026-07-16.

## §0 Metadados

- **Classe da mudança:** [x] **Nova fase** — a F6 do ADR-0011, entre a F5 (side-tables prontas) e a F7 (que a exige como gate).
- **Fases tocadas:** [x] **Fluxo (F6 — a fase inteira)** · [x] **um dedo na F5** (§1 — o reparo do `Assign`, precedente 013 §7.6) · [ ] demais.
- **Princípios afetados:** P1 (imutável por default — o `assign-to-immutable` finalmente ganha executor), P3 (tudo é expressão — `Assign : Void` é ruling §12-2), P4 (testemunha no erro de exaustividade; nada de side-table de rota), P7 (zero try/catch — `panic`/`Never` encerram fluxo).

### §0.5 Constitution check

Sem conflito. A F6 é a fase que o ADR-0011 define e a 013 §0.6 exige. O artefato formal da fase é
**doc formal de regras de fluxo** (ADR-0010 pede `flow.ott` ou doc — esta spec §2–§4 É o doc; Ott fica
como refinamento posterior, não-bloqueante). Art. IV-4: todo CA vira corpus (`conformance/flow/`).

### §0.6 O LEDGER — toda promessa feita à F6, com destino

Catalogado por varredura em 2026-07-16 (promessa não catalogada vira buraco — a lição da 011 §1.2b):

| # | Promessa | Fonte | Destino nesta spec |
| :-: | :-- | :-- | :-- |
| a | definite-return | ADR-0011; 013 §0.6 | §2–§3 (`missing-return`) |
| b | use-before-assign | ADR-0011; 009 §12-7 | §2–§3 (`use-before-assign`, `capture-before-assign`) |
| c | unreachable code | ADR-0011; `check.dart:349` | §3 (`unreachable-code` — severidade §12-1) |
| d | exaustividade + braço redundante | 009 §4.7 (contrato PRONTO) | §4 (Maranget; braço morto §12-1) |
| e | `break`/`continue` só em loop | 004 §177 | ✅ **JÁ PAGO na F4** (`resolver.dart:368-371`, CI 11.5.1; reset na fronteira de fn `:295-297`) — §8 re-roteia normativamente e adiciona a fixture da fronteira de closure |
| f | ordem de inicialização de globais | 008; `resolver.dart:73` | §5 — **modelo D do dono dissolveu a ordem** (`global-init-not-const` + `global-init-cycle`) |
| g | pureza do `where` + where-cíclico preciso | `desugar.dart:509-512` | §6 (ruling §12-5) + §5 (mesmo módulo SCC) |
| h | `self` em `FieldDecl.defaultValue` | 008 §133 | §3 (`self-in-field-default` — proibido; o Kernel não tem `this` em initializer de campo) |
| — | **`Assign` é BURACO na F5** (sondado 2026-07-16: `x = 2` sobre `let`, e `var y: Int; y = 2` LEGÍTIMO, caem ambos em `cannot-infer`) | dívida da 009 §4.8; F4 deferiu (`resolver.dart:465`) | **§1 — REPARO, pré-condição do DA** |

## §1 Pré-condição — o dedo na F5: `Assign` tipado (REPARO, sem crédito de feature)

Sem atribuição tipada, o definite-assignment analisaria um nó que a F5 nem aceita — cascata de
`cannot-infer`. O reparo é dívida declarada (009 §4.8) e fecha aqui:

- **Tipo:** `x = e` checa `e ⇐ tipo(x)` (nº6 `binderTypes`); `obj.field = e` é type-directed via nº3
  (008 §5.5). `+=`/`-=`/`*=`/`/=` **sobrevivem ao desugar** (`desugar.dart:468-469` preserva `n.op`)
  ⟹ tipam como `x = x + e`.
- **Imutabilidade (P1 ganha executor):** alvo `let`/param ⟹ **`assign-to-immutable`**; campo sem
  `var` ⟹ idem; alvo não-atribuível (chamada, literal) ⟹ `invalid-assign-target`.
- **`Assign : Void`** — atribuição NÃO rende valor (ruling embutido, **§12-2**): mata `x = y = 1` e
  `if x = 1` por tipo, e **apaga os conjuntos bivalentes when-true/when-false do JLS §16.1** — a
  maior economia desta spec (precedente Swift/Go/Rust-stmt).

## §2 O flow-walk — UMA descida, três fatos entrelaçados

SDD **L-atribuída** (Dragon 5.2.4) sobre o programa canônico tipado: um DFS calcula, por statement,
**(i)** `completesNormally` (JLS §14.21, indução estrutural), **(ii)** o conjunto **DA** de `var`s
definitely-assigned (JLS §16 — só `var` entra: o §12-7 da 009 matou a metade "definitely unassigned"
do JLS, que existia por `final`; `let` nasce ligado), **(iii)** reachability (o DUAL de (i):
`stmt[i+1]` é alcançável sse `stmt[i]` é alcançável ∧ completa). Entrelaçados, não paralelos:
DA-após-stmt-que-não-completa = ⊤ (verdade vácua — JLS §16).

Regras por construção (as que não são óbvias):

| Construção | completesNormally | Nota |
| :-- | :-- | :-- |
| `ExprStmt(e)` | `tipo(e) ≠ Never` | `panic` (e todo `Never` da nº1) **encerra** — type-informed, precedente Kotlin `Nothing` *(assinado)* |
| corpo `=>` | — (trivialmente rende) | RD-1: só `BlockBody` roda o predicado |
| `match` | braço é **EXPRESSÃO** (RD-1) ⟹ `return` nunca ocorre DENTRO de braço | "todos os braços retornam" colapsa em `return match {…}` ou em `match : Never` via join (`check.dart:1468`); exaustividade **não precisa acoplar** — se não-exaustivo, a F6 já errou por política |
| `while` | completa sempre, **exceto** cond = `BoolLit(true)` **sintático** sem `break` ligado ao loop | JLS usa const-expr; o Itá não tem const-fold ⟹ restringe a literal *(assinado)*. `break` dentro de closure não conta (F4 já corta na fronteira) |
| `if` sem `else` | completa sempre | o carve-out deliberado do JLS |
| `guard … else blk` | o `blk` **TEM de não completar** | §3 `guard-must-exit` |
| closure (criação) | completa; **cria OBRIGAÇÃO de DA** | §3 `capture-before-assign` |

## §3 Sítios e erros (EN kebab-case; span em todos)

| Erro | Regra | Fundamento |
| :-- | :-- | :-- |
| `missing-return` | fn `-> T` (T ≠ `Void`) cujo corpo-bloco **pode** completar normalmente | JLS §8.4.7 verbatim; vale igual para `-> Never` |
| `guard-must-exit` | `completesNormally(else-block)` = true | Swift TSPL "Early Exit" *(aplicação da meta-diretriz ADR-0016 §A — assento próprio: **§12-3**)*. `Guard`/`GuardLet` sobrevivem ao desugar (`desugar.dart:197-201`) |
| `unreachable-code` | statement não-alcançável (pós-`return`/`Never`/`break`/`continue`) | JLS §14.21 — **severidade é ruling §12-1** |
| `use-before-assign` | uso de `var` fora do conjunto DA | JLS §16 |
| `capture-before-assign` | criação de closure com `var` livre capturado ∉ DA | C# spec (DA × anonymous functions) *(assinado)*; assign DENTRO da closure não contribui DA para fora |
| `self-in-field-default` | `self` em `FieldDecl.defaultValue` | 008 §133; Kernel não tem `this` em initializer de campo |
| `global-init-cycle` | ciclo no grafo de initializers de globais — **com o ciclo NOMEADO** | §5 |

## §4 `match` — U(P,q) sobre o `ast.asdl` real — `[Maranget 2007]`

Núcleo: `U` (usefulness), `S(c, P)` (especialização por construtor), `D(P)` (default). Exaustividade
= `¬U(P_unguarded, (ω…ω))` — **braço com guard NÃO conta para cobertura** (009 §4.7, cravado).
**Redundância** = o mesmo `U`: braço `i` morto sse `¬U(P₁..ᵢ₋₁ não-guarded, pᵢ)`. **Testemunha
OBRIGATÓRIA no erro** (P4): a recursão de U constrói o contraexemplo — *"`.none` não coberto"*.

Normalização dos patterns (`ast.asdl` → matriz):

| Pattern | Vira | Nota |
| :-- | :-- | :-- |
| `Bind`/`Wildcard` | ω | binder liga, não discrimina |
| `EnumPattern` | construtor `c_v`, aridade da **Σ** (F5, 009 §4.7b) | `.variant` já resolvido pela F5 |
| `T?` | Σ = `{some/1, none/0}`; `LiteralPattern(nil)` ≡ `none` | Option ≡ `T?` (009 §4.6) |
| `Bool` | finito `{true, false}` | fecha sem ω |
| `Int`/`String` literais | Σ **infinito** — só ω fecha | 009 §4.7 cravou |
| `Float` literal | **nunca conta** para cobertura | NaN; Rust deprecou float-pattern *(assinado)* |
| `RangePattern` | interval-splitting decidível (endpoints são Int-literais **por construção** — `parser.dart:1859-1861`) | técnica rustc; ranges nunca fecham `Int` sem ω. Defesa: endpoint-expr degrada a guard |
| `Record`/`Struct` | **produto** = assinatura de tamanho 1 — S expande os campos em colunas na ordem declarada | omitidos/`hasRest` → ω; irrefutável sse subpadrões irrefutáveis |
| `pat-list` | família `List_n` (exato) + `List_{≥k}` (rest): especializa por comprimentos `0..m` + um representante `> m` (m = maior aridade fixa da coluna) | **a lacuna real de Maranget** (ele cobre cons-list); adaptação *(assinada)*, precedente rustc (FixedLen/VarLen). Fecha com ω OU rest cobrindo `[k,∞)` + todos `< k` cobertos |

Bônus da mesma especialização: **`wildcard-covers-known-variants`** (warning §12-6 da 009) sai de
graça — os construtores ausentes são a lista que o ω engoliu.

## §5 Globais — o modelo **D do dono**: 100% estático (const-eval)

**Ruling §12-4 (dono, 2026-07-16 — desenho DELE, contraproposto no clarify):** *"tudo que for global,
100% determinístico e estático por natureza"*. Formalizado como **D-V1**:

- **Global é `let` com initializer CONST-AVALIÁVEL**: literais · operadores sobre consts · construção
  de struct/enum com args const · referência a outro global const. **SEM chamadas na V1.**
  Violação ⟹ **`global-init-not-const`**.
- **A pergunta da ordem DISSOLVE**: não existe execução de initializer em runtime — o compilador
  computa os valores e a F7 os embute prontos. A side-table de ordem **morre antes de nascer**.
  Sobra o grafo de referências const: **Tarjan SCC**, ciclo ⟹ **`global-init-cycle`** (erro, ciclo
  NOMEADO). O **where-cíclico preciso** usa o MESMO módulo SCC (o desugar sobre-aproxima por design —
  `desugar.dart:509-512`; aqui há escopos reais).
- **`var` global: BANIDO** (`mutable-global`) e **statement top-level: BANIDO**
  (`top-level-statement`) — top-level = declarações + `let` const; `main` é a ÚNICA entrada, zero
  código roda antes dele. São checks de FORMA (não de fluxo) ⟹ moram no dedo da F5 (§1 cresce).
  Reabrível por ADR se doer.
- **V2 — const-fn** (a ideia completa do dono: *"funções de primeira ordem, sem recursão"*, + fuel
  para terminação — precedente Zig branch-quota): **spec própria**, roteada. A V1 não a bloqueia nem
  a pressupõe.
- **Precedentes do D**: Rust (`static`/`const` exigem const-expr), Zig (comptime). Os modelos
  A (Go: eager por dependência), B (textual) e C (lazy da VM) foram apresentados e **caíram** — o D
  domina: elimina a semântica de ordem em vez de escolhê-la. O C levou junto o §12-6 (a verificação
  de lazy ficou irrelevante).

**O acoplamento com o `where` DISSOLVEU**: global-const não precisa de regra de pureza (const-eval
não TEM efeitos por construção). O `where` computa valores de runtime — segue sozinho no §6.

## §6 Pureza do `where` — decidido: **1+3** (ruling §12-5)

Contexto: sem FFI, o único IO do chão é `print` (013 §8.2) ⟹ os primitivos de efeito são um conjunto
**FECHADO e sintático**: `Assign` · `Panic` · `Await` · `Spawn` · `Emit`.

**Ruling §12-5 (dono, 2026-07-16): opção 1+3.**
- **(1)** Os 5 primitivos são PROIBIDOS dentro de binding de `where` ⟹ **`impure-where-binding`**
  (walk trivial).
- **(3)** A **ordem topológica-determinística É a semântica publicada** (a 006 §3.6 já define where
  como letrec ordem=dependência; Kahn + empate textual já existe em `desugar.dart:507-509`) — o
  resíduo interprocedural (chamada que efetua) roda NA ordem publicada, honesto por definição.
- **Sistema de efeitos** (opção 4, Lucassen & Gifford — a inclinação declarada do dono no clarify):
  **registrado como débito de roadmap** — vira ADR `proposed` próprio quando o dono quiser puxá-lo;
  ao chegar, aperta o resíduo interprocedural daqui. A 014 NÃO o espera.

*(Opções 2 — proibir Call, mata o where — e 4-já foram apresentadas e recusadas no clarify.)*

## §7 Contrato F6 → F7

- ~~Side-table de ordem de globais~~ — **MORTA pelo modelo D** (§5): não há ordem a entregar; a F7
  recebe os **valores const já computados** (a forma exata — const no `.dill` vs recomputo trivial —
  é decisão de emissão da 013).
- **Side-table nº8 — `flowFacts`**: `completesNormally` por corpo. A F7 precisa para o **throw
  defensivo de fim-de-corpo** (o verifier do Kernel não checa — 013 §0.6; a VM devolveria null
  implícito; o CFE emite `ReachabilityError` no caso análogo). A F7 **não recomputa** (ADR-0004).
- **Exaustividade NÃO vira side-table**: pós-F6, todo `match` é exaustivo **por política de fase** —
  o carimbo é o gate do driver, não um campo. Armazenar rota seria o "campo de rota" que a 009 §4.6
  recusou (P4). A F7 emite match sem default-branch **porque a fase passou**, não porque leu um bit.

## §8 Re-roteamentos e assentos

- **(e) `break`/`continue` fora de loop**: assentado como **F4, já pago** (`resolver.dart:368-371` —
  context-flags, o mecanismo do CI 11.5.1; reset na fronteira de fn). Nem parser (a legalidade cruza
  fronteira de FUNÇÃO — `while { let f = { break } }` é ilegal — contexto de binding, não gramática;
  e a recuperação N2 multiplicaria falsos positivos), nem F6 (pagar duas vezes). A spec 004 §177
  ganha nota datada apontando para cá. **Débito de teste:** fixture da fronteira de closure.

## §9 Checklist de completude

- [ ] `frontend/analysis/` — flow-walk (A) + match analysis (B) + módulo SCC (C)
- [ ] o dedo na F5 (§1): `Assign` tipado + `assign-to-immutable` + `Assign : Void`
- [ ] side-table nº8 (`flowFacts`) + valores const dos globais saem no resultado da fase (o padrão da 011: a fase não joga fora o que a próxima lê)
- [ ] **corpus `conformance/flow/`**: um `.tu` por CA (§11)
- [ ] doc formal de regras (§0.5 — ADR-0010); Ott como refinamento posterior
- [ ] tree-sitter/GRAMMAR: **N/A** (nenhuma mudança de superfície além do que §1 já tipa)

## §10 Compatibilidade, migração e alternativas

- **Breaking?** Programas hoje verdes que a F6 passará a recusar: fn non-Void sem return em algum
  caminho (eram `.dill` inválido em potência — é o ponto); `match` não-exaustivo (política da 009,
  agora com executor); `var` usado antes de atribuir. **É o comportamento prometido pelas specs
  anteriores — a quebra é a promessa sendo cumprida.** O modelo D acrescenta quebra NOVA e ruled:
  `var` global, statement top-level e initializer não-const deixam de existir (a gramática segue
  aceitando — o erro é semântico; corpus/testes com globais dinâmicos ajustam quando a F6 aterrissar).
- **Alternativas descartadas:** CFG/dataflow completo (Dragon 9.2 — otimização-grade, sem goto não
  paga); exaustividade por árvore de decisão own-rolled (Maranget é o algoritmo com testemunha e
  literatura de warnings — reinventar perde as duas); acoplar exaustividade ao definite-return
  (desnecessário — RD-1 fez braço ser expressão).

## §11 Critérios de aceite (viram `conformance/flow/`)

- **CA1** fn `-> Int` com `if` sem else e return só no then ⟶ `missing-return`.
- **CA2** fn `-> Int { panic("x") }` ⟶ **verde** (`Never` não completa).
- **CA3** `return match { … }` exaustivo em todos os braços ⟶ verde; o mesmo match com braço faltando ⟶ erro de exaustividade **com testemunha** (*"`.none` não coberto"*).
- **CA4** `guard let x = e else { print("a") }` ⟶ `guard-must-exit` (else completa); com `return`/`panic` no else ⟶ verde.
- **CA5** `while true { … }` sem break, após o loop nada ⟶ fn non-Void **verde** (loop não completa); com `break` ⟶ `missing-return` se faltar return depois.
- **CA6** `var y: Int` + uso antes de atribuir ⟶ `use-before-assign`; atribuído nos DOIS braços do if/else e usado depois ⟶ verde; só num braço ⟶ erro.
- **CA7** closure captura `var` não-atribuído ⟶ `capture-before-assign`; atribuição DENTRO da closure não libera o uso externo.
- **CA8** braço de match coberto pelos anteriores ⟶ diagnóstico de braço morto (severidade §12-1); braço com guard nunca é acusado de morto.
- **CA9** `match xs { [] => …, [a] => …, [a, ..resto] => … }` ⟶ exaustivo (comprimentos 0, 1, ≥1... verificar: 0 + 1 + rest≥1 cobre); sem o rest ⟶ erro com testemunha de comprimento.
- **CA10** dois globais com initializers mutuamente dependentes ⟶ `global-init-cycle` **nomeando o ciclo**.
- **CA11** `let x = 1` seguido de `x = 2` ⟶ `assign-to-immutable` (§1 — o P1 com executor); `var` idem ⟶ verde e tipado (`y = "s"` com `y: Int` ⟶ `type-mismatch`).
- **CA12** `x = y = 1` ⟶ erro por tipo (`Assign : Void` — §12-2).
- **CA13** `unreachable-code` pós-return ⟶ **ERRO** (§12-1).
- **CA14** `self` em default de campo ⟶ `self-in-field-default`.
- **CA15** global `let g = f(1)` (chamada no initializer) ⟶ `global-init-not-const` (D-V1); `let g = 1 + 2` e `let h = g` ⟶ verdes, valores computados.
- **CA16** `var g = 1` top-level ⟶ `mutable-global`; statement solto top-level ⟶ `top-level-statement`.
- **CA17** `let a = b` + `let b = a` (globais) ⟶ `global-init-cycle` nomeando `a → b → a`.
- **CA18** `V where { let x = panic("boom") }` ⟶ `impure-where-binding`; `let m = soma(xs)` no where ⟶ verde (chamada roda na ordem publicada).

## §12 Fila de clarify/rulings — ⚠️ ABERTA

| # | Pergunta | Bloqueia | Decisão (2026-07-16, fila apresentada em 2 levas com contexto integral) |
| :-: | :-- | :-- | :-- |
| 1 | **Severidade** de `unreachable-code` e do braço morto | corpus/CI | ✅ **Dono: ERRO nos dois.** Sem `#if`/const-fold, morto nunca é intencional; coerente com exaustividade-é-erro (009) e ADR-0013 |
| 2 | **`Assign : Void`** | §1 (o reparo) | ✅ **Dono: SIM.** Atribuição não rende valor — `x = y = 1` e `if x = 1` morrem por tipo; o §16.1 bivalente do JLS fica fora. P3 intacto na leitura "quando possível" |
| 3 | **`guard-must-exit`** (Swift TSPL) | CA4 | ✅ **Dono: SIM.** Aplicação da meta-diretriz (ADR-0016 §A) com este assento próprio |
| 4 | **Modelo de init de globais** | §5, F7 | ✅ **Dono: modelo D-V1 — DESENHO DELE** (contraproposta no clarify, não opção do menu): global 100% const-eval; a ordem dissolve; `var` global e stmt top-level **banidos** (2ª pergunta da leva, também dele). **V2 (const-fn, 1ª ordem, sem recursão, + fuel) roteada a spec própria** |
| 5 | **Pureza do where** (desacoplado do global pelo D) | §6 | ✅ **Dono: 1+3** (`impure-where-binding` + ordem publicada). **Sistema de efeitos** — a inclinação declarada dele — vira **débito de roadmap** (ADR `proposed` futuro), não segura a 014 |
| 6 | Semântica exata do lazy de campo estático na VM | §12-4-C | 💀 **MORTA por irrelevância** — o modelo C caiu com o D; a verificação não é mais necessária |

## Definition of Done

- [x] §12 fechado (5 rulings; a 6ª morreu por irrelevância); status → `clarified` ✅ 2026-07-16.
- [ ] O dedo na F5 (§1) implementado ANTES do flow-walk (é pré-condição do DA).
- [ ] CA1–CA18 no corpus `conformance/flow/`, verdes; suíte inteira verde; analyzer limpo.
- [ ] Side-table nº8 (`flowFacts`) + valores const entregues (contrato F6→F7 — a 013 §0.6 destrava).
- [ ] Spec 004 §177 anotada (re-roteamento do (e) para F4 — §8).
- [ ] Constitution check sem conflito; CI verde.
