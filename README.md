# ita-next

**A reescrita do compilador [Itá](https://github.com/ita-lang/ita) — do zero, fase a fase, pela sequência do Dragon Book.**

O Itá (*pedra*, em Tupi) é uma linguagem fortemente tipada, imutável por default, funcional-first, que compila para **Dart Kernel** (`.dill`) e roda na Dart VM. Este repositório não é uma versão nova do compilador: é **outro compilador**, construído com o antigo ao lado, vivo, servindo de referência.

---

## Por que existem dois repositórios

| | [`ita-lang/ita`](https://github.com/ita-lang/ita) | `ita-lang/ita-next` |
| :-- | :-- | :-- |
| **O que é** | a **PoC**, e ela funciona | a reescrita |
| **O que provou** | o pipeline inteiro: `.tu → tokens → AST → .dill → VM` (M0–M4) | — |
| **Papel hoje** | **oracle** — a referência contra a qual cada fase nova é validada | o compilador que fica |
| **Estado** | congelado como referência | em construção |

O `ita/` **não é legado a ser substituído no lugar**. Ele é o **oracle**: cada fase nova do `ita-next` tem de reproduzir os goldens e a paridade que o `ita/` já passa. Um oracle precisa estar **vivo e rodando** para se poder comparar com ele — é por isso que são dois repositórios e não dois branches. Apagá-lo ou reescrevê-lo por cima destruiria a única referência executável que o projeto tem.

## Por que do zero, e não refatoração

Duas razões, e as duas estão escritas e datadas no registro deste repo.

### 1. A estrutura de fases estava incompleta — e tinha um erro conceitual

[**ADR-0011**](.specify/memory/adr/ADR-0011-faseamento-horizontal-front-end.md) (2026-07-10). O plano da reescrita começava por um *tradutor em miniatura* — um slice vertical fino tocando todas as fases, para **provar o pipeline**. Foi descartado por uma razão simples:

> *"o **`ita/` já é essa prova**. Re-provar o pipeline é retrabalho. […] o valor da reescrita é **completude e organização**, não re-validação."*

E o levantamento nos dois livros (Dragon Book + *Crafting Interpreters*) achou o erro: o núcleo que o projeto seguia — *"léxico → sintaxe → SDD → semântica → codegen"* — tratava **SDD como uma fase**. Não é: *Syntax-Directed Translation* é a **técnica** usada **dentro** das fases. Faltavam **cinco fases** que os livros recomendam.

Não dá para refatorar um pipeline até ele ganhar fases que ele nunca teve. A abordagem é **horizontal**: cada fase feita inteira, documentada, com os artefatos formais do livro, e validada pelo output dela mesma (`itac tokenize`, `itac parse --dump`, `itac check --dump-types`).

### 2. A fase semântica do oracle é estruturalmente incapaz de errar

[**ADR-0013**](.specify/memory/adr/ADR-0013-inferencia-falha-e-erro.md) (2026-07-15). O `ita/` nasceu sem fase semântica — o codegen gerava Kernel direto da AST, e *"fortemente tipada era decorativa"*. Uma fase foi acrescentada depois ([ADR-0004](.specify/memory/adr/ADR-0004-fase-semantica-side-table.md)) com um compromisso de bootstrap explícito: a **regra de ouro** `UnknownType → dynamic`, *"onde a inferência não é confiável"*.

Foi **a decisão certa para aquele momento**: prioridade em não rejeitar programa válido, num compilador que ainda não sabia inferir. Mas o resultado, medido:

> A semântica do `ita/` tem **1355 linhas e checa 4 regras**. A causa é estrutural — o `UnknownType` é **curinga nos dois sentidos**, então o checker **nunca erra** onde a inferência não alcança. Não checa aridade, tipo de argumento, `return` vs `-> T`, membro inexistente, nem condição de `if`.

Isso é a família **"compila mas roda errado"** de volta, pela porta que a regra de ouro abriu. E não é uma lista de bugs a consertar: o curinga está na **fundação do modelo de tipos**. No `ita-next` a distinção que faltava é a primeira coisa que existe — `TypeVar` ("ainda não sei", e **deve** sumir até o fim) **≠** `ErrorType` (absorvente, pós-erro-já-reportado). Falha de inferência é **erro**, com span e hint. `dynamic` não é tipo de superfície.

## O corte: o que implementamos e o que a VM dá de graça

[**ADR-0007**](.specify/memory/adr/ADR-0007-roadmap-dragon-book.md). Como a Dart VM é o backend **permanente** ([ADR-0001](.specify/memory/adr/ADR-0001-dart-vm-backend-permanente.md)), boa parte do Dragon Book descreve trabalho que o Itá **herda** em vez de construir:

- **Grupo A — o Itá implementa (caps 2–6):** léxico, sintaxe, semântica, IR e codegen para Kernel. A fronteira é a emissão de código intermediário.
- **Grupo B — a Dart VM entrega (caps 7–12):** runtime, GC, otimização, código de máquina, alocação de registradores.

Disso vem o P0 do projeto: sem LLVM, **gerar Kernel tipado é a única alavanca de performance** — e é o mesmo trabalho que conserta os bugs "compila mas roda errado". Cada `dynamic` emitido é, literalmente, não fazer o trabalho que justifica a fase.

> A razão de recusar `dynamic` na superfície é o **princípio 4 — sem mágica**, não o custo no backend. Se um backend futuro baratear o dinamismo, o custo evapora e o princípio não evapora junto.

## Estado

**Fases 1–6 do front-end completas.** 852 testes verdes, analyzer limpo. *(Fase 6 — exaustividade de `match` (Maranget) — concluída em 2026-07-19.)*

| # | Fase | Entrega | CLI |
| :-: | :-- | :-- | :-- |
| 1 | **Léxico** | scanner à mão, maximal munch, erros não-abortantes | `itac tokenize` |
| 2 | **Sintaxe → AST** | descendente-recursivo, cascata de 13 níveis, span byte-preciso, recuperação de erro | `itac parse --dump` |
| 3 | **Desugaring** | AST canônica — reescreve `??`, `?.`, `\|>`, `>>`, `where`, `if let`, `$0..$n` | `itac desugar` |
| 4 | **Binding** | resolução de nomes, side-table por identidade (modelo rustc) | `itac resolve` |
| 5 | **Semântica / Tipos** | bidirecional (não HM), `T?` nativo, zero coerção, inferência que falha é erro | `itac check --dump-types` |
| 6 | **Análises de fluxo** | ✅ definite-return, `unreachable-code`, `guard-must-exit` · ✅ **exaustividade + redundância de `match`** (Maranget §3.1/§3.2 + rustc slice/interval): selados, `Int`/range, produto, `List`, `String` | `itac flow` |
| 7 | Codegen → Kernel | `.dill` — não iniciado (`codegen/` vazio; gates em spec 013 §0.6) | — |

```bash
make test                          # o gate único: conformância + unit
dart run bin/itac.dart check f.tu  # a Fase 5
```

## Como este repositório decide

O `ita-next` carrega o próprio registro de decisões, e ele é a coisa mais incomum aqui:

- [**`.specify/memory/constitution.md`**](.specify/memory/constitution.md) — os princípios permanentes da linguagem. Art. I não se emenda sem processo.
- [**`.specify/memory/adr/`**](.specify/memory/adr/) — 14 ADRs datados e **imutáveis**. Quando uma decisão muda, não se edita o ADR: cria-se um novo que a `supersedes`.
- [**`specs/`**](specs/) — 11 specs, uma por fase, com critérios de aceitação.

Duas regras que valem a pena roubar:

**Data não é fonte.** Um comentário que diz *"ruling do dono, 2026-07-15"* é inauditável — o próximo leitor não tem como conferir. Um que diz *"ADR-0012 §A-1"* é um `grep`. Isto foi aprendido do jeito difícil: encontrámos comentários no código que **afirmavam rulings que nunca existiram**, escritos na voz do dono do projeto. Ver [ADR-0014](.specify/memory/adr/ADR-0014-procedencia-de-ruling-data-nao-e-fonte.md).

**Falsa acusação é pior que lacuna declarada.** Quando o compilador não implementa algo, o erro diz *"lacuna do COMPILADOR"* — nunca acusa o usuário de um erro que ele não cometeu. `fn f<T: Ord>(x: T) => x.cmp(y)` dava `unknown-member` no `cmp`; a verdade era *"não lemos o teu bound"*.

## Filosofia

1. **Imutável por padrão** — `let` é o default, `var` é explícito
2. **Valor vs referência explícito** — `struct` copia, `class` referencia
3. **Tudo é expressão** quando possível
4. **Sem mágica** — nunca esconde o que acontece
5. **Funcional é o caminho natural**, OO quando faz sentido
6. **Zero annotations** — `@decorators` não existem
7. **Zero try/catch** — `Result` + `?` + `panic`
8. **Zero code generation** — sem build_runner, sem annotation processors

O posicionamento é **Itá : Dart :: Elixir : Erlang** — uma linguagem própria sobre uma VM madura, sem ser a linguagem dela. Ver o [MANIFESTO](https://github.com/ita-lang/ita/blob/main/MANIFESTO.md).

---

Sintaxe do Itá em [`examples/`](examples/) · gramática formal em [`compiler/docs/spec/grammar.ebnf`](compiler/docs/spec/grammar.ebnf) · corpus de conformância em [`conformance/`](conformance/).
