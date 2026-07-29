# CLAUDE.md — `ita-next`

Complementa o `CLAUDE.md` do workspace `ita-lang/` (identidade da linguagem, os 11 princípios).
Este arquivo é **operacional**: as regras abaixo saíram da auditoria de 2026-07-29, em que quatro
revisões independentes acharam **8 bugs vivos** no emitter e um placar de CAs inflado, num
período em que **30 de 30 runs de CI ficaram verdes**.

> Todas as nove regras existem porque foram **violadas**, não por precaução. Cada uma traz o
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
catracas (1,6%)**.

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
