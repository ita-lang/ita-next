# binding.md — Regras de escopo e resolução de nomes (Fase 4 — Binding)

> Artefato formal da **Fase 4** (ADR-0010: *"doc de regras de escopo / resolução de nomes"*).
> Fonte-da-verdade **citável** do binding; par do [`ast.asdl`](./ast.asdl), [`grammar.ebnf`](./grammar.ebnf)
> e [`desugar.md`](./desugar.md). O código (`lib/frontend/binding/`) é a materialização à mão (P11).
>
> **Fundamentação:** Crafting Interpreters cap 11 (resolver estático) · Dragon Book 1.6.1/1.6.3 (escopo
> léxico), 2.7/2.7.1 (tabela de símbolos encadeada), 5 (SDD/atributos). **Contrato:** ADR-0011 (F4 produz
> nome→decl + hops; F5 consome, não reconstrói escopo). **Side-table por identidade:** ADR-0004.
> **Spec de processo:** `specs/008-binding/`.

## Modelo

O Binding é um **passe estático** (nenhum efeito de runtime) que produz, para cada uso de nome, a
declaração-alvo. Roda sobre a AST **canônica** (pós-Fase 3) e **não a muta** — grava numa side-table:

```
Map.identity<Expr, ResolvedName>              -- chave = nó de USO (Ident | SelfExpr), por IDENTIDADE

sealed ResolvedName
  = LocalRes(AstNode binder, int hops)        -- binder ∈ { BindPattern, Param };  hops = nº de escopos
  | TopLevelRes(Decl decl)                     -- FnDecl | Struct/Class/Enum/TraitDecl | global let/var
  | SelfRes(AstNode receiver)                  -- o self sintético do método envolvente
```

O valor aponta o **nó-declaração** (não só `hops` como no Lox 11.4): o alvo é o Dart Kernel, que referencia
variáveis **por objeto** (`VariableGet(VariableDeclaration)`), não por nome+distância — modelo rustc
(`Res::Local`/`DefId`). O `hops` permanece: contrato ADR-0011 + **detecção de captura** (uso cujo `hops`
cruza fronteira de `Closure`/`FnDecl` = variável capturada).

## Disciplina de escopo

- **Pilha de escopos** encadeados (Dragon 2.7.1: o aninhamento forma uma pilha). `beginScope`/`endScope` por
  bloco. Lookup sobe a cadeia; o mais interno vence (Dragon 1.6.3 — shadowing).
- **1 walk, O(n)** (CI 11.2.1): sem short-circuit — visita os dois ramos do `if`, o corpo do loop 1×.
- **Split declare/define** (CI 11.3.2): `let x = e` ⟹ *declare* `x` (existe, não-pronto) → resolve `e` →
  *define* `x`. Um uso de `x` dentro de `e` = `read-in-own-initializer`. `FnDecl` define **ansioso**
  (antes do corpo) → permite recursão.

## Regras de resolução (por escopo)

- **Módulo — letrec (two-pass):** todos os nomes top-level (`fn`, tipos, `let`/`var` globais) são
  declarados ANTES de resolver qualquer corpo → visibilidade mútua independente da ordem textual (recursão
  mútua; coerente com o `where`-letrec da spec 006). A ordem de *inicialização* em runtime é Fase 6.
- **Bloco / fn — léxico estrito (single-pass):** um `let x` local entra em escopo **após** sua declaração
  (Dragon 1.6.3; CI 11.1). Itá é estático — não hoista como JS.
- **Shadowing:** permitido em escopo ANINHADO (o interno vence). Proibido no MESMO escopo →
  `duplicate-declaration`.
- **Namespace UNIFICADO** (um nome = um significado, P4): não há namespaces separados valor/tipo
  (diferente de rustc). `Foo(…)` resolve `Foo` no mesmo espaço.
- **`self`:** binder sintético injetado no corpo de método; `SelfExpr` → `SelfRes`.

### Tratamento por nó (AST canônica)

| Nó | Escopo | Liga |
| :-- | :-- | :-- |
| `Block`/`BlockStmt` | novo | — |
| `FnDecl`/`InitDecl` | nome externo (ansioso); corpo filho | `Param`s no corpo |
| `Closure` | filho | `Param`s (incl. `$0`) |
| `LetStmt`/`var` | atual | cada nome do pattern (destructuring) |
| `MatchExpr` arm | 1 filho por braço | nomes do pattern |
| `ForStmt` | filho (corpo) | `target` |
| `GuardLetStmt` | **continuação** (escopo atual, a partir do ponto) | `target` |
| `Try`/`CopyWith`/`Binary.pow`/if-bool | — | só recursão nos filhos |

## Fronteira F4 ↔ F5 (contrato ADR-0011)

| Resolve em **F4 (Binding)** | Fica para **F5 (Semântica)** — type-directed |
| :-- | :-- |
| `Ident` local/param/global/callee | `Member.name` / `.field` / `.método` (tipo do receptor — Dragon 1.6.4) |
| `SelfExpr` | `.variant` / `EnumShorthand` (contextual) |
| binders (pattern/param/for/match/guard-let) | aridade / overload / currying (assinatura) |
| — | namespace de **TIPO** (`NamedType`/annotations/bounds — inseparável do reticulado) |

## Erros de binding (type-agnostic — EN kebab-case + span)

| Erro | Quando |
| :-- | :-- |
| `unresolved-name` | nome não declarado (Itá é estático — diverge do Lox, que adia p/ runtime) |
| `read-in-own-initializer` | `let a = a` |
| `duplicate-declaration` | redeclaração no mesmo escopo |
| `self-outside-method` | `SelfExpr` sem método envolvente |
| `break`/`continue`-outside-loop; `return`/`emit`-outside-fn/stream | context-flag (CI 11.5.1) |

**F5/F6:** `assign-to-immutable` (alvo type-directed), definite-return / unreachable / use-before-assign
(path-sensitive, flow-graph — Fase 6).

## Observável

`itac resolve <f.tu> --dump [--spans]` — pipeline **parse → desugar → bind**. A árvore é IDÊNTICA ao
`desugar --dump` (mesmo `AstDumper`, via callback `annotate` — o printer NÃO importa `binding/`), mas cada
`Ident`/`SelfExpr` ganha **um filho** com a resolução (formato determinístico ASCII):

| Anotação | Significado |
| :-- | :-- |
| `->L<binderOffset>^<hops>` | **local**: liga ao binder no offset dado; `hops` = escopos cruzados (0 = mesmo escopo) |
| `->L<binderOffset>^<hops>*` | idem, **capturado** (`*` = o uso cruza uma fronteira de fn/closure — Grupo B, diagnóstico) |
| `->T<declOffset>` | **top-level** (letrec de módulo) — sem `hops` |
| `->S<receiverOffset>` | **self** (método) — offset do nó do tipo envolvente |
| `->?` | **não resolvido** (`unresolved-name` / `self-outside-method`) — ausente na side-table |

Ex.: `(id x ->L42^1*)` = `x` liga ao binder no offset 42, 1 escopo acima, capturado. `(self ->S7)`. Erros de
binding: `resolve-error: <code> @<offset>+<length>`. Corpus `conformance/resolve/*.tu` → `.resolve` (dump
anotado) e `.errors` (erros), cruzados com o oracle `ita/`. Gate único `make test`.

## Notas de fronteira (Grupo B)

- **Captura de closure NÃO é materializada:** a Dart VM faz closure-conversion nativa (Grupo B). O Kernel
  emite `VariableGet` referenciando o `VariableDeclaration` externo direto; F4 só *sinaliza* a captura via
  `hops`, não constrói upvalues (diverge do clox).
- **Imune ao bug de vazamento do Lox (CI 11.1.1) por construção:** resolução estática ao nó-binder + AST
  imutável + Kernel-por-objeto — o cenário do bug (re-resolver por nome em runtime) não existe.
