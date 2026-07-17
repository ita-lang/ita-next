# Blueprint — F6 flow-walk (spec 014 §2–§3): o desenho que o implementador segue

> **Escopo deste lote:** `missing-return` · `guard-must-exit` · `unreachable-code` ·
> `use-before-assign` · `capture-before-assign` · `self-in-field-default` + side-table nº8
> (`flowFacts`). **FORA:** Maranget (§4), const-eval/SCC (§5, `global-init-cycle` incluso),
> `impure-where-binding` (§6).
>
> **Fundamento-mestre:** a TÉCNICA é SDD L-atribuída em UM walk (Dragon 5.2.4/5.5); as REGRAS são
> norma — JLS §14.21 (completes-normally/reachability, indução estrutural), §8.4.7
> (missing-return), §16 (definite assignment); lacunas assinadas na spec (Kotlin `Nothing`,
> Swift TSPL Early Exit, C# spec DA×anonymous-functions). **Dragon 9.2 (CFG/fixpoint) NÃO entra**
> — otimização-grade, só paga com goto/labels (spec 014 §cabeçalho).

---

## 0. Invariantes de implementação (violar = bug, não opinião)

- **I1 — A F6 caminha `check.program`, NUNCA re-desugara.** As side-tables da F5 são
  `Map.identity` sobre os nós DA árvore canônica (`type_table.dart:453-508`, ADR-0004). Um
  `desugarProgram` novo produz nós novos → toda consulta a `exprTypes`/`annotations` erra em
  silêncio. O `analyzeFlow` recebe o `CheckResult` e usa `check.program` — ponto.
- **I2 — Consulta a side-table FALHA alto.** `exprTypes[e]` ausente ⟹ `StateError` (o mesmo
  contrato do `typeOf` da F5 — `check.dart:136-138`: totalidade é invariante; default silencioso
  é a doença do oracle).
- **I3 — F6 só roda sobre F5 limpa.** Erro de F4/F5 aborta antes (o padrão do driver:
  `checkProgram` aborta sobre binding-errors, `driver.dart:287`). `ErrorType` nas tabelas
  envenenaria Never-reachability e o predicado de retorno — cascata, não diagnóstico.
- **I4 — Um walk, três fatos** (parecer W1): `completesNormally` ⊗ DA ⊗ reachability,
  entrelaçados — DA-após-stmt-que-não-completa é verdade vácua (JLS §16), e reachability é o
  dual de completes (JLS §14.21).

---

## 1. Módulo, assinatura, driver (item 1)

### 1.1 `compiler/lib/frontend/analysis/flow.dart`

```dart
/// Erro de fluxo (EN kebab-case + span) — espelha CheckError/BindingError.
class FlowError {
  final String code;
  final int offset;
  final int length;
  const FlowError(this.code, this.offset, this.length);
  String format() => 'flow-error: $code @$offset+$length';
}

/// O resultado da F6 (contrato F6→F7, spec 014 §7). O padrão da 011: a fase
/// NÃO joga fora o que a próxima lê.
class FlowResult {
  final List<FlowError> errors; // ordenados por offset (espelha check.dart:106-107)

  /// **Side-table nº8** — `completesNormally` por corpo-BLOCO.
  /// Chave: `FnDecl | InitDecl | Closure` (identidade; os três SÃO AstNode).
  /// Só corpos `BlockBody` têm entrada — corpo `=>` nunca "cai do fim" (RD-1;
  /// F7 emite `ReturnStatement(expr)` direto). Totalidade: garantida em
  /// programa VERDE (com erro, a F7 nunca lê — o gate aborta).
  final Map<ast.AstNode, bool> completesNormally;

  bool get hasErrors => errors.isNotEmpty;
}

FlowResult analyzeFlow(
  CheckResult check,
  Map<ast.AstNode, ResolvedName> resolution,
);
```

**Por que `resolution` é parâmetro:** o `CheckResult` NÃO carrega a side-table da F4
(`type_table.dart:453-508` — só nº1–nº7), e o DA precisa de `Ident → LocalRes(binder, hops,
captured)`. **Achado de plumbing:** o `checkProgram` do driver hoje DESCARTA `resolved.resolution`
(`driver.dart:283-299`) — a mesma classe de bug que a 011 matou ("a fase joga fora o que a próxima
lê"). Para a F6 resolve-se no driver (abaixo); **registrar**: a F7 vai precisar do MESMO mapa
(emitir `VariableGet(VariableDeclaration)` exige `Ident → binder`) — quando a spec da F7 aterrissar,
promover `resolution` a campo do contrato.

### 1.2 Driver — comando NOVO `itac flow`; `itac check` fica intocado

```dart
// driver.dart
({CheckResult check, FlowResult? flow}) flowProgram(ast.Program program) {
  final resolved = resolveProgram(program);
  if (resolved.errors.isNotEmpty) {
    return (check: /* o CheckResult 'unresolved-before-check', como checkProgram */, flow: null);
  }
  final check = checkTypes(resolved.program, resolved.resolution);
  if (check.hasErrors) return (check: check, flow: null); // I3: gate
  return (check: check, flow: analyzeFlow(check, resolved.resolution));
}

String flowErrorDump(List<FlowError> errors); // 'flow-error: <code> @off+len'
String flowFactsDump(FlowResult res);         // §10.2 abaixo
int runFlow(List<String> args, {StringSink? out, StringSink? err});
// `itac flow <file.tu> [--dump-facts]` — exit 0/65/64/66, a família de sempre.
```

**Recomendação (com justificativa): comando novo, não engordar `itac check`.**
1. **Disciplina fase-por-comando** — `tokenize`/`parse`/`desugar`/`resolve`/`check` são cada um o
   observável da sua fase (`driver.dart` inteiro); a F6 é FASE PRÓPRIA (ADR-0011, spec 014 §0).
2. **Estabilidade do corpus** — `conformance/check/*.tu` foi escrito para a semântica da F5
   (ex.: `err_try.tu` tem fns non-Void sem return em todo caminho — `semResult()`, linha 14).
   Dobrar a F6 para dentro de `itac check` quebraria fixtures verdes da F5 retroativamente.
3. O usuário final não perde nada: quando a F7 nascer, `itac build` roda o pipeline inteiro e o
   gate da F6 (013 §0.6) é obrigatório lá.

---

## 2. A descida — estrutura de retorno e estado do walker (item 2)

**Forma:** SDD L-atribuída (Dragon 5.2.4) = um DFS com atributos sintetizados
(`completesNormally` por stmt) e herdados (DA de entrada, contexto de loop). Sem ponto-fixo, sem
CFG — a indução estrutural do JLS §14.21 é a norma.

**Tipo de retorno por statement: `bool` cru** (`bool _stmt(ast.Stmt s)`), não record. Dos três
fatos, só `completesNormally` é SINTETIZADO puro; DA é estado do walker mutado in-place (com
cópia explícita em branch — §3), e reachability é DERIVADO na costura da sequência (o caller
decide, não o nó). Um record `(completes, da, reachable)` obrigaria cópia de set a CADA stmt —
custo sem retorno; a mutação disciplinada é o desenho do próprio javac (`Flow.java`).

**Estado do walker (`_FlowWalker`):**

```dart
final CheckResult _check;                        // nº1 exprTypes, nº4 annotations, nº2 types
final Map<ast.AstNode, ResolvedName> _resolution; // F4
final List<FlowError> errors;
final Map<ast.AstNode, bool> completesNormally;   // nº8 (saída)

final Set<Object> _domain = Set.identity(); // binders `var` rastreados (§3)
Set<Object> _da = Set.identity();           // definitely-assigned corrente
bool _unreachableReported = false;          // anticascata (§6)
_LoopCtx? _loop;                            // sawBreak + breakDAs (§7); null fora de loop
```

**Unidade de análise:** cada corpo top-level (fn/método/init/operator-fn) começa com
`_domain`/`_da` vazios e `_loop = null`. Closures são walked INLINE dentro do corpo que as cria
(§5) — não são unidades separadas, porque o DA delas herda o ponto de criação.

**Quem dispara os corpos** (`analyzeFlow` percorre `program.body`):

| Nó de topo / membro | Ação |
| :-- | :-- |
| `FnDecl` (topo, membro de Struct/Class/Enum/Trait/Actor/Impl/Extension) | corpo != null → walk (§11 missing-return + nº8) |
| `OperatorDecl` | `n.fn` idem |
| `InitDecl` | walk do body (sem missing-return — não tem `returnType`; nº8 sim) |
| `FieldDecl.defaultValue` | scan `self` (§9) + walk como expr (domínio vazio) |
| `Param.defaultValue` (fn/init/case-payload) | walk como expr (uso de global apenas; ver §14-L3) |
| `LetStmt` top-level (global) | **NÃO walked neste lote** — initializer é do const-eval (§5 da spec, lote seguinte) |
| `ImportDecl`/`ErrorDecl` | nada |

### 2.1 Tabela nó→regra — TODOS os 13 statements do `ast.dart` (§3, linhas 230-330)

Evidência de sobrevivência: o `_stmt` do desugar mapeia os 13 **1:1** (`desugar.dart:179-229`) —
Guard/GuardLet RETIDOS (`:197-208`), For RETIDO (`:215-222`). **Nenhum stmt é N/A.**

| Stmt | `completesNormally` | DA / notas |
| :-- | :-- | :-- |
| `LetStmt` | `value == null ∨ tipo(value) ≠ Never` | `isVar`: binders entram no `_domain` (§3); com `value` → também no `_da`. Never-clause: extensão Kotlin do precedente já assinado — ver §4. `let` sem valor NÃO existe (parser `let-requires-value`, `parser.dart:700`; `ast.asdl:86`: `value==null` só com `isVar` + `BindPattern`) |
| `ReturnStmt` | **false** | walk do `value` antes (JLS §14.21) |
| `IfStmt` | `¬hasElse ∨ C(then) ∨ C(else)` (carve-out do JLS p/ if-sem-else) | branch-merge por ∩ (§3); `ElseIf` recursa `_stmt(n.ifStmt)` |
| `GuardStmt` | **true** | §8: `C(orElse) == true ⟹ guard-must-exit`. DA do else é descartado (else não completa — vácuo) |
| `GuardLetStmt` | **true** | idem; walk: `value` → `condition?` → `orElse` (cópia). Binder é `let` — fora do domínio DA |
| `WhileStmt` | `true`, **exceto** cond `BoolLit(true)` sintático sem break ligado (§7) | body em cópia do DA (pode rodar 0×, JLS §16.2.10); DA-após = DA-após-cond; while-true: DA-após = ∩ breakDAs (§7) |
| `ForStmt` | **true** (pode rodar 0×; sem const-análise de iterable) | body em cópia, descartada; target é `let` per-iteração — fora do domínio |
| `BreakStmt` | **false** | marca `_loop.sawBreak` + snapshot do DA em `_loop.breakDAs` (§7) |
| `ContinueStmt` | **false** | nada além |
| `EmitStmt` | `tipo(value) ≠ Never` | mesma regra da nº1 (§4) |
| `ExprStmt` | `tipo(expr) ≠ Never` | **a linha da spec §2** — §4 |
| `BlockStmt` | = costura da sequência (§6) | sem gestão de escopo: chaves por identidade tornam saída de escopo grátis (§3) |
| `ErrorStmt` | **true** (defensivo) | inalcançável na F6: o driver aborta em erro de parse (`driver.dart:162-166`) |

**Costura de sequência** (`bool _stmts(List<Stmt>)` — usada por Block/corpo): itera; se `s_i` não
completa e existe `s_{i+1}` → mecânica do §6; senão continua. Sequência vazia completa. Após cada
stmt que completa: `_unreachableReported = false` (região fechada — §6).

### 2.2 Expressões — recursão estrutural total + 5 casos especiais

Switch EXAUSTIVO sobre `sealed Expr` (a lição do `check.dart:224-229`: nunca `default`).
Recursão em **ordem de avaliação** (receptor→args; left→right). Casos especiais:

| Expr | Regra |
| :-- | :-- |
| `Ident` | checagem de USO (§3): `LocalRes r` com `r.binder ∈ _domain ∧ ∉ _da` → `capture-before-assign` se `r.captured`, senão `use-before-assign`. `TopLevelRes`/`SelfRes`: nada (modelo D matou DA de global) |
| `Assign` | walk target-receptor (se `Member`/`Index`) → walk `value` → **GEN**: target `Ident→LocalRes` com binder no domínio ⟹ `_da.add(binder)`. `op != assign` (`+=` etc.) LÊ antes: o target-Ident é USO (checa) e depois GEN (JLS §16.1.8). Target-Ident de `=` puro NÃO é uso |
| `Closure` | §5 inteiro |
| `IfExpr` | `binding == null` sempre (if-let desugara p/ match, `desugar.dart:272-285`); walk subject; branches em cópias; merge ∩ com braço-Never = ⊤ (neutro) — §3/§4 |
| `MatchExpr` | walk scrutinee; por braço: guard em cópia descartada (é Bool — Assign:Void o barra de qualquer forma), body em cópia; DA-após = ∩ sobre braços com `tipo(body) ≠ Never` (braço que diverge é vácuo — §4); todos Never ⟹ o match é Never via join (`check.dart:1622-1650`) e a regra de STATEMENT já corta |

Demais (`Binary and/or`, `Try`, `CopyWith`, `Panic`, `Await`, `Spawn`, `Str`, `Tuple/List/Map/
Range`, literais, `ForceUnwrap` se sobreviver): recursão estrutural pura. **Por que `&&`/`||` não
precisam de cópias:** os conjuntos bivalentes do JLS §16.1 existiam por Assign-dentro-de-Bool;
`Assign : Void` (ruling §12-2) torna isso erro de TIPO na F5 — operando de `&&` é Bool ou
`not-bool` (`check.dart:1541-1544`). A maior economia da spec, colhida aqui. Açúcar que nunca
chega (coalesce/pipe/compose `desugar.dart:249-251`, if-let `:285`, opt-chain `:263`, where
`:513-586` → match aninhado): os cases ficam no switch (totalidade) como recursão estrutural —
inofensivos se mortos, corretos se um dia retidos.

---

## 3. Domínio DA — representação, chave, merge, ⊤ (item 3)

- **Domínio: só `var`** (009 §12-7; `let-requires-value` no parser matou a metade
  definitely-unassigned do JLS §16 — `let` nasce ligado). Populado no walk: `LetStmt(isVar:true)`
  → binders do pattern via a MESMA recursão do `_mutableBinder` da F5 (`check.dart:200-221`:
  Bind/Enum/Struct/Record; List/Rest são `pattern-binder-unsupported` — débito D4, nada a marcar).
  Sem valor ⟹ só domínio; com valor ⟹ domínio + DA.
- **Chave de identidade: o nó-binder** (`BindPattern`), `Set<Object>` com `Set.identity()` — é
  EXATAMENTE o domínio de `LocalRes.binder` (`scope.dart:44-49`) e de `binderTypes` (nº6,
  `type_table.dart:477-485`). `Object` e não `AstNode` porque `Param` não é AstNode (mas Param
  nunca entra no domínio — param nasce ligado).
- **Uso**: `_resolution[ident]` → `LocalRes` → membership. Zero re-resolução de escopo.
- **Escopo é GRÁTIS**: identidade de nó é única por declaração; um binder de branch/bloco morto
  léxico não é referenciável fora dele (F4 garantiu), então entradas "vazadas" em `_da` são
  inertes. Nenhuma pilha de escopos na F6.
- **Branch-merge**: `if`/`IfExpr`/`match` — walk de cada braço sobre CÓPIA; merge:
  `_da = ∩ { da_b | braço b completa }`. **⊤ (verdade vácua, JLS §16) nunca é estado
  armazenado** — é o elemento NEUTRO do ∩, representado por omissão: braço que não completa
  simplesmente não participa da interseção (no código: acumula com `null` = ainda-nenhum-braço).
  Se NENHUM braço completa, o stmt não completa e o caller para (§6) — o "estado ⊤" nunca vive.
  É o reticulado inteiro sem classe de reticulado.
- **Cópia**: `Set.identity()..addAll(_da)` nos branches. Sets são pequenos (vars vivos por corpo);
  O(|domínio|) por branch é ruído.

---

## 4. Never type-informed — tabela e chave exatas (item 4)

- **Tabela: nº1 `exprTypes`** (`Map<ast.Expr, Type>`, `check.dart:136` / `type_table.dart:464-467`).
  **Chave: o próprio nó `Expr` da árvore canônica** que o walker tem na mão (I1 garante que é a
  mesma identidade que a F5 povoou). Consulta: `_check.exprTypes[n.expr]` com falha-alta (I2).
- **Regra da spec §2:** `ExprStmt(e)` completa sse `tipo(e) is! NeverType` — cobre `panic(...)`
  (`check.dart:682`: `Panic → NeverType`) e todo Never derivado (match cujos braços divergem —
  join em `check.dart:1622-1650`).
- **Extensão do blueprint (mesma tabela, mesmo precedente Kotlin já assinado):** `LetStmt` e
  `EmitStmt` com `tipo(value) == Never` também não completam. `let x = panic("TODO")` é o idioma
  de rascunho irmão do CA21; Kotlin marca código após `val x = TODO()` como inalcançável. A spec
  §2 lista "as regras que não são óbvias", não é taxativa — isto NÃO a contradiz, completa a
  tabela por nó. Custo: uma consulta à nº1 que já está feita.
- **Fronteira deliberada (JLS-fiel):** Never ANINHADO em subexpressão não propaga —
  `x = panic("boom")` como ExprStmt tem `tipo(Assign) = Void` (`check.dart:1467`) ⟹ completa.
  O JLS §14.21 tem exatamente este comportamento (throw dentro de expressão não conta);
  propagar seria a análise de CFG de expressão do Kotlin — custo de outra classe, fora do
  desenho. Consequência aceita: `fn f() -> Int { x = panic("b") }` acusa `missing-return`
  (falso-positivo benigno; o fix — panic direto — é trivial e o Java faz igual).

---

## 5. Closures — obrigação na criação, DA inicial, sem recomputar captura (item 5)

**Norma:** spec §2 ("criação = cria OBRIGAÇÃO de DA") + §3 ("`var` livre capturado ∉ DA");
fundamento C# spec (DA × anonymous functions): *o DA de uma variável externa no início do corpo
da função anônima = o DA no ponto de criação; atribuições lá dentro não fluem para fora* (a
closure roda em momento arbitrário — ou nunca).

**Identificar capturas com o que a F4 já pagou — zero re-resolução:** um `Ident` no corpo da
closure cujo binder vive FORA dela tem `LocalRes.captured == true` por construção
(`resolver.dart:121`: `crossedFn` liga ao cruzar `isFnBoundary`); um Ident de local PRÓPRIO da
closure tem `captured == false` (o binder é achado antes da fronteira). Logo
`captured ∧ binder ∈ _domain` ⟺ "é `var` rastreado capturado" — o flag da F4 é o detector.

**Mecânica no nó `Closure`:**

1. **Pre-scan de obrigação**: percorre a subárvore do corpo coletando
   `{ binder → Ident de menor offset }` para todo Ident com
   `LocalRes(captured: true) ∧ binder ∈ _domain`. Para cada binder `∉ _da` →
   **`capture-before-assign`**, UM por binder por closure, **span no primeiro Ident capturador**
   (o formato de erro é `code @off+len` sem payload — apontar o Ident nomeia a variável de
   graça; apontar a closure inteira seria mudo). Custo: O(corpo) por nível de aninhamento —
   aceitável; a alternativa fundida (checar durante o walk do corpo) perde a semântica de
   criação e complica a atribuição do erro.
2. **Anticascata**: adiciona TODOS os binders capturados a uma CÓPIA do `_da` — o erro já foi
   dado na criação; o corpo não re-acusa uso a uso.
3. **Corpo**: salva `_loop` e zera (`break` não cruza fronteira de fn — espelho de
   `resolver.dart:295-297`); salva `_da` e walka o corpo sobre a cópia do passo 2 (**DA inicial =
   DA do ponto de criação** — a resposta do item 5, C# verbatim); `BlockBody` → costura §6 +
   `completesNormally[closure] = resultado` (nº8) + predicado §11; `ExprBody` → walk da expr.
4. **Descarte**: restaura `_da` e `_loop` — *assign lá dentro NÃO flui pra fora* (CA7, 2ª cláusula).

**Aninhamento**: o pre-scan da closure EXTERNA já vê os Idents profundos (captura transitiva —
`captured` é true neles também); locais da closure externa capturados pela interna só entram no
domínio quando o walk da externa os declara, e a obrigação deles é checada na criação da INTERNA.
Sem contagem dupla: o passo 2 já os pôs em DA.

**Delta anotado vs C# (sem ruling — a spec crava):** a obrigação vale para QUALQUER ocorrência
capturada, inclusive write-only (`var x: Int; let f = { x = 1 }` → erro na criação). O C# aceita
a lambda e só policia leituras. A forma da spec é mais estrita E mais simples (captura no Kernel
é por referência de contexto — a célula É usada), e relaxar depois é backwards-compatible
(aceita mais programas). Registrado; não bloqueia.

---

## 6. `unreachable-code` sem cascata — a mecânica exata (item 6)

**Regra do DoD:** UM erro por região morta. Mecânica (o bit de recovery do javac, adaptado):

1. Na costura de sequência, quando `s_i` não completa e existe `s_{i+1}`:
   - se `_unreachableReported == false` → **`unreachable-code` no span de `s_{i+1}`** e seta o flag;
   - se `true` → NÃO re-emite (a morte já foi acusada dentro de `s_i` — a região é a mesma);
   - em ambos os casos **PARA de walkar o resto do bloco** (irmãos mortos não são visitados:
     zero erros aninhados, zero DA fantasma, zero flowFacts de código morto) e retorna
     `completa = false` — a VERDADE (o bloco não completa; é o que faz
     `fn f() -> Int { return 1; junk }` acusar SÓ unreachable, nunca missing-return junto —
     removido o morto, o programa fica verde: o erro segue o fix).
2. `_unreachableReported` limpa quando um stmt COMPLETA na costura (região fechada) e no início
   de cada corpo top-level.

**Regiões aninhadas, os dois sentidos:**
- *Morto DENTRO de morto*: nunca walkado ⟹ nunca reportado. Ex.: `return; if c { junk }` — um
  erro, no `if`.
- *Morte que ATRAVESSA blocos*: `{ return; x } y` — erro em `x` (bloco interno); o interno
  retorna `false` com o flag setado; o externo vê `y` morto, flag em pé ⟹ silêncio. UMA região
  dinâmica, UM erro. Já `if c { return } else { return } y` não setou flag em lugar nenhum ⟹
  erro em `y`, correto.

---

## 7. `while true` — onde vive o "tem break ligado" (item 7)

**Carve-out SÓ para `BoolLit(true)` sintático** (ruling assinado — sem const-fold; o desugar não
toca literais, o nó chega intacto). O "break ligado ao loop" é **flag sintetizado na própria
descida** — nada de re-resolver:

```dart
class _LoopCtx {
  bool sawBreak = false;
  final List<Set<Object>> breakDAs = []; // snapshot do _da em cada break
}
```

- Entrar em corpo de `while`/`for`: `save = _loop; _loop = _LoopCtx()`. Sair: restaura. Isso dá
  o binding ao loop MAIS PRÓXIMO de graça: `while true { for x in xs { break } }` — o break
  marca o ctx do `for`, o while-true fica sem break ⟹ não completa. Correto por construção.
- Fronteira de closure zera `_loop` (§5 passo 3) — o espelho em-fase do corte da F4
  (`resolver.dart:295-297`); um `break` dentro da closure nem chega aqui legal (F4 já deu
  `break-outside-loop`), mas um `while { break }` INTERNO à closure não pode destravar o
  while-true EXTERNO — é a fixture da fronteira (§13).
- `BreakStmt`: `_loop!.sawBreak = true; _loop!.breakDAs.add(cópia de _da)`. (`_loop` não-nulo:
  F4 garantiu break-em-loop; `!` com StateError é o contrato I2.)
- Fechamento do `WhileStmt` com cond `BoolLit(true)`:
  `completa = ctx.sawBreak`; se completa, `_da = ∩ ctx.breakDAs` — **JLS §16.2.10**: V é DA após
  o while sse DA antes de cada `break` (o caminho cond-false não existe). É o que deixa verde o
  idioma `var x: Int; while true { x = f(); break }; usa(x)`. Para while comum a interseção
  colapsa em DA-após-cond (todo breakDA ⊇ DA-do-início-do-corpo = DA-após-cond) — não computa.

---

## 8. `guard-must-exit` — mesmo predicado, sítio novo (item 8)

Confirmado contra a forma pós-desugar: `GuardStmt` e `GuardLetStmt` sobrevivem VERBATIM
(`desugar.dart:197-208` — retidos porque continuação + else-divergente são statements, RD-1).
Regra: `elseCompletes = _block(n.orElse)` (sobre cópia do DA); se `true` →
**`guard-must-exit` com span no bloco `orElse`** (o sítio do pecado — CA4). O guard em si
completa `true` (a continuação é o caminho cond-verdadeira). Nada além: é LITERALMENTE o mesmo
predicado `completesNormally` aplicado ao else (Swift TSPL Early Exit, ruling §12-3). Em
`GuardLetStmt`, `value` e `condition` (o `&&`-refino) são walked antes; o binder é `let` — fora
do DA.

---

## 9. `self-in-field-default` — sítio e reconhecimento (item 9)

- **Evidência de que é dívida da F6:** a F4 RESOLVE `self` dentro de `FieldDecl.defaultValue` —
  `resolver.dart:249-255` seta `_selfType` antes de `_expr(n.defaultValue!)`, então o `SelfExpr`
  vira `SelfRes` sem erro. A proibição (008 §133; o Kernel não tem `this` em initializer de
  campo) ficou prometida à F6 — ledger (h) da spec.
- **Reconhecimento: SINTÁTICO** — scan da subárvore do `defaultValue` por nós `SelfExpr`. É
  completo porque `self` é sempre explícito no Itá (P4): a F4 não injeta campos no escopo
  léxico (não há campo-implícito que um `Ident` alcance — `resolver.dart` só liga `self` via
  `_selfType`), logo todo acesso a estado da instância passa por um `SelfExpr` físico. Closures
  dentro do default idem (o `this` também não existe lá no Kernel — a captura não salva).
- **Erro por OCORRÊNCIA**, span no `SelfExpr` (pecados distintos, spans precisos; a regra
  "um-por-região" é do código morto, não daqui).
- **Onde:** no dispatcher de decls do `analyzeFlow` (§2, tabela) — para TODO `FieldDecl` com
  `defaultValue` em qualquer lista de membros (Struct/Class/Enum/Actor/Trait/Impl/Extension —
  uniforme; se a F5 rejeita campo em algum desses, a F6 nem chega lá por I3).

---

## 10. `flowFacts` (nº8) — chave, valor, saída (item 10)

- **Valor:** `bool completesNormally` (cru — YAGNI num record de um campo; o dia em que a F7
  pedir mais fatos, o Map muda de valor, não de chave).
- **Chave:** o nó DONO do corpo — `FnDecl | InitDecl | Closure`, todos `AstNode`, identidade.
  NÃO o `FnBody` (produto sem span, sem utilidade de lookup para a F7, que caminha por decls) e
  NÃO só "fn": o §7 diz "por corpo", e a F7 emite `FunctionNode` para closure e `Constructor`
  para init — o throw defensivo de fim-de-corpo (o motivo de existir da nº8: o verifier do
  Kernel não checa queda-do-fim; o CFE emite `ReachabilityError` no caso análogo — 013 §0.6)
  vale nos três.
- **Só corpos `BlockBody`**: corpo `=>` vira `ReturnStatement(expr)` na F7 — não há fim-de-corpo
  do qual cair (RD-1); registrar seria ruído.
- **Totalidade**: garantida em programa VERDE (todo BlockBody alcançado tem entrada). Com erro,
  parcial por design — código morto não é walkado (§6) e a F7 nunca roda (gate). ADR-0004: a F7
  NÃO recomputa.
- **Saída:** campo `completesNormally` do `FlowResult` (§1.1) — o padrão da 011.
- **Observável:** `itac flow --dump-facts`, uma linha por corpo em ordem de offset:
  `fn <name> @<off>+<len> completes=<bool>` · `init @<off>+<len> …` · `closure @<off>+<len> …`.
  Determinístico; vira golden `.facts` no corpus (§13).

## 11. `missing-return` — o predicado (item 11)

JLS §8.4.7 verbatim: *erro se o corpo PODE completar normalmente e a fn declara retorno*.

```
corpo é BlockBody                                  (RD-1: `=>` nunca roda o predicado)
∧ corpo completesNormally == true                  (o fato da nº8, recém-computado)
∧ ret ≠ Void                                       (inclui ret = Never — spec §3)
∧ asyncMarker ≠ asyncStar                          (stream fn rende por `emit`; fim-de-corpo
                                                    fecha o stream — precedente gerador Dart/Java)
⟹ missing-return @span da decl
```

- **`ret` de `FnDecl`:** `returnType == null` ⟹ Void (sem `->` = Void, nada a checar); senão
  `annotations[fn.returnType]` (nº4, `type_table.dart:461-462`) — falha-alta se ausente (I2).
- **`ret` de `Closure` com BlockBody:** `exprTypes[closure]` é `FunctionType` (totalidade da
  nº1) → `.ret`. Closure É fn — a leitura natural do §3, e o buraco de soundness (cair do fim
  com retorno non-Void) é idêntico; a F7 precisaria do fato de qualquer jeito.
- **`async`** entra (cair do fim de `async fn f() -> Int` completaria o Future com null — o
  veneno do ADR-0013); **`InitDecl`** não tem returnType — isento.
- **CA21 é consequência, não caso especial:** `fn f() -> Int { panic("TODO") }` → ExprStmt
  Never (§4) → corpo NÃO completa → predicado falso → VERDE. CA2 idem. CA5: while-true sem
  break não completa → verde; com break completa → precisa do return.

---

## 12. Ordem de implementação sugerida (fatias testáveis)

1. Esqueleto `flow.dart` + costura + completes por stmt (sem DA): fecha `missing-return`,
   `unreachable-code`, `guard-must-exit`, while-true (§7 sem breakDAs) e nº8.
2. `flowProgram`/`runFlow` no driver + `--dump-facts`.
3. DA: domínio + uso + Assign-GEN + merges (if/IfExpr/match) + breakDAs: fecha
   `use-before-assign`.
4. Closures (§5): fecha `capture-before-assign`.
5. `self-in-field-default` (scan independente — pode ser a fatia 0, é a mais barata).

## 13. Corpus `conformance/flow/` (item 12)

**Formato:** o runner espelha `collect_test.dart:49-59/828-833` — casa a lista EXATA de códigos
em ordem-fonte via `// EXPECT-FLOW: <code>`; fixtures verdes usam golden `.facts` (o runner de
`.types` como molde, `collect_test.dart:33-46`): golden presente ⟹ exige zero erros + dump
`--dump-facts` byte-igual. Casos verdes no MEIO de fixture de erro são bem-vindos (o padrão do
`err_try.tu`: falso-positivo neles quebra a lista).

| Arquivo | CA | Regra coberta |
| :-- | :-- | :-- |
| `missing_return_if.tu` | CA1 | §11 — `if` sem else, return só no then ⟹ `missing-return` |
| `never_body.facts` (verde) | CA2 | §4 — `panic` como corpo: sem erro E `completes=false` no golden (testa a nº8 direto) |
| `guard_must_exit.tu` | CA4 | §8 — else que completa ⟹ erro; else com `return`/`panic` verde no mesmo arquivo |
| `while_true.tu` | CA5 | §7 — sem break: verde non-Void; com break + sem return depois: `missing-return` |
| `use_before_assign.tu` | CA6 | §3 — uso antes; atribuído nos 2 braços ⟹ verde; só num braço ⟹ erro |
| `capture_before_assign.tu` | CA7 | §5 — captura ∉ DA ⟹ erro; assign interno não libera uso externo (`use-before-assign` no uso de fora) |
| `unreachable_after_return.tu` | CA13 | §6 — ERRO (§12-1); incluir a variante `{ return; x } y` = UM erro |
| `self_in_field_default.tu` | CA14 | §9 |
| `panic_todo_green.facts` (verde) | CA21 | §11 — a fixture NOMEADA do idioma de rascunho |
| `closure_loop_boundary.facts` (verde) | §8 da spec | §7 — `while true` externo com closure contendo loop+break interno: o break NÃO destrava o while-true (fn non-Void + return ausente = segue verde porque o while não completa) |
| `while_true_break_da.facts` (verde) | (bônus §7) | JLS §16.2.10 — `var x; while true { x = 1; break }; usa(x)` verde |

(CA3/CA8/CA9 = lote Maranget; CA10/CA15–CA20 = lote const-eval; CA11/CA12 já pagos no §1 —
`2d46313`.)

## 14. Lacunas e achados (não bloqueiam este lote; não resolver sozinho)

- **L1 — `resolution` fora do `CheckResult`** (§1.1): resolvido via driver aqui; promover a
  contrato quando a F7 especificar. Plumbing, não ruling.
- **L2 — Estritude da captura write-only** (§5): a spec crava "ocorrência capturada"; delta vs
  C# anotado; relaxamento futuro é compatível. Registrado, sem ruling.
- **L3 — `self` em default de PARÂMETRO**: a F4 o resolve (`resolver.dart:272-288` seta
  `_selfType` antes de `_resolveFunction`, que resolve defaults em `:300-302`) e NENHUMA spec o
  proíbe — mas o alvo Kernel quase certamente não o suporta (default de param não tem `this`).
  Irmão do §9 sem assento normativo. **Rotear: pergunta ao `dart-vm-expert` + nota de spec do
  dono** (possível `self-in-param-default`).
- **L4 — Never aninhado não propaga** (§4): fronteira deliberada, JLS-fiel, documentada — não é
  lacuna, é recusa com fundamento; fica registrada para não reabrir por acidente.
