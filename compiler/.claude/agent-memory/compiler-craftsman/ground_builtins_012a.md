---
name: ground-builtins-012a
description: Review adversarial W3 do CHÃO dos built-ins (spec 012 LT-012a — .length/[]/+). Sound, mas o chão só alcança receptor TIPADO; literal de coleção nu não sinta.
metadata:
  type: project
---

# LT-012a (spec 012) — o CHÃO dos built-ins na F5: veredito do ataque W3

`.length`/`[]`/`+` de List/Map/String na F5 (`check.dart`). Codegen gated pelo pin.
**Veredito: 🟢 sound** — sem furo de soundness nem crash. `_synthInner`(778-806),
`_index`(1827-1847), `_binary` list-branch(1694-1700), `_groundShape/_groundField`(1808-1820),
`_member` ground(1876-1877). Dragon 6.3.6 (.length=record→Int) / 6.5.1 (`[]`=array→t).

**Why (o que provei certo):** nº1 total (I2, `flow.dart:186` `_typeOf` falha-alta) resiste — `_index`
sinta receptor+índice em TODOS os ramos, `_check`/`_synth` sempre gravam. Condição 2 da doutrina do
chão (nunca `dynamic`) é ESTRUTURAL: este rewrite não tem `DynamicType`/`UnknownType`; miss → `_lookup`
(`recv is! NamedType → null`, 1993) → `unknown-member`. `optional(args[1])` colapsa `V??=V?`. Tabela
genuinamente fechada (só `.length`).

**How to apply — os 5 furos (nenhum é soundness):**
1. **🟠 O CHÃO SÓ ALCANÇA RECEPTOR TIPADO.** `ast.ListExpr`/`ast.MapExpr` NÃO têm caso em
   `_synthInner` → `cannot-infer`. Não são desugarados (sobrevivem, `desugar.dart:289`). `_check`
   só trata coleção VAZIA (2122); não-vazia cai em `_synth`→cannot-infer. Logo `[1,2,3].length`,
   `[1]+[2]`, `[1][0]` NÃO tipam no F5 → **CA1/CA2/CA3/CA9/CA10 da spec (todas literais) não são
   demonstráveis**. A suíte `check_test.dart:1878+` CONTORNA com param (`fn f(xs:List<Int>)`).
   String literal FUNCIONA (`ast.Str` está no switch) → só List/Map falham. Depende da fatia C
   (inferência de literal de coleção). NÃO deixar o pin de codegen assumir `[1,2,3].length` compila.
2. **🟠 `+` diverge da §4.3.** Regra é `ys ⇐ List<E>` (CHECK); código faz `_synth(n.right)`+`l==r`
   (1677/1697) → `xs + []` dá cannot-infer (o `⇐` tiparia via ramo vazio do `_check`). Conserto:
   `_check(n.right, l)`.
3. **🟡 `_index` sobre `OptionalType` → `unknown-member`** (não tem ramo optional) — inconsistente
   com `_member` que dá `member-on-optional` (1866). Viola `diagnostico-nunca-mente`. Espelhar a guarda.
4. **🟠 Deleção TOTAL do gate reclassifica `.map`/`.filter`/`.add` → `unknown-member`.** Reabre a
   mentira que a 011 §4.7 criou `builtin-member-unsupported` p/ evitar (*"unknown-member seria FALSO
   — o membro existe"*). RULING-BACKED (spec 012 §0.5-W0/§4.6/CA5 blessed), então FIEL, não bug —
   mas a reconciliação c/ 011 §4.7 não foi feita. Lacuna p/ dono/visionary.
5. **🟡 `xs[[]]` (lista vazia como índice) → `Int` silencioso.** Raiz PRÉ-EXISTENTE no `_check`
   ramo vazio (2122, não valida `expected` ser coleção; `let x:Int=[]` idem); `_index` só dá entrada
   nova. Fora do escopo 012.

Detalhe completo: só na resposta do review (não escrevi report .md). Fonte: Dragon 6.3.6/6.5.1;
doutrina do chão (spec 010 §4.6.1, 3 condições); 011 §4.7 (`builtin-member-unsupported`).
