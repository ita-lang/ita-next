# ADR-0018 — Sistema de efeitos (stub — débito de roadmap declarado pelo dono)

- **Status:** **`proposed`** — ⚠️ **STUB deliberado.** Este arquivo existe para o débito ter ENDEREÇO
  (a alternativa — "vira ADR quando o dono puxar" numa linha de spec — é promessa-de-artefato, a
  doença do [[ADR-0014]]). **Nada aqui está decidido além da intenção registrada.** Quem o expande e
  ratifica é o dono, quando quiser puxá-lo. **Não bloqueia NADA** — a spec 014 foi desenhada para
  não esperar por ele.
- **Data:** 2026-07-16
- **Relacionados:** spec `014-flow-check` §6/§12-5 (o sítio que gerou o débito) · [[ADR-0016]] §A ·
  Lucassen & Gifford 1988 (*Polymorphic Effect Systems*, POPL — a literatura-mãe; **lacuna declarada
  dos livros do projeto**: nem Dragon nem CI cobrem efeitos)

## A intenção do dono — verbatim (clarify da spec 014, 2026-07-16)

> *"Estou REAL inclinado para o 04 [sistema de efeitos]"*

— dito ao decidir a pureza do `where` (spec 014 §12-5). A decisão operacional foi **1+3** (primitivos
sintáticos proibidos + ordem topológica publicada), com este ADR como o registro de que a inclinação
é REAL e aguarda o momento certo — não foi recusa, foi sequenciamento.

## O que um sistema de efeitos compraria (esboço, não-normativo)

- A pureza do `where` (014 §6) deixa de ter resíduo interprocedural — `let m = mean(xs)` seria
  aceito **porque `mean` prova pureza**, não porque a ordem publicada o torna bem-definido.
- `const-fn` (a V2 do modelo D de globais — 014 §5) ganharia a fundação natural: const-avaliável ⊂ puro.
- Fronteiras de actor/spawn (visão C9) poderiam declarar o que cruzam.

## O custo que fez o dono sequenciar

Efeito é **viral**: toda assinatura de `fn` carrega (ou infere) o seu efeito; toda fn de ordem
superior propaga. É decisão de identidade da linguagem (P4/P6 — como a anotação aparece SEM virar
`@decorator`, que o P6 veta para sempre) e atravessa F2→F7 inteiras.

## Gatilho de expansão

Este stub vira RFC de verdade quando o dono disser — os candidatos naturais a forçar a conversa:
a V2 do const-fn, o design de actors (M4+), ou a dor real do resíduo interprocedural do `where`.
