---
name: phase5-builtin-members-chao-vs-biblioteca
description: Ruling — membros de built-in se partem em CHÃO (~4 acessadores irredutíveis) vs BIBLIOTECA (map/filter/fold, escrevíveis em .tu hoje). O teste da mágica é PRIVILÉGIO, não tabela.
metadata:
  type: project
---

# Chão vs Biblioteca — de onde vêm os membros dos built-ins (spec 010/011)

Emitido 2026-07-15 a pedido da orquestração, antes de escrever a spec 010 (fatia C).

## A distinção-mãe (mata o category error da pergunta)
"Membros de built-in" **não é uma categoria** — são duas, e conflatá-las faz o chão parecer
enorme e o marcador parecer urgente. Nenhum dos dois é verdade.
- **CHÃO** = irredutível, tem de tocar o Dart: `.length`, `[]`, `.slice`, `+` (concat). **~4.**
- **BIBLIOTECA** = derivável do chão em Itá puro, zero mecanismo novo: `map`, `filter`, `fold`,
  e **os 5 métodos hard-coded de `Option`/`Result`**.

**Provas (verificadas, não intuídas):**
- `stdlib/iter.tu:56` `flatMap` é **`map` + concat escrito em Itá puro** sobre o chão. Se `flatMap`
  existe em `.tu`, `map` não pode precisar de mágica. Mata a premissa "o corpo precisa tocar o Dart".
- `stdlib/iter.tu:64-73` `compact` faz `match item { .some(v) => …, .none => {} }` ⟹ `Option.map`
  = `extension Option<T>` + `match`, **zero chão**. Os 5 de `_addBuiltinMethod` são **puro débito
  de bootstrap do oracle**, não decisão de design.
- `extension T { }` é atestado e é o mecanismo real da stdlib (24×: `extension Stack`, `Queue`…).

## O teste da mágica: **PRIVILÉGIO, não tabela**
O §12-4 do dono ("tabela hard-coded = a mágica que §4.5/§8.3 recusam") **não proíbe tabela** —
proíbe **poder que o usuário não alcança**. Teste: *"o usuário obtém isto para o tipo DELE
escrevendo Itá?"*
- `for` sobre `List` via tabela → **não** (o tipo dele não ganha `for`) ⟹ privilégio ⟹ mágica.
  Por isso a cura foi o **trait `Iterator`** — ele **abre** o poder. O dono acertou.
- `.length` no chão → o tipo dele tem campo/`extension` ⟹ sem lacuna de poder ⟹ **não é privilégio**.
Mesma forma de [[phase5-types-identity-rulings]] R5: *"overload é o que torna built-in
não-privilegiado; RECUSAR overload é que seria a mágica"*. **A tabela é détail; o privilégio é o pecado.**

## Rulings firmes (lei, não recomendação)
1. **Não estender `_addBuiltinMethod` nem criar tabela de método no CODEGEN.** **ADR-0013
   (Accepted, 2026-07-15)** já ordenou o inverso — built-ins *"devem migrar para a tabela de tipos
   da F5… senão o vazamento sobrevive à reescrita e a F7 continua dona do conhecimento de tipo"*.
   Reforçado por Art. II Norte (*"built-ins migrados para `.tu`"*, MANIFESTO:50).
2. **Membro desconhecido = ERRO** (`unknown-member`), nunca `UnknownType` silencioso. O
   `_inferMember` "conservador" do oracle (`type_checker.dart:190`) **é a doença que o ADR-0013
   nomeou** (item 3 do Contexto: "o checker nunca erra onde a inferência não alcança").
3. **Tabela hard-coded é legítima como DÉBITO DECLARADO (forma M5)** sse: **fechada** + **erra no
   desconhecido** + **destino `.tu` escrito na spec**. Precedente do dono: `Ops(sym)` (débito M5).
4. **Marcador NUNCA pode ser `@intrinsic`/`@extern`** — **P6 é permanente** ("`@decorators` **nunca**
   serão implementados"). Se um marcador entrar, é **keyword**, e é conversa do M5, não da 010.

## `xs.map { $0*2 }` (CA15) — o fixture virou flagship
**Correção do meu próprio quase-erro:** `xs.map { $0*2 }` **É atestado** — mas só em
`conformance/desugar/dollar_closure*.tu` (5 arquivos), onde é **carrier sintático** do teste de
aridade do `$0`, com `map` **jamais resolvido** (F3 é type-agnostic). Na `stdlib` real: **zero**
`.map`/`.reduce` sobre `List`. `iter.tu` ("Combinadores funcionais sobre List") tem **`flatMap` sem
`map`**, **`scan` sem `fold`**, `takeWhile`/`partition` sem `filter` ⟹ **buraco**, não doutrina
(ninguém entrega `flatMap` sem `map` de propósito).
**Hazard concreto:** sob ADR-0013 esses fixtures referenciam membro inexistente — se a conformance
rodar F5 neles, quebram. `xs.reduce { $0+$1 }` idem (`reduce` também não existe).
**Argumento circular a não repetir:** *"o idioma real do `.map` é Option/Result"* — os 5 métodos que
existem são **exatamente** os 5 hard-coded no codegen. É a mágica descrevendo a si mesma como doutrina.

## DECIDIDO pelo dono (2026-07-15) — `.map` em container é o idioma
**Minha rec (`|>` + função livre) foi RECUSADA.** Aceito sem ressalva: eu mesmo cravei que a
constituição é silente ali e que era taste, logo decisão dele (Governança). Registro para não
reabrir. **Não usar Art. II ("Elixir tem pipe") para reabrir** — a analogia é sobre RUNTIME
([[systems-low-ffi-vision]]), seria over-leitura que já errei.

### A entailment que o ruling 1 CRIOU (review da 010, 2026-07-15)
**`.map` em container + §3.1 (`map` é biblioteca) + §3.3-1 (chão FECHADO) ⟹ `extension List<T>`
TEM de ser legal.** Não é pergunta em aberto: se `map` é membro de `List`, e `map` não cabe no chão
fechado, ele só pode vir de `extension` em `.tu`. Se o dono responder "não" ao `extension List<T>`,
**o ruling 1 não tem caminho de implementação** que não seja hard-code de `map` no compilador —
que é a **2ª face do privilégio** e mata o Norte do Art. II. ⟹ o ruling 1 volta à mesa.

### O teste do privilégio tem DUAS faces (minha doutrina estava incompleta)
1. **Poder que o tipo do usuário não alcança** (`for` sobre `List`, não sobre `MyType`) — a que eu
   escrevi.
2. **Poder sobre o built-in que só o compilador tem** (o compilador dá `.map` a `List`; o usuário
   não pode) — a que o ruling 1 tornou load-bearing. É o que `extension List<T>` decide.

### Destino do `|>` (escrever, senão alguém o deleta como vestigial)
`|>` **não morre**: perde os combinadores da stdlib, **mantém pipeline de função livre do usuário**
(`data |> parse |> validate`), onde método não é opção. Divisão coerente — `.map` para container,
`|>` para pipeline de domínio. **`iter.tu` migra inteiro para `extension List<T>` na 011** (é a
consequência do ruling 1; a 010 não pode escrever nada que atrapalhe).

## Aberto ao dono
- **Forma do chão:** `.length` vs `.length()` (o `Map.keys()` da 010 já mistura as duas grafias).
- **§12-4 defere, não dissolve:** o trait `Iterator` resolve o *contrato* do `for`, mas o `impl
  Iterator for List` **cai no mesmo chão**. ⟹ **a spec do `Iterator` e a de "membros de built-in"
  são a MESMA spec** (011): *"como um built-in ganha contrato que o usuário também escreveria"*.

## Armadilha do "chão" na spec 010 (§4.6) — o critério vazou
A tabela chamada "o chão" pegou **`.slice`** (derivável de `[]`+`+`+`.length`, exatamente como
`chunk`/`take` — é **biblioteca com sintaxe de membro**) e **perdeu `[]` e `+`**, porque a FORMA
"tabela de membros" não comporta índice nem operador. ⟹ **duas listas, dois destinos:** chão
irredutível (`.length`, `[]`, `+` → `dart:` explícito no M5, nunca some) vs compat-stdlib
(`.slice`, `.set`, `Map.keys()` → `extension` em `.tu` na 011, some). Sem isso, o critério de
adesão vira *"a stdlib chama"* = aberto, e a condição FECHADA perde os dentes.

## Auditoria W0 da spec 012 (2026-07-20) — veredito **liberado-com-ressalva**, sem conflito

A spec 012 (`.length`/`[]`/`+`, o chão irredutível) honra as 3 condições e as 2 faces; escopo
autorizado por ruling 2 + §12-4. **Dois refinamentos que ficam como doutrina:**

1. **Face 1 tem DUAS rotas — `.length` ≠ `[]`/`+`.** `.length` passa face 1 **hoje** (usuário
   escreve `let length: Int`, atestado 010 §12-B2). Mas **`[]`/`+` NÃO** — o `MyType` do usuário
   só ganha índice/operador via `OperatorDecl`, **diferido a 012+** (011 §1.3 nº5, ruling §12-4).
   Na foto de hoje, **`[]`/`+` estão na MESMA posição de face 1 que o `for`**: poder que o tipo do
   usuário ainda não alcança, cura diferida. **O que os põe no chão e mantém `for` fora NÃO é o
   teste de privilégio — é ruling do dono** (ruling 2 autoriza o chão; §12-4 nomeia a tabela
   `List<T>→T` do `for` como "a mágica"). Face 1 **confirma `[]`/`+` no destino** (M5, `List`
   declarado + OperatorDecl); não os distingue do `for` no presente. ⟹ §0.5 que ilustra face 1
   só com `.length` está **incompleto** (não errado): deixa `[]`/`+` parecerem não-privilegiados
   "como `.length`" quando a razão honesta é autoridade-do-dono + cura-diferida. Emenda proposta,
   dono assente.
2. **`[]`-ausência é UM operador, decida List e Map JUNTOS.** A 012 §4.1 pende (B) `Map[k]→V?`
   (ausência normal — idioma `if let x=m[k]` é itaiano), enquanto §4.3 roteia `List[i]`
   out-of-bounds ao dono (A panic / B `E?` / C Result, todas P7-ok). É o **mesmo `[]`** — a decisão
   de ausência deveria ser um ruling só, senão split acidental. **Assimetria principiada existe:**
   Map-ausência = normal (B); List-fora-de-faixa = erro de limite. **Minha leitura pende (A) panic
   p/ List** (mais chão: assinatura limpa `E`, quadrante "let it crash", precedente Swift `array[i]`
   trap p/ não impor `Optional` no caso comum) — mas **nada de identidade FORÇA A** (B não é mágica,
   `E?` é visível), logo **é ruling do dono**, não decido.

**Relacionadas:** [[phase5-types-identity-rulings]] (R5, catálogo #1), [[doctrine-argumento-de-ausencia]]
(as ausências dos fatos 1/6 eu **verifiquei**: confirmadas), [[phase3-iteration-protocol-ruling]],
[[conformance-lowering-identity-reading]] (Norte pede DECL `.tu`, não representação própria — o mesmo
que salva o chão tocar `dart:core` como débito de bootstrap).
