---
name: phase6-flow-identity-rulings
description: Review pré-implementação dos 5 rulings da Fase 6 (spec 014, flow-check) — veredictos, cercas e o achado CA15×009 §178. Todos CONFIRMA; o débito de efeitos REFINA na forma.
metadata:
  type: project
---

# Rulings de identidade da Fase 6 (spec 014, flow-check) — review de 2026-07-16

Rulings JÁ do dono (spec 014 §12, fechados 2026-07-16); meu papel foi régua, não reabertura.

## 1. Código morto = ERRO (unreachable + braço morto) — CONFIRMA (P4)
Código que o leitor vê mas nunca roda = programa mentindo (P4). Linha da casa: ADR-0013
(inferência falha=erro) + exaustividade=erro (009) + must-use=erro. A tensão "trava rascunho"
dissolve: `panic("TODO")` é o stub sancionado (CA2 verde, `Never` não completa) e código
estacionado se COMENTA — P4 pede que código que não roda pareça que não roda. **Linha fina:**
erro = código que MENTE; warning = legal mas informativo (`wildcard-covers-known-variants`
segue warning, 009 §12-6). Sem `#if`/const-fold, morto nunca é intencional no Itá.

## 2. `Assign : Void` — CONFIRMA com cerca (P3 pelo próprio qualificador + P1 + RD-1)
Não é exceção ad-hoc: (i) "quando possível" está no TEXTO do P3; (ii) RD-1 já diz que só `=>`
rende — `x = 1` render seria yield sem glifo; (iii) P1 empurra contra (mutação LOCALIZADA;
assign-valor a deslocaliza). **A cerca contra esvaziar P3:** futura não-expressão exige
(a) footgun nomeado com precedente, (b) OUTRO princípio permanente empurrando contra render,
(c) assento próprio (Art. IV-6c). Conveniência de implementação (o "apaga o JLS §16.1
bivalente") é reforço, nunca fundamento ([[doctrine-vm-data-reinforces]]). Lista de
não-expressões ENUMERADA e fechada: declarações, loops, assign — nada por analogia.

## 3. `guard-must-exit` — CONFIRMA; assento bem-formado (ADR-0016 §A + Art. IV-6)
As duas cercas do §A cumpridas: não cita §A sozinho (assento próprio spec 014 §12-3) e a
aplicação voltou ao dono. Mérito é quase entailment: guard sem exit é `if` invertido — o
escopo pós-guard depende do else não completar. Swift = precedente, não muleta.

## 4. Modelo D-V1 (globais const-eval; `var` global e stmt top-level banidos) — CONFIRMA (Art. II + P4 + P1)
Pela régua C9 (quadrante Erlang/Elixir) é o desenho MAIS itaiano: Elixir não tem var global —
tem module attributes compile-time (= a forma do D-V1) e estado em PROCESSOS supervisionados.
**O ban não fere a visão de actors — a PREPARA:** estado mutável terá endereço único (dentro
do actor, via mensagem). Drivers: const-data (tabelas, magic bytes) é o caso systems; valores
no `.dill` = startup determinístico, dissolve o static-init-fiasco em vez de administrá-lo.
`main` única entrada = P4 (nada roda escondido); REPL futuro é contexto próprio, não preclui.
V2 (const-fn/comptime) roteada certo — comptime pede marca (glifo Zig) p/ não ferir P4.
**⚠️ Achado: CA15 contradiz spec 009 §178** ("global → ANOTADO") — o D dissolve a razão
(letrec→grafo const), mas decisão sobrevive à queda da razão (padrão ADR-0014 §2) E tem
fundamento independente (global = API pública ⟹ borda anota). Implementação mantém anotação;
relaxar é pergunta explícita de dono.

## 5. Where 1+3 + débito de efeitos — CONFIRMA o 1+3 (P4); REFINA a forma do registro
O 1+3 refina legitimamente meu veredicto da F3 ([[where-clause-identity]]): a defesa de P4
muda de "efeito inobservável" para "efeito com ordem PUBLICADA e determinística" — sem mágica
= nada escondido, não = sem efeito. Pureza total exigiria interprocedural (fora de alcance,
DECLARADA). Opção 2 (proibir Call) mataria o where (um dos 3 caminhos de init imutável, R6).
**REFINA:** "vira ADR proposed quando o dono puxar" dentro de linha de §12 é promessa-de-
artefato, não artefato — variante da doença do ADR-0014. Forma anti-órfã: ADR-stub `proposed`
JÁ (inclinação verbatim + ponteiro spec 014 §12-5 + "não segura a 014"), ou linha nomeada no
ROADMAP.md. Estrutural: os 5 primitivos (`Assign/Panic/Await/Spawn/EmitStmt` — conferidos na
AST) moram em UM ponto substituível; nó de efeito novo (`AwaitRace`/`AwaitAll` forward-compat)
entra na lista no mesmo commit, senão o "fechado" apodrece.

## Consequências passadas à implementação (resumo)
Erro sem cascata (1/região morta) · `panic("TODO")` como fixture nomeada · diagnóstico de
Assign-Void ensina ("atribuição não rende valor") · citações nomeiam a spec (IV-6d) · CA15
ganha anotação · hints do D não prometem V2 · lista de efeitos em ponto único · ADR-stub do
sistema de efeitos junto da implementação.
