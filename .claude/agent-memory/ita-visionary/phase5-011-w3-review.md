---
name: phase5-011-w3-review
description: Review W3 da spec 011 (resolução de membro) — 2 conflitos abertos (override sem checagem de assinatura; CA73 = privilégio de built-in) + o ruling copy-with×init-de-corpo (entailment).
metadata:
  type: project
---

# Review W3 da spec 011 — o que o código entregou vs. o que a visão prometeu

2026-07-15. Revisão do diff `2dd4069..e61c15a` contra os CAs do §11 da 011.

## Doutrina que este review CONFIRMOU (não reabrir)
- **`override` obrigatório é itaiano** — passa no teste do `mut`: informa o LEITOR de algo que ele
  não vê (a superclasse está noutro arquivo). Cerimônia é marca **sem** informação (`@Override` do
  Java). As duas cercas do `_checkOverride` estão certas: requisito de trait (body==null) **não**
  pede `override`; default de trait **pede**.
- **Taxonomia `-unsupported`** (§4.7): o sufixo significa **lacuna do COMPILADOR**, não erro do
  usuário nem ruling pendente. Usá-lo para indecisão de design (`extension-field-unsupported`)
  **estica a taxonomia** — promete "um dia funciona" onde o destino Swift é ilegal-para-sempre.

## Conflitos abertos que este review levantou (precisam do dono)
1. **`override` sem checagem de assinatura** ⟹ `D ≤ A` é MENTIRA. `_checkOverride` só checa
   presença; `_checkTraitConformance` pula os que têm default (`want.decl.body != null → continue`),
   que são exatamente os que `override` cobre. **Os dois checks têm domínios complementares e a
   assinatura cai no vão.** CA69b **canoniza** o insound (`A.f()->Int` / `override D.f()->String`,
   `errors isEmpty`). Mesmo argumento do `missing-trait-member` (subtipagem É obrigação).
2. **CA73/§4.6 NÃO foi entregue** e ninguém declarou. `let xs: List<Int> = []` ok;
   `let s: Stack<Int> = Stack.new()` ⟹ `cannot-infer` (o `_check` não tem caso de `Call`; o
   `expected` nunca desce no retorno). **É a face 1 do privilégio de built-in que a própria spec
   §4.6 proibiu** — e ela crava que adiar isto "não é neutro: é declarar um PRIVILÉGIO", logo
   **ruling do dono**, não decisão de escopo.

## Ruling do W0 — copy-with × `struct` com `init` de corpo: **ENTAILMENT, não ruling do dono**
Achado do `dart-vm-expert`: `_copyWith` só barra não-`struct` ⟹ `c.{ deg: 1.0 }` sobre `struct C` com
`init(f:)` **tipa**, mas a F7 não tem construtor all-fields para emitir.
- **Copy-with está DEFINIDO sse existe memberwise.** `p.{ y: 9 }` ≡ `P(x: p.x, y: 9)` =
  `ConstructorInvocation` do memberwise ⟹ copy-with **não é 2ª via de construção; é açúcar sobre a
  única via**. Sem memberwise ele não tem **denotação** — a F5 não licencia algo perigoso, licencia
  algo **sem significado**. A razão 3 entra só no 2º momento (quando alguém propõe sintetizar o
  all-fields) → [[doctrine-porta-fechada]].
- **Entailment porque os DOIS lados são do dono:** (i) "init no corpo substitui o memberwise" (Swift,
  2026-07-15) + (ii) ADR-0012 #1 ⟹ ou **erro**, ou **ele se contradiz**. Não há escolha para ele fazer.
  Mesmo teste do `missing-trait-member`. **"Não é decisão minha" (VM-expert) ≠ "é do dono"** — é
  **roteamento**: pergunta de identidade, logo minha. Não repassar.
- **Saídas:** (a) `copywith-on-custom-init` = **a regra**, e **separada** de `copywith-on-reference-type`
  (o predicado cobre os dois, mas o hint "mova o init p/ extension" é **mentira** p/ `class`); (b)
  "casar campos com params do init" = **recusada** (legalidade dependeria de nomes de param noutro
  arquivo = P4; e `init(f:)` que normaliza em `deg` nunca casaria); (c) `init` em `extension` = **o
  escape, não alternativa** — e está QUEBRADA (`extensionInits` write-only) ⟹ **co-requisito duro:
  (a) + a leitura de `extensionInits` são o MESMO entregável**, senão fechamos a porta e mandamos o
  usuário para saída que não abre; (d) "memberwise sobrevive sempre" (divergir do Swift) = **única
  que exigiria emenda do dono**, recusada (institucionaliza a razão 3: init validante vira decoração).
- **Achado adjacente:** `TypeInfo.init` é `FunctionType?` **sem procedência** — `_initOf` sabe qual
  porta construiu e **joga o fato fora**. A F5 tem de **registrar** memberwise-vs-explícito (fato
  semântico load-bearing; a forma é do `compiler-craftsman`).

## Regra de método que se repete (4ª vez — refinada em 2026-07-15)
**Feature meio-ligada é pior que feature ausente.** ⚠️ **Refino (R9 de [[phase5-types-identity-rulings]]):**
o co-requisito duro foi pago **só para `struct`** — o gate `cands.length > 1` deixa a `class` com `init` só
em `extension` dando `no-init`, e os testes (`check_test.dart:713`/`:1144`) exercitam extension-init
**apenas sobre `struct`**. ⟹ **testar a chamada em TODOS os kinds que o glifo admite**, não só no primeiro. `extensionInits` é write-only ⟹ o `init` em
`extension` (diretriz Swift do dono) é aceito na decl e **inalcançável** no uso; o erro que sai é
`argument-label-mismatch` contra o memberwise = **mentira**. Antes havia `extension-init-unsupported`
(honesto). O teste só provou a metade negativa ("preserva o memberwise"), nunca chamou o init novo.
⟹ **Ao aceitar um glifo, testar a CHAMADA, não só a decl.**

**Relacionadas:** [[phase5-types-identity-rulings]] (R5, variância invariante),
[[phase5-builtin-members-chao-vs-biblioteca]] (as 2 faces do privilégio),
[[doctrine-argumento-de-ausencia]].
