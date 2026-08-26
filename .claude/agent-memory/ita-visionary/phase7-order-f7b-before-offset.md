---
name: phase7-order-f7b-before-offset
description: Ruling de ORDEM (F7) — LT-F7b (contrato explícito) antes do follow-up (a) do offset secundário; o repasse solto é mágica ativa a matar, o offset é dívida rastreada c/ gatilho.
metadata:
  type: project
---

# Ordem da F7: contrato (F7b) antes do offset secundário (a)

Debate dos três especialistas, 2026-07-26. Escolha da PRÓXIMA fatia de código da F7 entre
**Opção 1 (LT-F7b — promover `resolution` a campo de `CheckResult`/`FlowResult`)** e
**Opção 3 (fechar o follow-up (a) do offset secundário do `OffsetNormalizer`)**.

**Veredito: Opção 1.** É ruling de **ordem do trabalho** (minha alçada), não de princípio ferido —
nenhuma das duas fere permanente, logo **sem emenda do dono**.

## Por quê (ângulo identidade/ordem)
1. **A spec já sequencia a 1 antes.** `013/tasks.md` §"Ordem e gate final" passo 2 agrupa
   `F7a+F7c+F7b` como "corrige spec e contrato ANTES do grosso da emissão"; só o passo 3 abre a §7.4.
   A Opção 3 está marcada no próprio texto (linha 74/75) como "follow-up **do dono**, **NÃO bloqueia
   o §7.4**". Gate vs. dívida registrada — categorias distintas.
2. **Repasse solto = mágica ativa (P4).** `resolution` (F4, `Ident→binder`) trafega por parâmetro
   fantasma no `driver.dart`, não é campo. Canal invisível ao leitor do result. A nota da linha 91:
   "promover ANTES de a F7 herdar o repasse — a doença que a 011 já matou uma vez". Janela: enraizar
   depois custa mais (lição 011, [[phase5-011-w3-review]] entailment/contrato).
3. **Na Opção 3 a mentira ATIVA já morreu** — o comentário foi honestado (não afirma "bus error" sem
   fonte). A diretriz "diagnóstico nunca mente" já foi satisfeita; resta *grounding* (fundamentar/
   completar/remover), não saneamento de mentira. Urgência caiu p/ dívida.
4. **Martelar (a) agora fere a disciplina.** Fundamentar o offset exige o `kernel_loader.cc` C++
   **fora do vendor** = rabbit-hole proibido pela §Regras ("nunca chutar a VM"; só confirmar na fonte
   vendorada). E (a) tem **gatilho próprio**: `VariableDeclaration.fileEqualsOffset` +
   `ForInStatement.bodyOffset` só tocam código no 1º `let` da §7.4. Decidir no ponto-de-uso, c/ o dono.

## Concessão registrada (não esquecer)
(a) NÃO é cosmética: premissa "bus error" sem lastro + risco de pass fazer trabalho morto OU faltar
2 campos. Adiar só é itaiano se **rastreado**: (a) deve viajar como item de checklist DENTRO da fatia
do 1º `let` da §7.4. Débito solto e esquecido é, ele mesmo, mágica escondida.

**Relacionadas:** [[doctrine-porta-fechada]] (P4/sem-mágica), [[doctrine-argumento-de-ausencia]]
(não chutar a VM fora do vendor), [[phase5-011-w3-review]] (a doença do repasse solto).
