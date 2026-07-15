---
name: walks-sources
description: Os 5 walks sobre TypeInfo.sources — por que NÃO fundir (Dragon 6.5.2 max/widen), o desenho do H1 (a aresta em TypeInfo), o invariante do _conform que mata 6 filtros, e a tabela de mutação (D1-D5) que é a única prova contra divergência inobservável.
metadata:
  type: project
---

# Walks sobre `TypeInfo.sources` — o H1 (W1 do desenho, 2026-07-15)

⚠️ **Paths:** os arquivos vivem em `lib/frontend/semantic/` (a minha memória antiga dizia
`lib/src/semantic/` — podre). Linhas abaixo medidas em 2026-07-15.

## Contagem: **5** walks (o `type_table.dart:258-266` diz 4 e MENTE — omite o `_offeredBy`,
e lista o `_isSubtype`, que nem anda o grafo: quem anda é o `_superTypesOf`)
1. `check.dart:1611 _lookup` — recursivo; nível 0 CORTA; `_denota` post-filtra; **único que FALHA**.
2. `check.dart:2002 _superTypesOf` (driver `_isSubtype:1904`) — ∃ (bool ∨).
3. `collect.dart:937 _implementationAbove` — DFS, pula nível 0, filtra `body != null`, 1º hit.
4. `collect.dart:1027 _offeredBy` (driver `_checkInheritedConflict:1006`) — map nome→sig.
5. `collect.dart:1222 _reaches` — DFS sobre **decls**, `visited`, **sem substituição**.

## Veredito: NÃO fundir o percurso — 6.5.2 é o precedente
`max` e `widen` andam o **MESMO grafo** (Fig. 6.25(a)); a Fig. 6.27 roda `max` 1× e `widen` 2× na
MESMA ação semântica e **o livro não os funde**. Ele fatora a **figura**. ⟹ **fatore a ARESTA, não o
percurso.** Os 4 eixos que os separam (alcance / filtro de corpo / monoide / totalidade) vivem todos
no CORPO do loop — **nenhum atravessa a assinatura da aresta**. É essa a prova de que uma aresta
serve os 4 sem parametrizar o monoide.

## ⭐ O INVARIANTE que decide o desenho (achado 2026-07-15, com prova)
`_conform` é o **único escritor** de `superclass`/`traits` (`collect.dart:261-262`); o corte de ciclo
(`:1213`) só **remove**. E o guard `collect.dart:219-220` é
`final ti = t is NamedType ? types.of(t.decl) : null; if (ti == null) continue;`
⟹ **`sources ⊆ { NamedType n | types.of(n.decl) ≠ null }`, sempre.**
Logo os **6** `if (s is! NamedType) continue` (`collect.dart:943,1009,1036,1070,1230`; `check.dart:2008`)
são **MORTOS**, por 2 provas independentes: (1) o guard; (2) `substitute` preserva NamedType-ness
(`type.dart:484-488` reconstrói `NamedType(decl,kind,[...])`).

## O desenho aprovado — 2 artefatos em `TypeInfo` (`type_table.dart`, vizinhos do `sources`)
```dart
Map<TypeParamType, Type> substFor(List<Type> args)           // ex-`_substOf` ×2 (8 call-sites)
List<NamedType> sourcesUnder(Map<TypeParamType, Type> subst) // [for (s in sources) substitute(s,subst) as NamedType]
```
**Método, não função livre** (função do estado; `sources` já é getter — precedente). `type_table.dart:23-24`
**já importa** `ast`/`type` ⟹ zero import novo, zero dep de `TypeTable`/`Collector`/`_err`.
`_substOf`: `check.dart:589` ≡ `collect.dart:1118`. Call-sites: `check.dart:541,572,761,1617,2005` +
`collect.dart:947,1033,1076`.

**A equação de que TUDO depende** (escrever no commit):
`substitute(NamedType(d,k,as), σ) ≡ NamedType(d,k,[σ(a)])` ⟹
`si.substFor(substitute(s,σ).args) ≡ _substOf(si, [substitute(a,σ) for a in s.args])` — que é
**literalmente** `collect.dart:947` e `:1033`. Prova que "lazy" (`(nó cru, subst pendente)`:
`_implementationAbove`/`_offeredBy`) e "eager" (`NamedType` instanciado: `_lookup`/`_superTypesOf`)
são a **mesma aresta** — a diferença era convenção, não política. `substitute(t,{})=t`
(fast-path `type.dart:480`) preserva **identidade de objeto** na raiz.

`_offeredBy` **perde o param `subst`** (recebe nó instanciado). `_implementationAbove` mantém
`(info, name, [subst])`. `_superTypesOf` sobrevive como adaptador table-side.

## ⭐ Por que `TypeInfo` e NÃO `TypeTable.sourcesOf` — **rejeito a minha proposta antiga**
A política de `types.of(s.decl) == null` **diverge hoje**: `_implementationAbove:944` e `_offeredBy:1031`
**descartam** a fonte; `_superTypesOf:2002` **não checa** e a devolve (e no `_isSubtype:1946` ela ainda
casa por `_sameApplication`). Divergência real, invisível **porque o conjunto é vazio** (o invariante
acima). A aresta em `TypeInfo` **não tem a tabela** ⟹ é **incapaz** de escolher silenciosamente uma das
duas. `TypeTable.sourcesOf(NamedType)` **teria** essa capacidade — é o ponto cego em pessoa.
⟹ Razão técnica nova para o ruling do W0, que ele não tinha. Corolário: os `if (si == null) continue`
**ficam verbatim**; não viram `!`.

## Não tocar (além das 3 cercas do W0)
- **Convenção de ENTRADA** — `_implementationAbove` entra por `(TypeInfo, const {})`, `_lookup` por
  `NamedType` instanciado. Unificar via "self type" (subst identidade) mata o fast-path do `substitute`,
  perde identidade, e funde o **percurso** (perguntas diferentes: *"que membro `D<Int>.f` denota?"* vs
  *"a decl de `D` sobrepõe algo?"*). **Fora do H1.**
- **Guard do `_substOf`** (`args.length != generics.length → const {}`; latente via `collect.dart:369`)
  — move **verbatim**; consertar dentro do H1 destrói o critério de verificação. Item separado.
- **`_offeredBy` last-wins entre irmãos (`:1036`)** — são, mas por argumento não escrito: o colapso só
  ocorre sobre `si.sources`, e `si` também é visitado pelo `for (info in types.all)` do
  `_checkWellFormed:822` ⟹ se conflitam, `si` já foi acusado. Merece 1 linha de doc.

## ⭐ A PROVA contra a divergência inobservável: tabela de MUTAÇÃO (rodar ANTES do H1)
| # | Divergência | Mutação | Teste que morre |
|---|---|---|---|
| D1 (C1) | `_offeredBy` **não** filtra corpo (`collect.dart:1038`) | `+ && m.decl.body != null` | ✅ `check_test.dart:1008` |
| D2 | `_implementationAbove` **filtra** corpo (`:949`) | `- && x.decl.body != null` | ✅ `check_test.dart:478` |
| D3 (C3) | post-filtro `_denota` (`check.dart:1675-1694`) | usar `hits` direto | ✅ `check_test.dart:968` + `:994` |
| D4 (C2) | `_reaches` na aresta CRUA, `visited` próprio | `seen` no compartilhado | 🔴 **NENHUM** |
| D5 | os 6 filtros mortos | remover | 🔴 **NENHUM** (mortos) |

- **Correção medida ao W0:** ele disse que C1 é *"golden muda, não quebra"*. **Falso — vai a VERMELHO:**
  `check_test.dart:1008` assere `contains('inherited-signature-conflict')` (código específico).
  **Fragilidade que ele não viu:** os testes de `collect_test.dart:284-313` (o grupo que LEVA o nome)
  usam **default** (tem corpo) e **sobrevivem** à mutação. C1 pende de **um** teste, no outro arquivo.
- **D5 é invariante ⟹ vira EXECUTÁVEL:** os 6 `continue` colapsam num `as NamedType` na aresta. O cast
  **é** o enforcement (lança em release, não só debug) — *violação de contrato = `throw`, não
  diagnóstico* (ver [[dispatch-members]] item 4). O `continue` é a forma silenciosa da mesma doença.
- **D4 é prova de ASSINATURA, não de teste** — e é por isso que é o ponto cego: se o `seen` voltar,
  **nada trava e nada fica vermelho**; a doutrina *"duas passadas, e a ordem é o ponto"*
  (`collect.dart:806-814`) evapora com a suíte verde. Garantia: `sourcesUnder` é **stateless**, sem
  `seen` na assinatura; `_reaches` **não a chama**. Verificável por leitura/grep, e mora no doc do
  `sources`.
- **Critério global falsificável:** H1 é refactor puro ⟹ **o diff não pode tocar `test/`**. Contra um
  refactor que se harmoniza com testes verdes, o sinal não é "verde" — é **"verde sem tocar nos testes"**.

## Achado antigo que continua de pé: `_lookup` conta REQUISITO como hit
Resolvido pelo `_denota` (`check.dart:1700`) — o post-filter. Ver o caveat *"só é são porque trait é
FOLHA"* (`:1669`) e o `Ruling ita-visionary — contestável` (`:1674`), que o H1 **não pode lavar**.
**Por que `_lookup` e `_implementationAbove` não se contradizem:** `_checkOverride` pergunta *"que TIPO
meu override deve ter?"* → iguais → escolha inobservável; `_lookup` pergunta *"que DECL este nome
denota?"* → dois corpos → indeterminado. **A mesma igualdade que torna a escolha inobservável para um
deixa o outro genuinamente indeterminado.** É a prova mais limpa de que os walks não são fundíveis.

Não medi: não rodei os testes. Tudo acima é leitura de código + livro.
