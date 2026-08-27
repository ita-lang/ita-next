---
name: phase7-init-body-restoration
description: Corpo do `init` — levantar a restrição do emissor é RESTAURAÇÃO (não precisa de ruling); os 5 rulings que sobram para o dono; co-requisito duro com o walk da F6.
metadata:
  type: project
---

# Corpo do `init` — a fronteira entre restaurar e decidir (2026-07-29)

Contexto: `emit.dart:844`/`:936` restringia o corpo do `init` a `self.campo = e`. O
impedimento real caiu no mesmo dia (`check.dart:326 _initDecl` — a F5 passou a tipar o corpo).

## RESTAURAÇÃO — não precisa de ruling. Quatro artefatos:
1. `grammar.ebnf:229` `initDecl ::= "init" "(" paramList ")" block` + `:273`
   `block ::= "{" ( statement ";"? )* "}"` — o MESMO `block` de `fn`/`while`. Sem produção restrita.
2. A restrição **não tem casa normativa nenhuma**: grep de `init-body` fora de `third_party/`
   volta só `emit.dart` e `conformance/codegen/class_ca3.tu`. Nasceu prosa no emissor.
3. **ADR-0016 §B** (verbatim): o `init` de corpo mata o memberwise porque *"é possível que você
   esteja fazendo trabalho especial que o default desconhece"*. Sob a restrição não há trabalho
   especial possível ⟹ o usuário paga o preço e não recebe nada.
4. `check.dart:1064-1069` — a F5 recusa copy-with em `struct` com init de corpo *"porque o único
   construtor **valida**"*. Duas fases do mesmo compilador com premissas contrárias.

**Escopo do levantamento inclui `emit.dart:1046-1047` (`struct-init-explicit`)** — mesma família;
consertar só a `class` reproduz "feature meio-ligada".

**Kernel tem vocabulário** (não é minha decisão, é do `dart-vm-expert`): `LocalInitializer`
(`third_party/dart/3.12.2/pkg/kernel/lib/src/ast/initializers.dart:321-324`) + `BlockExpression`
(`.../expressions.dart:5211`). Logo a razão escrita em `emit.dart:844-847` descreve limite da
TÉCNICA escolhida, não do Kernel.

## CO-REQUISITO DURO
`flow.dart:257` (`case ast.InitDecl(): break;`) — a F6 **não** caminha o corpo do `init`. Abrir o
corpo sem ligar o walk entrega `guard`/`panic` (o idioma de validação, P7) sem `guard-must-exit`,
sem `unreachable-code`, sem DA. Levantar a restrição e ligar o walk são o MESMO entregável.

## Fila do dono (5 perguntas; (a) NÃO é uma delas)
- **(a) ordem observável = ENTAILMENT**, não ruling: `block` é o mesmo de todo lugar; ordem textual
  ≠ ordem de execução só em `init` seria P4 (Art. I-4).
- **(b) campo `let` atribuído 2×** — RULING. Hoje `check.dart:1912` permite N vezes, em qualquer
  posição, sem ninguém ter decidido (caiu da isenção anti-falso-`assign-to-immutable`).
  Opções: uma-vez (Swift/P1) · livre · `let` uma-vez + `var` livre.
- **(c) terminar sem atribuir todos os campos** — METADE é consenso (nenhum candidato aceita campo
  non-nullable sem valor; `initializers.dart:111-112` põe isso no frontend), METADE é ruling
  (campo `T?` implícito-`nil`? default de decl cobre? diagnóstico F5 ou F6?).
  ⚠️ **Buraco vivo HOJE**: nada em `compiler/lib` nem `codegen/lib` checa cobertura de campo.
- **(d) ler `self` antes de tudo atribuído** — RULING maior (compra ou recusa o two-phase do Swift).
  Precedente: `self-in-field-default` (spec 014 §3). Recomendo a regra que **só afrouxa depois**.
- **(e) `return`/`guard`/`panic` no init** — hoje `return` tipa como Void por
  `check.dart:340` (`_currentFnReturn = VoidType`), fato de implementação, não ruling.

**Relacionadas:** [[phase7-f7-identity-audit]], [[doctrine-ice-nao-e-cerca]],
[[doctrine-consenso-entre-candidatos]], [[doctrine-restricao-nomeia-impedimento]],
[[phase5-011-w3-review]] (feature meio-ligada > 4ª vez).
