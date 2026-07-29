# CLAUDE.md — `ita-next`

Complementa o `CLAUDE.md` do workspace `ita-lang/` (identidade da linguagem, os 11 princípios).
Este arquivo é **operacional**: as regras abaixo saíram da auditoria de 2026-07-29, em que quatro
revisões independentes acharam **8 bugs vivos** no emitter e um placar de CAs inflado, num
período em que **30 de 30 runs de CI ficaram verdes**.

> Todas as onze regras existem porque foram **violadas**, não por precaução. Cada uma traz o
> sinal que a detecta antes do commit.

---

## R1 — A F7 não decide nada. Ela traduz.

Toda decisão em `codegen/lib/emit.dart` tem de ser rastreável a uma **side-table da F5**
(nº1 `exprTypes`, nº3 `resolvedMembers`, nº5 `resolvedCalls`, …) ou à **identidade da decl**
(`Map.identity`). Qualquer outra origem é **redecisão com chave mais fraca**.

❌ **Proibido:** comparar com string vinda do texto-fonte do usuário — `p.variant == 'none'`,
`name == p.typeName`, `type.classNode.name == 'int'`. Grafia não é injetiva: `enum Estado
{ none, ativo }` e `Option.none` têm o mesmo lexema e famílias diferentes.
✅ **Exceção única:** nomes de plataforma (`dart:core`, `num::+`) — vocabulário fechado e externo
ao programa do usuário —, confinados aos `_resolve*`.

```bash
# sinal — hoje volta 6 hits em emit.dart
rg -n "\.(variant|typeName|label)\s*==\s*'" codegen/lib/
```

Um hit só é legítimo quando o **tipo guarda antes** e o lexema apenas refina — o molde é
`emit.dart:1357` (`s.variant == 'none' && check.exprTypes[s] is OptionalType`). Os outros cinco
(`:2176`, `:2177`, `:2436`, `:2439`, `:2523`) decidem **sem olhar `subjectType`**, e são os bugs
2, 3 e 4.

## R2 — Shell antes de membro, para TODO o grafo de tipos

Toda entidade nomeada que outra possa mencionar nasce em duas fases: **shell registrado na
tabela** → membros. Vale para `struct`/`enum`/`class`/`trait`, não só para `fn` — o grafo de
declarações de módulo é **cíclico por construção** (`struct No { prox: No? }` não tem ordem
topológica), e a F4 já provou que *"ordem textual não importa"*.

**Sinal:** compilar cada fixture **duas vezes**, com `program.body` revertido na segunda.
Stdout idêntico, zero ICE. Um `ice-*-unemitted-*` sobre programa legal é **bug nosso**, não fronteira.

## R3 — `_expr` nunca roda duas vezes sobre o mesmo nó

Toda subexpressão-fonte que apareça mais de uma vez na árvore emitida tem de aparecer como
**leitura de um temporário**. `checkNoSharedNodes` (um nó, um pai) e "avaliar uma vez" puxam em
sentidos opostos; **o temporário é a única construção que satisfaz os dois** — re-emitir a
subárvore satisfaz o invariante e **cria** dupla execução.

Atinge: `obj.f op= v`, `a[i] op= v`, `??=`, `++`, e sobretudo o **copy-with `p.{x:1}`**, que
leria o receptor uma vez **por campo não-mencionado**.

**Sinal:** assert de fase — contador `Map.identity<ast.Expr,int>` na entrada de `_expr`; segunda
chamada sobre o mesmo nó falha. Fixtures de valor-L usam receptor **com efeito**
(`fn f() -> Caixa { print("[efeito]"); … }`) — golden de valor puro não percebe.

## R4 — O tipo do nó emitido é IGUAL ao que a F5 provou

Nunca supertipo, nunca subtipo. `Int + Int` com `functionType` de `num::+` grava `num` no `.dill`
— passa no verify, roda igual no JIT, e **custa unboxing em AOT** (a TFA só concede `kInt` para
subtipo de `int`). `checkNoDynamic` é o caso degenerado desta regra.

Exceções só por ADR, em lista fechada. `pkg/kernel` já resolve:
`TypeEnvironment.getTypeOfSpecialCasedBinaryOperator`.

## R5 — Gate estrutural é visitor que FALHA no desconhecido

Nunca lista-branca de sítios. `RecursiveVisitor.defaultNode` **desce e cala** ⟹ nó novo é
aprovado em silêncio, e o conjunto de nós vem de um pacote **externo e versionado**. Um gate cuja
falha-padrão é "OK" é documentação executável do que alguém lembrou.

Use `VisitorThrowingMixin` (`pkg/kernel/lib/visitor.dart:1868`) ou `implements Visitor<void>`.
**Todo gate novo nasce com um RED que ele efetivamente pega.**

⚠️ `verifyComponent` é *well-formedness*, **não** type-checking (`verifier.dart:127-129`, verbatim).
Não detecta `dynamic` indevido, tipo estático errado, nem `interfaceTarget` de classe errada.
Não o cite como evidência de correção. E o invariante da F7 **não roda no `itac build`** —
`compile.dart` não importa `invariants.dart`.

## R6 — A emissão não estreita a linguagem

Se o codegen não emite o que `grammar.ebnf` + a spec permitem, há três saídas, nesta ordem:
**implementar** → **erro nomeado da fase dona** (`*-unsupported`, `build-error:`) → **ICE com
catraca**. Nunca uma quarta: reescrever a regra da linguagem na prosa para o limite parecer design.

Hierarquia do dono: *lacuna declarada > silêncio > restrição secreta*. Um `_ice` sobre programa
legal **mente sobre a causa** — diz "erro interno" quando a verdade é "esta fatia não existe".

```bash
# sinal: diff que adiciona um _ice E um parágrafo que justifica por que a linguagem é assim
git diff | rg -n "não é preguiça|a conversão exige|por construção não|a única forma|não há como"
```

## R7 — Nenhuma restrição sai do commit sem catraca

`_ice` novo ⟹ fixture `// EXPECT-ICE:` no mesmo commit. Comentário no `.dart` ou no `.tu`
**não é catraca** — não fica vermelho quando a fatia nasce. Hoje: **127 `_ice(` contra 2
catracas (1,6%)**. R11 acrescenta o caso em que a violação não é uma frase, e sim uma OMISSÃO.

`EXPECT-ICE` deve **recusar** ICE que nomeie estado do emissor (`unemitted`, `unbound`,
`untyped`) — fixture nunca pode *esperar* um defeito nosso. Só nome de construção
(`fn-generic`) é fronteira legítima.

## R8 — Citação que sustenta um "nunca/sempre" vem com verbatim

Âncora que **resolve** não é âncora que **apoia**. O caso real: `ADR-0012 §A-1` existe, a regra
é verdadeira, e **quem a crava é o ADR-0016 §D** — a âncora foi pescada por saliência e a
modalidade escalou de condicional para universal. Um grep de âncoras passa; o verbatim não.

- `§12-N` **sempre nomeia a spec** (Art. IV-6d, constituição 1.1.0) — `spec 009 §12-1`, nunca `§12-1` nu.
- `ruling do dono` + data **sem artefato** = `ruling-sem-artefato` (Art. IV-6a).
- Ruling de conversa **assenta-se no registro ANTES** de virar código (Art. IV-6c).

```bash
rg -n "§12-[0-9]" codegen/ compiler/lib/ | rg -v "spec [0-9]{3} §12-|ADR-[0-9]{4}"
rg -n "ruling do dono|decisão do dono" codegen/ compiler/lib/ conformance/
```

Ambos têm legado (o primeiro volta ~8 hits hoje). Tratar como **catraca com baseline**: o número
só pode **descer**. O que não pode é um `§N` novo entrar sem nome de spec.

## R9 — Um CA só é verde quando o texto INTEIRO foi verificado, no alvo que ele exige

Meia verificação com tick verde é mentira por omissão. Cláusulas separadas por `;`/`+` são
cláusulas separadas, cada uma com fixture nomeado. O alvo escrito no item ("3 alvos", "VM + JS")
tem de ter **rodado** — não basta JIT.

O placar deve ser **derivado** (um ledger CA → texto/alvos/fixtures + teste que falha), nunca
uma tabela markdown editada pelo mesmo commit que ela avalia.

## R10 — Impossibilidade é hipótese, não achado

Toda frase que **encerra uma investigação** — *"não é possível"*, *"não é testável"*,
*"exigiria X"*, *"não chega aqui"*, *"a F<n> já reprovou"*, *"só apareceria em runtime"* —
só entra no repo com o complemento escrito: **"não é possível SEM mexer em ___"**. Se o
branco se preenche com código NOSSO, não é limite: é fatia, e fatia tem nome, dono e catraca.

Esta é a mais perigosa das três formas de transferir sujeito, porque **parece honestidade
e funciona como desistência** — veste o dialeto da R6 (*lacuna declarada > silêncio*) e
passa em revisão como rigor. As outras duas são contestáveis com evidência do mesmo tipo
que as sustenta; esta tem por conteúdo *"aqui não há evidência a colher"*.

| forma | soa como | esconde |
|---|---|---|
| argumento-de-ausência (*"a linguagem não tem como"*) | conhecimento | não fiz o grep |
| restrição-para-caber (R6) | design | não implementei a fatia |
| **impossibilidade declarada** | **honestidade** | não achei o ângulo |

**A diferença é medível:** a lacuna legítima nomeia o **trabalho** que a fecha e **custa**
alguma coisa (parcial no ledger, recorte no nome do job, fixture vermelho). A desistência
nomeia a **dificuldade** e não custa nada — só encerra.

Em 2026-07-29 isto aconteceu três vezes numa sessão. As três alavancas que resolveram:
**injetar a dependência** (`checkOrderIndependence(body, emit)`), **construir o defeituoso
à mão** (RED sintético), **consertar a outra metade** (`_checkPatternTypeName`). Se nenhuma
serve, diga qual você tentou.

```bash
# no DIFF, não no repo — a frase nova é que importa
git diff | rg -n "não é possível|não dá para|não há como|não é testável|exigiria|só apareceria|não chega aqui"
```

## R11 — Garantia de outra fase se cita com verbatim, ou não se cita

*"A F5 já cobrou X"* é afirmação sobre **outro arquivo** — que nem o autor nem o revisor
abrem. Toda garantia citada precisa do sítio (`arquivo:linha`) que a implementa, colado.

O custo de não fazer isso foi medido: `emit.dart` justificava resolver campos por NOME
dizendo *"a F5 já cobrou `pattern-type-mismatch`"* — a F5 **nunca lia `typeName`**. E
`type_table.dart` afirmava *"totalidade é invariante: todo nó de expressão tem entrada"* —
a F5 não descia em `InitDecl.body`, `OperatorDecl.body` nem no operando de `panic`, e a F7
**emite** o corpo do `init`. `Map[k]` devolve `null` igual para "ausente" e "nunca
visitado", o emitter absorvia, e `init(a: Float, b: Float) { self.r = a / b }` emitia `~/`
sobre doubles: **segfault da Dart VM**, em programa legal, sem uma linha de diagnóstico em
fase nenhuma.

A rede que sobrou disso, e que vale para a próxima região esquecida: **pré-condição na
porta do consumidor**. `_expr` começa com `if (!check.exprTypes.containsKey(e))
_ice('untyped-<T>')`. Converte "artefato errado em silêncio" em lacuna declarada — e foi
ela que achou o `panic` depois de o `init` estar curado.

```bash
rg -n "a F[0-9] (já|garante|acusa|reprova)|já (cobrou|reprovou|validou|barrou)|não chega aqui" codegen/lib/ compiler/lib/
```

---

## Antes de declarar uma fatia fechada

1. **Passada adversarial com contexto limpo** — subagente instruído a *procurar o que quebra*,
   não a confirmar o que funciona, e a escrever ≥ 1 caso que você **não escolheria**. É o único
   mecanismo desta fase com captura comprovada: duas rodadas acharam 3 bugs 🔴 em ~20 min.
2. **Testes metamórficos**, não só goldens — os 8 bugs são **relações entre programas**:
   renomear identificadores do usuário para lexemas privilegiados (`none`, `ok`, `int`) ·
   permutar/reverter declarações · inserir função morta que usa `Result` · trocar receptor puro
   por efeituoso. Em todos: **stdout idêntico**.
3. **Ordem de implementação segue dependência de invariante**, não payoff visível: construção que
   introduz **estrutura de ligação** (função/closure) precede toda construção que aninha dentro
   dela. `while` antes de closures deixou `_loops` sem fronteira de função e um
   `_LocalFunctionIdAssigner` com 0% de cobertura real.
4. **Nenhum passe de saneamento fica verde sem ao menos um fixture que ele efetivamente altere.**

## Como escrever a justificativa

**Derivar do artefato → decidir → implementar.** Se o parágrafo nasceu depois do código, ele é
advocacia do diff: escala modalidade ("nunca"), pesca a âncora mais próxima e chama limite de
ferramenta de design. Pergunta antes do commit: *"eu reabri o arquivo citado nesta sessão, ou
pesquei a âncora da memória?"* Se foi da memória — cola a frase, ou não cita.

Memórias e doutrinas de agente são **observações datadas**, não fatos vivos. Reverifique contra o
código antes de usar como premissa: a alucinação *"`verifyComponent` não tem chamador"* (há 5)
viveu 9 dias numa memória e vazou para 3 sítios de código.
