---
paths:
  - "codegen/**"
  - "compiler/lib/**"
  - "tools/**"
---

# R5 · R12 · R13 — o gate, o passe e a mensagem

As três formas de uma verificação ficar verde sem verificar: aprovando o que não conhece (R5),
não se aplicando a nada (R12), ou sendo indistinguível de outra (R13).

## R5 — Gate estrutural é visitor que FALHA no desconhecido

Nunca lista-branca de sítios. `RecursiveVisitor.defaultNode` **desce e cala** ⟹ nó novo é
aprovado em silêncio, e o conjunto de nós vem de um pacote **externo e versionado**. Um gate cuja
falha-padrão é "OK" é documentação executável do que alguém lembrou.

Use `VisitorThrowingMixin` (`pkg/kernel/lib/visitor.dart:1868`) ou `implements Visitor<void>`.
**Todo gate novo nasce com um RED que ele efetivamente pega.**

⚠️ `verifyComponent` é *well-formedness*, **não** type-checking (`verifier.dart:127-129`, verbatim).
Não detecta `dynamic` indevido, tipo estático errado, nem `interfaceTarget` de classe errada.
Não o cite como evidência de correção. E o invariante da F7 **não roda no `itac build`** —
`compile.dart` não importa `invariants.dart`.

## R12 — Passe ou gate que não se aplica a nada é DECLARADO, não silencioso

Um passe com 0 aplicações é indistinguível de um passe removido — e acumula tick
verde para sempre. Medido: o `LocalFunctionIdAssigner` roda duas passadas por
fixture sobre 5621 nós e altera **zero**; o mutante que o tirava do caminho de
produção sobreviveu à suíte inteira.

Todo passe conta aplicações; o runner imprime o número; passe vacuoso entra numa
lista com **razão escrita e a fatia que o fecha**. A lista é catraca nos dois
sentidos: fora dela com 0 aplicações reprova, dentro dela aplicando também
reprova. Sem a segunda metade, a lista vira silenciador permanente.

O mesmo vale para o corpus: `checkOrderIndependence` devolve `exercitou`, porque
**11 dos 36 fixtures têm uma declaração só** e imprimiam o mesmo ✓ dos outros —
afirmando o letrec sem ter o que permutar.

## R13 — Dois caminhos não podem dizer a mesma frase

Duas guardas com a mesma mensagem são indistinguíveis no relatório **e na
asserção**. Foi assim que uma anti-vacuidade ficou inalcançável por dias: o RED
assertava `contains('não testou nada')`, que casava com os dois sítios, e atingia
sempre o primeiro. Nenhuma cobertura de linha pega isso — a linha do teste
executa, a asserção passa, e o caminho que ela deveria cobrir nunca roda.

`make assertions` acha duplicata na fonte. Sufixo `-A`/`-B` basta.
