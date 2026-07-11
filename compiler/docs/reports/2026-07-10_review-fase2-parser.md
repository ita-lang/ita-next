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

---

## Deferido (débito rastreado — item · lente · fase/dono)

| Item | Lente | Onde resolver |
| :-- | :-- | :-- |
| **Spans de interpolação `${…}`** ficam relativos ao sub-fonte — a info do offset absoluto **morre no lexer** (Fase 1). Conserto: lexer guarda `['expr', src, baseOffset]`; parser rebaseia. Bloqueia posição correta em DWARF/source-maps. | vm (BLOCKER) + craftsman (A9) | **Fase 1** (cedo = barato) |
| **Offset dos nós pós-fixos** usa o início do receptor; o Kernel quer o ponto do seletor (`.nome`/`(`/`!`). Cadeia multi-linha reporta linha errada; `ForceUnwrap` é o mais sensível. | vm (A1) | Modelagem (campo `opOffset`) antes do codegen |
| **Recuperação intra-bloco** (`_block`/`_typeBody`) ausente → cascata + `}` engolido. Parcial: `_mapLiteral` já reancora local. Falta o modelo geral (sync-frame por bloco, boundary-closers). | craftsman (A2/A3) | Fatia 2 (N2 completo) |
| **Param/MapEntry sem span** — viram nós posicionados do Kernel (`VariableDeclaration`/`MapLiteralEntry`); sem span degrada breakpoint/hover. | vm (A3) | Modelagem (dar span a `Param`) |
| **`operator left/right` descartado mudo** — mesmo anti-padrão que D3 proibiu no `pub`. `Fixity` não distingue associatividade. Representar ou rejeitar. | vis (RD-3) + craftsman | Fatia 3 |
| **`spawn` → `dart:isolate`** (entry-point top-level/estático + message sendable); **não existe em `dart2js`** → furo de paridade JS. `await`/`emit` exigem legalidade (await-em-async, emit-em-stream) que o verificador do Kernel cobra. | vm (A2/A4) | §8 (Fases 4–6 / runtime) |
| **`let`/`var` init obrigatório** — confirmar contra GRAMMAR §3 se `var x: T` sem init é legal. | craftsman (A6) | Confirmação de GRAMMAR |
| **`Program.body: List<AstNode>`** perde exaustividade (admite Expr/Type/Pattern no topo). ASDL definiu `item = ItemDecl\|ItemStmt`; materialização divergiu de propósito. | craftsman (A7) | Baixa (opcional) |
| **`fn` sem corpo** aceito em qualquer posição (sem gate `allowNoBody`). "AST representa, não valida" — garantir barreira em fase posterior. | craftsman (A8) | Fase semântica |
| **`where`-clause** (nível 0, deferido) — a semântica exata (só `let`? escopo?) fica em aberto; é a forma itaiana de bindings-antes-do-valor que sustenta a opção A do if-expr. | vis | Decisão de dono |

**Confirmado OK pelas 3 lentes** (não mexer): cascata/associatividade, os 8 cantos, `_isClosureStart`,
recuperação local do `_mapLiteral`, mapeamento M3/M4/M5/M6 → Kernel, Await→AwaitExpression /
Panic→Throw / Emit→YieldStatement / ForStmt.isAwait→ForInStatement.isAsync, `meaningless-pub`
(precedente P4), dump determinístico, taxonomia de erro kebab-case.
