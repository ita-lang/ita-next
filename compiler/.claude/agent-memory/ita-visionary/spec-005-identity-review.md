---
name: spec-005-identity-review
description: Review de identidade da spec 005 (init/traits/guard-let-cond) — veredito, bloqueador pub-init, tensão guard-&&
metadata:
  type: project
---

Spec 005 completou a superfície declarativa da Fase 2: `InitDecl` (construtor),
conformances inline (`StructDecl/ClassDecl/ExtensionDecl.traits`; em `class` 1º type
após `:` = superclass, resto = traits), `GuardLetStmt.condition` (`&&`-refino).

**Veredito (review 2026-07-11):** itaiano no essencial. Nenhuma das 4 construções altera
princípio permanente (confirma §0.5 da spec). Dump transparente: `class` distingue
`(extends …)` de `(traits …)` — a distinção super-vs-trait por posição na fonte é honesta,
não armadilha. `init` com `self.x = x` = `Assign` cru (construção-vs-mutação deferida à
Fase 3, coerente com imutabilidade P1). Guard-let `condition` distinta de `value`; CA7
(sem `&&` → null) preservado. Coerente com [[doctrine-ast-representa]] e nullity-invariant
(desembrulho só p/ `T?`).

**Bloqueador levantado — `pub init` engolido:** em `_member()` o parser consome `pub` e
chama `_initDecl` SEM `isPublic`; `InitDecl` não tem slot. `pub fn`/`pub field` preservam
o marcador; só `pub init` some. Fere P4 ("a AST representa, não esconde") e destoa do
precedente `meaningless-pub`. **Fix fiel:** adicionar `bool isPublic` a `InitDecl`
(ASDL+dart+parser+printer `:pub`), espelhando `FnDecl`/`FieldDecl` — deferindo a política
(init pode ser pub/priv? por-kind?) à Fase 3. Não decidir semântica, só representar.

**Tensão aberta (sugestão, não-bloqueio):** o split guard-`&&` é "operando esq. do `&&` de
topo" (ruling de dono). Com `&&` left-assoc, `guard let v = opt && c1 && c2` → value=`opt
&& c1`, cond=`c2` (não value=`opt`). Fiel à letra do ruling, mas ergonomia de multi-refino
é contra-intuitiva. Mitigado por Fase 3 (value tem de ser `T?`, então `opt && c1` como
value seria erro de tipo). Refinar redação do ruling é decisão de dono.

**Menor:** spec §10 diz "init em qualquer corpo"; corpo de `enum` NÃO roteia init (loop
próprio, `init` é keyword → erro). Correto na prática (init-em-enum é sem sentido); apertar
a redação da spec.
