# ADR-0019 — O corpo do `init`: levantar a restrição e decidir o que ela escondia

- **Status:** **Parcialmente aceito** (2026-07-29) — o dono mandou *"faça o recomendado"*. **R2, R3, R4 e as bordas §5-1/§5-2 estão IMPLEMENTADOS** pela derivação recomendada, cada um com CA negativo e teste na suíte da F5 (ver §9). **R1 continua ABERTO** — a recomendação era (B) explícito, e o glifo é superfície de linguagem que este ADR não propôs; sem R1 não há corte, e sem corte o R5 não tem onde valer.
- **Data:** 2026-07-29
- **Relacionados:** [[ADR-0012]] §A-1 (`init` explícito quando há estado a validar/normalizar) · [[ADR-0016]] §A (meta-diretriz Swift não se auto-executa), §B (`init` no corpo **substitui** o memberwise; em `extension` **preserva**), §D (`init` não se herda) · [[ADR-0013]] (inferência que falha é ERRO) · spec 005 §3.1a/§10 · spec 013 §7.4-c · spec 014 §1–§3 (flow-walk) · `grammar.ebnf:229,273`

## Procedência

Preparado em 2026-07-29 por dois pareceres independentes, **assinados** (Art. IV-6b):
`dart-vm-expert` (restrições verificadas no vendor `third_party/dart/3.12.2/pkg/kernel` e na fonte
da VM @3.12.2, arquivo:linha) e `ita-visionary` (leitura pelos 11 princípios e pelos artefatos
existentes). Este ADR é **auto-contido** — o que os pareceres provaram está transcrito aqui com as
fontes. **A recomendação é derivação da sessão; a decisão é do dono.**

O gatilho foi mecânico, não editorial: em 2026-07-29 a F5 passou a tipar o corpo do `init`
(`_initDecl` em `check.dart`), depois de um `.dill` mal-tipado ter **segfaultado a Dart VM** sobre
programa legal. Com isso caiu o único impedimento real que sustentava a restrição — e ninguém teria
notado, porque **nenhum gate vigia a razão de uma restrição, só a restrição**. Ver §8.

---

## §1 Contexto — a restrição, e por que ela não é lei

`codegen/lib/emit.dart` restringe o corpo do `init` a **apenas** `self.campo = e`; qualquer outro
statement vira `_ice('init-body-<T>')`. A justificativa está escrita ao lado, verbatim:

> *"A conversão exige que o corpo seja **só** atribuições a `self` … **Não é preguiça**:
> `FieldInitializer` roda ANTES do corpo, então misturar lógica entre as atribuições mudaria a
> ORDEM de avaliação em silêncio."*

Quatro fatos, cada um verificável:

1. **A gramática concede o bloco inteiro.** `grammar.ebnf:229` — `initDecl ::= "init" "(" paramList ")" block` — e `:273` — `block ::= "{" ( statement ";"? )* "}"`. É o **mesmo** não-terminal de `fn`, `while`, `if`. Não existe produção restrita de "bloco de atribuições".
2. **A restrição não tem casa normativa.** Grep de `init-body` fora de `third_party/` devolve exatamente dois sítios: o emissor e `conformance/codegen/class_ca3.tu`. Nenhuma spec, nenhum ADR, nenhum teste — e **nenhum `EXPECT-ICE`**. Nasceu prosa no emissor e nunca foi lei.
3. **Ela esvazia a razão pela qual o memberwise foi morto.** [[ADR-0016]] §B, verbatim: *"o `init` explícito no corpo **substitui** o memberwise (**'é possível que você esteja fazendo trabalho especial que o default desconhece'**)"*. Sob a restrição o corpo **não pode fazer trabalho especial nenhum** — só o que o memberwise já fazia. O usuário paga o preço inteiro e não recebe nada.
4. **Duas fases do compilador já apostam o contrário.** `compiler/lib/frontend/semantic/check.dart:1064-1069`: a F5 **recusa** copy-with sobre `struct` com init de corpo *"porque o único construtor **valida**"* — protegendo uma validação que a F7 torna impossível de escrever.

## §2 O que o Kernel de fato exige — e o que não exige

**A premissa da justificativa é verdadeira no fato e falsa na conclusão.**

**Verdadeiro:** a lista de initializers roda antes do corpo, sempre.
`runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc`, `BuildFunctionBody`:

```cpp
if (constructor) { body += BuildInitializers(...); }
if (body.is_closed()) return body;
```

**Falso:** que isso obrigue a restrição. O Kernel tem a forma canônica para intercalar avaliação na
lista — `LocalInitializer` —, e **o próprio CFE a usa**. Comentário verbatim da VM no
`case kLocalInitializer:`:

```
//   The frontend converts   A(a, b) : super(a + b), x = 2*b {}
//   to                      A(a, b) : tmp = a + b, x = 2*b, super(tmp) {}
```

Três correções ao comentário do emissor, todas verificadas:

- *"campo `final` … atribuí-lo no corpo é malformado"* — **não é malformado, é inexprimível**.
  `InstanceSet` resolve por `getNonNullableMemberReferenceSetter`, que faz `member.setterReference!`
  (`src/ast/helpers.dart:147-150`); `Field.immutable` tem `setterReference == null` ⟹ o nó **estoura
  na construção**, dentro do `itac`, antes de existir `.dill`.
- *"misturar lógica mudaria a ordem em silêncio"* — só se a lógica ficar no **corpo**.
- **Fato que falta e morde design futuro:** `BuildInitializers` executa, antes de tudo, os
  inicializadores de **declaração** (`Field.initializer`). Hoje é inócuo; no dia em que campo tiver
  default, *"default de declaração antes de toda a lista"* é regra **da VM**, não nossa.

**O vocabulário disponível** (`Initializer` é `sealed`, 6 subclasses — `src/ast/initializers.dart:12`):

| forma | carrega | serve para |
|---|---|---|
| `FieldInitializer` | `Expression` | **a única** escrita de campo pré-corpo; vale para final e mutável |
| `LocalInitializer` | `VariableDeclaration` | avaliar expressão arbitrária **na posição textual** |
| `AssertInitializer` | só `AssertStatement` | nada de útil (gated por `--enable-asserts`) |
| `Super`/`Redirecting` | `Arguments` | n/a (herança é ICE) |
| `InvalidInitializer` | mensagem | erro de compilação |

**Contrato duro do `LocalInitializer`** — os dois consumidores (VM e dart2js) concordam, e é isto que
nos vincula: a variável fica *"in scope for the remainder of the initializer list, but is **not** in
scope in the constructor body"* (`initializers.dart:321-324`); o initializer é obrigatório; tem de ser
`isFinal`; **não** pode ser const.

## §3 O que é RESTAURAÇÃO — e portanto não pede ruling

**Levantar a restrição devolve o que a gramática já concede.** Os quatro fatos do §1 são artefatos,
não interpretação. Nenhum princípio do Itá a sustenta, e três a contradizem: P4 (sem mágica — é o
compilador escondendo o que a linguagem é), o ADR-0016 §B (o "trabalho especial" que ela proíbe), e a
coerência interna (a F5 rejeita programas para proteger uma validação impossível de escrever).

**Escopo obrigatório do levantamento** — sob pena de repetir *"feature meio-ligada é pior que feature
ausente"*:

- `emit.dart` `_ice('init-body-<T>')` — a restrição em `class`;
- `emit.dart` `_ice('struct-init-explicit')` — a **mesma família**, cortando o construto que o
  ADR-0016 §B decidiu e que a F5 já implementa (`initFromBody`);
- **co-requisito duro:** `compiler/lib/frontend/analysis/flow.dart` tem `case ast.InitDecl(): break;`
  — **a F6 não caminha o corpo do `init`**. O comentário dela nomeia o pré-requisito (*"Quando o
  `init` entrar na F5, este case vira o walk"*), e ele caiu. Abrir o corpo sem ligar o walk põe o
  idioma canônico de validação (`guard … else { panic(…) }`, P7) na linguagem **sem**
  `guard-must-exit`, sem `unreachable-code` e sem definite-assignment.

**Também não pedem ruling** (registrado para o dono não gastar tempo):

- **A ordem observável é entailment de P4.** `block` é o mesmo não-terminal de `fn`/`while`/`if`. Se
  um statement desse bloco rodasse fora da ordem-fonte, o `init` seria o **único** lugar do Itá onde
  ordem de escrita ≠ ordem de execução. `init(a) { valida(a); self.x = a }` roda `valida` antes,
  ponto. O que é decisão aqui é a técnica de emissão, não a semântica.
- **Campo não inicializado é consenso, e já foi implementado** (`field-not-initialized`, 2026-07-29).
  Toda opção em aberto rejeita `class C { let x: Int, let y: Int  init(a) { self.x = a } }` — ele
  imprimia **`null`** para um `Int`. O `pkg/kernel` põe a obrigação aqui, verbatim
  (`src/ast/initializers.dart:111-112`): *"The frontend should check that all final fields are
  initialized exactly once, and that no fields are assigned twice in the initializer list"*; e o
  `checkInitializers` do verifier é **função vazia** (`verifier.dart:2194-2196`).

## §4 Os cinco rulings

### R1 — O corte é IMPLÍCITO ou EXPLÍCITO? *(o central — decide a forma dos outros)*

A emissão que funciona particiona o corpo: **prefixo** (até o último `self.campo = e`) vira
`initializers` — `FieldInitializer` para as atribuições, `LocalInitializer` para o resto, na ordem
textual — e **sufixo** vira `function.body`, onde `self` está completo e todo statement vale.
Tecnicamente as duas opções emitem **o mesmo Kernel**; a diferença é quem enxerga o corte.

- **(A) Implícito** — o compilador infere o corte no último assign de campo.
  *Custo:* existe uma fronteira semântica real (antes dela `self` é ilegível, `let` local não
  atravessa) que **não aparece no texto**. Mover uma linha muda o que o programa aceita, sem que nada
  no fonte diga por quê. É o tipo de regra invisível que o P4 recusa.
- **(B) Explícito** — um glifo separa as duas fases.
  *Custo:* superfície nova (mudança de gramática) e um conceito a mais para quem escreve um `init`
  trivial. Em troca, a fronteira fica legível e o diagnóstico pode apontá-la.
- **(C) Sem corte — tudo no corpo, via `InstanceSet` sobre `this`.**
  *Custo (três moedas, todas verificadas):* obriga `Field.mutable` em **todo** campo escrito no
  `init`, inclusive os de `let` — a promessa do `let` some do artefato; perde o **slot imutável** da
  VM (`runtime/vm/compiler/backend/slot.cc`: `IsImmutableBit::encode(field.is_final() && !is_late())`
  — slot imutável faz load de campo sobreviver a chamadas); e cria janela em que campo não-nulável
  vale `null`, Kernel que o CFE nunca emite. *(A janela em AOT não foi medida — risco declarado, não
  fato.)*

> **Derivação da sessão:** (B) ou (A), com (B) preferida por P4 — a fronteira existe, e escondê-la é
> exatamente o que a restrição atual fazia em outra escala. (C) descartada: paga o `let` inteiro.
> **A escolha do glifo, se for (B), é do dono e não está proposta aqui.**

### R2 — Campo `let` de `class` é `final` no `.dill`?

- **(A) Sim.** `let` vira `Field.immutable`, escrito só por `FieldInitializer`. Ganha o slot imutável;
  **obriga** o corte (R1-C morre).
- **(B) Não** — campo sempre mutável no artefato, `let` vira convenção de front-end.
  *Custo:* perde a otimização e o `.dill` deixa de registrar uma promessa que a linguagem faz.

> **Derivação:** (A). É o único que mantém `let` significando algo depois da compilação.

### R3 — Campo `let` pode ser atribuído mais de uma vez dentro do `init`?

⚠️ **Há comportamento vivo não-registrado.** Hoje `check.dart` permite **N** atribuições, em qualquer
posição, porque a guarda é `!d.isMutable && !(_inInitBody && m.receiver is SelfExpr)`. Ninguém
decidiu isso: caiu da isenção escrita em 2026-07-29 para evitar o falso `assign-to-immutable`. E o
ADR-0016 §A crava que a meta-diretriz Swift **não se auto-executa** — *"cada aplicação dela entra no
registro por assento próprio"*.

- **(A) Exatamente uma vez.** Alinha com P1 (`let` liga, não muta).
  *Custo:* exige o definite-assignment da F6 e proíbe `self.x = 0` seguido de `if c { self.x = 1 }` —
  que se reescreve `self.x = if c => 1 else 0`, forma que a linguagem já tem (P3/RD-1).
- **(B) Quantas vezes quiser** (o de hoje). *Custo:* dentro do `init` o `let` vira `var`; a diferença
  entre os dois glifos deixa de existir num escopo.
- **(C) `let` uma vez; `var` livre.** *Custo:* duas regras — mas cada uma é a leitura literal do glifo.

> **Derivação:** (A) ou (C). (B) só se o `init` for deliberadamente uma janela de mutação.
> *Não verifiquei o diagnóstico literal do compilador Swift nesta sessão* — se o dono quiser paridade
> textual, isso precisa ser checado antes de virar spec.

### R4 — `self` pode ser LIDO antes de todos os campos estarem atribuídos?

Precedente que tangencia sem decidir: `self-in-field-default` (spec 014) já recusa `self` onde o
objeto não existe. E o ADR-0016 §D (`init` não se herda) elimina a cadeia de super, o que torna a
opção barata viável.

- **(A) `self` só como ALVO de atribuição, antes do corte.** Regra de uma linha, sem análise de fluxo.
  *Custo:* proíbe `self.area = self.largura * self.altura`, que se reescreve com local.
  **É a única que só afrouxa depois** — qualquer relaxamento futuro aceita mais programas e não
  quebra nenhum já escrito.
- **(B) Two-phase do Swift** — leitura liberada quando todos os campos estiverem definitivamente
  atribuídos. *Custo:* depende do DA da F6 e institui fase observável no `init`. Ganha ergonomia real.
- **(C) Livre.** *Custo:* `self.metodo()` com campo por escrever lê um `Int` que não existe — é o
  buraco do `field-not-initialized` por outra porta.

> **Derivação:** (A) agora, (B) quando a F6 tiver DA de campo — nessa ordem, porque (A)→(B) só amplia.

### R5 — O que vale no PREFIXO (se R1 = A ou B)

Quatro gates são consequência do Kernel, não gosto — mas **o diagnóstico** de cada um é escolha:

1. **Nada no prefixo lê `self`** — dart.dev: *"The right-hand side of an initializer list can't access `this`"*.
2. **Nada no prefixo tem fluxo não-local** — o `?`/`Try` emite `BlockExpression` com `ReturnStatement`;
   a VM tolera, mas "retornar de um construtor com campos por escrever" é lixo semântico.
3. **`let` local no prefixo não atravessa o corte** (`initializers.dart:323-324`). Proibir com
   diagnóstico honesto, ou aceitar o escopo partido?
4. **Control-flow de statement antes do corte** — `Initializer` é `sealed` e nenhuma forma carrega
   statement (só `AssertInitializer`, e só `AssertStatement`). Escape possível via `BlockExpression`,
   **com risco de paridade JS não verificado**. Proibir, ou pagar o risco?

> **Derivação:** proibir os quatro no prefixo, com erro nomeado da F5/F6 apontando o corte. Para
> decidir valor de campo condicionalmente, a saída é `if` como **expressão** (RD-1) →
> `ConditionalExpression`, que cabe num `FieldInitializer` sem truque nenhum.

## §5 As três bordas do `field-not-initialized`

O consenso já está implementado; estas três não são consenso:

1. **Campo `T?` sem default e não atribuído:** inicializa implicitamente com `nil`, ou exige
   `self.x = nil`? *(Implícito custa uma exceção ao P4 — o compilador escreve valor que o usuário não
   escreveu. Exigir custa verbosidade.)*
2. **Campo com default na decl:** o default cobre a omissão (hoje sim, por implementação) e o `init`
   pode sobrescrever. Confirmar — e decidir se o default roda antes do corpo (§2: a VM diz que sim).
3. **A fase dona:** F6 (é literalmente o JLS §16 sobre outro conjunto de slots, e a F6 tem o walk) ou
   F5? Hoje está na F5, **sintática**, e vira unsound no dia em que o corpo aceitar `if`.
4. **`return` nu dentro do `init`:** o `init` tem saída antecipada? Se tem, o DA vale em todo caminho
   de saída? *(Hoje tipa, porque `_currentFnReturn = VoidType` — fato de implementação, não ruling.)*

> **Derivação:** 1 = exigir (P4 + invariante de nulidade); 2 = cobre; 3 = F6.

## §6 Consequências (se ratificado)

- Sai a doutrina inventada de `emit.dart` e de `conformance/codegen/class_ca3.tu` — **apagar**, não
  reescrever: a premissa é sobre o Kernel e é falsa como enunciada, e a conclusão é sobre a
  linguagem, que o emissor não decide.
- O CA3 (*"`class` com `init` explícito **valida**"*) passa a ter fixture onde algo de fato valida —
  hoje a cláusula é evidenciada por um fixture onde nada valida.
- `flow.dart` ganha o walk do `init`; `guard`/`panic`/`unreachable-code`/DA passam a valer lá.
- `field-not-initialized` migra de sintático para o DA da F6 (§5-3).
- A fatia nasce com **LT nomeada** na spec 013 `tasks.md` — o trabalho do CA3 entrou sem uma, e isso
  é o padrão *"declaração que só existiu na conversa"*.

## §7 O que fica FORA

Herança (`super` não existe na gramática), `init` de `extension` como construtor adicional
(`extensionInits`, hoje ICE — é a 2ª cláusula do CA3), e `late`/lowering do CFE (descartado: `late` é
transformer por Target, e nós não rodamos transformer — paridade JS em risco).

## §8 A regra que este incidente compra

O repo tem a **R7** — todo `_ice` precisa de fixture `EXPECT-ICE`, que fica vermelho quando a fatia
nasce. **Não existe sinal para o caso simétrico: a restrição fica e a razão dela morre.** Foi o de
hoje: a F5 passou a tipar o corpo, o ICE continuou cortando programa legal, e o CI seguiu verde.
A R7 vigia a *restrição*; ninguém vigia a *razão*. E o `flow.dart` prova que nomear em prosa não
basta — ele **nomeou** o pré-requisito, com precisão, e não ficou vermelho.

**Proposta (R15):** toda restrição nomeia o impedimento que a mantém viva, e o impedimento é uma
**asserção executável** — sonda comportamental sobre o artefato da fase dona (a mais forte: para
*"a F5 não tipa o corpo do `init`"*, rodar o checker e assertar que `exprTypes` não tem entrada — e
essa sonda teria ficado vermelha no próprio commit que adicionou `_initDecl`), sonda sobre o pacote
externo (*"o Kernel não tem como"* → `!existeNoKernel('LocalInitializer')`, que teria sido vermelha
**desde o dia zero**), ou asserção estrutural sobre a fonte (fraca, declarada como tal).

Cercas: o impedimento nunca é constante nem re-enunciado da restrição — tem de olhar **outro**
artefato; e toda entrada nomeia a LT que a fecha, que é o que faz o ledger custar alguma coisa.
Limite honesto: para restrição cuja razão é *"ninguém decidiu ainda"*, o impedimento é a ausência de
artefato e a sonda é frágil — essas entram como **ponteiro para a fila do dono**, sem reivindicar
garantia.

---

## Fontes

- `runtime/vm/compiler/frontend/kernel_binary_flowgraph.cc` @3.12.2 — `BuildFunctionBody`, `case kLocalInitializer`
- `runtime/vm/compiler/backend/slot.cc` @3.12.2 — `IsImmutableBit::encode`
- `third_party/dart/3.12.2/pkg/kernel/lib/src/ast/initializers.dart` — `:12` (sealed), `:111-112` (TODO), `:321-324` (escopo do `LocalInitializer`)
- `third_party/dart/3.12.2/pkg/kernel/lib/src/ast/helpers.dart:147-150` · `verifier.dart:744-768`, `:2194-2196`
- [Constructors — dart.dev](https://dart.dev/language/constructors) · [not_initialized_non_nullable_instance_field](https://dart.dev/tools/diagnostics/not_initialized_non_nullable_instance_field)
- `compiler/docs/spec/grammar.ebnf:229,273` · `specs/005-decl-surface/spec.md:54,109,130`

---

## §9 O que foi implementado em 2026-07-29

Sob *"faça o recomendado"*, e **só o que não dependia do R1**:

| ruling | opção | estado | evidência |
|---|---|---|---|
| **R2** `let` é `final` no `.dill` | (A) | **já era** — `emit.dart` emite `Field.immutable` para `let`, `Field.mutable` para `var` | — |
| **R3** `let` atribuído 2× | **(A)** exatamente uma vez | ✅ `field-assigned-twice` | `err_field_assigned_twice.tu` + 2 testes |
| **R4** ler `self` cedo | **(A)** só como alvo | ✅ `self-read-in-init` | `err_self_read_in_init.tu` + 3 testes |
| **§5-1** `T?` sem default | exigir atribuição | ✅ — `T?` não é isento do `field-not-initialized` | `err_field_not_initialized.tu` |
| **§5-2** campo com default | cobre a omissão | ✅ | teste na F5 |
| **R1** o corte | — | ⛔ **ABERTO** | — |
| **R5** gates do prefixo | — | ⛔ bloqueado por R1 | — |
| **§5-3** fase dona | F6 | ⛔ bloqueado pelo walk (co-requisito §3) | — |

**Nota sobre o R4 e a monotonicidade.** A regra vale hoje para o corpo INTEIRO,
porque não há corte — tudo vira `initializers`. Quando o R1 existir, ela relaxa
para *"antes do corte"*: no sufixo o objeto está completo e a leitura é livre.
Essa direção é deliberada — (A)→(B) só amplia, e nenhum programa escrito sob (A)
quebra. A ordem inversa quebraria código.

**Nota sobre o R3.** O comportamento anterior (N atribuições) não era decisão: caiu
por acidente da isenção escrita no mesmo dia para evitar o falso
`assign-to-immutable` dentro do `init`. O ADR-0016 §A proíbe exatamente isso — a
meta-diretriz Swift *"não se auto-executa"*.

**Por que o R1 não foi decidido junto.** A derivação era (B) explícito, e (B)
exige um glifo — superfície nova de linguagem, que este ADR deliberadamente **não
propôs**. E a escolha não é reversível: programas escritos sob (A) implícito
quebram se (B) entrar depois, porque passariam a exigir o glifo. Decidir por
conta seria inventar superfície e travar a linguagem numa direção — o erro que
esta série inteira existe para corrigir.