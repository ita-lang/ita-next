---
name: fase2-structural-gaps
description: Lacunas estruturais entre a AST/EBNF do ita-next (Fase 2) e a identidade do Itá — construtos do oracle/manifesto sem representação. Recomendações aguardando dono.
metadata:
  type: project
---

# Lacunas estruturais da Fase 2 (ita-next) vs. identidade

Achadas em revisão de completude conceitual (2026-07-11). Todas têm respaldo no oracle
`ita/` (conformance suite) ou nos 11 princípios; são RECOMENDAÇÕES aguardando decisão de dono.
Fonte: `ita-next/compiler/docs/spec/{ast.asdl,grammar.ebnf}` vs. `ita/compiler/docs/GRAMMAR.md`.

- **Membros `async fn` / `stream fn`** — `member ::= "pub"? (fnDecl | field)` NÃO tem marcador;
  `FnDecl.async` existe mas é inalcançável em membro. O oracle `decl_actor.tu` tem `stream fn ticks`
  DENTRO de um actor (actor que emite stream) — core da concorrência (Art. II). Gap real.
- **`init` (construtor)** — keyword reservada (EBNF §2) mas sem produção em `member` e sem `InitDecl`
  na ASDL. Oracle `decl_class.tu` usa `init(nick:) { self.nick = nick }`. Struct ganha memberwise
  grátis (`Point(x:, y:)` = `Call` c/ labels); `init` é a história OO de `class` (P2/P5).
- **`guard let PAT = e && cond`** — `GuardLetStmt(pattern,value,orElse)` sem campo de condição-extra;
  usado em `ita/examples/modern.tu`. Sugestão: campo `expr? condition`.
- **Conformances inline** — `struct P: Trait`, `class D : Super, TraitA` (1º = super, resto = traits),
  `extension S : Trait`. `StructDecl`/`ExtensionDecl` sem lista de traits; `ClassDecl.superclass` é
  único (sem traits). Oracle `decl_class.tu`/`decl_extension.tu` usam os três (P5, traits/OO).
- **`await race(...)` / `await all(...)`** — concorrência estruturada (oracle §4.1); deferido no
  ita-next (canto 6 → nós `AwaitRace`/`AwaitAll`).

**Já bem modelado (não mexer):** let/var (`isVar`), `MutType`, `CopyWith` (update imutável), `Try`/`Panic`/
`Spawn`/`Await` como nós próprios, `EmitStmt` (yield de stream — SÓ isso; pub/sub usa métodos normais),
`ForStmt(isAwait)`, tuplas, args nomeados, `EnumShorthand` (`.ok`/`.err`/`.none`), padrões ricos + if-expr
`else`-obrigatório (exaustividade). Ver [[identity-yield-and-nao-fazer]].

**Tensão nº1 (P4/exaustividade):** `Binary`/`Unary`/`Assign` guardam `op:string` → perde o switch
exaustivo de graça (CI 5.2.1). Deferido p/ Fase 7, mas o DESUGARING (Fase 3) já faz switch sobre
`|>`/`>>`/`??`/`?` — recomendo migrar p/ enum fechado ANTES da Fase 3, não na 7.
