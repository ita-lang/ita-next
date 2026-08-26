---
name: fn-as-value-abi-label-identity
description: Leitura de identidade das 4 opções para `fn` em posição de valor (ABI named × posicional) + o opt-out `_` + label obrigatório — e a 5ª opção derivada do Art. II (captura `&f`, forma Elixir).
metadata:
  type: project
---

# `fn` como valor, ABI e label — a leitura de identidade (2026-07-29)

W0 do ADR a escrever sobre as três decisões amarradas. `aplica(f: dobro, v: 5)` passa no
`itac check` e morre em `ice-codegen-type-FunctionType` (`emit.dart:1682` — `_emitType` não
tem arm de `FunctionType`).

## Os dois fatos que ninguém tinha citado (e que reordenam o problema)

1. **A linguagem JÁ tem duas ABIs, decididas pelo KIND.** `collect.dart:645` dá
   `label: p.label ?? p.name` a **todo** param de `fn`; `check.dart:1079-1081` declara
   *"Closure é **posicional pura** — a superfície não tem label ali"*. Nenhuma das duas foi
   decidida por artefato. ⟹ (C) não INVENTA a cisão: dá ao usuário o volante de uma cisão que
   o compilador já fez. Logo a justificativa correta de (C) é **P4**, não P2 (ver abaixo).
2. **Nada de ordem superior RODA hoje.** Além do `_emitType` sem `FunctionType`, o
   `codegen/lib/emit.dart` tem **zero** `FunctionExpression` (grep) ⟹ closure também não é
   emitida. Toda opção quebra apenas programas *check-verdes / build-mortos*. É a janela mais
   barata que este ruling vai ter.

## Vereditos

- **(A) eta-expansão implícita — NÃO-ITAIANA (P4).** 3ª instância da doença que já recusei
  duas vezes (flow-narrowing, ruling 2; default no override, R11): *o mesmo nome responde
  diferente conforme a via, sem marca*. Após `let g = dobro`, `g(x: 5)` é ilegal e
  `dobro(x: 5)` é legal — nada no fonte diz por quê. E é resolução **type-directed silenciosa**:
  meu R5 permite contexto decidir *"quando o glifo PEDE"*; a eta-expansão não tem glifo pedindo.
  **Mas:** é a única opção **puramente aditiva** — cabe depois de (B), (C), (D) ou (E) sem
  quebrar nada. ⟹ pela régua do ADR-0019 R4, é a que se ADIA, não a que se recusa.
- **(B) proibir — ITAIANA COMO CERCA, não como destino.** Converte ICE em erro nomeado
  ([[doctrine-ice-nao-e-cerca]]). Não fere o namespace unificado (F4 #1): `struct Foo` também
  não é valor — `Foo(x:1)` é o tipo invocado. Fere P5 na margem. **Cerca precisa ser POSICIONAL**
  (callee = chamada; resto = erro), senão mata `|>`/`>>`, que passam por `_synth(n.callee)`
  (`check.dart:1577`).
- **(C) `_` na declaração — ITAIANA NA FORMA, com o rótulo errado.** O `_` não sobrecarrega o
  ADR-0016 §C: §C governa **o que um label presente faz** (confirma), (C) governa **se ele
  existe**. Questões diferentes. E `_` no slot de label = o mesmo wildcard de `pattern ::= "_"`
  (`grammar.ebnf:377`): "não ligue este nome". **Não é "P2 aplicado a funções"** — P2 separa
  o que o valor É (identidade × cópia); (C) separa como se ESCREVE a chamada. A analogia
  promete semântica e entrega sintaxe. O custo real: torna ordem-superior um **opt-in que o
  autor do callee concede**, invisível no call-site — inverte o default do P5.
- **(D) marcador de ABI dupla — NÃO É UMA QUARTA OPÇÃO; é um modificador das outras.**
  Ver o arquivo do ADR. Resumo: (D)-como-default **É** (A) (superfície idêntica; lowering é
  técnica, Art. III) ⟹ só existe como opt-in ⟹ pressupõe (B) ou (C). Sobrevive ao P4
  ([[doctrine-porta-fechada]]: o usuário pode abrir quantas portas quiser; o pecado é o
  compilador abrir). Cai por três custos próprios: o marcador é **por-fn** e a ABI é
  **por-param** (costura); fura permanentemente a decisão 3; e o `.dill` carrega duas formas ou
  perde "defaults saltáveis do meio" (spec 013 §12-3, confirmado pelo dono 2026-07-16).
- **(E) captura explícita no USO — `&dobro` — DERIVAÇÃO DA SESSÃO, do Art. II.** Nenhuma das
  quatro veio do posicionamento. **Elixir/Erlang exigem marcador para virar valor** (`&f/1`,
  `fun f/1`) — pelo mesmo motivo (nome+aridade ≠ valor). `&` está lexado (`grammar.ebnf:129`) e
  **morto no parser** (`:141-143`, bitwise foi p/ `Bits.*`) ⟹ glifo livre, custo léxico zero.
  Sem aridade (Itá não tem overload — ADR-0017 §1). É **(A) com o glifo que o P4 pede**, no
  sítio do fenômeno (mesma forma do `?` e do `any Ord`), e desamarra a decisão 1 das outras duas.

## A amarração — o que descobri

- **Decisão 3 (label obrigatório) não é sobre `div(den:2,num:10)`; é sobre `|>`, `>>` e a
  trailing-closure.** `desugar.dart:815-816` (`>>`), `:838`/`:845` (`|>`) constroem
  `Arg(null, …)` e são **type-agnostic por design** (`:829`) ⟹ não têm como injetar label.
  `trailingClosure ::= block` (`grammar.ebnf:320`) **não tem slot de label**. Obrigatoriedade
  exige lista de isenções = o compilador escrevendo a forma que proíbe ao usuário.
- **Combinação a excluir por nome: (A) + label obrigatório.** O compilador fabrica, em silêncio,
  exatamente a chamada posicional que proíbe ao usuário. Mesma doença por outra porta em
  (B/C/D) + 3 sem isenção declarada.
- Ordem que nunca quebra código: **2 antes de 3** (nota do dono no `type.dart:301-304`);
  1 = (B) é grátis agora; 1 = (A) cabe a qualquer momento depois; 1 = (C) **depois** de 3 é fatal.

## Recomendação (derivação, não ruling)
**(B) agora** (cerca honesta, zero porta fechada) + **(E) `&f` como destino, ruling do dono**
(superfície nova) + **(A) explicitamente adiada** + **`_` entra com a semântica Swift (remove o
label), desacoplado de "é valor"** + **decisão 3 = NÃO obrigatório** enquanto `|>`/`>>`/trailing
não tiverem resposta própria.

**Relacionadas:** [[phase5-types-identity-rulings]] (R10 — label é da decl; R5 — contexto só
quando o glifo pede), [[doctrine-declaracao-vs-tipo]], [[doctrine-porta-fechada]],
[[doctrine-ice-nao-e-cerca]], [[phase4-binding-identity-rulings]] (#1 namespace unificado).
