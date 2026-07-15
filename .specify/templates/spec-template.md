<!--
================================================================================
 TEMPLATE DE SPEC — Itá (RFC de linguagem / mudança de compilador)
================================================================================
 Gerado por `/speckit-specify`. Copiado para: specs/<NNN>-<short-name>/spec.md

 COMO PREENCHER
 - Idioma: PT-BR na prosa; identificadores de código sempre entre `backticks`;
   erros internos em EN kebab-case; tokens/tipos no dialeto do Itá.
 - Este é UM template MULTI-FASE. Uma mudança de compilador atravessa só um
   SUBCONJUNTO das fases do Dragon Book. **Remova por completo (heading incluso)
   toda seção de fase que a mudança NÃO toca** — não deixe "N/A".
 - A §4 (Especificação formal) é OBRIGATÓRIA sempre que a mudança altera tipo
   ou semântica. É dispensável apenas para mudanças puramente mecânicas
   (ex.: açúcar sintático que não muda regra de tipo).
 - Cada fase cita o capítulo do Dragon Book que a fundamenta ([cap X.Y]),
   a mesma disciplina do ROADMAP.md.
 - Não descreva HOW-de-implementação de baixo nível aqui; descreva a REGRA
   (o que passa a valer) e o comportamento observável por alvo.
 - Antes de sair de `draft`: rode `/speckit-clarify` (zera ambiguidades) e o
   Constitution check (§0.5) sem conflito aberto.
 Apague este bloco de comentário ao finalizar.
================================================================================
-->

# Spec <NNN>: <título da mudança>

> **Tipo:** decisão-de-linguagem | feature-sintaxe | feature-codegen | stdlib | perf · **Marco:** `<M4 | …>`
> **Status:** `draft` | `clarified` | `accepted` | `implemented`
> **Autor / Data:** <nome> · <AAAA-MM-DD> · **Issue/PR:** `<link>`

## §0 Metadados

- **Classe da mudança** (Apêndice A — orientação objeto vs fase):
  - [ ] **Nova construção** — mexe numa classe de nó da AST (`gen`/`jumping`/`reduce`/`check`).
  - [ ] **Nova regra/fase** — atravessa várias classes / uma fase inteira.
  - [ ] Ambos.
- **Fases tocadas** (marque; remova as seções não marcadas):
  - [ ] Léxico (§2) · [ ] Sintaxe (§3) · [ ] Formal/Tipos (§4) · [ ] SDD/atributos (§5) · [ ] Fluxo (§6) · [ ] Codegen/IR (§7) · [ ] Runtime (§8)
- **Princípios do Itá afetados:** `<lista — ver constitution.md>`

## §1 Motivação e resumo

<!-- 3-6 frases: qual dor resolve, por que agora, origem (issue/roadmap/paridade). -->

**Antes → Depois** (exemplo mínimo em `.tu`):

```tu
// antes — comportamento atual
```

```tu
// depois — comportamento proposto
```

**Não-objetivos:** <o que esta spec explicitamente NÃO faz — evita scope creep>.

---

<!-- ===================== FASES (remova as que não tocam) ===================== -->

## §2 Léxico — `[cap 3.3]`

<!-- Remova esta seção inteira se a mudança não cria/altera token. -->

- **2.1 Tokens novos/alterados** — nome do token (= terminal que a gramática enxerga, `[cap 4.2.1]`).
- **2.2 Padrão do lexema** — definição regular / classes de caractere (alfabeto Unicode):

  ```
  letter_ → [A-Za-z_]
  digit   → [0-9]
  <novo>  → <regex sobre alfabeto e definições anteriores>
  ```
- **2.3 Atributos do token** — que valor léxico o lexer devolve (`lexval`, `lexeme`) `[cap 5.1.1]`.
- **2.4 Colisão com keywords** e fronteira léxico↔sintaxe — o que fica na regex vs sobe à gramática `[cap 4.3.1]`. Lookahead/contexto à direita, se houver `[cap 3.3.5]`.

## §3 Sintaxe — `[cap 4.2–4.3]`

<!-- Remova se não muda a gramática. -->

- **3.1 Produções novas/alteradas** (BNF/EBNF; `|` alterna, `[…]` opcional, `{…}` repetição):

  ```
  <não-terminal> → <corpo> | <corpo>
  ```
- **3.2 Precedência e associatividade** — nível na cadeia de não-terminais por precedência.
- **3.3 Ambiguidade** — a produção introduz ambiguidade? Qual a regra de desambiguação (ex.: dangling-else) `[cap 4.3.2]`.
- **3.4 Adequação ao parser descendente** — exige eliminar recursão à esquerda (`A → Aα|β` ⇒ `A → βA'`, `A' → αA'|ε`) ou fatoração à esquerda? `[cap 4.3.3–4.3.4]`.
- **3.5 Reconciliação** — delta ao `GRAMMAR.md` normativo e à gramática **tree-sitter** (prática do projeto).
- **3.6 O que sobra para a semântica** — restrições não expressáveis por CFG (declarar-antes-de-usar, aridade) `[cap 4.3.5]`.

## §4 Especificação formal (tipos e regras) ⭐ — `[cap 6.3, 6.5]`

<!-- OBRIGATÓRIA se a mudança altera tipo ou semântica. É o núcleo de uma RFC de linguagem. -->

- **4.1 Expressões de tipo** — tipos/construtores novos (`array(n,T)`, `record(T)`, `s→t`, `s×t`, var. de tipo `α`) `[cap 6.3.1]`.
- **4.2 Equivalência de tipos** — estrutural | por nome (qual vale para o tipo novo) `[cap 6.3.2]`.
- **4.3 Regras de tipo** — notação premissa/conclusão `[cap 6.5.1]`:

  ```
        Γ ⊢ e₁ : Int      Γ ⊢ e₂ : Int
        ───────────────────────────────
             Γ ⊢ e₁ & e₂ : Int
  ```
- **4.4 Inferência vs síntese** — síntese (constrói dos operandos) ou inferência (deduz do uso; `α,β`, `∀`, unificação / unificador mais geral) `[cap 6.5.4–6.5.5]`.
- **4.5 Conversões/coerção** — widening (implícita, preserva) vs narrowing (cast explícito, perde); `max(t₁,t₂)`, `widen(a,t,w)` `[cap 6.5.2]`.
- **4.6 Erros de tipo detectados** — mensagens e spans (EN kebab-case no erro interno).

## §5 SDD / Tradução dirigida por sintaxe — `[cap 5.1, 5.4]`

<!-- Remova se a §4 já cobre a regra e não há atributos/ações novos a declarar. -->

- **5.1 Atributos** — sintetizados (dos filhos) vs herdados (do pai/irmãos à esquerda) `[cap 5.1.1]`:

  | PRODUÇÃO | REGRAS SEMÂNTICAS |
  | :-- | :-- |
  | `E → E₁ + T` | `E.val = E₁.val + T.val` |
- **5.2 Classe da SDD** — S-atribuída | **L-atribuída** (modelo do Itá, casa com descendente) — e ausência de ciclos `[cap 5.1.2, 5.4]`.
- **5.3 Ações do SDT e efeitos colaterais** — inserção na tabela de símbolos, `offset += width` etc. `[cap 6.3.4–6.3.5]`.

## §6 Fluxo de controle — `[cap 6.6]`

<!-- Remova se a mudança não é uma construção de controle (if/match/loop/?/&&/||). -->

- **6.1 Atributos de controle** — `B.true`, `B.false`, `S.next`, variáveis de rótulo (`newlabel()`).
- **6.2 Layout de código** — ordem de `B.code`/`S₁.code`/gotos (diagrama) e regras semânticas:

  ```
  S → while ( B ) S₁   begin=newlabel(); B.true=newlabel(); B.false=S.next; S₁.next=begin;
                       S.code = label(begin) ‖ B.code ‖ label(B.true) ‖ S₁.code ‖ gen('goto' begin)
  ```
- **6.3 Curto-circuito / fall-through** e booliano como valor vs controle `[cap 6.6.6]`.

## §7 Código intermediário e geração — `[cap 6.2, 8.1]`

<!-- Remova se a mudança não altera a emissão de Kernel. -->

- **7.1 Instruções de IR / Kernel afetadas** — o alvo é **Dart Kernel** (`.dill`); o análogo do livro é o código de três endereços `[cap 6.2.1]`.
- **7.2 Gabarito de código** — esqueleto por construção (o que o codegen emite) `[cap 8.1.3]`.
- **7.3 Comportamento por alvo** — a saída observável em cada alvo de graça da toolchain Dart:

  | Alvo | Comportamento esperado | Observação |
  | :-- | :-- | :-- |
  | **VM** (JIT) | <saída> | referência (oracle) |
  | **AOT** (`dart compile exe`) | <saída> | deve empatar a VM |
  | **JS** (`dart2js`) | <saída> | paridade VM×JS; MATCH/NUM/… |

## §8 Runtime — premissas sobre a Dart VM — `[cap 7.1]`

<!-- Remova se a mudança não depende de nada específico do runtime. -->

- **8.1** O que a spec **assume** da VM (memória, registro de ativação, GC, alinhamento) — **sem reespecificar a VM** (Grupo B; a VM entrega). Só declarar a dependência e o interop `dart:` explícito, se houver.

---

## §9 Checklist de completude (Apêndice A)

- [ ] `lexer` — token novo tem `Tag`/padrão? `[A.3]`
- [ ] `symbols` — tipo novo tem `width`/`numeric`/`max`? `[A.4]`
- [ ] `parser` — recursão à esquerda removida, `match`/lookahead? `[A.8]`
- [ ] `inter` — nova construção = nova classe de nó (`gen`/`jumping`/`reduce`/`check`)? `[A.5–A.7]`
- [ ] fase semântica — `compiler/lib/semantic/`, consumo via `_analysis.typeOf`
- [ ] `tree-sitter` reconciliada · `GRAMMAR.md` atualizado
- [ ] **corpus de conformância** no CI cobre os casos novos
- [ ] **benchmark de compile-time** (`itac` AOT) sem regressão

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** <sim/não; quem quebra>.
- **Plano de migração** (`.tu` afetados, período de transição).
- **Alternativas consideradas e descartadas** — outras semânticas possíveis e por quê não.

## §11 Critérios de aceite (viram testes de conformância)

<!-- Cada CA precisa virar um caso .tu no corpus + saída esperada, ou um caso de paridade.
     CA não-testável é mal-escrito. Validação SEMPRE via MCP `ita` + CI. -->

- **CA1** — <programa `.tu`> ⟶ <saída/erro esperado> (VM; e paridade JS se aplicável).
- **CA2** — <caso de erro> ⟶ `<erro interno EN kebab-case>` com span.

## Definition of Done

- [ ] CAs cobertos por casos no corpus e verdes (VM/AOT/JS conforme §7.3), validados via MCP `ita`.
- [ ] Constitution check sem conflito aberto (§0 princípios).
- [ ] CI verde (conformance + unit + benchmark de compile-time).
