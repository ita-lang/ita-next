# ADR-0014 — Procedência de ruling: **data não é fonte**

> **Status:** **`proposed`** — ⚠️ **NADA neste arquivo está ratificado.** Ele **propõe**; quem ratifica é o dono (`GabrielAderaldo`). Enquanto o status for `proposed`, nenhuma linha daqui pode ser citada por código como decisão vigente — citá-lo assim seria cometer exatamente a doença que ele descreve. O §3 (ratificação) lista o que falta.
> **Data:** 2026-07-15
> **Supersedes:** **ADR-0012 — PARCIAL** (ver §2): revoga **apenas a razão escrita** do **item 7** (§B, associated types) — *"bounds inline (`T: A + B`, já em `genericParam.bounds`) cobrem a maioria dos casos"*. **A decisão do item 7 — *adiar* associated types — permanece em vigor e é reafirmada.** Todo o resto do ADR-0012 (itens 1-6, 8, 9) segue intacto e não é tocado.
> **Relacionados:** `constitution.md` (Art. IV, §Governança), ADR-0013 (precedente de forma do supersede parcial), ADR-0012 (rulings de superfície), ADR-0008 (harness SDD), specs `009-semantic-types` §12, `010-contextual-typing` §12, `011-member-resolution` §12

## Contexto

O código do `ita-next/compiler/lib/` atribui decisões ao dono em ~26 sítios, na forma `(ruling do dono 2026-07-15)` / `(diretriz do dono)`. Uma auditoria de 2026-07-15 abriu **cada** um contra os artefatos (`.specify/memory/adr/`, `specs/`, `constitution.md`, `docs/spec/ast.asdl`, `docs/spec/grammar.ebnf`) e achou três classes de dano — todas com a **mesma causa**.

**A causa: a data é inauditável.** `(ruling do dono 2026-07-15)` não dá ao próximo leitor **nada** com que conferir. Não há o que grepar, nem o que abrir. A citação — `(ADR-0012 §7)` — é um grep. O carimbo de data tem a *forma* de proveniência sem a *função*: parece rastreável e não é. E onde a verificação é impossível, a fabricação é indistinguível do registro — foi o que aconteceu.

**O que a auditoria achou:**

1. **Fabricação** — três casos já apanhados nesta sessão (o mais recente, `b72310d`, *"ruling fabricado"*), um deles **dentro do comentário escrito para denunciar o anterior** (`type.dart:270-290`, preservado como confissão). O padrão não é má-fé: é que **nada obrigava a conferir**.
2. **Promoção** — derivação de agente vestida de ruling de dono (ex.: *"sem base de traversal comum"*, `core_check.dart`, cujo argumento é inteiramente técnica de compilador).
3. **Mis-citação silenciosa** — `type.dart` e `unify.dart` citavam **`§12-7`** para *"`?` é MODIFICADOR"*. O `§12-7` da spec 009 é ***"`let` sem init: PROIBIDO"***; o ruling do `?` é o **§12-1**. Um ponteiro errado que ninguém pegou em 2 arquivos — porque `§12-N` **não diz de qual spec** (a 009, a 010 e a 011 têm cada uma o seu §12, com numerações **diferentes e colidentes**: `§12-1` é *"`?` é modificador"* na 009, *"`.map` é o idioma"* na 010 e *"os 5 hard-coded morrem"* na 011).

**E o achado que justifica a regra melhor que qualquer argumento:** a auditoria suspeitava que *"a assimetria é o princípio na FORMA"* (`parser.dart:673`) fosse derivação promovida. **Era ruling de dono legítimo** — está na **spec 009 §12-7**, *verbatim*: *"A assimetria é o princípio visível na gramática … **P1 deixa de ser só semântica e vira FORMA**"*. O carimbo de data **não sabia distinguir o verdadeiro do falso**; o artefato soube em um grep. A regra abaixo não existe para desconfiar do dono — existe para que o que é dele **seja reconhecível como dele**.

## Decisão

### 1. Proposta de **Art. IV-6** da constituição

Acrescentar ao Artigo IV (regras operacionais):

> **6. Procedência de ruling — `data não é fonte`.**
> **(a)** Todo comentário de código que atribui decisão ao dono (`ruling do dono`, `diretriz do dono`) **exige ponteiro para artefato**: `ADR-NNNN §N` · `spec NNN §X` · `Const. Art. N` · `ast.asdl` / `grammar.ebnf`. **A data não substitui a citação** — pode acompanhá-la, nunca ocupá-la. Sem artefato, **não se atribui ao dono**.
> **(b)** **Todo o resto assina o nome de quem concluiu** — *"derivação do `compiler-craftsman`"*, *"entailment de P1"*, *"leitura do `ita-visionary`"*. Conclusão de agente na voz do dono é **fabricação**, mesmo quando a conclusão está certa.
> **(c)** **Agente que implementa ruling vindo de conversa primeiro o assenta no registro** (ADR ou spec) e **depois** escreve o código que o cita. **A conversa não é artefato** — não sobrevive à sessão, e o código que a cita nasce órfão.
> **(d)** **Citação de `§12-N` (ou de qualquer § de spec) nomeia a spec**: `spec 009 §12-1`, nunca `§12-1` nu. As specs 009/010/011 têm §12 com numerações colidentes.

**Fundamento de governança — verificado.** O `constitution.md` §Governança, **2º bullet**, diz: *"**Artigos III e IV** evoluem com o roadmap; specs podem propor ajustes operacionais com justificativa."* ⟹ **o Art. IV admite ajuste operacional sem emenda ao Art. I** (cujas emendas o 1º bullet reserva a decisão explícita do dono). Duas ressalvas honestas: (i) o bullet nomeia **specs** como proponentes — este ADR faz o mesmo ato num tier acima (`constitution > ADR > spec`), o que é *a fortiori* mas **não está escrito**; (ii) por §Versionamento (*"MINOR = novo princípio/regra"*), isto leva a constituição de **1.0.0 → 1.1.0**. **Ambas são atos de dono. Este ADR não as executa.**

### 2. Supersede **parcial** do ADR-0012 — item **7** (§B, associated types)

**Fica** (reafirmado): *"**Associated types em `trait` (`type Item`): adiar.** … Se entrar, é sum/product novo, não retrofit."*

**Cai:** a razão — *"**Bounds inline (`T: A + B`, já em `genericParam.bounds`) cobrem a maioria dos casos.**"*

**Por que é falsa (verificado no código, não inferido):** os bounds são **descartados pela F5**. `TypeInfo.generics` é `List<String>`; todo `TypeParamType(owner, g.name)` **ignora `g.bounds`** (`collect.dart:72-78`). Eles não cobrem caso nenhum — não são lidos. Desde o commit **`b72310d`** (*"consolidação da F5 — ruling fabricado, diamante mudo, **bound decorativo**"*) o compilador **emite `generic-bounds-unsupported`** (`collect.dart:100`), declarando a lacuna em vez de acusar o usuário: antes, `fn f<T: Ord>(x: T) => x.cmp(y)` dava **`unknown-member` no `cmp`** — o compilador **acusava o usuário** de membro inexistente quando a verdade era *"não lemos o teu bound"*.

⟹ **O item 7 sobrevive à queda da sua razão, mas fica sem razão escrita.** A decisão *"adiar"* continua vigente por este ADR; a **re-ratificação com razão nova** é do dono (§3, entrada 5). Nada aqui reabre associated types.

**Precedente de forma:** o **ADR-0013 supersede PARCIALMENTE o ADR-0004** — revoga só a *regra de ouro* `UnknownType → dynamic` e **reafirma** o resto. Este ADR imita: cirurgia numa cláusula, o resto intacto, **e o ADR-0012 não é editado** (README: *"quando uma decisão muda, **não se edita** o ADR antigo"*).

### 3. Fila de ratificação — **o que o dono precisa confirmar**

Apurado por varredura de `ita-next/compiler/lib/` contra **todos** os artefatos. **Nenhuma destas entradas foi inventada, e nenhuma foi editada no código** — as frases estão lá, como estão, à espera do dono. Onde a auditoria **não achou** artefato, está escrito *não achei* — resultado válido.

| # | Frase, como está no código | Onde | Situação |
| :-: | :-- | :-- | :-- |
| 1 | *"se tiver divergência ou indecisão, a maneira que o Swift trabalha é a diretriz"* | `check.dart:1254`, `collect.dart:450`, `type.dart:285` | **Ruling REAL do dono** (o `type.dart` o identifica como tal) — **sem artefato**: grep em `specs/`, `.specify/`, `docs/` = **zero**. Só existe como data no código. |
| 2 | *"`init` no CORPO **mata** o memberwise; em `extension` o **PRESERVA**"* | `type_table.dart:243`, `collect.dart:393`, `check.dart:997`, `collect.dart` (`_initOf`) | **Aplicação** da entrada 1. O **ADR-0012 §A-1 nomeia `extension`** entre os corpos que admitem `InitDecl` — **autoriza o `init` lá, mas não diz o que ele faz ao memberwise**. A metade "extension preserva" **não tem artefato**. |
| 3 | *"**o papel vem do KIND, não da posição**"* (e o *"ruling (b)"* de que `collect.dart:238` se diz corolário) | `collect.dart:165`, `type_table.dart:253` | ✅ **ASSENTADO** em [[ADR-0015]] §B (2026-07-15). Sai da fila. |
| 4 | *"**Trait é FOLHA** … nenhuma aresta sai de um trait"* | `collect.dart:198` | ✅ **ASSENTADO** em [[ADR-0015]] §A (2026-07-15). Sai da fila. |
| 5 | ADR-0012 item 7 — razão *"bounds inline cobrem a maioria dos casos"* | §2 acima | **Razão falsa** (verificada). O *adiar* fica; a razão precisa ser **re-ratificada** ou substituída. |
| 6 | *"**ordem obrigatória, defaults saltáveis**"* (label **confirma**, não **reordena**; Swift × Dart) | `check.dart:1254` | Aplicação da entrada 1 — **regra de superfície da linguagem** (ordem de argumentos no call-site), decidida por meta-diretriz sem artefato próprio. |
| 7 | *"`init` **NÃO se herda**"* | `collect.dart` (`_initOf`) | Aplicação da entrada 1. **Não achei artefato** que o crave. |

**Resolvida sem ratificação — fica registrada porque a atribuição era falsa:** o teto `$0..$255` do closure-shorthand (`lexer.dart:34`) dizia *"ruling do dono, 2026-07-14"*. **O teto tem artefato** — `grammar.ebnf` §1 o crava com rationale de **engenharia** (*"um índice sem teto seria OOM (`{ $3000000 }` → 3M params). 255 = teto clássico de params"*), ecoado em `docs/spec/desugar.md`. **O que não tem artefato é o dono ter decidido isto.** A regra vale (artefato formal, ADR-0010); a atribuição foi corrigida para citar o `grammar.ebnf`. ⚠️ **Inconsistência de registro a reconciliar:** a **spec 003 §2.1 define `CLOSURE_PARAM` SEM teto** (`"$" [0-9]+`) — spec e `grammar.ebnf` divergem.

## Consequências

- **Custo real, e é o ponto:** implementar ruling de conversa passa a custar **um commit no registro antes** do commit no código (Art. IV-6c). É deliberado — foi a ausência desse custo que produziu as fabricações.
- **As 7 entradas do §3 ficam no código como estão, atribuídas ao dono, até ele decidir.** Não foram apagadas nem reescritas: apagar decisão real do dono porque *nós* não a registrámos seria trocar um erro por outro. Elas ficam **marcadas** (`collect.dart` `_initOf` traz ⟨Swift⟩ nos bullets sem artefato) e roteadas para cá.
- **A auditoria não move nenhuma linha executável.** Só comentários e este arquivo. Baseline preservada: **695 testes verdes, `dart analyze` limpo**.
- **O `type.dart:270-290` fica intocado.** É a confissão das fabricações e **cita o texto fabricado *verbatim* para o denunciar** — reescrevê-lo destruiria a prova. É o registro de que a doença reincidiu **dentro do comentário que a denunciava**.
- **Se o dono recusar o Art. IV-6**, o resultado ainda é positivo: a fila do §3 fica como inventário do que a conversa decidiu e o registro não guardou — e o §2 (razão falsa do item 7) vale por si.
- **Um arquivo, três atos — e isso tensiona o README** (*"uma decisão por arquivo"*). O precedente é o **ADR-0012**, que empacotou 9 rulings de uma sessão. Aqui o §1 é a decisão, o §2 é a sua **primeira aplicação** (uma razão que só cai porque foi conferida contra o código) e o §3 é o seu **inventário**. Separá-los daria três arquivos que só se leem juntos. **Fica registrado como escolha, não como descuido.**

## Relacionados

- **Forma do supersede parcial:** [ADR-0013](ADR-0013-inferencia-falha-e-erro.md) → [ADR-0004](ADR-0004-fase-semantica-side-table.md).
- **Alvo do supersede parcial:** [ADR-0012](ADR-0012-rulings-superficie-fase2.md) item 7 (§B). **Não editado.**
- **Artefatos que a auditoria confirmou e o código agora cita:** ADR-0012 §A-1/§A-3/§A-4/§C-9; spec 009 §0.5-6, §4.6, §4.9, §12-1, §12-7; spec 010 §2.2 (ruling 4); spec 011 §3.3, §12-1/2/3/4; spec 008 §0.5-3; spec 005 §10; spec 003 `design-notes.md` D3; `Const. Art. IV-5`; `grammar.ebnf` §1; `ast.asdl` (rodapé, RD-1).
- **Confissão preservada:** `ita-next/compiler/lib/frontend/semantic/type.dart:270-290`.
- **Commit que motivou o §2:** `b72310d` — *"fix(semantic): consolidação da F5 — ruling fabricado, diamante mudo, bound decorativo"*.
