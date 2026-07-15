---
name: labels-params
description: Label de parâmetro — o livro COBRE (6.9 + Fig 6.18 + 6.3.1), a regra SE-0111 é derivável do Dragon, o opt-out `_` é 4 camadas (só 1 é gramática) e a evidência do stdlib.
metadata:
  type: project
---

# Label de parâmetro / opt-out `_` (fundamento, 2026-07-15)

## CORREÇÃO da minha própria memória (dispatch_members.md, item 0)
Eu escrevi *"o livro **não cobre** param nomeado (6.3.1 produto cartesiano; Alg. 6.16 unário)"*.
**Parcialmente FALSO.** O mesmo texto está em `check.dart:1256`, `type.dart:216` e
`type.dart:238` — propagado. O livro cobre o **modelo em duas partes**:

- **6.3.1** dá DOIS construtores distintos: `record` *"aplicação do construtor de tipo record aos
  **nomes dos campos** e a seus tipos"* (nomeado) e `×` — *"produto cartesiano s x t … podem ser
  usados para representar uma **lista ou tupla de tipos** (por exemplo, para parâmetros de função)"*
  (posicional). Param de função cai no `×` **por escolha do livro**, não por omissão.
- **6.9, bullet "Tabelas de símbolos"** é a peça que faltava: *"Os **parâmetros formais** de uma
  função podem ser tratados **em analogia com os nomes de campo de um registro** (veja a Figura
  6.18)"*. Fig 6.18 = `T.type = record(top)` — os nomes vão para a **tabela de símbolos `t`**.
- **6.9, bullet "Tipos de função"** fecha: *"Os tipos de função podem ser representados pelo uso de
  um construtor `fun` aplicado ao **tipo de retorno** e uma **lista ordenada de tipos** para os
  parâmetros"* — **tipos, não nomes**.

⟹ **SE-0111 é derivável do Dragon**: nome de param mora na **declaração** (tabela `t`, 6.9/Fig 6.18),
nunca no **tipo** (`fun(ret, [tipos])`, 6.9). `ParamType.==` comparar só `type` (`type.dart:252`) já
está **certo pelo livro** — não precisa do Swift. O item #3 "mais urgente" da pesquisa de campo **já
está pago**.

**O que o livro NÃO tem** (lacuna real, declarar): nenhum call-site com nome. `A → ε | E,A` (Fig 6.52)
é **posicional puro**. 6.5.3: *"A assinatura para uma função consiste no **nome da função e nos tipos
de seus argumentos**"* — a seleção do livro é por **tipo**, nunca por label. **Crafting Interpreters:
lacuna total** — `arguments` do jlox/clox é posicional puro; nem label nem default.

## Walks: label obrigatório NÃO custa walk, e ABRE uma porta
- O discriminador é `Arg.label`, produzido no **parser** (`parser.dart:1219-1222`) ⟹ conhecido com
  **zero síntese**. Obrigatório = `arg.label == null && params[pi].label != null → erro` dentro do
  `_matchArgs`, que já tem `params[pi]` na mão. **Zero walk a mais.**
- **O argumento forte não é "é sintático" — é o `_isCheckingOnly`** (`check.dart:1298`): overload por
  TIPO exige sintetizar o arg antes de escolher o candidato, e `[]`/`{}`/`nil`/`.variant`/closure
  **não têm regra de síntese** ⟹ `f(xs: [])` seria indecidível em 1 walk. Label é conhecido **antes**
  de descer ⟹ `expected` chega ao arg ⟹ checking-only sobrevive. É por isso que 011 pôde ter
  `_initCandidates` e não pôde ter overload.
- **Unlock:** com label obrigatório o discriminador vira **total** ⟹ a chave da tabela pode ser o
  **seletor** (`f(a:b:)`), e "overload por label" deixa de ser overload: vira **nome distinto**
  (`Env.get`, Fig 2.37/2.38). O que sobra (mesmo seletor, tipos diferentes) é **6.3.6 duplicata**
  (*"um nome pode aparecer no máximo uma vez"*) — o caso barrado vira erro por construção.
  Admitir overload-por-label é **identidade** (`ita-visionary`), não técnica.

## Bug latente achado (independe da decisão)
`check.dart:999-1005`: labels opcionais ⟹ `P(1, 2)` dá `labels = [null, null]` ⟹ `_labelsFit` passa
para **todo** candidato de aridade compatível ⟹ `firstOrNull` escolhe por **ordem de coleta**, mudo.
Falta `ambiguous-call`. Com defaults sobrepondo seletores (`init(a:b:=0)` × `init(a:)`) o caso
persiste mesmo com label obrigatório.

## Opt-out `_`: 4 camadas, só a 1ª é gramática
1. `grammar.ebnf` §8: `param ::= "_" IDENT (…)? | IDENT IDENT? (…)?` — **LL(1) pelo 1º token**
   (`Tag.underscore` × `Tag.identifier`); léxico já pronto (§1: `_` sozinho = `underscore`).
2. `parser.dart:643` `_consume(Tag.identifier)` → aceitar `underscore` na 1ª posição e **exigir**
   IDENT depois.
3. **AST/ASDL (F2) — a camada cara.** `Param.label` é `String?` e precisa de **3 estados**: não
   escrito (⟹ label = nome), `_` (posicional), externo. `label == null` já significa "não escrito"
   ⟹ mapear `_` → `null` no parser **reintroduz ambiguidade na árvore**. Precisa de sum/flag
   (`ast.asdl` + `ast_printer.dart:432` ⟹ **quebra golden**). Mesma doença do `op:string` (spec 006).
4. `collect.dart:571` `label: p.label ?? p.name` → 3 vias.
**`type.dart:223` já está pronto** (`label: null` = *"posicional puro"*): o modelo de TIPO antecipou o
opt-out; a **sintaxe** não. Nada muda em `ParamType`.

## Consequência de gramática que ninguém levantou
Label só pode ser `Tag.identifier` (`_param`, `_finishCall:1219`) ⟹ **`in`/`for`/`where`/`as` são
keywords** (`token.dart:56-71`) e **não parseiam como label**. O Swift admite keyword em posição de
label justamente porque a posição é inambígua. Sem isso, a frase preposicional — o argumento mais
forte a favor do label — fica capenga (`copy(from:)` ok, `iterate(in:)` não). `from/left/right/all/race`
são contextuais (IDENT) e passam.

## Trailing closure é o carve-out OBRIGATÓRIO
`parser.dart:1234`: `args.add(Arg(null, _trailingClosure()))` — trailing closure é **sempre
posicional**, e `Arg` (`ast.dart:732-734`) **não guarda que era trailing** ⟹ `_matchArgs` não
distingue de um posicional escrito. Label obrigatório sem isenção mata `xs.map { $0 }`. Isentar exige
bit `isTrailing` no `Arg` — **outra vez F2/ASDL**.

## Evidência do oracle (stdlib `.tu`, 374 `fn`)
- **A favor do `_`:** `math.tu:16-19` `min(a: Int, b: Int)`, `max`, `minf`, `maxf` — é o
  `min(number1, number2)` do Swift e o `min(arg1, arg2)` do PEP 570, **na nossa linha 16**.
- **A favor do label (a preposição vaza pro nome — Kotlin KEEP-0439, verbatim, aqui):**
  `datetime.tu:36-63` `addDays(n:)`, `addHours(n:)`, `addMinutes(n:)`, `addSeconds(n:)` — **4 funções
  = 1 função + unidade** (`add(days:)`); `collections.tu:644,777,928` `addEdge(from: Int, to: Int)` —
  o par preposicional **já está nos nomes dos params**; `validate.tu:30-42` `min/max/minVal/maxVal`.
- Ressalva: a stdlib está no **dialeto antigo** (não parseia, ver `[[rd1-so-arrow-rende]]` do projeto)
  ⟹ vale como evidência de **intenção**, não como corpus compilável.
