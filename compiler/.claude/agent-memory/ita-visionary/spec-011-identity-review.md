---
name: spec-011-identity-review
description: Ruling pré-011 + review da spec escrita + W0 dos 5 itens de fecho (2026-07-15) — itaiano; 1 bloqueante (`for` por tabela reprova na face 1); copy-with é SÓ de struct
metadata:
  type: project
---

# W0 dos 5 itens de fecho (2026-07-15) — **passa, nenhuma emenda**

**Cravei:**
1. **`missing-trait-member` = ERRO.** *"Conformance é declaração de intenção"* (ADR-0012 #2) é **má-leitura**:
   o "intenção" ali contrasta com **"retrofit externo"** (ONDE se escreve), não com "obrigação". Prova
   interna: o #2 põe as duas formas como **equivalentes**, e a 009 §4 dá às duas o mesmo efeito
   `T ≤ Trait`. **Subtipagem É obrigação** — subtipo que não implementa o supertipo é mentira; a chamada
   tipa (walk acha no nível 1) e explode em runtime = "compila mas roda errado" (ADR-0013). **Não é ruling
   do dono — é entailment.** Default de trait EXISTE (`fnBody?` opcional; `ast.dart:47` *"sem corpo =
   trait"*; CA70 já o assume).
2. **`override` OBRIGATÓRIO** (P4: sem ele, `class D : A { fn f() }` não diz se `f` é novo ou substitui —
   informação que muda o comportamento, escondida noutro arquivo). **P6 decide a FORMA (keyword, já feito),
   não a obrigatoriedade** — eixos ortogonais (Java `@Override` opcional × Swift `override` obrigatório).
   Não é cerimônia: carrega informação **para o leitor**, que não tem a superclasse na tela (economia do
   `mut`). ⚠️ **Distinção fina que a spec precisa:** `override` marca **substituir implementação**
   (superclasse concreta / default de trait), **não satisfazer requisito sem corpo** — senão dispara em
   toda conformance.
3. **Copy-with é SÓ de `struct`.** Sobre `class` **fura o `init`** — ADR-0012 #1: *"`class` usa `init`
   explícito **quando há estado a validar/normalizar**"* ⟹ copy-with é porta dos fundos para o invariante
   que o `init` guarda. + identidade nova sem glifo (fronteira de P2) + slicing pelo tipo estático sob
   herança. **`s.{ }` vazio: MOOT** — `postfixOp ::= "." "{" fieldInit ("," fieldInit)* "}"` exige **1+**;
   a gramática já fechou (classe do `where-empty`).
4. **Memberwise leva TODOS os campos, ordem de declaração; campo com default ⟹ param com default**
   (entailment do #1 "concisão" + P4: o default está escrito e o leitor o vê). **`let`/`var` NÃO muda nada**
   — governa mutação PÓS-construção; `let` que excluísse do init tornaria `struct P { let x: Int }`
   inconstruível. (`parser.dart:284-285`: field sem marca ⟹ `isMutable=false` — **P1 honrado no default**.)
5. **`Stack.new()` reafirmado** — vacuidade 6.5.1, o `[]` com outro nome. **Turbofish não parseia**
   (`primary` não tem `IDENT genericArgs`; `Stack<Int>.new()` vira **comparação** `(Stack<Int)>(.new())`).

**Rulings do dono levados:** (a) memberwise exige **label**? (`arg ::= (IDENT ":")? expr` — opcional; a
stdlib é 100% labelada; P4 favorece exigir); (b) **`class` sem `init`** — inconstruível (`no-init` no USO,
não na decl) e **`init` NÃO se herda**? (meu lean: sim aos dois — fecha a porta das regras de
designated/convenience/required init do Swift, que é a complexidade que o Itá não quer); (c) copy-with em
`class` **se ele quiser** — mas tem de responder `init` e slicing; (d) **turbofish** — gate é medir a stdlib,
como a 010 mediu o `[]` (25+, 100% sob anotação).

# Review da spec 011 escrita (2026-07-15) — **itaiano, 1 bloqueante**

**BLOQUEANTE §1.4 — `for` por tabela NÃO é "o chão".** A spec usou o ruling do CHÃO (010 §12-2:
`.length`/`[]`/`+`) para autorizar a tabela `List<T>→T` do **`for`**, que o **§12-4 da 009** nomeou
*"a mágica que §4.5/§8.3 recusam"*. **São tabelas diferentes e o §12-2 não revoga o §12-4** — prova:
a 010 §1.4-2 o chama de *"**o deferido** §12-4"* (vivo, roteado), e o §4.6.1 lista o chão **sem `for`**.
Critério que separa: **face 1** (010 §3.2), cujo exemplo canônico **é o `for`** — `.length` por tabela
não nega poder ao tipo do usuário (ele escreve `let length: Int`, B2); **`for` é sintaxe que só o
built-in alcança, e nenhuma linha de Itá conserta**. O pecado não é de onde vem a informação — é o que
o usuário não alcança. Do grep (`for` não precisa de `Iterator` **tecnicamente**) **não segue** "vai
por tabela na 012": a dependência do dono é **normativa**. ADR-0012 §C-9 já diz o interino: *"o `for`
HOJE é **retido como `ForInStatement`**"*. ⟹ **"como a F5 tipa o binder do `for` até o M5" é ruling do
dono**, não dedução da 012.

**Correção doutrinária 1 (§1.5) — "`next()` é contra P1" é FALSIFICÁVEL.** `mut self` **não viola P1**
(*"mutação é explícita e localizada"*); a stdlib tem `MutStack`/`MutQueue`/`MutDeque`. Forma que aguenta:
`next()` põe **o laço mais usado da linguagem** pelo caminho da mutação ⟹ contra o **"por padrão"** de
P1 e contra **P5**. E *"o quadrante que o Art. II nomeia"* está esticado — a analogia Elixir:Erlang é
sobre **RUNTIME** ([[systems-low-ffi-vision]]); o Elixir é **reforço**, P1+P5 é a razão (doutrina §8.3
contra nós mesmos).

**Correção doutrinária 2 (§12-4) — "o 6.5.3 nunca é invocado nesta linguagem" é FALSO hoje.**
`check.dart:49` — `_primitiveOps` é `Map<BinaryOp, List<(Type,Type,Type)>>`; `add` tem **3 triplas**
= resolução de sobrecarga por argumentos = **6.5.3 literal, rodando**. ADR-0012 #8 mantém `operator`
infix; **009 R5**: *"overload é o que torna built-in não-privilegiado; **recusar** overload é que seria
a mágica"*. O ruling do dono é "sem overload de **método**" — generalizar para "a linguagem" **mata a
peça que evita o privilégio**. (`check.dart:41-44` já escreve o destino M5: *"`Ops(sym)` perde o ∪"* —
é o precedente que a 010 §3.3 cita.)

**Q5 / §4.6 — `Stack.new()` é o `[]` com outro nome, e o "risco nº1" está mal enquadrado.** Zero args
⟹ `T` não é determinável por síntese ⟹ **Fundamento A da 010 §4.1 (vacuidade, 6.5.1)**, checking-only:
`let s: Stack<Int> = Stack.new()` ok / `let s = Stack.new()` `cannot-infer` — **simétrico a `[]`**. **Não
atravessa fronteira de declaração** (a assinatura `-> Stack<T>` está ANOTADA; instanciar ≠ inferir
através). **Não é HM.** E o inverso É anti-itaiano: `[]` (built-in) com contexto e `Stack.new()` (tipo
do usuário) sem = **face 1 falhando**. ⟹ *"se não couber, declarar não-objetivo"* **não é neutro** —
é declarar privilégio de built-in; vira **ruling do dono**.

**Q1 / §2.1 — a atribuição é fiel (o §3 da 010 é meu; assino), o diagnóstico é IMPRECISO.** *"A
declaração é escrevível; a chamada não"* **está errado — a declaração também não é**: a Prova 2 falha
em **3 eixos independentes** — (1) `extension Option<T>` é error-production pela §3.3 da própria 011;
(2) alvo **sem declaração** (`collect.dart:227`) e `Option` é **alias** → `OptionalType` (`:245-248`);
(3) call-site `member-on-optional`. Com um só eixo escrito, sobra a leitura *"basta destravar o
call-site"*; com os três, o ruling 1 fica **sobredeterminado**. É o escudo fraco no lugar do forte.

**Q2 / §3.3 — fiel. Lacuna: o `impl` ficou sem regra de alvo.** `implDecl ::= "impl" type ("for" type)?`
⟹ `impl Voa for Ave<T>` não cai em lugar nenhum. A regra que eu cravei e **não entrou**: **posição de
ALVO = nome nu** (sítio de binder); **demais posições = tipos normais com o `T` do alvo em escopo** ⟹
`impl Comparable<T> for Stack` e `extension Stack: Ord<T>` são **legais** (trait é *use site*).
`extension-target-has-type-args` é estreito no nome — cobre os dois.

**Q3 — o corte chão(012) × declaração-de-`List`(M5) está CERTO** (012 é o débito forma-M5; M5 é onde ele
morre = condição 3). Não há tensão comigo × `compiler-craftsman`: built-in-**generics** (`extension List`)
≠ built-in-**members** (`.length`). O que reprova é o **`for` ter viajado junto com `.length`**.

**§1.1 ("`_member` inteiro") — aceito, é melhor que a minha frase.** Ele **estreitou**, não alargou:
a unidade é a `record(t)`, não a decl; campo+CopyWith já eram escopo declarado da 010 (`[ ]` no DoD).

**Menores:** CA63 (flagship) é **o CA53 outra vez** se o corpo for o da stdlib — precisa de memberwise
(**F3, não existe**: `check.dart:182-185`) e `+` de List (**012**). CA73 depende do memberwise **por
construção**. ⟹ memberwise não é "dívida herdada" (passivo): é **pré-requisito** de 2 CAs.

---

# Ruling pré-011 (2026-07-15)

**Correção da minha própria tese.** Eu cravei que *"a spec do `Iterator` e a de membros-de-built-in são
a MESMA spec"*. **Certo sobre a PERGUNTA, errado sobre o VENUE:** o dono já roteou o `Iterator` para o
**M5** (ADR-0012 §C-9, 2026-07-12 — *"o contrato de iteração passa a ser um trait Itá na des-Dartificação
(M5)"*; o `for` fica `ForInStatement` até lá). De "uma pergunta" não segue "uma spec" — segue **uma
resposta, no lugar que o dono escolheu**. Força real da tese: **a 011 não pode responder** (não pode
inventar mecanismo que o M5 tenha de desinventar). Ver [[doctrine-extension-declaracao-legivel]].

**Escopo cravado (Q4):**
- **011 = "extension/impl entram na F5"** — (i) coletar + (ii-a) escopo genérico do alvo + (iii) member
  dispatch (walk de traits/superclasse). **Unidade indivisível:** consertar (i) sozinho faz os 29
  `extension` da stdlib **errarem no `T`** (silêncio vira falso-erro), e sem (iii) o coletado é morto.
- **M5 (não "012") = a declaração dos built-ins** — `List`/`Map`/`Result` ganham decl `.tu`; daí saem
  `extension List` (⟹ `.map`), `impl Iterator for List`, `for`. **(ii-b) + (iv) são a MESMA pergunta.**

**Q5 — é BUG, e pior do que o `compiler-craftsman` achou.** Não é só "corpo de extension não checado"
(P4/ADR-0013). `collect.dart:98-102` só lê `n.traits` (forma inline); **`ImplDecl` nunca é lido** ⟹ a
regra **da spec 009 §4** (*"`T : Trait` (inline **ou `impl Trait for T`**) ⟹ `T ≤ Trait`"*) é **inerte**,
e das duas formas que **ADR-0012 #2** mandou coexistir só a inline funciona. **Achado contra o review da
009/010** (não o de F3-4 — a F4 trata extension/impl certo, `resolver.dart:201-204`). Consertar É a 011;
o que é review é o **registro** (a spec não pode cobrar crédito de feature pelo que é reparo).

**Rulings de dono levados a Gabriel (2026-07-15):**
1. **§12-B1 re-ratificar** — ele ratificou *"`extension List<T>` é legal"* sob **premissa errada** (essa
   grafia não declara `T`). A **capacidade** sobrevive; a **grafia** é `extension List` e a
   **alcançabilidade** é M5 ⟹ dispara o escape-hatch do §12-B1 por motivo **diferente** do escrito:
   não "ilegal", **inalcançável**.
2. **§12-1 (`.map` é o idioma) fica PRESERVADO-MAS-ADIADO** para o M5 — ou o M5 entra na 011 (fere a
   "calma e parcimônia" que ele pediu). Hard-codar `map` é proibido (§3.4 + ADR-0013). **A 010 §2.1
   ("a stdlib migra na 011") é void.**
3. **`Option.map` × `member-on-optional`** — colisão frontal não vista: `T?` tem **Σ_membros = ∅**
   (009 §4.6, implementado `check.dart:750-756`, testado CA9) ⟹ `opt.map(f)` é **erro**. A Prova 2 do
   §3.1 da 010 (`extension Option<T> { fn map … }`, "zero chão") é **inalcançável no call-site** — erro
   meu, no meu próprio texto. Os 5 hard-coded **morrem** (idioma = `match`/`if let`), ou o ban vira
   fallback e a pedagogia do `if let` erode. **010 §1.4-4 ("é barata") é falso nos dois ramos.**
4. **`Iterator` nomeia DOIS protocolos incompatíveis** — ADR-0012 §C-9 diz *"`next() -> Option<T>`,
   modelo Elixir `Enumerable`"*: `next()` é cursor **com estado** (Rust/Swift, pede `mut self`, fere o
   espírito de P1); `Enumerable` é **fold/reduce** com suspensão (`:cont`/`:halt`/`:suspend`) — é o que
   a imutabilidade **força**, e é o quadrante do Art. II. Não ler aquela linha como fechada. `for` sobre
   `Map` rende o quê é da mesma decisão. **Tudo M5.**
