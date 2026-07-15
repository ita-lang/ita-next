---
name: doctrine-ast-representa
description: Doutrina de identidade "a AST representa, não valida" — lente governante das specs de sintaxe (Fase 2)
metadata:
  type: project
---

Doutrina governante da Fase 2 (Sintaxe→AST) do `ita-next`: **a AST REPRESENTA o que
foi escrito, não VALIDA**. Restrições semânticas (posição, tipo, existência de trait,
superclasse-é-class, struct-não-deveria-ter-init) são todas Fase 3 (binder/type-checker).

**Why:** é como o codebase concilia superfície declarativa rica com princípios permanentes
sem antecipar semântica. Ancorada em `ast.asdl` (§linha ~48) e `nullity-invariant.md` ("o
parser representa, não valida"). P4 aparece nas specs sob a forma "a AST representa, não
**esconde**".

**How to apply:** ao revisar sintaxe, o teste de identidade não é "o parser rejeita o
inválido?" (isso é Fase 3) mas "o parser **representa fielmente e sem esconder** o que a
fonte escreveu?". Corolário forte: engolir um token gramaticalmente aceito **sem
representá-lo** fere P4 — não é "não-validar", é esconder. Precedente do codebase: `pub`
sem sentido vira **error production** `meaningless-pub` (grammar.ebnf §declaration),
nunca consumo mudo. Ver [[spec-005-identity-review]].
