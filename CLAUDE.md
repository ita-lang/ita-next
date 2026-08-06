# CLAUDE.md — `ita-next`

Complementa o `CLAUDE.md` do workspace `ita-lang/` (identidade da linguagem, os 11 princípios).
Este arquivo é **operacional**: as regras abaixo saíram da auditoria de 2026-07-29, em que quatro
revisões independentes acharam **8 bugs vivos** no emitter e um placar de CAs inflado, num
período em que **30 de 30 runs de CI ficaram verdes**.

> Todas as catorze regras existem porque foram **violadas**, não por precaução. Cada uma traz o
> sinal que a detecta antes do commit.

**Onde cada uma mora.** Ficam aqui as seis que governam o que se **declara** — prosa, catraca,
placar, portão. Elas valem ao escrever um ADR, um comentário ou uma mensagem de commit, e nada
disso casa um path. As oito **técnicas** foram para `.claude/rules/`, escopadas por `paths:` ao
código que governam:

| arquivo | regras | carrega ao tocar |
|---|---|---|
| `.claude/rules/f7-traduz.md` | R1 · R4 · R11 | `codegen/**`, `compiler/lib/**` |
| `.claude/rules/emissao-estrutura.md` | R2 · R3 | `codegen/**` |
| `.claude/rules/gates-e-passes.md` | R5 · R12 · R13 | `codegen/**`, `compiler/lib/**`, `tools/**` |

⚠️ Regra com `paths:` **não é re-injetada depois de `/compact`** — ela só volta quando um arquivo
que casa o padrão é lido de novo. Sessão compactada + mexer no emitter ⟹ reabrir o arquivo antes
de decidir. É o mesmo defeito que a última seção deste arquivo descreve: doutrina lembrada de
memória em vez de relida.

---

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
**não é catraca** — não fica vermelho quando a fatia nasce. A R11
(`.claude/rules/f7-traduz.md`) acrescenta o caso em que a violação não é uma frase, e sim uma
OMISSÃO.

`EXPECT-ICE` deve **recusar** ICE que nomeie estado do emissor (`unemitted`, `unbound`,
`untyped`) — fixture nunca pode *esperar* um defeito nosso. Só nome de construção
(`fn-generic`) é fronteira legítima.

**Baseline (2026-07-29): 151 `_ice(` · 152 códigos · 8 catracas.** O denominador honesto
não é 152: os ~88 códigos que nomeiam estado do emissor (`-untyped`, `-unemitted`,
`-unbound`, `-slot-arity`) a régua acima **proíbe** de ter catraca. Contra os ~63 que nomeiam
construção, 8 catracas são **13%** — e o número anterior (127 · 2 · 1,6%) media contra o
total, o que fazia a dívida parecer pior e a régua, inalcançável. Só pode **subir**; o bloco
∀ (6 fixtures `ice_generic_*.tu`) foi o primeiro pagamento.

Nem toda fronteira aceita catraca hoje, e a diferença é **ordem, não impossibilidade**
(R10): `type-generic` e `type-fn-generic` são inalcançáveis porque a declaração genérica dá
ICE antes de qualquer uso do tipo, e a gramática não tem anotação `<T>(T) -> T`. Ambas
viram alcançáveis quando ∀ nascer, e a catraca nasce **nessa** fatia. Declarar isso no sítio
é obrigatório — um ICE sem catraca e sem razão escrita é indistinguível de um esquecido.

`make assertions` cobra o outro lado: dois sítios com o **mesmo código** de ICE são uma
fronteira só para a catraca (R13, `.claude/rules/gates-e-passes.md`). Um fixture cobriria um
deles e o outro ficaria mudo.

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

A âncora certa é a que **crava**, não a mais próxima. Caso de 2026-08-06, em `compile.dart`: o
`libraryFilter` que mantém o `.dill` mínimo era atribuído à `§7.1` em cinco sítios — e a §7.1 só
especifica *"serialização via `BinaryPrinter`; formato 130"*. Quem sustenta a decisão é a §8.1
(*"casado com o `vm_platform.dill` do pin"*), e o filtro em si é **derivação nossa**, sem texto
normativo. Exigir o verbatim é o que separa as duas coisas.

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

## R14 — O harness prova que sabe ficar VERMELHO

Antes de qualquer asserção, cada suíte roda `Harness.selfTest()`: `check(false)`
conta, `check(true)` não conta. Sem isso, neutralizar `if (!cond) _fails++`
deixava `make codegen-test` **inteiramente verde** — a falha que apaga todas as
outras, porque com ela os 12 invariantes, o golden-runner, o ledger e o gate de
citações viram decoração ao mesmo tempo.

**`make gate` é o portão**, e ele tem **duas** camadas, cada uma nativa do seu lado — porque
nenhuma cobre o caso da outra:

| camada | mecanismo | cobre | furo |
|---|---|---|---|
| `tools/git-hooks/pre-commit` | `core.hooksPath` (git) | `git commit` de qualquer cliente, com ou sem sessão aberta | `core.hooksPath` é config **local**: não vem no clone |
| `.claude/hooks/gate-armed-hook.sh` | `hooks.PreToolUse` (Claude Code) | clone onde `make setup-hooks` nunca rodou; recusa `--no-verify` | só existe dentro de uma sessão |

A duplicidade é **limitação do git**, não resíduo: não há como versionar o hook path junto com o
repo. `make setup-hooks` arma a primeira; `make gate-hook-selftest` (pendurado no `make gate`)
mata o mutante que desarmaria a segunda.

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
