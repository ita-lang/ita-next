# ADR-0016 — Ratificação da fila do ADR-0014: a meta-diretriz Swift, suas aplicações e a razão nova do item 7

- **Status:** Accepted
- **Data:** 2026-07-16
- **Relacionados:** [[ADR-0014]] (a fila §3 que este arquivo esvazia; o Art. IV-6 que o mesmo ato aceita) · [[ADR-0015]] (precedente de forma — o 1º a tirar entradas da fila) · [[ADR-0012]] (§A-1; o item 7 ganha aqui a razão que o [[ADR-0014]] §2 revogou) · `constitution.md` Art. IV-6 (1.0.0 → 1.1.0)
- **Assentado por:** ratificação do dono em **2026-07-16** (ver §Procedência).

## Contexto

O [[ADR-0014]] §3 inventariou 7 frases que o código atribuía ao dono **sem artefato** — rulings reais
de conversa, vivos apenas como carimbo de data. O [[ADR-0015]] assentou as entradas 3 e 4. Restavam
**cinco**: a meta-diretriz Swift (1), três aplicações dela (2, 6, 7) e a razão caída do ADR-0012
item 7 (5).

## Procedência — como esta ratificação aconteceu

Em **2026-07-16**, a fila integral foi apresentada ao dono **entrada por entrada** — frase verbatim,
sítios verificados no código naquele dia, o que faltava em cada uma e o desenho de dependências
(a meta-diretriz destrava 2, 6 e 7). O dono ratificou **em bloco**, aprovando o curso recomendado:
assentar as cinco entradas, redigir razão nova para o item 7, aceitar o Art. IV-6 e virar o
[[ADR-0014]] para `accepted`.

Transcrição **sem interpretação** (a disciplina do [[ADR-0015]]): o que é verbatim do dono está
entre aspas; o que é redação da sessão está **assinado como derivação** (§E e as cercas do §A).
A ratificação foi **do inventário como apresentado** — nenhuma frase foi alterada entre a
apresentação e este assento.

## Decisão

### A. A meta-diretriz Swift (entrada 1)

> *"se tiver divergência ou indecisão, a maneira que o Swift trabalha é a diretriz"*

Ruling do dono (sessão de 2026-07-15), verbatim. Com este ADR, deixa de existir só como data em
comentário (`check.dart` `_matchArgs` · `collect.dart` `_initOf` · `type.dart`).

**Duas cercas — redação desta sessão, não do dono:**

1. **A meta-diretriz não se auto-executa.** Cada aplicação dela entra no registro por assento
   próprio (Art. IV-6c) — este ADR assenta três (§B–§D). Citar "§A" sozinho para justificar
   comportamento **novo** é exatamente a promoção de derivação que o [[ADR-0014]] proíbe.
2. **O escopo não foi delimitado pelo dono.** "Divergência ou indecisão" entre o quê (Swift × Dart?
   qualquer par?) e sobre qual território (superfície? semântica?) fica **em aberto**; na dúvida, a
   aplicação nova volta ao dono antes de virar código.

### B. `init` no CORPO **mata** o memberwise; em **`extension`** o **PRESERVA** (entrada 2)

Aplicação de §A — no Swift, *"o compilador só gera o memberwise se a declaração do tipo não define
um init próprio"*, e o `init` em extension é o workaround canônico.

- **Metade "mata":** o `init` explícito no corpo **substitui** o memberwise (*"é possível que você
  esteja fazendo trabalho especial que o default desconhece"*). Duas portas para o mesmo tipo, uma
  bypassando a validação da outra, é o furo que fez o dono recusar copy-with em `class`
  (ADR-0012 §C-razão-3). O ADR-0012 §A-1 **implicava** esta metade (memberwise "sem `init`
  explícito"); este ADR a **crava**.
- **Metade "extension preserva":** o ADR-0012 §A-1 nomeia `extension` entre os corpos que admitem
  `InitDecl` — autoriza o `init` lá, mas **não dizia** o que ele faz ao memberwise. Este ADR crava:
  **preserva**. A extension é o glifo que diz *"estou ADICIONANDO, não substituindo"* — sem ela,
  quem precisa de um 2º construtor perde o memberwise inteiro.
- **Implementação (já em vigor, testada):** `initFromBody = true` mata; `extensionInits` acumulam
  como **adicionais**, com precedência do `init` do corpo (é ele que diz "faço trabalho especial").

### C. Ordem obrigatória, defaults saltáveis — o label **confirma**, não **reordena** (entrada 6)

Aplicação de §A com **divergência real e documentada**: Dart deixa reordenar named args; Swift não
(*"argument 'num' must precede argument 'den'"*). Seguimos o Swift.

- **A regra:** a chamada espelha a assinatura. Param com default é **omissível** — e é assim que se
  salta. O label confirma a posição; nunca a troca.
- **O que mata:** `div(den: 2, num: 10)` ligando invertido **em silêncio**; `f()` com default dando
  `arity-mismatch` falso; `f(zz: 1)` (label inexistente) passando.
- **Códigos de erro que funda:** `argument-label-mismatch` · `unknown-label` · `missing-argument`
  (e corrige o `arity-mismatch` falso com defaults). Sítio: `check.dart` `_matchArgs`.
- É a mais visível ao usuário final das três aplicações — **regra de superfície da linguagem**,
  vale para todo call-site do Itá.

### D. `init` **NÃO se herda** (entrada 7)

Aplicação de §A. Coerente com o contraste que o ADR-0012 §A-1 criou: `class` sem `init` não ganha
memberwise, e o erro é no **USO** (`no-init`), não na decl — classe base tem campos e nunca é
construída. Herdar `init` reabriria pela lateral a porta que o §A-1 fechou pela frente.
Implementação por **omissão estrutural**: `_initOf` só deriva `init` dos membros do próprio tipo;
nenhum caminho copia construtor de superclasse.

### E. A razão nova do ADR-0012 item 7 (entrada 5)

O **adiar** associated types **fica** — reafirmado pelo [[ADR-0014]] §2, e este ADR não o reabre.
A razão revogada (*"bounds inline cobrem a maioria dos casos"*) era **falsa** (verificada: a F5
descarta os bounds). A razão nova, **redigida por esta sessão (derivação) e aceita pelo dono no
ato de ratificação**:

> Associated types dependem de infra de bounds que a F5 **não tem** — os bounds inline são hoje
> descartados e declarados como lacuna (`generic-bounds-unsupported`, desde `b72310d`), não lidos.
> E, pela metade do item 7 que sempre foi verdadeira: *"se entrar, é sum/product novo, não
> retrofit"* — espera design próprio, não emenda.

### F. Os dois atos acima da fila

No mesmo ato de 2026-07-16 o dono:

1. **Aceitou o Art. IV-6** (*"data não é fonte"*, texto integral no [[ADR-0014]] §1) — a
   constituição vai de 1.0.0 → **1.1.0**, e as duas ressalvas honestas do [[ADR-0014]] §1 ficam
   decididas: ADR pode propor ajuste operacional ao Art. IV (*a fortiori* do bullet de specs em
   §Governança), e o bump é **MINOR** (§Versionamento: "novo princípio/regra").
2. **Virou o [[ADR-0014]] para `accepted`** — a partir de agora ele é citável como decisão vigente.

## Consequências

- **A fila do [[ADR-0014]] §3 está VAZIA** — entradas 3 e 4 no [[ADR-0015]]; 1, 2, 5, 6 e 7 aqui.
- **O código troca data por citação** no commit seguinte a este (Art. IV-6c: registro **antes** do
  código): `check.dart`, `collect.dart`, `type_table.dart`, `lexer.dart`. Nenhuma linha executável
  muda — só procedência de comentário.
- **A confissão do `type.dart` (bloco "fabricava de novo") não é reescrita** — [[ADR-0014]]: é
  prova. Ganha no máximo ponteiro **aditivo** para este ADR.
- **Reconciliação registrada:** a spec 003 §2.1 passa a cravar o teto `$0..$255` do `CLOSURE_PARAM`
  citando o `grammar.ebnf` §1 — fecha a inconsistência apontada na nota final do [[ADR-0014]] §3.
  A direção é essa porque a própria spec 003 (§2.5) declara o `grammar.ebnf` como *"a
  fonte-da-verdade citável do léxico"*.
- **Segue em aberto (fora desta fila, e este ADR NÃO decide):** a lacuna dos labels
  obrigatórios + opt-out `_` (`type.dart`: *"as duas metades são um ruling só"*) · a lowering de
  conformance (pré-F7).

## Relacionados

- **Fila de origem:** [[ADR-0014]] §3 (agora vazia).
- **Precedente de forma:** [[ADR-0015]] (transcrição sem interpretação; derivações assinadas).
- **O que este ADR completa no [[ADR-0012]]:** §A-1 ganha as duas metades que implicava (§B, §D);
  item 7 ganha razão nova (§E). **O ADR-0012 não é editado** (README: decisão que muda não edita o
  ADR antigo).
- **Constituição:** Art. IV-6 (a–d) entra em vigor com a 1.1.0.
