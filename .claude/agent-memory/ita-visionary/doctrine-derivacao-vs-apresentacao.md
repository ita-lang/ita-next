---
name: doctrine-derivacao-vs-apresentacao
description: Doutrina — "X decide o papel, não a posição" proíbe o compilador de DERIVAR da posição; não proíbe a linguagem de exigir que a posição não CONTRADIGA o papel.
metadata:
  type: feedback
---

# Doutrina: derivação × apresentação

**Regra:** quando um ruling diz *"o papel vem de X, não da posição"*, ele governa a **DERIVAÇÃO**
(como o compilador descobre o papel) — **não a APRESENTAÇÃO** (o que a fonte pode escrever). Exigir
que a posição **concorde** com o papel derivado não contradiz o ruling: o **completa**.

**Why:** nasceu do ruling do dono de 2026-07-15 (*"o papel vem do KIND, não da posição"*, em
`class D : A, B`) contra a cerca `class-after-trait` ("superclasse primeiro ou em lugar nenhum"). A
leitura ingênua vê contradição — "ele acabou de dizer que a posição não manda". É category error:
- **Derivação:** o compilador não pode **inferir** papel da posição (era o bug — `class Pato : Voa`
  com `Voa` trait dava `superclass-not-a-class`, e classe-que-conforma-sem-herdar era inexprimível).
- **Apresentação:** a fonte não pode **contradizer**, na posição, o papel que o kind já deu.
A cerca **só é enunciável porque a derivação por kind é verdadeira** — é preciso o kind para saber se
a posição 1 é superclasse. Uma depende da outra; não competem.

**Teste que acompanha (P4):** a apresentação é justificada quando a forma livre deixaria a **leitura
natural mais provável ERRADA e sem correção**. `class Dog : Barker, Animal` com ordem livre convida
a ler `Barker` como superclasse — toda linguagem da família `:` põe a superclasse primeiro. Forma que
torna a leitura natural correta é P4-positiva.

**How to apply:** ao receber "isto contradiz o ruling do dono de que Y decide, não a posição?" —
pergunte **qual dos dois lados** o ruling tocou. Se ele consertou o compilador e a proposta conserta o
leitor, são o mesmo argumento aplicado duas vezes, não um contra o outro. Sinal de que a distinção
está em jogo: a proposta é **enunciável apenas se** o ruling for verdadeiro.

**Cuidado que veio junto:** a justificativa da cerca vinha **superestimada** no comentário ("saber se
herda exigiria olhar o kind dos três") — a posição 1 dá *"os demais NÃO são superclasse"*, não *"herda
de alguém"*. O ganho honesto é **busca de N arquivos → 1**. Mesma forma do `override` (aponta, não
responde). Justificativa superestimada em comentário é semente de decisão errada futura — corrigir
mesmo quando o veredicto se mantém.

Relacionadas: [[phase5-types-identity-rulings]] (R7), [[phase5-011-w3-review]] (a doutrina do
`override`/cerimônia — que aqui **não** se aplica direto: fala de *marca*, e a cerca não põe glifo).
