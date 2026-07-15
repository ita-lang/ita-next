---
name: crivo-5-decisoes-identity-review
description: Crivo de identidade das 5 decisões abertas (2026-07-15) — label/lowering-trait/bounds-§B-7/walks/ruling-fabricado. 3 fabricações NOVAS apanhadas; ADR-0014 é UM artefato que serve 3 decisões
metadata:
  type: project
---

# Crivo das 5 decisões (2026-07-15) — vereditos, e as 3 fabricações novas

## As 3 fabricações NOVAS desta rodada (todas verificadas)

1. **`type.dart:280` fabrica DENTRO da confissão.** Diz *"O que **é** ruling do dono: 'ordem
   obrigatória, defaults saltáveis; o label confirma, não reordena'"* — mas `check.dart:1245-1252`,
   o sítio que a implementa, atribui **honestamente**: *"Diretriz do dono: 'se tiver divergência…
   Swift é a diretriz'"* + *"**Seguimos** o Swift"*. ⟹ ruling do dono = a **meta-diretriz**;
   "ordem obrigatória" é a **aplicação** dela (derivada, `compiler-craftsman`). O `type.dart:280`
   **promove derivação a ruling** — no comentário que denuncia a promoção anterior. **Fabricação de
   2ª ordem.** Consequência: o "a favor" central do H0 do label (*"não é ausência de decisão, é
   decisão parcial já tomada"*) está de pé sobre ela.
2. **A auditoria do H2 (decisão 5) fabricou a própria prova.** Alegou *"`tools/build-itac.sh`,
   `tools/pin-dart.sh`, `dart-sdk.pin`: **nenhum existe; `tools/` nem é diretório**"*. **FALSO em
   2 de 3**: `ita-next/tools/pin-dart.sh` e `ita-next/dart-sdk.pin` **existem** (olhou em
   `compiler/tools/`, cwd errada). O `pubspec.yaml:17` referencia exatamente os dois que existem.
3. **A perna que sobra do H2 não prova o que ele diz.** Art. IV-3 (*"O CI **tem** benchmark"*) é
   falso — `ci.yml:60-63` é placeholder comentado —, **mas não é "regra sem verificador decaiu"**:
   é a constituição escrevendo **roadmap no presente** (*"Entra na fase de codegen"*). Mecanismo
   diferente, e **um lint de citação não o pegaria**. Argumenta por *uma* cerca, não por *esta*.

## Vereditos

- **Label:** H0 **não-itaiano por omissão** (e seu argumento é a fabricação 1). H1 sozinho
  **não-itaiano** — `_` **não parseia hoje** ⟹ é **superfície nova** ⟹ ruling do dono (ADR-0012 é
  literalmente *"rulings de dono da **superfície**"*). *"Monotônico ⟹ não precisa de ruling"*
  confunde **reversibilidade** com **autoridade**: é a porta dos fundos que eu já vetei (f5 ITEM 1).
  H2 **itaiano em espírito, exige o dono** — (a)+(b)+keyword-em-label são **um** ruling.
  H3 **não-itaiano**: cria 2 convenções de chamada e a especial é a do compilador — face-2 do teste
  do privilégio, e re-fabrica o ruling que foi fabricado.
- **Lowering de trait:** H1 **morre por citação** — ADR-0013 §2: `dynamic` só onde *"o Kernel exige um
  tipo que **não sabemos nomear**"*, e aqui sabemos (`Barker`); *"`Object?` > `dynamic`"* mesmo lá.
  H3 **não-itaiano** (decreta sobre mundo inexistente: imports são no-op). H2 **itaiano SÓ com a
  moldura corrigida**: hoje os dois casos falham pela **MESMA razão** (`collect.dart:340`,
  `declNamed('Int') == null` — *"falta a **declaração**"*, minha doutrina). *"Conformance retroativa
  **nunca** chega"* pressupõe que `Int` baixa para `dart:core::int` — **fork do M5 não tomada**
  (`type.dart:79`: `IntType` é classe própria hoje). Deixar a topologia do Kernel decidir se o `Int`
  do Itá implementa um trait do Itá é **o backend legislando o front-end** (Art. II) — o mesmo
  não-sequitur que eu já cravei nos bounds. ⟹ split **sim** (P4: *"o erro diz DE QUEM é a lacuna"*),
  **"nunca" não**.
- **Bounds/§B-7:** H2 **itaiano** (é o que eu já cravei), com 3 correções: (i) **ADR é imutável**
  (`adr/README.md:3-5`) ⟹ re-ratificar = **ADR novo com supersede parcial** (precedente ADR-0013 ×
  0004), **não** editar §B-7; (ii) a razão nova é **derivada** ⟹ entra **assinada**; o dono ratifica
  a **decisão**, não a nossa prosa — escrevê-la na voz dele seria a mesma doença; (iii) H3 **não** é
  a mesma coisa que o H1 do label: `T: A + B` **parseia e é impresso hoje** (`grammar.ebnf:211`,
  `ast_printer.dart:423`) e o glifo está **no texto do §B-7** ⟹ ativar semântica ≠ criar superfície.
  Mesmo assim: relaxa, demanda medida zero ⟹ adiar. H4 morre por citação (§B-7 *"adiar"* está de pé).
- **Walks:** H0 **não-itaiano** (falsa acusação — *"pior que lacuna declarada"*, f5 ITEM 2). H3 morre
  (Dragon §6.5.2 + `_reaches`). H2(a) = **entailment** (*"subtipagem É obrigação"*, spec-011 #1).
  **H2(b) NÃO gasta ruling do dono — eu assino**: é *palavra por palavra* a f5 ITEM 3 (*"a precedência
  inventada torna-se **inobservável**"*); zero corpos ⟹ remover candidato que não denota ≠ escolher.
  H2(c) idem, via ADR-0013.
- **Ruling fabricado:** H2 **itaiano** (é a minha doutrina executada), com a prova re-fundada:
  o que sustenta é a **erosão ~4/dia** + a **assimetria da evidência perecível**, não o Art. IV-3.
  Art. IV-6 = **Governança §84** (Art. IV evolui barato), bump **1.0.0 → 1.1.0** (§87). H3 morre:
  P4 (id opaco esconde a frase) + `type_table.dart:238` já nomeia o perigo (*"duas fontes de verdade"*).

## As 3 descobertas que só o cruzamento dá

1. **`_sameParamDecls` (`type.dart:577`) JÁ compara `label`** — e a razão escrita é
   *"um override que renomeia o label **quebra quem chama por nome**"* (`:559-560`). ⟹ o compilador
   **já trata label como PROMESSA** (nível declaração) enquanto o call-site o trata como decorativo.
   **Segunda testemunha interna** da minha ITEM 1 (*"uma das duas metades é decorativa"*), agora em
   sítio diferente: a promessa é checada, a obrigação não. H2 do label **não conflita** com os walks —
   ele torna `_sameParamDecls` **necessário** em vez de meramente prudente.
2. **ADR-0014 é UM artefato que serve TRÊS decisões** — assentar (dec. 5) + re-ratificar §B-7
   (dec. 3, que a própria dec. 5 já lista como item (b)) + destravar dec. 1 (a meta-diretriz Swift
   **é ela mesma inauditável**: só data, em `check.dart:1247`/`collect.dart:444`/minha memória).
3. **A cerca dos walks (dec. 4 H2b) e o (c) repousam em rulings INAUDITÁVEIS** — *"trait é FOLHA"*
   (`collect.dart:197`) e *"o papel vem do KIND"* (`type_table.dart:253`), os dois com **grep vazio**
   e os dois na lista de ~3 do ADR-0014. ⟹ **dec. 5 antes de dec. 4.**

## Ordem cravada
**5 (ADR-0014) → 4 (a+b+c) → 3 (texto do §B-7, dentro do mesmo ADR-0014) → 1 (o dono) → 2 (split).**
O split da dec. 2 é independente e barato; só não pode nascer decreto.

Ver [[doctrine-citacao-ou-nome]] (a cerca), [[f5-consolidacao-identity-review]] (os 3 vereditos que
este crivo estende), [[doctrine-extension-declaracao-legivel]] (o *"falta a declaração"* da dec. 2).
