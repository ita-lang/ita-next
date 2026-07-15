# Constituição do Itá

> **Fonte única de veto do projeto Itá.** Toda spec (`/speckit-specify`) faz um *Constitution check*
> contra este documento (§0 do template). Conflito com um princípio permanente **bloqueia** a spec até
> ser resolvido — ou a spec se ajusta, ou o dono decide emendar a constituição (ver Governança).
>
> Consolidado de: `CLAUDE.md` (raiz + `ita/`), `references/livro-compiladores/ROADMAP.md`, e as regras
> operacionais registradas na memória do projeto. Quando houver conflito, **esta constituição referencia,
> não substitui** as fontes normativas de cada repo (ex.: `GRAMMAR.md` para sintaxe).

**Ratificada:** 2026-07-10 · **Versão:** 1.0.0

---

## Artigo I — Princípios permanentes da linguagem

São os invariantes de design do Itá. **Imutáveis** salvo decisão explícita do dono (Governança).

1. **Imutável por padrão** — `let`/`var`; mutação é explícita e localizada.
2. **Valor vs. Referência explícito** — `struct` (valor) vs. `class` (referência); nunca ambíguo.
3. **Tudo é expressão** quando possível.
4. **Sem mágica** — o código nunca esconde o que acontece.
5. **Funcional é o caminho natural**, OO quando faz sentido.
6. **Zero annotations** — `@decorators` **nunca** serão implementados. O type-checker infere **sem exigir** anotação.
7. **Zero try/catch** — tratamento de erro por `Result` + `?` + `panic`.
8. **Zero node_modules** — dependências via TOML + cache central (`~/.ita/packages/`).
9. **Zero Python** como dependência de build ou runtime.
10. **OpenSSL apenas para crypto** — nenhuma outra dependência nativa difusa.
11. **Zero code generation em build-time** — sem `build_runner`, sem annotation processors. Geração de
    código, se necessária, é feita pelo dev via scripts próprios, fora do build.

> **Regra para specs:** nenhuma fase (léxico → codegen) pode violar estes princípios. Em especial, a
> fase de semântica (type-checker) infere sem anotações (P6); a independência do Dart (Artigo III) não pode
> introduzir codegen em build-time (P11).

## Artigo II — Posicionamento: Itá : Dart :: Elixir : Erlang

- **Itá está para o Dart como o Elixir está para o Erlang** — duas linguagens sobre a mesma VM, com
  princípios e ergonomia **próprios**. O Itá **usa** a Dart VM sem **ser** Dart e sem depender do **Flutter**.
- **Backend permanente = Dart VM.** O Itá compila para **Dart Kernel (`.dill`)**. **LLVM foi abandonado
  (2026-07-04)** — um backend nativo próprio contraria o objetivo nº1 (build/pipeline rápidos).
- **Três alvos de graça** pela toolchain Dart, a partir do mesmo `.dill`: **JIT** (dev/REPL), **AOT nativo**
  (`dart compile exe`), **JavaScript** (`dart2js`). Toda mudança de codegen declara seu comportamento nos
  três (spec §7.3).
- **Norte transversal — independência do Dart:** minimizar código Dart no ecossistema Itá rumo a "só código
  Itá" (stdlib em `.tu`, built-ins migrados, self-hosting no horizonte). Interop com `dart:` é **explícito,
  fino e enumerado** (I/O, crypto), nunca difuso.

## Artigo III — Régua do Dragon Book (o que o Itá implementa vs. herda)

O roadmap é ancorado no *Compiladores — Princípios, Técnicas e Ferramentas* (Aho, Lam, Sethi, Ullman).
O livro se parte em dois grupos, e as specs respeitam essa divisão:

- **Grupo A — o Itá IMPLEMENTA (caps 2–6):** front-end + semântica + IR + codegen para Kernel. É onde está
  **todo o trabalho real** (léxico, sintaxe, desugaring, binding, type-checker, análises, geração de
  **código intermediário**). **A fronteira do Grupo A vai até a emissão de código intermediário — Cap 6 →
  Dart Kernel (`.dill`); tudo até aí é implementado pelo Itá.**
- **Grupo B — a Dart VM ENTREGA DE GRAÇA (caps 7–12):** **runtime/execução (Cap 7)**, GC, **código de máquina
  e otimização (Caps 8–12)**, alocação de registradores, paralelismo. O Itá **lê** esses capítulos para
  entender o que herda — **não os implementa** (assim como o Elixir não reescreve a BEAM). **Que o Cap 8
  (código de máquina) seja Grupo B NÃO faz do codegen→Kernel (Cap 6) algo herdado — o Kernel é emitido pelo
  Itá.** Specs só declaram *dependências* da VM (§8).

## Artigo IV — Regras operacionais (como se trabalha no Itá)

Vinculam qualquer sessão/agente que atue no projeto:

1. **Toda mudança de linguagem/compilador é validada ao vivo via MCP `ita`** — nunca chutar comportamento.
   Delegar execução ao agente do compilador e confirmar via `compile`/`run`/`debug` do MCP.
2. **Não mexer no git durante subagente ativo** — não rodar `checkout`/`branch`/`commit` no working tree
   enquanto um subagente edita o mesmo repo (troca o HEAD sob os pés dele).
3. **Compile-time perto do Go (métrica obrigatória)** — o `itac` de dev/CI **é** o binário **AOT**
   (`tools/build-itac.sh`), não o JIT. O CI tem **benchmark de compile-time que falha em regressão**.
4. **Conformância no CI** — todo CA de spec vira caso no **corpus de conformância**; nada entra sem CI verde
   (conformance + unit + benchmark). Paridade VM×JS vigiada pelo golden-runner quando o codegen muda.
5. **Extensão de arquivo `.tu`**; documentação em PT-BR, identificadores de código em EN/backticks, erros
   internos em EN kebab-case.

## Governança

- **Emendas aos princípios permanentes (Artigo I) e ao posicionamento (Artigo II)** exigem decisão explícita
  do dono (`GabrielAderaldo`). Uma spec **não** pode contradizê-los por conta própria — se precisar, ela
  propõe a emenda e aguarda ratificação.
- **Artigos III e IV** evoluem com o roadmap; specs podem propor ajustes operacionais com justificativa.
- **Precedência em conflito:** `constitution.md` (princípios) > fontes normativas de repo (`GRAMMAR.md`,
  `ROADMAP.md`) > SKILL.md > conhecimento geral do modelo.
- **Versionamento:** MAJOR = remoção/redefinição de princípio; MINOR = novo princípio/regra; PATCH = ajuste
  de texto sem mudar semântica.
