# Revisão da Fase 2 (parser) — 3 especialistas · 2026-07-10

Code review adversarial da Fase 2 (Sintaxe → AST) após os 23 CAs verdes, por três
lentes independentes: **`compiler-craftsman`** (técnica de front-end), **`dart-vm-expert`**
(forward-compat do Kernel) e **`ita-visionary`** (identidade / 11 princípios).

**Veredito global:** parser tecnicamente sólido (cascata/cantos corretos) e fortemente
"itaiano" (zero violação de princípio permanente). Achados: 1 crash real, um cluster de
correção e um conjunto de débitos de forward-compat/recuperação para fases futuras.

---

## Corrigido nesta rodada (commit da correção)

### Cluster de correção (compiler-craftsman)
- **B1** — crash `tokens[-1]` na recuperação quando o token ofensor já é boundary sem
  handler (ex.: `init` no topo). Fix: progresso garantido no `catch` de `parseProgram`
  (`_synchronizeDecl` para no boundary; força ≥1 avanço só se `_current == before`).
- **A5** — `match` exigia vírgula entre arms. Fix: separador opcional (newline separa).
- **A1** — supressão de trailing-closure vazava para closures aninhadas em `(...)`/`[...]`/`{...}`
  dentro de condições. Fix: helper `_bracketed` limpa o flag ao entrar em bracket
  (`_finishCall` args, `_parenOrClosure`, `_listLiteral`, `_mapLiteral`, index, copy-with,
  match arms). CA21 preservado (o `{` após `)` respeita a supressão externa).
- **A4** — span do generic interno curto 1 byte no split `>>`. Fix: `_splitTypeGt` consome o
  `>` de fecho e INSERE o restante, então `_previous()` reflete o fecho (M1).

### if-EXPRESSÃO — ruling RD-1, opção A (ita-visionary + dono)
`if [let PAT =] SUBJECT => then else orElse`, ramos = EXPRESSÃO, `else` obrigatório, cobre a
forma if-let (desembrulho). Invariante cravada: **`=>` é o único token "rende valor"** no Itá
(fn-body, closure, match-arm, if-expr). `IfExpr` remodelado (`block`→`expr` + `binding?`).

### Spans de interpolação (Fase 1) — RESOLVIDO
O offset absoluto do conteúdo do `${…}` deixou de morrer no lexer: `_string` guarda
`['expr', source, offsetAbsoluto]` e o `Lexer` ganhou `baseOffset` (soma no offset de todo
token/eof/erro). O parser passa esse `baseOffset` ao sub-lexer da interpolação → os nós da
sub-expressão nascem com span ABSOLUTO (DWARF/source-maps corretos). Ex.: `"x=${a + 1}!"` →
`a`/`1` com offset do arquivo, não do fragmento.

### Offset dos pós-fixos (`opOffset`) — RESOLVIDO
Os nós pós-fixos (`Call`/`Member`/`OptChain`/`Index`/`TupleIndex`/`ForceUnwrap`/`Try`/
`CopyWith`) ganharam `opOffset` = offset do SELETOR/operador (`.`/`(`/`?.`/`[`/`!`/`?`),
capturado no topo do loop de `_postfix`. O span completo `(offset, length)` do receptor até
o fim da cadeia é PRESERVADO (range de IDE); o `opOffset` é o `fileOffset` que o codegen dará
ao Kernel (stack trace no seletor). Não entra no dump. Ex.: `x!` → span@0, opOffset@1.

---

## Resolvido no cluster de débitos (2026-07-11)

Rodada dedicada a fechar os débitos deferidos que eram **legítimos na Fase 2**. Todos
com caso de conformância + unit test; `make test` verde, `dart analyze` limpo.

- **D5 — `let`/`var` init opcional (conformidade GRAMMAR §3).** Era um **bug real**: o
  parser exigia `=` sempre, mas `GRAMMAR §3` permite `let x` / `var x: T` sem init na
  forma bind (`IDENT`). `LetStmt.value` virou `expr?`; `_letStmt` só exige `=` na forma
  **destructure** (`{…}`/`[…]`). Golden `stmt_let_no_init` + 3 unit (inclui o guard de que
  destructure sem `=` ainda é erro).
- **D3 — associatividade de `operator` preservada.** `_operatorDecl` lia `left`/`right` e
  **descartava** (tudo virava `Fixity.infix`); a `precedence` nem entrava no dump. Novo
  `enum Associativity {none,left,right}` + campo em `OperatorDecl`; o dump agora emite
  `(prec N) (assoc left|right)`. Golden `decl_operator` + 2 unit.
- **D2 — span em `Param` e `MapEntryNode`.** Viram nós posicionados do Kernel
  (`VariableDeclaration`/`MapLiteralEntry`); ganharam `offset`+`length` byte-precisos
  (dump padrão inalterado — spans elididos). 2 unit assertando o span via `substring`.
- **D1 — recuperação intra-bloco (`_block`/`_typeBody`).** A peça que faltava da Fatia 2:
  `_synchronizeInBlock` (consciente do boundary-closer) + `_recoverInBlock` enxertam
  `ErrorStmt`/`ErrorDecl` e reancoram no próximo item **sem engolir o `}`** e sem cascata.
  Golden `recover_intra_block` (erro no bloco → `let` seguinte recupera → `fn g` de topo
  parseia, 1 erro só) + 3 unit.

## Deferido (débito rastreado — item · lente · fase/dono)

> Estes **permanecem deferidos por razão estrutural** — não são pendências de esforço, e
> resolvê-los na Fase 2 seria incorreto (sem backend, ou fura o princípio "AST representa,
> não valida", ou exige decisão de dono).

| Item | Lente | Onde resolver |
| :-- | :-- | :-- |
| ~~Spans de interpolação `${…}`~~ ✅ **RESOLVIDO** (2026-07-10). | vm (BLOCKER) + craftsman (A9) | — |
| ~~Offset dos nós pós-fixos~~ ✅ **RESOLVIDO** (2026-07-10 — `opOffset`). | vm (A1) | — |
| ~~**Recuperação intra-bloco** (D1)~~ ✅ **RESOLVIDO** (2026-07-11 — `_synchronizeInBlock`). | craftsman (A2/A3) | — |
| ~~**Param/MapEntry sem span** (D2)~~ ✅ **RESOLVIDO** (2026-07-11). | vm (A3) | — |
| ~~**`operator left/right` descartado** (D3)~~ ✅ **RESOLVIDO** (2026-07-11 — `Associativity`). | vis (RD-3) | — |
| ~~**`let`/`var` init** (D5)~~ ✅ **RESOLVIDO** (2026-07-11 — era bug de conformidade). | craftsman (A6) | — |
| **`spawn` → `dart:isolate`** (entry-point top-level/estático + message sendable); **não existe em `dart2js`** → furo de paridade JS. `await`/`emit` exigem legalidade que o verificador do Kernel cobra. ⏸️ **Deferido: não há codegen na Fase 2** — o parser já produz o nó `Spawn`; nada a fazer aqui. | vm (A2/A4) | §8 (Fases 4–6 / runtime) |
| **`fn` sem corpo** aceito em qualquer posição (sem gate `allowNoBody`). ⏸️ **Deferido por design**: "AST representa, não valida" — a barreira (só trait/impl podem omitir corpo) é da fase semântica. `GRAMMAR §2` confirma `fnBody?` opcional. | craftsman (A8) | Fase semântica |
| **`where`-clause** (nível 0) — semântica exata (só `let`? escopo?) em aberto; sustenta a opção A do if-expr. ⏸️ **Deferido: decisão de dono** (não é técnica). | vis | Decisão de dono |
| **`Program.body: List<AstNode>`** perde exaustividade. ⚖️ **Mantido de propósito**: o Dart expressa a união `item = ItemDecl\|ItemStmt` via subtipagem (`AstNode` = supertipo de `Decl`/`Stmt`); um wrapper `Item` só adicionaria boilerplate. Revisitar se a semântica precisar distinguir. | craftsman (A7) | Baixa (opcional) |

**Confirmado OK pelas 3 lentes** (não mexer): cascata/associatividade, os 8 cantos, `_isClosureStart`,
recuperação local do `_mapLiteral`, mapeamento M3/M4/M5/M6 → Kernel, Await→AwaitExpression /
Panic→Throw / Emit→YieldStatement / ForStmt.isAwait→ForInStatement.isAsync, `meaningless-pub`
(precedente P4), dump determinístico, taxonomia de erro kebab-case.
