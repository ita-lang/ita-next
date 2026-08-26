---
name: fase7-ltf7b-ordering
description: F7 debate de ordenação (2026-07-26) — LT-F7b (promover `resolution` a campo) ANTES do follow-up (a) do offset secundário; a dependência da §7.4 e o custo são assimétricos
metadata:
  type: project
---

# LT-F7b (promover `resolution`) ANTES do offset secundário — parecer de debate (2026-07-26)

Contexto: dono pediu debate 3-especialistas p/ escolher a PRÓXIMA fatia da F7 entre **Opção 1**
(LT-F7b: `resolution` da F4 vira campo de `CheckResult`/`FlowResult`) e **Opção 3** (fechar follow-up
(a) do offset SECUNDÁRIO em `codegen/lib/sanitize.dart`). Minha posição (dono do contrato F5→F6→F7):
**Opção 1 primeiro** — e vale mesmo fora do meu território.

**Por quê (assimetrias):**
- **Dependência:** §7.4 (`VariableGet(VariableDeclaration)`) precisa DURO do `Ident→binder` da F4. Hoje
  `resolution` (`Map.identity<AstNode,ResolvedName>`) é só var local em `driver.dart:357-376` — NÃO é
  campo (`type_table.dart:453` lista nº1–nº7 só; `flow.dart:90-109` idem). Codegen mora em pacote irmão
  `ita_next_codegen`; sem o campo, sem alça → re-rodar `resolveProgram` (viola não-recompute, Dragon 6.3)
  ou herdar o param-fantasma CRUZANDO fronteira de pacote (a "doença que a 011 já matou", tasks:91).
  Opção 3 é anotada NÃO-bloqueante (tasks:75).
- **Risco de base:** Opção 1 não-resolvida = débito ESTRUTURAL que compõe c/ cada consumidor de codegen.
  Opção 3 não-resolvida = passe defensivo GREEN e INÓCUO (zerar offset 2º de nó sintético é cosmético,
  não fere soundness; sanitize.dart:46).
- **Custo:** Opção 1 = cirúrgica (campo em 2 result-classes, dropar param solto), rede dos 862, contida no
  `compiler`. Os PRÓPRIOS comentários (driver.dart:354, flow.dart:116-122) mandam promover "quando a spec
  da F7 aterrissar" — LT-F7a VERDE ⟹ aterrissou.
- **Opção 3 quer vir DEPOIS do 1º `let` real:** premissa "bus error" vive no `kernel_loader.cc` C++ FORA
  do vendor (território dart-vm-expert); decidir completar-vs-remover só é confiável com `let` p/ testar na
  VM (MCP ita). §7.4+LT-F7c fornecem esse `let`.

**Concessão honesta (melhor arg. da Opção 3):** os dois passes COLIDEM no mesmo nó — o 1º `let` traz
`VariableDeclaration.fileEqualsOffset` + `ForInStatement.bodyOffset`, ambos default -1 (sanitize.dart:45).
Se a premissa for VERDADEIRA, §7.4 só-com-Opção-1 deixa crash latente que compose/curry (LT-F7c) dispara.
Mitiga: fundamentar a premissa (ler C++, dart-vm-expert) é BARATO e roda EM PARALELO — só a mudança de
código quer o `let`. Sequência: Opção 1 destrava §7.4 → dart-vm-expert funda premissa em paralelo → §7.4
emite 1º `let` → Opção 3 assenta informada.

**Design da promoção (rodada 2, livros na mesa — Dragon §1.2.7/§1.2.8, Nystrom §11.4):** `resolution`
já é `Map.identity()` (`resolver.dart:56`), off-to-the-side (Nystrom §11.4) — identidade preservada DE
GRAÇA, promover = mover a REFERÊNCIA (param→campo), NÃO re-armazenar; on-node fica fora (mataria a
descartabilidade). **RECOMENDO:** `resolution` = 9º campo de `CheckResult` SÓ (não duplicar em
`FlowResult` — a `tasks.md` LT-F7b GREEN diz "CheckResult E FlowResult", CORRIGIR p/ só CheckResult;
`analyzeFlow(check)` lê `check.resolution`, dropa o param). Modelo Dragon §1.2: o resultado da fase
forwarda o environment que consumiu; as 9 são a MESMA forma (`Map<nó,fato>` descartável) ⟹ record de
side-tables, não God-object. REJEITO objeto único F4+F5+F6 (gating I3 divergente `flow==null`, quebra
CheckResult standalone da F5, dono do blob ambíguo — AÍ mora o God-object). Interface F7 (Dragon §1.2.8)
= o record `(check, flow)` de `flowProgram` que já existe; nomear via `typedef Analysis` é açúcar opcional.

Ver [[fase7-codegen-skeleton]] (LT-F7a, CodegenVisitor S-atribuído), [[types]] (contrato não-recompute).
