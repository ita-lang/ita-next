---
name: doctrine-ice-nao-e-cerca
description: Doutrina — ICE da F7 não pode ser cerca de LINGUAGEM; restringir programa legal por conveniência de emissão é a emissão ditando a semântica.
metadata:
  type: feedback
---

# Doutrina: o ICE não é cerca de linguagem

**Regra.** A spec 013 §7.8 define: *"A F7 não tem erro de usuário. Entrada é programa
F5+F6-verde; qualquer impossibilidade interna é ICE — e ICE em corpus é bug de fase
anterior que vazou."* ⟹ **um ICE que corta programa LEGAL e F5-verde é uma cerca de
linguagem disfarçada de erro interno.** Não vale como "restrição declarada".

**Why:** o ICE mente sobre a causa. Ele diz "erro interno do compilador" (exit 70) para
um programa que a gramática admite, a F5 aprovou e a F6 liberou — a falha não é do
programa nem de fase anterior, é a emissão não ter fatia. Fere a diretriz do dono
*"diagnóstico nunca mente"* (spec 014 §12-11) e o P4: a mensagem esconde o que
realmente aconteceu. E é o **oposto** do que a emissão deve fazer — a semântica manda
na emissão, não o contrário (Art. III: Cap 6 é implementado pelo Itá, não herdado).

**Precedente já pago:** o `missing-main` era ICE e virou `build-error:` do DRIVER
(LT-F7e, 2026-07-28), *"a fase que reprovou é o driver"*. Todo `ice-codegen-*` que corta
programa legal é o **mesmo bug**, ainda aberto.

**How to apply — as três saídas legítimas, nessa ordem:**
1. **Implementar** — se a fatia é pequena, a cerca não deveria existir.
2. **Erro NOMEADO da fase que é dona do diagnóstico de usuário** (F5 `-unsupported`,
   ou `build-error:` do driver), com fixture `EXPECT-ERROR`. A taxonomia `-unsupported`
   significa *lacuna do COMPILADOR* (spec 011 §4.7) — é honesta aqui, e só aqui.
3. **ICE COM CATRACA** — fixture `EXPECT-ICE:` no corpus. Sem o fixture não há
   declaração: a catraca é o que fica **VERMELHO** quando a fatia nasce
   ([[doctrine-declaracao-sobrevive-ao-tick-verde]]). Comentário no `.tu` ou no
   docstring **não** é catraca.

**Teste rápido:** *"um usuário que escreveu isto errou?"* Se **não**, o ICE é ilegítimo.

**Achado que gerou a doutrina (auditoria F7, 2026-07-29):** ~120 `_ice(...)` no
`emit.dart`, **2** com fixture. Cortam programa legal sem catraca: `init-body-*`,
`binary-pow` (`**` é RETIDO por `core_check.dart:12`, F5 o tipa), `call-nonident`
(valor-função), `let-target-*` (destructuring), `enum-methods`, `class-superclass`,
`trait-default-method` (CA5), `toplevel-ExtensionDecl`/`ImplDecl` (CA6).

**Relacionadas:** [[phase7-f7-identity-audit]], [[phase6-maranget-slicing-identity]]
(o gate confessa o que não verificou), [[doctrine-declaracao-sobrevive-ao-tick-verde]].
