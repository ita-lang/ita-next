---
name: doctrine-porta-fechada
description: Doutrina — o pecado não é "duas portas para o tipo"; é o COMPILADOR abrir uma porta que o usuário fechou. Reformulação da razão 3 do ban de copy-with (ADR-0012 #1).
metadata:
  type: project
---

# Doutrina: o compilador não abre porta que o usuário fechou

Cravada em 2026-07-15, no W0 do achado "F5 licencia programa inemitível" (copy-with × `struct` com
`init` de corpo). É a **reformulação da razão 3** do dono (ADR-0012 #1, *"copy-with bypassa o `init`
⟹ porta dos fundos para o invariante que o `init` existe para guardar"*).

## O enunciado
**Não é "um tipo tem de ter uma porta só".** O usuário pode abrir quantas quiser — `init` em
`extension`, fn factory, memberwise. **O pecado é o COMPILADOR abrir uma que o usuário fechou.**

- Escrever `init` no CORPO **é o ato de fechar** a porta all-fields (Swift, ratificado pelo dono
  2026-07-15: *"você pode estar fazendo trabalho especial que o default desconhece"*).
- Sintetizar um all-fields privado por baixo **desfaz o ato**, em silêncio, noutro arquivo.
- `init` em `extension` **preserva** o memberwise e **não** é hipocrisia: a porta all-fields segue
  aberta porque o usuário **nunca a fechou**. O glifo `extension` diz *"estou ADICIONANDO"*.

## Por que importa (o que a reformulação corrige)
1. **A razão 3 nunca foi sobre `class`.** Seu domínio real é **"tipo sem memberwise"**, que corta os
   dois kinds: `class` está 100% dentro (ruling do dono: class nunca ganha memberwise); `struct` com
   `init` de corpo **também está**. Razões 1 (identidade sem glifo) e 2 (slicing) seguem de pé e
   **independentes** — são reforço, não a parede mestra ([[doctrine-vm-data-reinforces]]).
2. **Mesma forma do teste de privilégio** ([[phase5-builtin-members-chao-vs-biblioteca]]): *"o pecado
   não é de onde vem a informação — é o que o usuário não alcança"*. Aqui: não é haver duas portas —
   é **quem as abre**.

**Relacionadas:** [[phase5-011-w3-review]] (o ruling concreto que ela decidiu), ADR-0012 #1.
