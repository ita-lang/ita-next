---
name: doctrine-declaracao-vs-tipo
description: Doutrina — o que a DECLARAÇÃO carrega não vira parte do TIPO por morar no mesmo registro. Carregar ≠ equiparar; e o teste é a gramática do tipo.
metadata:
  type: project
---

# Doutrina: declaração × tipo (carregar ≠ equiparar)

Cravada em 2026-07-15, no W0 do achado "nenhuma fn nomeada casa com `(Int) -> Int`" (label dentro do
`ParamType.==`). Vale além do label — volta em `mut`, `async`, default, e em tudo que a decl escreve.

## O enunciado
**Um atributo que a declaração escreve (label, default) precisa ser CARREGADO no registro do tipo para
o call-site poder checá-lo. Isso não o torna parte da EQUIVALÊNCIA de tipos.** `ParamType.label` é dado
que o `_matchArgs` lê; pô-lo no `==` é confundir *carregar* com *equiparar*.

## O teste decisivo — a gramática do TIPO
**Se o atributo não tem slot na produção `type`, ele não é do tipo.** `grammar.ebnf:353` — o tipo-função
é `"(" (type ("," type)*)? ")" ("->" type)?`: só `type`, sem label, sem default. Corolário que fecha:
se o label fosse do tipo, o tipo de `fn dobro(x: Int) -> Int` seria **inexprimível na linguagem** — e o
compilador estaria carregando por dentro uma distinção que o usuário não pode escrever nem ver. **É P4
ao contrário:** a mágica não é só esconder o que acontece; é o compilador saber um tipo que a superfície
não sabe dizer.

## As DUAS noções, e nunca fundi-las
| Noção | Quem compara | Label | Default |
| :-- | :-- | :-: | :-: |
| **`==` de TIPO** (`unify`, `_isSubtype`, anotação) | dois **tipos** | ❌ | ❌ |
| **`sameSignature`** (override / conformance) | duas **declarações** | ✅ | ✅ (hoje; ver R11) |

`unify.dart:109-111` já documentava a linha certa (*"label/default são da declaração e não participam da
equivalência estrutural"*) enquanto o `ParamType.==` fazia o oposto — **duas noções no mesmo arquivo, uma
negando a outra**. O `compiler-craftsman` chegou à mesma distinção sozinho
(`f5_quantifiers_subtyping.md:40`): *"`==` de tipo ≠ `sameSignature` de membro"*.

## Por que o atributo não "some" (a objeção P4)
Passar `dobro` onde se espera `(Int) -> Int` **não engole glifo nenhum**: o label segue valendo,
integralmente, em todo call-site **por nome**. O que ele promete é *"no MEU call-site, nomeie o
argumento"*; por um valor não existe "meu call-site". Contraste com o `T??` (R1), onde eu disse
*"engolir em silêncio um glifo declarado é P4"* — **ali o glifo não faria nada em lugar nenhum**. A
diferença entre "o glifo não faz nada" (P4) e "o glifo faz algo, onde está escrito" (legítimo).

## Precedente interno que sela (auto-consistência)
É a mesma forma da opção **(b) recusada** no copy-with ([[phase5-011-w3-review]]): *"casar campos com
params do init = recusada — a legalidade dependeria de nomes de param noutro arquivo = P4"*. Label no
tipo é isso: `aplica(f: dobro)` passaria ou não conforme o autor de `dobro` ter chamado o param de `x`
ou de `valor`, noutro arquivo, invisível no call-site.

**Relacionadas:** [[phase5-types-identity-rulings]] (R10/R11), [[doctrine-derivacao-vs-apresentacao]]
(parente: lá é posição × kind; aqui é decl × tipo), [[doctrine-argumento-de-ausencia]].
</content>
</invoke>
