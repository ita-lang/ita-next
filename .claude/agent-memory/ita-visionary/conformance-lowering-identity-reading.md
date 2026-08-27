---
name: conformance-lowering-identity-reading
description: Leitura de identidade (assinada, Art. IV-6b) para o ADR proposed da lowering de conformance em built-in — (A)-para-sempre é ilegítima; C limpo; B condicional a valores+prova; D exige decl .tu, não representação própria.
metadata:
  type: project
---

# Lowering de conformance em built-in — leitura de identidade (pré-F7)

2026-07-16, a pedido da orquestração; alimenta ADR `proposed` (dono decide). Contexto técnico:
a fork aberta do `collect.dart:344-395` (`Int` baixa p/ `dart:core` × decl `.tu` própria) + as 4
saídas (A proibir-sempre / B wrapper / C witness / D decl própria).

## Os 5 vereditos (resumo citável)
1. **`extension Int : Ord` é EXIGIDO, não opcional** — entailment de Art. II Norte ("built-ins
   migrados p/ `.tu`") + face-2 do privilégio **em espelho** (incapacidade que só o built-in tem:
   sem `Int ≤ Ord`, `sort<T: Ord>` sobre `List<Int>` vira hard-code = a mágica do R5) + ADR-0012 #2.
   Rota "função livre + `|>`" NÃO escapa: pipe muda grafia, não dissolve a conformance — e o dono
   já recusou essa rota p/ container ([[phase5-builtin-members-chao-vs-biblioteca]]).
2. **P4 vigia o OBSERVÁVEL, e o glifo JÁ existe**: `fn f(o: Ord)` é escrito pelo usuário; subsunção
   contra tipo esperado declarado é sancionada (009 §4.2b). **(C) witness = P4-limpo por
   construção** (valor intacto; witness = a info do `impl` entregue ao call-site; não é P11 — P11
   veta geração de FONTE, não estrutura no `.dill`). **(B) wrapper = condicional**: só valores
   (P2 nega identidade a valor ⟹ box é representacionalmente grátis), com prova de invisibilidade
   em 4 canais — `==` heterogêneo, round-trip `is`/`match`, borda `dart:`, mensagens. Prova por
   corpus, não intuição ([[doctrine-argumento-de-ausencia]]). **B morto p/ semântica de referência**
   (forjaria 2ª identidade — P2). Custo de alocação NÃO entra em P4 ([[doctrine-vm-data-reinforces]]).
3. **Subsunção-de-struct-como-box é CONSEQUÊNCIA de P2, não tensão** — valor não tem identidade a
   perder. Duas cercas: box não pode criar sharing (mutação visível através do slot = referência
   sem glifo); slicing já banido (struct não herda). **Campo de batalha pequeno**: `f<T: Ord>(x: T)`
   resolve witness estático, zero box; só o slot EXISTENCIAL importa. **Interage com ruling aberto
   do dono**: `any Ord` marcado vs implícito ([[phase5-types-identity-rulings]] #4) — o ADR nomeia,
   não decide de lado.
4. **(A)-hoje (lacuna declarada) é honesta; (A)-PARA-SEMPRE é ILEGÍTIMA como motivada**: única razão
   disponível é topologia do Kernel = backend legislando front-end (a cerca do próprio
   `collect.dart`, minha) = inversão da [[doctrine-vm-data-reinforces]]; inverte a taxonomia
   `-unsupported` em mentira retroativa; e sob (D) exigiria código dedicado para MANTER a
   incapacidade = privilégio em espelho. Mata a visão systems (C9): protocolos binários sobre
   Int/bytes virariam "embrulhe em newtype primeiro". Não aprovo nem com pedido — seria emenda
   contra o próprio Norte.
5. **A fork (D) é binária FALSA**: o Norte exige a **DECLARAÇÃO** de `Int` em `.tu` (contrato,
   membros, conformances), NÃO a representação própria. Quadrante literal: o integer do Elixir É o
   da BEAM + protocolos por cima; Elixir ≈ (C), Swift ≈ (B+C), D-puro ≈ ninguém do quadrante.
   D-puro que mate Smi unboxing trai a premissa fundadora (MANIFESTO:35-37 "16×"; a razão do
   ADR-0001) — **formulação correta**: não "D é não-itaiano porque lento", mas "o Norte não exige o
   que o D-puro paga; pagar não compra identidade". Forma-Elixir (decl `.tu` + backing
   `dart:core::int`) serve Art. II e III ao mesmo tempo; mecanismo é do craftsman/vm-expert; se
   precisar marcador, é **keyword, nunca `@`** (P6).

## A régua absorver × ceder (frase-síntese)
**Absorver custo onde a alternativa barata esconde semântica** (witness a mais, marca `any`, erro
verboso); **ceder representação onde a semântica observável não muda** (layout, dispatch, unboxing
= Grupo B, Art. III).

## Inegociável (para o ADR)
Conformance em built-in existe na superfície · inobservabilidade provada nos 4 canais · identidade
de referência nunca forjada · a razão nunca é topologia do Kernel · zero `@marcador`.
**Negociável:** qual mecanismo (C / B-condicionado / D-híbrido), cronograma, `any` marcado,
fronteira decl/backing.

**Relacionadas:** [[phase5-builtin-members-chao-vs-biblioteca]] (privilégio, 2 faces),
[[doctrine-vm-data-reinforces]], [[systems-low-ffi-vision]], [[phase5-types-identity-rulings]] (#4
existencial aberto, R5).
