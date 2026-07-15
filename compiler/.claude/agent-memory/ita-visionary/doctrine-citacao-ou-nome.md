---
name: doctrine-citacao-ou-nome
description: Doutrina anti-ruling-fabricado — a DATA não é fonte (aponta p/ conversa não-commitada); cite artefato (ADR-NNNN §X / spec NNN §X) ou assine com teu nome. Autoridade custa citação; opinião é grátis.
metadata:
  type: feedback
---

# "Cite o artefato, ou assina" — a cerca contra o ruling fabricado

**A regra:** `ruling do dono` só é escrevível com ponteiro para **artefato** (`ADR-NNNN §X` ou
`spec NNN §X`). **Uma DATA não é fonte.** Toda outra conclusão leva o **nome de quem a tirou**
(`ruling ita-visionary`, `entailment — não gasta ruling`) ou vira `⚠️ Ao dono:` / `lacuna declarada`.

**Why:** 3 fabricações numa sessão (2026-07-15). `type.dart:272` afirmava *"memberwise é sempre
chamado por label (**ruling do dono 2026-07-15**)"* — ruling **inexistente**, conclusão do
`compiler-craftsman` escrita na voz do dono. Auditei o registro inteiro: **toda citação com `§` que
testei se verifica em 1 grep; as 2 que testei sem `§` (só data) NÃO EXISTEM no registro**
(`collect.dart:164` *"papel vem do KIND"*, `:197` *"trait é FOLHA"* — grep vazio em `specs/` e
`adr/`; podem ser reais, mas são **inauditáveis**). A data aponta para uma **conversa que não é
artefato do repo** — citação a um lugar aonde o leitor não pode ir. Inverificável + autoritativo =
a definição do defeito. **A data é o vetor**, e o fabricado vestia roupa idêntica à do real.

**O ponto que quase ninguém vê:** ruling fabricado é **invisível a todo teste** — goldens, CI, MCP
`ita` — porque o código se comporta igual com ou sem o ruling. É a única classe de defeito a que o
**Art. IV-1** (*"nunca chutar comportamento"* + MCP como verificador) é **cega por construção**.
Por isso passou 3×.

**NÃO é P4** (dizer que é seria a mesma doença — esticar o Art. I sobre território que ele não
reivindica; Art. I §15-17 legisla *"princípios permanentes **da linguagem**"*, e comentário não é a
linguagem). É **Art. IV** (*"como se trabalha no Itá"*, *"vinculam qualquer sessão/agente"*), que
evolui pela **via barata** (Governança §84: *"specs podem propor ajustes operacionais"*) — **não
exige emenda do Art. I**. P4 é a **analogia diagnóstica**, não a autoridade.

**How to apply:** o vocabulário de 3 estados **já existe** no código, inventado organicamente —
não inventar outro: (1) `ruling do dono §X` = ratificado; (2) `ruling ita-visionary` /
`entailment — não gasta ruling` (`collect.dart:923`, `:955`, `check.dart:741`) / `doutrina do
ita-visionary` (ADR-0013:23, *"reforça; não fundamenta"*) = derivado, **contestável por
construção**; (3) `⚠️ Ao dono:` (`collect.dart:88`) / `Ruling §12-B3 PENDENTE` (`:432`) /
`lacuna declarada` (`type.dart:284`) = em aberto. A falha nunca foi falta de vocabulário — é que
(1) e (2) são **tipograficamente confundíveis** e ninguém policia. **A assimetria é o design:
autoridade custa citação, opinião é grátis** — porque o valor do ruling fabricado é exatamente sua
**infalsificabilidade**; sem a atribuição, a mesma frase vira opinião que o próximo leitor contesta
de graça.

**O que a cerca NÃO pega (declarar sempre):** fabricação por **§ errado** (a 2ª desta sessão —
*"label PARTICIPA do `==` de assinatura"*, atribuída à spec 011, que **não diz isso**: os únicos
`label` lá são §12-4 *"default params + labels"* e a tabela `P(zz: 9) → sem erro`). Lint de
ponteiro não lê conteúdo. **O ganho real não é detectar mentira — é tornar a mentira checável em
1 grep** (custo de checar `spec 011 §12` = um grep; custo de checar `2026-07-15` = infinito).
Risco nomeado: exigir citação converte fabricação-por-data em fabricação-por-§-errado, que
*parece* mais legítima — mas é refutável em 1 grep, e inrefutável perde para refutável.

**As duas faces novas (2026-07-15, crivo das 5 decisões) — a doutrina precisava das duas:**
1. **Fabricação de 2ª ordem: a confissão fabricou.** `type.dart:280` — *"O que **é** ruling do dono:
   'ordem obrigatória, defaults saltáveis…'"* — no comentário que denuncia a 1ª fabricação. O sítio
   que a implementa (`check.dart:1245-1252`) atribui certo: ruling do dono = a **meta-diretriz
   Swift**; "ordem obrigatória" é a **aplicação** dela (*"Seguimos o Swift"*). **Promover derivação a
   ruling é o mesmo ato**, e ele reincide no gesto de o corrigir. ⟹ a cerca tem de valer para
   `ruling do dono` que **conclui a partir de** ruling real, não só para o inventado do nada.
2. **A auditoria fabrica a própria prova.** A proposta de lint (2026-07-15) alegou *"`tools/` nem é
   diretório; nenhum existe"* — **`ita-next/tools/pin-dart.sh` e `dart-sdk.pin` existem** (olhou em
   `compiler/tools/`). Dentro da proposta de parar de fabricar. **Corolário:** *"eu medi"* é uma
   afirmação de autoridade como qualquer outra — **custa o comando/caminho, ou vale o mesmo que
   opinião.** A cerca vale para o auditor.

**Item novo de citável:** a **meta-diretriz Swift** (2026-07-15, *"se tiver divergência ou indecisão,
a maneira que o Swift trabalha é a diretriz"*) é **ruling real do dono e inauditável** — só data, em
`check.dart:1247`, `collect.dart:444` e nesta memória. É **entrada obrigatória do ADR-0014**: sem ela
assentada, todo sítio que se apoia nela cai no lint, e são justamente os que decidem o label.

Ver [[f5-consolidacao-identity-review]] (item 1, a fabricação original), [[crivo-5-decisoes-identity-review]]
(as 3 desta rodada + a ordem) e [[doctrine-ast-representa]] (a outra doutrina que governa por lente,
não por caso).
