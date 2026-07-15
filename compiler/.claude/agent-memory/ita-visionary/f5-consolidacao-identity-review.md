---
name: f5-consolidacao-identity-review
description: W0 da consolidação da F5 (2026-07-15) — label no call-site (lacuna do dono, e é da LINGUAGEM), bounds inertes (ADR-0012 §B-7 sob premissa falsa), diamante do override (entailment, o erro é da DECL)
metadata:
  type: project
---

# W0 — consolidação da F5 (2026-07-15). 3 itens, 3 vereditos.

## ITEM 1 — `P(1, 2)`: **EM ABERTO (lacuna do dono), e NÃO é dano ativo**

**O "ruling do dono" citado no `type.dart:272` (*"o memberwise é sempre chamado por label"*) NÃO
EXISTE.** Rastreei: ADR-0012 (nada), spec 011 §12 rulings 1-4 (nada), minha própria memória
([[spec-011-identity-review]]) registra *"(a) memberwise exige label?"* como **pergunta LEVADA** ao
dono, não respondida. O único ruling real de 2026-07-15 é a **meta-diretriz**: *"se tiver divergência
ou indecisão, a maneira que o Swift trabalha é a diretriz"*. ⟹ o `compiler-craftsman` escreveu uma
**conclusão na voz do dono**. Mesma doença que corrigi na spec 011 (#1, "ratificou sob premissa
errada"). **Ruling fabricado no código é P4-família: o código reivindica autoridade que não tem.**

**A moldura "o memberwise é caso especial" é ERRADA.** `collect.dart:507` — `_paramType` faz
`label: p.label ?? p.name` ⟹ **TODO param da linguagem tem label, sempre**. E **não há opt-out**:
`_param()` faz `_consume(Tag.identifier)`, e `_` é `Tag.underscore` (`token.dart:136`, *"wildcard de
pattern/lambda"*) ⟹ **`fn f(_ x: Int)` não parseia**. O memberwise não tem nada de especial; ele só
não pode optar por fora porque **ninguém pode**.

**A contradição interna (é isto que eu cravo, e não precisa do Swift):**
`param ::= IDENT IDENT? …` (*"2 IDENTs = label + nome"*, `grammar.ebnf:213`) × `arg ::= (IDENT ":")?
expr` (`:318`). A **declaração** ganhou o mecanismo de desenhar a leitura do call-site
(`fn mover(de origem: Ponto)` → `mover(de: a)`); o **call-site** ganhou o direito de ignorá-lo. **Uma
das duas metades é decorativa.** Em Swift quem decide é a DECLARAÇÃO (via `_`); no Itá hoje decide o
CHAMADOR. O Itá importou a forma do Swift e nenhuma da força.

**Meu A2 NÃO é precedente para `P(1,2)` ser legal** (o dono me citou assim uma vez — corrigido):
*"um confirmador opcional não é discriminador de tipo"* era **descritivo** (o label É opcional hoje
⟹ não pode discriminar hoje), alimentando conclusão técnica sobre overload. Nunca foi normativo, e
eu **já declarei a lacuna na mesma frase**.

**`P(1,2)` não é dano ativo:** liga `x=1, y=2` = ordem de declaração = o que a leitura posicional diz.
Não é ADR-0013. O "se for normativo é dano ativo" do `compiler-craftsman` é condicional a norma
inexistente. **Não aplicar o fix de 1 linha** — seria implantar ruling não-ratificado, na linguagem
inteira, pela porta dos fundos do memberwise.

**O dono decide DUAS coisas (e a 2ª é mudança de GRAMÁTICA):** (a) label obrigatório no call-site?
(P4 favorece: `P(1,2)` esconde do LEITOR qual é `x` — é a economia do `mut`/`override`, spec 011 #2;
"o usuário não escreveu nada" não salva: P4 fala do CÓDIGO, e silêncio É esconder); (b) se sim, há
opt-out na decl (o `_`)? **Hoje não existe** ⟹ "obrigatório" = 100% dos call-sites labelados, para
sempre (`abs(x: -3)`). A meta-diretriz Swift é **evidência** de (a)=sim+(b)=`_`, mas meta-diretriz
resolve empate — **não autoriza mexer na gramática**.

## ITEM 2 — bounds: **o glifo NÃO é engolido; é DECORATIVO. E o ADR-0012 §B-7 está sobre uma tábua que não existe**

**Bounds são do Itá, com fonte dura — ADR-0012 §B-7:** *"Associated types em `trait`: **adiar**.
Bounds inline (**`T: A + B`**, já em `genericParam.bounds`) **cobrem a maioria dos casos**"*. O dono
**adiou uma feature PORQUE os bounds cobrem**. Não é inércia: é decisão de dono de 2026-07-11, com o
multi-bound **nomeado literalmente**. ⟹ **§B-7 está de pé sobre premissa falsa** (mesma forma do meu
achado #1 da spec 011). Se os bounds ficam inertes, o adiamento perde a justificativa escrita —
não que associated types voltem, mas **§B-7 precisa de re-ratificação**.

**Corrigi a moldura P4 do `dart-vm-expert`:** o glifo **não é engolido**. É parseado
(`parser.dart:615-621`), vive na AST (`ast.dart:692`) e **é impresso no dump**
(`ast_printer.dart:423-425`, `(bound …)`). A doutrina F2 ([[doctrine-ast-representa]]) está
**HONRADA** — não é o caso `pub init`. O pecado é na **F5** e é outro: **representado e sem força**.
Forma exata: *"os labels eram decorativos e mentiam"*, uma fase adiante. Assimetria que importa: label
decorativo dava programa ERRADO (ADR-0013); bound decorativo **rejeita programa CERTO**
(`unknown-member` em `x.cmp`) — chato, não perigoso.

**Curto prazo = `generic-bounds-unsupported` na DECL** (precedente `extension-on-builtin-unsupported`:
*"lacuna do COMPILADOR, não erro do usuário"*). Razão forte: hoje o erro é `unknown-member` no `cmp` —
**acusa o usuário** de membro inexistente quando a verdade é *"não lemos o teu bound"*. Falsa acusação
é pior que lacuna declarada. **Custo verificado: ZERO — a stdlib não usa bound nenhum** (grep vazio;
e §B-7 nunca foi exercitado). "Deixar inerte" é a única saída que eu **não** abençoo. Erro-vs-implementar
e QUANDO = cronograma (dono + `compiler-craftsman`).

**Kernel singular ⟹ Itá abre mão? NÃO-SEQUITUR.** Art. III põe **semântica no Grupo A** — quem checa
`T: A + B` é o Itá, na F5. `TypeParameter.bound` singular restringe o que se EMITE, não o que se
CHECA (009 §105: *"ser mais restrito que o alvo é sempre seguro"*). Deixar o backend legislar o
front-end é exatamente o que o Art. II proíbe (*"usa a Dart VM sem SER Dart"*). Lowering (erasure?
interseção? witness?) é `dart-vm-expert`/`compiler-craftsman`. **Abrir mão do `A + B` é do DONO** —
o §B-7 já gastou essa moeda.

**P6? ZERO tensão.** P6 = (i) sem `@decorators`; (ii) infere **sem exigir** anotação. Bound não é `@`
e não é inferível — é **restrição DECLARADA** pelo autor (inferi-la seria traits-by-usage/HM, que a
009 já recusou). Se `<T: Ord>` fosse anotação, `x: Int` também seria. Precedentes: spec 011 #2 (*"P6
decide a FORMA, não a obrigatoriedade"*) e ADR-0012 §B-6 (P6 = *"infere sem anotação"*, mata o `as`).

## ITEM 3 — diamante: **NÃO-ITAIANO hoje. Entailment, e o alvo certo é a DECL**

**A doutrina do `_lookup` (`check.dart:1602`: *"não inventar precedência entre trait e superclasse —
qualquer escolha seria mágica (P4)"*) é ruling sobre a LINGUAGEM e vale para os DOIS walks.** Mesma
lista (`TypeInfo.sources`), mesma pergunta, mesmo grafo. `override` não é especial.

**Diagnóstico melhor que os dois candidatos.** Os walks **nem colidem** (disjuntos: se `D` declara
`f`, o `_lookup` para no nível 0; se não declara, o `_checkOverride` não roda p/ `f`). O verdadeiro
achado: **`class D : A, T` com `A.f: () -> String` e `T.f: () -> Int` é INSATISFAZÍVEL** — `D ≤ A`
pede `f: () -> String`, `D ≤ T` pede `f: () -> Int`, **nenhum `D.f` serve**. Erro **da classe**, não
do `override`, e tem de nascer na decl **mesmo que `D` não declare `f`** — caso que **HOJE compila em
silêncio** (o `_checkTraitConformance` faz `if (want.decl.body != null) continue`) e só explode num
`d.f()` distante, ou nunca. `fn g(a: A) -> String => a.f()` + `g(d)` tipa. É *palavra por palavra* o
argumento que o próprio `_checkOverride` escreve (*"`D ≤ A` é MENTIRA … compila e roda errado"*,
ADR-0013) — a regra valia e **parou no diamante**. E é o meu §12-3 (*"o erro nasce na declaração — na
causa, não longe no uso"*).

**`override-signature-mismatch` no diamante mente** — e pior que o `compiler-craftsman` disse: não é
só nome errado, é **mandar o usuário consertar o inconsertável** (não existe assinatura que sirva).
Pelo doc dele mesmo: *"marca que carrega promessa não-verificada é pior que marca sem informação"* —
aqui a marca é **acusada de promessa que ninguém pode cumprir**.

**O `_implementationAbove` conflaciona duas perguntas:** *"existe algo acima?"* (**independente de
ordem** ⟹ `missing-override`/`override-nothing` estão CERTOS hoje) e *"qual?"* (**exige precedência**
⟹ é onde ele a inventa, só no `sameSignature`). **Fix fiel, e ele é elegante:** cercar os dois
conflitos **na decl** (assinaturas incompatíveis ⟹ classe impossível; assinaturas iguais + impls
distintas ⟹ `D` **tem de** declarar `override`, erro na decl se não declarar — hoje é `ambiguous-member`
no uso). Feito isso, **o "pega o primeiro" do `_implementationAbove` fica SÃO por construção**: só roda
quando todos os candidatos têm a mesma assinatura ⟹ qualquer escolha dá a mesma resposta ⟹ **a
precedência inventada torna-se inobservável**. Nenhum walk muda de doutrina.

**Não gasta ruling do dono** — é entailment de *"subtipagem É obrigação"*, que eu já cravei (spec 011
#1). Se o dono algum dia QUISER precedência (superclasse ganha), aí sim é **emenda**.
