---
name: doctrine-extension-declaracao-legivel
description: Doutrina de identidade — a forma de `extension` é `extension Alvo` (alvo NU, T implícito do alvo); logo o built-in precisa de uma DECLARAÇÃO legível, não de um mecanismo novo
metadata:
  type: project
---

# `extension Alvo` — e o corolário da declaração legível

**A forma (ruling do `ita-visionary`, 2026-07-15):** `extension Alvo` com **alvo NU** (nome, sem
type-args). Os genéricos vêm do alvo **por nome**, implícitos — `struct Stack<T>` + `extension Stack
{ fn push(v: T) }` (stdlib, 29× — `collections.tu:29-38`). É **design deliberado**, linhagem Swift
(a mesma do `guard let`/trailing-closure/`.variant`/memberwise-init), **não** acidente.

**A regra, em uma frase:** *"`extension` é o corpo do tipo, escrito noutro lugar — vê o que o corpo
vê."* Não há binder escondido: o binder é `struct Stack<T>`, e o leitor **pode ler**. Por isso passa
em P4.

**Why (por que reading-(a) e não `extension<T> List<T>` à la Rust):**
1. **Reading-(b) institucionaliza o privilégio que ela vinha remover** — daria `extension<T> List<T>`
   para built-in e `extension Stack` para tipo do usuário: **duas formas, e a especial é a do
   built-in**. É a face 2 de [[spec-011-identity-review]] escrita na gramática.
2. Abre especialização (`extension List<Int>`) e renomeio de binder — linguagem de tipos inteira.
   Contraria a parcimônia de ADR-0012 #7 (associated types adiados).
3. Forkaria a stdlib (29 extensions na forma-(a)) e o oracle (`ita/…/GRAMMAR.md:112`:
   `extensionDecl = "extension" IDENT …` — **IDENT, não `type`**).
> `extension List<T>` parsear hoje é **artefato**: a gramática do `ita-next` alargou `IDENT` → `type`
> (`grammar.ebnf:223`), e o `<T>` vira **referência** de tipo, não binder. Representar-como-outra-coisa
> fere P4 tanto quanto engolir ⟹ alvo com type-args é **error production** (ver [[doctrine-ast-representa]]).

**O corolário que decide tudo (Q2):** a regra **exige uma declaração para ler**. `List`/`Map`/`Option`/
`Result` são `BuiltinKind` **sem nó-decl** (`collect.dart:223-235` — *"a stdlib os usa e nunca os
declara"*) ⟹ `extension List` não é **ilegal**, é **inalcançável**. O que falta **não é mecanismo — é
a declaração de `List`**.
- **Sintetizar `generics: ['T']` no compilador FERE P4** — e a razão **não** é "o usuário não escolheu
  a letra"; é que **não haveria declaração alguma para o leitor consultar**. Nome em escopo sem binder
  visível é literalmente "código que esconde o que acontece".
- **Declarar `List<T>` em `.tu` NÃO tira ele do chão:** chão é o **corpo** (tem de tocar o Dart), não a
  **declaração**. Declaração ≠ implementação. É o Norte do Art. II (`MANIFESTO:50`).
- **Teste do privilégio (2 faces) passa POR CONSTRUÇÃO** só na forma-(a) com declaração: o mecanismo
  fica **incapaz de distinguir** built-in de tipo do usuário. É o sinal de que a regra é a certa.

**How to apply:** toda proposta de "dar membro a built-in" tem de responder **antes**: *o built-in tem
declaração legível?* Se a resposta for "não, mas o compilador sabe", é privilégio ⟹ recusar. A pergunta
"como um built-in ganha um contrato que o usuário também escreveria?" **reduz-se** a "o built-in tem
declaração?" — e ela é **uma só** para `extension List`/`.map`, `impl Iterator for List`, `for`, e os 5
hard-coded de `Option`/`Result`. Uma pergunta, **uma resposta**, no lugar que o dono já escolheu: **M5**
(ADR-0012 §C-9). Ver [[systems-low-ffi-vision]].
