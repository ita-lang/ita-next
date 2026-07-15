# Spec 006: Preparar a Fase 3 — `where`-expr + operadores tipados

> **Tipo:** feature-sintaxe + decisão-de-linguagem · **Marco:** `Fase 2 → 3 (preparação)`
> **Status:** `draft`
> **Autor / Data:** orquestração (Claude) · 2026-07-11 · **Issue/PR:** revisão de identidade `ita-visionary` 2026-07-11 (#4 + tensão `op:string`)

## §0 Metadados

- **Classe da mudança:**
  - [x] **Nova construção** — nó `WhereExpr` (nível 0 da cascata).
  - [x] **Nova regra/fase** — migração de `Binary`/`Unary`/`Assign` de `op:string` para enum fechado (exaustividade em todas as fases seguintes).
- **Fases tocadas:** [ ] Léxico · [x] Sintaxe (§3) · [ ] Formal · [x] SDD/modelagem (§5) · [ ] Fluxo · [ ] Codegen · [ ] Runtime
- **Princípios afetados:** P3 (tudo é expressão + leitura top-down — `where`), P4 (sem mágica — exaustividade de `switch`, o oposto de string livre). **Nenhum princípio permanente alterado.**

### §0.5 Constitution check

O `ita-visionary` (revisão 2026-07-11) listou o `WhereExpr` como alvo explícito do desugaring (ADR-0011) e recomendou a migração de operadores para enum fechado *antes* da Fase 3 ("a fase mais açucarada operando sobre o tipo menos seguro"). Ambas preenchem o que os princípios já pedem; nenhuma altera a constituição. **Sem conflito aberto.** Code review de identidade pós-implementação fecha o ciclo.

## §1 Motivação e resumo

Duas mudanças que **destravam a Fase 3** (desugaring/semântica) sem tocar codegen:
1. **`where`-expr** (P3): a forma itaiana de "bindings-depois-do-valor" — leitura top-down (o *quê* antes do *como*). É alvo nomeado do desugaring na ADR-0011; **sem o nó, a Fase 3 não tem entrada para baixá-lo**.
2. **Operadores tipados** (P4): `Binary`/`Unary`/`Assign` guardam o operador como **string livre**, furando a exaustividade que o resto da AST garante via `sealed`. O desugaring (Fase 3) é o primeiro a fazer `switch` sobre `|>`/`??`/`?` — migrar para enum fechado restaura o erro-de-compilação ao esquecer um caso.

**Antes → Depois** (exemplo mínimo em `.tu`):

```tu
// antes:
let r = { let a = 1; let b = 2; a + b }   // bloco-nu não é expr (Q1) — sem forma top-down
// e internamente: Binary("+", …) — op é string, switch não-exaustivo
```

```tu
// depois:
let r = a + b where {                       // value primeiro, bindings depois (P3)
  let a = 1
  let b = 2
}
// e internamente: Binary(BinaryOp.add, …) — enum fechado, switch exaustivo (P4)
```

**Não-objetivos:** (1) desugaring/semântica do `where` (escopo, resolução, checagem de pureza) — é Fase 3; aqui só o **nó** e o **parse**. (2) Migrar o **dump** — o símbolo (`+`, `??`) continua sendo a tag do S-expr (goldens inalterados). (3) `where`-clause de genéricos (`T: A + B` já é `bounds`; não confundir). (4) Operadores custom (`operator` decl — spec anterior).

---

## §3 Sintaxe — `[cap 4.2–4.3]`

### 3.1 Produções novas/alteradas

**(a) `where`-expr (nível 0 da cascata — o mais frouxo):**

```
expression   ::= whereExpr
whereExpr    ::= assignment ( "where" "{" ( letStmt ";"? )+ "}" )?
```
Nó novo: `WhereExpr(expr value, stmt* bindings)` — `value` = a `assignment` à esquerda; `bindings` = os `let` do bloco (o parser só aceita `let`/`var`; outro statement → `parse-error: where-binding-not-let`). Sem `where` → a produção devolve o `assignment` direto (nenhum `WhereExpr`; não regride).

### 3.2 Precedência e associatividade
`where` é o **nível 0** (mais frouxo de todos) — liga por último. `a + b where {…}` tem `value = (a + b)`. Um único `where` por expressão (não-associativo; `where` seguido de `where` é erro).

### 3.3 Ambiguidade
`where` é keyword reservada (já no léxico). O `{` após `where` é sempre bloco-de-bindings (não map/closure) — posição inequívoca. Não colide com o `where` de bounds de genérico (que não existe como cláusula separada — bounds são inline em `genericParam`).

### 3.4 Adequação ao parser descendente
`whereExpr ::= assignment ( "where" … )?` é LL(1) (o `where` opcional é decidido por `_check(kwWhere)`). Sem recursão à esquerda.

### 3.6 O que sobra para a semântica (Fase 3)
- **Desugaring** (ADR-0011): `V where { let x = e; … }` baixa para o equivalente de um `let`-block que avalia os bindings e então `V` (ordem de avaliação = dependência, não textual). Alvo nomeado da Fase 3.
- **Pureza** dos bindings (ruling §10): a Fase 3 rejeita bindings com efeito observável.
- **Escopo:** os bindings visíveis **apenas** na `value` (e entre si) — resolução na Fase 4 (binding).

## §5 SDD / modelagem — operadores tipados `[cap 5.1]`

Migração de `op: string` → enum fechado nos três nós de operador. O **dump não muda** (uma função mapeia enum → símbolo). Restaura exaustividade (CI 5.2.1) para as fases 3–7.

- **`Binary(binaryOp op, expr left, expr right)`** — `binaryOp = Add | Sub | Mul | Div | Mod | Pow | Eq | Ne | Lt | Gt | Le | Ge | And | Or | Coalesce | Pipe | Compose`.
  Tags de dump: `+ - * / % ** == != < > <= >= && || ?? |> >>` (respectivamente).
- **`Unary(unaryOp op, expr operand)`** — `unaryOp = Neg | Not`. Tags: `neg` (`-`), `!`. (`await`/`spawn`/`panic` seguem nós próprios — não migram.)
- **`Assign(assignOp op, expr target, expr value)`** — `assignOp = Assign | AddAssign | SubAssign | MulAssign | DivAssign`. Tags: `= += -= *= /=`.

O parser converte o `Tag` do token → variante do enum no ponto de construção; o printer converte enum → símbolo. **Nenhum símbolo cru sobrevive na AST.**

---

## §9 Checklist de completude (Apêndice A)

- [ ] `parser` — `whereExpr` (nível 0); conversão `Tag`→enum em cada operador; sem recursão à esquerda `[A.8]`
- [ ] `inter` — `WhereExpr` nova classe `sealed`; `binaryOp`/`unaryOp`/`assignOp` enums fechados `[A.5]`
- [ ] `ast.asdl` ↔ `ast.dart` em sincronia (à mão, P11)
- [ ] `ast_printer` — mapeamento enum→símbolo; **dump byte-idêntico aos goldens existentes**
- [ ] `grammar.ebnf` §Syntactic — `whereExpr` no nível 0
- [ ] corpus + unit cobrem `where` e a exaustividade dos operadores
- [ ] `dart analyze` limpo; `make test` verde (incl. **todos os goldens antigos inalterados**)

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** Não. `where` só amplia; a migração de operadores é interna (dump preservado) — nenhum golden muda.
- **Rulings de dono cravados (Frente C):**
  - **`where`:** o parser aceita `let`/`var` bindings (representa); a **pureza** (rejeitar `var`, exigir bindings sem efeito) e o escopo (só a expressão-valor) são impostos na **Fase 3** — ruling de dono 2026-07-11 ("representar e deferir": AST representa, não valida). Erro de parse só para statement não-binding (`where-expects-binding`).
- **Alternativas descartadas:** manter `op:string` (perde exaustividade — o defeito que a migração corrige); `where` como statement (contra P3 — `where` é sobre render um valor, não sequência de efeitos); bloco-nu como expr (viola RD-1 / Q1).

## §11 Critérios de aceite (viram casos de conformância)

- **CA1** — `let r = total where { let total = a + b\n let a = 1\n let b = 2 }` ⟶ `(let (bind "r") (where (id total) (let (bind "total") (+ (id a) (id b))) (let (bind "a") (int 1)) (let (bind "b") (int 2))))`.
- **CA2** — `let r = a + b` (sem `where`) ⟶ `(let (bind "r") (+ (id a) (id b)))` — nenhum `WhereExpr` (não regride).
- **CA3** — `where` com statement não-binding (`x where { y + 1 }`) ⟶ `parse-error: where-expects-binding` com span. (`var` no bloco é aceito no parse; pureza é Fase 3.)
- **CA4** — `2 + 3 * 4` ⟶ dump `(+ (int 2) (* (int 3) (int 4)))` **byte-idêntico ao golden atual** (migração de enum é invisível ao dump).
- **CA5** — exaustividade: um `switch` sobre `binaryOp`/`unaryOp`/`assignOp` sem `default` compila (todos os casos cobertos) — verificado por um teste que constrói cada variante.

## §7-nota — preparação Fase 3 (não é codegen)
`WhereExpr` e os enums de operador são consumidos pelo **desugaring (Fase 3, ADR-0011)**, não pelo codegen. Nenhuma emissão de Kernel nesta spec. O `dart-vm-expert` (review 2026-07-11) confirmou forward-compat (0 edições) — `WhereExpr` → `BlockExpression`/`Let`-chain do Kernel; o enum **evita** a confusão perigosa de `op:string ">>"` (compose ≠ bit-shift). Débitos de **codegen (Fase 7)**:
1. `WhereExpr` → `Let`-chain ou `BlockExpression`, **em ordem de dependência** (sort topológico é Fase 3; não é campo do nó).
2. Operadores sem operador-Kernel → desugar/call: `pipe`→`f(x)`, `compose`→closure, `coalesce`→`Let`+null-check, `pow`→`StaticInvocation`, `eq/ne`→`EqualsCall`, `and/or`→`LogicalExpression`.
3. Compound-assign (`+=`) → get+op+set com **single-eval** de receptor/índice via `Let`-hoist (`target` preservado como `Expr`).
4. Paridade VM×JS (ADR-0005): `pow`/bitwise carregam a preocupação numérica usual (spec 001); `>>` compose = closure pura, sem risco.

## Definition of Done

- [ ] CAs cobertos por casos `.tu`→`.ast` (CA1/CA2/CA4) + `// EXPECT` (CA3) + unit (CA5), verdes.
- [ ] `WhereExpr` + enums materializados à mão a partir do ASDL (P11).
- [ ] **Todos os goldens da spec 001–005 inalterados** (dump preservado).
- [ ] `grammar.ebnf` reconciliada; Constitution check sem conflito + code review de identidade aplicado.
- [ ] `make test` + `dart analyze` verdes.
