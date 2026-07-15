# Spec 008: Fase 4 — Binding / resolução de nomes

> **Tipo:** feature-fase · **Marco:** `Fase 4 (Binding) do ita-next`
> **Status:** `draft`
> **Autor / Data:** orquestração (Claude) · 2026-07-12 · **Fundamentação:** Crafting Interpreters cap 11 + Dragon Book 1.6/2.7 + oracle `ita/semantic/`; levantamento `compiler-craftsman` 2026-07-12

## §0 Metadados

- **Classe da mudança:** [x] **Nova regra/fase** — a Fase 4 (Binding) do ADR-0011: um passe que liga cada uso de nome à sua declaração, entre o Desugaring (Fase 3) e a Semântica (Fase 5).
- **Fases tocadas:** [ ] Léxico · [ ] Sintaxe · [ ] Formal · [x] **SDD/atributos (§5)** · [ ] Fluxo · [ ] Codegen · [ ] Runtime
- **Princípios afetados:** P1 (imutável — `let a = a` é erro; imutabilidade informa a resolução), P4 (sem mágica — namespace unificado; resolução estática visível), P2 (valor/ref — `self` implícito resolvido). **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

Vereditos do `ita-visionary` (2026-07-12): (1) **namespace unificado** (um nome = um significado — P4; recusa a separação valor/tipo do rust-style); (2) **shadowing aninhado permitido** (o mais interno vence, Dragon 1.6.3), mas **redeclaração no mesmo escopo = erro** `duplicate-declaration` (imutável-por-default); (3) **top-level = letrec de módulo** (`fn`/tipos/globais mutuamente visíveis por NOME, ordem textual não importa — coerente com o `where`-letrec da spec 006; a ordem de *inicialização* em runtime é Fase 6). **Sem conflito aberto.**

## §1 Motivação e resumo

Após o Desugaring, a AST canônica tem nomes (`Ident`, `SelfExpr`) que ainda **não sabem a que declaração se referem**. A Fase 4 resolve isso: um passe estático que, para cada uso, produz o **nó-declaração alvo** + a profundidade de escopo (hops), numa **side-table por identidade** (ADR-0004 — a AST fica imutável). É o pré-requisito da Semântica (Fase 5), que **consome** a resolução e **não reconstrói escopo** (contrato ADR-0011).

**Antes → Depois** (observável via `itac resolve --dump`):

```tu
fn outer() {
  let x = 1
  fn inner() { x }   // antes: `x` é um Ident solto
}
```
```
// depois: side-table anota
//   x (uso em inner) → binder = o `let x` de outer, hops = 1 (cruza a fronteira de inner → capturado)
```

**Não-objetivos:** (1) **tipos** — F4 não infere nem checa tipo (F5). (2) `.field`/`.método`/`.variant` (o SELETOR pós-`.`) — type-directed, resolve em F5. (3) aridade/overload/currying — precisam da assinatura (F5). (4) `assign-to-immutable`, definite-return, use-before-**assign** — flow/type-directed (F5/F6). (5) **captura de closure** não é materializada (a Dart VM faz closure-conversion nativa — Grupo B); F4 só *sinaliza* que um uso cruza fronteira.

---

## §5 A fase de Binding — `[CI cap 11; Dragon 1.6/2.7/5]`

### 5.1 O que o Binding produz (a decisão-mãe)
Uma side-table `Map.identity<Expr, ResolvedName>` — chave = nó de **uso** (`Ident` | `SelfExpr`); valor:

```
sealed ResolvedName
  = LocalRes(AstNode binder, int hops)   -- binder = BindPattern | Param
  | TopLevelRes(Decl decl)               -- FnDecl | Struct/Class/Enum/TraitDecl | global let/var
  | SelfRes(AstNode receiver)            -- o self sintético do método
```

**Divergência fundamentada do Lox (CI 11.4):** o Lox guarda só `hops` (seu runtime sobe cadeia por distância). O Itá aponta o **nó-binder**, porque o alvo é o **Kernel**, que referencia por objeto (`VariableGet(VariableDeclaration)`) — modelo **rustc** (`Res::Local(node)`/`DefId`). O `hops` permanece (contrato ADR-0011 + detecção de captura: um uso cujo `hops` cruza fronteira de `Closure`/`FnDecl`).

### 5.2 Arquitetura do passe
- **Resolver visitor com pilha de escopos** (CI 11.3; Dragon 2.7.1 — a cadeia forma uma pilha), **1 walk O(n)** (CI 11.2.1 — sem short-circuit; visita os dois ramos do `if`, o corpo do loop 1×).
- **Two-tier:**
  - **Módulo = declare-ALL-then-resolve** (letrec, §0.5-3): passada 1 registra todos os nomes top-level; passada 2 resolve os corpos → recursão mútua (`fn a` chama `fn b` posterior). Espelha o `_collectTopLevelBindings` do oracle.
  - **Bloco/fn = single-pass léxico:** um `let x` local só entra em escopo **após** sua declaração (Dragon 1.6.3; CI 11.1). Uso-antes-da-declaração de um local resolve o de fora ou é erro (Itá é estático, estilo Rust/Swift — **não** hoista como JS).
- **Split declare/define** (CI 11.3.2): ao visitar `LetStmt`, **declare** o binder → resolve o `value` → **define**. Captura `let a = a` como `read-in-own-initializer`. `FnDecl`: define ansioso (permite recursão, CI 11.3.5).

### 5.3 Tratamento por construção (AST canônica — só nós core)

| Construção | Ação |
| :-- | :-- |
| `Block`/`BlockStmt` | `beginScope`/`endScope` |
| `FnDecl`/`InitDecl` | nome no escopo externo (ansioso); `Param`s em escopo-filho do corpo |
| `Closure` | escopo-filho; `Param`s (incl. gensym `$0`) ligados nele |
| `LetStmt`/`var` | declare→resolve-init→define; **destructuring** liga CADA nome do pattern |
| `MatchExpr` arm | um escopo-filho por braço; o pattern liga nomes nele |
| `ForStmt` | escopo-filho do corpo; `target` liga no corpo |
| `GuardLetStmt` | **escopo de continuação** — liga `target` no escopo ATUAL a partir dali (§5.6-risco) |
| `SelfExpr` | liga ao `self` sintético do método; fora de método = erro |
| gensyms `$x`/`$c`/`$it` (do desugar) | binders **ordinários** (a higiene garante unicidade) |
| `Member.name` / `.variant` / callee-overload | **NÃO resolve** — só o receptor/`Ident`-callee |

### 5.4 Contrato F4 ↔ F5 (fronteira precisa)
- **F4:** namespace de **valor** com escopo léxico (`Ident` local/param/global/callee, `SelfExpr`, todos os binders). É a parte cara (hops/closures/shadowing).
- **F5:** tudo **type-directed** — `Member`/`.field`/`.método` (precisa do tipo do receptor, Dragon 1.6.4), `.variant`/`EnumShorthand` (contextual), aridade/overload/currying, e o **namespace de TIPO** (`NamedType`/annotations/bounds — mais plano, inseparável do reticulado de tipos; o oracle já o faz em F5).

### 5.5 Erros de binding (type-agnostic)

| Erro | Nota |
| :-- | :-- |
| `unresolved-name` | **diverge do Lox** (que adia p/ runtime); Itá é estático → erro de compilação (Dragon 1.6.3) |
| `read-in-own-initializer` (`let a = a`) | CI 11.3.2/11.5, via split declare/define |
| `duplicate-declaration` | redeclaração no MESMO escopo (§0.5-2); shadowing aninhado é OK |
| `self-outside-method` | `SelfExpr` sem método envolvente |
| `break`/`continue` fora de loop; `return`/`emit` fora de fn/stream | context-flag no resolver (CI 11.5.1) — **F4** (nesting-context, type-agnostic) |

**Ficam para F5/F6:** `assign-to-immutable` (o alvo `obj.field` é type-directed → F5), definite-return / unreachable / use-before-**assign** (path-sensitive → F6).

### 5.6 Riscos
- **`guard let` = escopo de continuação** (o mais traiçoeiro): liga `target` para o **resto do bloco**, não um filho.
- **`self` implícito:** binder sintético; `SelfExpr` já é nó distinto (sem colidir com `Ident("self")`).
- **Ordem 3→4→5:** o Binding vê só o CORE (sem `where`/`|>`/`??`/if-let — lowered). Trata os retidos (`GuardLetStmt`/`ForStmt`/`MatchExpr`/`Closure`/`Try`/`CopyWith`); só os que abrem escopo interessam.

---

## §9 Checklist de completude
- [ ] `binding/` — resolver visitor, pilha de escopos, two-pass módulo + single-pass bloco
- [ ] Side-table `Map.identity<Ident|SelfExpr, ResolvedName>` (nó-binder + hops)
- [ ] Split declare/define; `FnDecl` ansioso
- [ ] `itac resolve --dump` (parse→desugar→bind) + função pura testável
- [ ] Erros §5.5 (kebab-case + span)
- [ ] Corpus `conformance/resolve/*.tu` → `.resolve` + `.errors`
- [ ] `dart analyze` limpo; `make test` verde

## §10 Compatibilidade e alternativas
- **Breaking change?** Não — fase nova; `desugar --dump` inalterado. `resolve --dump` é output novo.
- **Rulings cravados:** namespace unificado; shadowing OK + dup-erro; letrec de módulo; side-table aponta o nó-binder (não só hops); F4=valor/escopo, F5=type-directed.
- **Alternativas descartadas:** só-hops estilo Lox (não serve ao Kernel-por-objeto); namespaces separados rust-style (contra P4); name-res unificado com type-names em F4 (duplica o walk que F5 precisa — split honra ADR-0011); marcar capture-set explícito (a VM faz closure-conversion — Grupo B).

## §11 Critérios de aceite (viram corpus `.resolve`/`.errors`)
- **CA1** — local: `let x = 1` … `x` ⟶ `x` resolve ao binder `let x`, hops 0.
- **CA2** — aninhado: uso de `x` dentro de bloco/closure interna ⟶ hops > 0 (cruza fronteira = capturado).
- **CA3** — letrec: `fn a() { b() }` … `fn b() { }` ⟶ `b` resolve (forward-ref, recursão mútua).
- **CA4** — `unresolved-name`: uso de nome não-declarado ⟶ erro com span.
- **CA5** — `read-in-own-initializer`: `let a = a` ⟶ erro.
- **CA6** — `duplicate-declaration`: `let x = 1; let x = 2` no mesmo escopo ⟶ erro. (Shadowing aninhado NÃO é erro — CA7.)
- **CA7** — shadowing: `let x = 1; { let x = 2; x }` ⟶ o `x` interno resolve ao binder interno (o mais interno vence).
- **CA8** — `self`: `SelfExpr` em método ⟶ `SelfRes`; fora de método ⟶ `self-outside-method`.
- **CA9** — `break` fora de loop ⟶ erro.
- **CA10** — `guard let v = o else { return }` … `v` depois ⟶ `v` resolve (escopo de continuação).
- **CA11** — destructuring: `let (a, b) = p` ⟶ `a` e `b` ligam a binders distintos.
- **CA12** — gensym: um `??` (que virou `match .some($x)`) ⟶ `$x` resolve como binder ordinário (sem tratamento especial).

## §7-nota — Débitos de codegen (Fase 7), do review `dart-vm-expert`

A side-table é forward-compatible (a decisão de apontar o **nó-binder** casa com `VariableGet.variable` do Kernel — por objeto). Débitos do CODEGEN (não da F4):
1. Mapa `binder-node → VariableDeclaration` (`Param`/`BindPattern`/`RestPattern`) → `VariableGet`.
2. Mapa `Decl → Kernel Member/Reference` (two-pass, espelha o letrec); estáticos usam `Reference`, não objeto direto. Global `let` cujo `decl` é `BindPattern` → `StaticGet`/`StaticSet`.
3. Dispatch por forma do uso de `TopLevelRes`: invoke → `StaticInvocation`; tear-off → `StaticTearOff`; `Foo(…)` → `ConstructorInvocation`.
4. **D4 (modelagem, recuperável):** `FieldPattern` (record/struct homônimo `{ x, y }`) não é `AstNode` e não tem span → dois binders colidem no dump `->L<offset>`. Recuperável por `Ident.name` no codegen; **fix futuro:** dar span próprio ao `FieldPattern` (toca parser). Sem golden que exercite hoje.
5. `self` de `extension`/`impl` → `VariableGet(#this)` (param sintético), não `ThisExpression` (dispatch pelo kind de `SelfRes.receiver`).
6. **Legalidade F5/F6:** `self` em `FieldDecl.defaultValue` (Dart proíbe `this` em init de campo) — verificar antes do codegen.

## Definition of Done
- [ ] CAs cobertos por corpus `.resolve`/`.errors` + unit, verdes via `itac resolve --dump`.
- [ ] Resolver + side-table à mão (P11); AST imutável (não anota tipos/símbolos nos nós — ADR-0004).
- [ ] Contrato F4↔F5 respeitado (nada type-directed resolvido aqui).
- [ ] Constitution check sem conflito + code review de identidade (`ita-visionary`) aplicado.
- [ ] `make test` + `dart analyze` verdes.
