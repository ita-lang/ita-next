---
name: doctrine-consenso-entre-candidatos
description: Doutrina de roteamento — ruling pendente NÃO bloqueia fix que todas as opções em aberto rejeitam; é entailment, não decisão do dono.
metadata:
  type: feedback
---

# Doutrina: ruling pendente não bloqueia o que todos os candidatos rejeitam

**Regra:** antes de mandar um bug esperar por um ruling de dono, teste-o contra **cada opção do espaço
de design em aberto**. Se **todas** rejeitam o comportamento atual, o fix é **entailment** — o dono não
tem escolha a fazer, e adiar é escolher a única resposta que nenhuma das opções defende.

**Why:** 2026-07-15, `_isSubtype` ignorando type-args (`class D : A<Int>` satisfaz `A<String>`). A
pergunta chegou como *"isto depende do ruling de variância, que está em aberto"*. **Não depende.**
Covariância licenciaria `A<Cachorro> ≤ A<Animal>` — args **relacionados** por `≤`. `Int` e `String` são
**não-relacionados**: nenhuma disciplina (co, contra, `in`/`out`, bi) licencia `A<Int> ≤ A<String>`. O
bug não era "invariância não imposta" — era **args ignorados**, insound sob toda regra candidata. O
ruling pendente era sobre a **forma da comparação**, não sobre **haver** comparação.

**How to apply:**
1. **Separe a pergunta em aberto da pergunta fechada.** Costuma haver uma fechada escondida: "*existe*
   comparação?" (fechada) vs. "*qual* comparação?" (aberta). Só a segunda espera.
2. **Enumere os candidatos e passe o caso concreto em cada um.** Se o veredicto é unânime, entailment.
3. **Consequência de forma:** isole no código o ponto onde os candidatos divergem (aqui: a comparação
   de args, hoje `==`) — é exatamente o ponto que o ruling futuro substitui. O fix fica correto agora e
   barato de trocar depois.
4. **Monotonia como desempate quando o teste não é unânime:** restringir-agora-relaxar-depois preserva
   todo programa válido; o inverso quebra. Sob ruling pendente, a restrição é o default seguro.

**Parente:** é o mesmo roteamento do copy-with × `init` de corpo ([[phase5-011-w3-review]]) —
*"entailment porque os DOIS lados são do dono ⟹ não há escolha para ele fazer"*. Ali o consenso era
entre rulings dele; aqui, entre opções futuras. Mesma conclusão: **não repassar ao dono**.

**Contraponto que evita o abuso:** o teste exige **enumerar** os candidatos, não intuir que "nenhum
funcionaria" — senão vira o vício que a [[doctrine-argumento-de-ausencia]] proíbe (afirmar ausência sem
prova). Se o espaço de design não é enumerável com honestidade, é lacuna → declarar e devolver ao dono.

Relacionadas: [[phase5-types-identity-rulings]] (R8), [[doctrine-vm-data-reinforces]].
