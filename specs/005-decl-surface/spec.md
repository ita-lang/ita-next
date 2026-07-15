# Spec 005: Completar a superfície declarativa da Fase 2

> **Tipo:** feature-sintaxe · **Marco:** `Fase 2 (Sintaxe → AST)`
> **Status:** `draft`
> **Autor / Data:** orquestração (Claude) · 2026-07-11 · **Issue/PR:** revisão de identidade `ita-visionary` 2026-07-11

## §0 Metadados

- **Classe da mudança** (Apêndice A):
  - [x] **Nova construção** — adiciona/estende classes de nó da AST (`InitDecl`; campos em `GuardLetStmt`/`StructDecl`/`ClassDecl`/`ExtensionDecl`).
  - [ ] Nova regra/fase.
- **Fases tocadas:**
  - [ ] Léxico (§2) · [x] Sintaxe (§3) · [ ] Formal/Tipos (§4) · [ ] SDD · [ ] Fluxo · [ ] Codegen · [ ] Runtime
- **Princípios do Itá afetados:** P2 (valor vs. referência — `struct` memberwise vs. `class` com `init`), P5 (funcional-first, OO quando faz sentido — `init`/traits), P4 (sem mágica — a AST representa, não esconde). **Nenhum princípio permanente é alterado** (veredito `ita-visionary`, revisão 2026-07-11).

### §0.5 Constitution check

O `ita-visionary` avaliou as quatro construções na revisão de identidade de 2026-07-11 e vereditou: *"nenhuma delas altera princípio permanente, então não exigem emenda da constituição; são preenchimento da superfície que os princípios já pedem"*. As decisões de dono associadas foram cravadas (ver §10). **Sem conflito aberto.** O code review de identidade pós-implementação (Art. IV) fecha o ciclo.

## §1 Motivação e resumo

A Fase 2 (Sintaxe → AST) está completa, mas a revisão de identidade apontou **quatro lacunas na superfície declarativa** que o oracle `ita/` já exercita e que a Fase 2 do `ita-next` ainda não representa. São todas sintáticas (parser + AST + gramática), sem codegen. Fechá-las completa a paridade declarativa com o oracle antes da semântica (Fase 3).

**Antes → Depois** (exemplo mínimo em `.tu`):

```tu
// antes — não representável na Fase 2 do ita-next:
class Animal {
  init(name: String) { self.name = name }   // `init` = parse-error (boundary sem handler)
}
struct Point: Eq { x: Int, y: Int }          // ": Eq" (conformance inline) = parse-error
guard let v = opt && v > 0 else { return }   // "&& v > 0" descartado silenciosamente
```

```tu
// depois — todas representáveis, com nós/campos próprios na AST:
class Animal { init(name: String) { self.name = name } }  // (class … (init (params …) (block …)))
struct Point: Eq { x: Int, y: Int }                       // StructDecl.traits = [Eq]
guard let v = opt && v > 0 else { return }                // GuardLetStmt.condition = (> v 0)
```

**Não-objetivos:** (1) validação semântica — checar que o trait existe, que `struct` não deveria ter `init` explícito, ou que a superclasse é uma `class`, é **Fase 3** ("AST representa, não valida"). (2) Codegen — nenhuma emissão de Kernel. (3) O `where`/operadores-tipados (spec 006). (4) Conformance genérica com bounds (`impl<T> …`) além do já modelado.

---

## §3 Sintaxe — `[cap 4.2–4.3]`

### 3.1 Produções novas/alteradas (W3C EBNF, dialeto do `grammar.ebnf`)

**(a) `init` — construtor** (nova produção + variante de nó):

```
member       ::= "pub"? ( ("async"|"stream")? fnDecl | initDecl | field )
initDecl     ::= "init" "(" paramList ")" block
```
Nó novo: `InitDecl(param* params, block body)` no sum `decl` (com `attributes (offset, length)`).

**(b) `guard let … && cond`** (campo novo):

```
guardStmt    ::= "guard" ( "let" pattern "=" pipeNoAnd ( "&&" expression )?
                         | expression ) "else" block
pipeNoAnd    ::= pipe   (* nível 2, com o `&&` de NÍVEL-TOPO reservado ao refino *)
```
Nó: `GuardLetStmt(pattern target, expr value, expr? condition, block orElse)` — `condition` é o `&&`-refino opcional. **Ruling de dono (2026-07-11): split no PRIMEIRO `&&`** — o `value` (opcional a desembrulhar) para no 1º `&&`; o `condition` é todo o refino restante. Ex.: `opt && c1 && c2` → `value = opt`, `condition = (c1 && c2)`. Alinha com a intenção "desembrulha o opcional, depois refina".

**Correção (2026-07-14, ruling de dono).** O `value` era parseado como `equality` (nível 6) para parar no `&&`. Isso o deixava também ABAIXO de `??`/`||`/`|>`/`>>`, que então **não parseavam no valor**: `guard let v = a ?? b else { … }` virava `error-stmt` — e `??` é operador central do Itá (P7). O `value` passou a ser `pipeNoAnd` = a produção `pipe` (nível 2) com o `&&` de nível-topo reservado ao refino via **parse contextual** (flag `_stopAtTopLevelAnd`, resetada em `_expression()` — a técnica do "no-struct-literal" do Rust), sem nível novo na cascata. O split no 1º `&&` segue preservado, e o `&&` volta a ser operador normal dentro de qualquer delimitador:

```
guard let v = a ?? b && c   → value = (a ?? b),  condition = c
guard let v = a && b && c   → value = a,         condition = (b && c)
guard let v = (a && b)      → value = (a && b),  condition = ausente
guard let v = f(a && b)     → value = f(a && b), condition = ausente
```

**(c) Conformances inline** (listas de trait):

```
structDecl    ::= "struct" IDENT genericParams? ( ":" type ( "," type )* )? typeBody
classDecl     ::= "class"  IDENT genericParams? ( ":" type ( "," type )* )? typeBody
extensionDecl ::= "extension" type            ( ":" type ( "," type )* )? typeBody
```
- `struct`/`extension`: todos os `type` após `:` são **traits** → `StructDecl(…, type* traits, …)`, `ExtensionDecl(type target, type* traits, …)`.
- `class`: o **1º** `type` após `:` é a **superclasse**; do 2º em diante são **traits** (regra do oracle `GRAMMAR.md §2`) → `ClassDecl(…, type? superclass, type* traits, …)`.

**(d) Reconciliação `grammar.ebnf` ↔ parser** (o parser vence — o `grammar.ebnf` estava desatualizado, não o parser):

```
enumMember   ::= "pub"? ("async"|"stream")? fnDecl | enumCase ( "," | ";" )?
operatorDecl ::= "operator" OPSYM "(" paramList ")" "->" type
                 ( "precedence" INT ("left"|"right")? )? block     (* assoc: JÁ no modelo — remove (DEFER) *)
```

### 3.2 Precedência e associatividade
Nenhuma expressão nova na cascata. O `&&` do `guard let` (b) é uma `expression` completa após o `=` — reusa a cascata existente (nível 5, `and`), sem novo nível. O `pipeNoAnd` do `value` (correção 2026-07-14) também **não** é nível novo: é a produção `pipe` sob um flag de contexto que só impede o `&&` de nível-topo; a precedência de todos os operadores fica intacta.

### 3.3 Ambiguidade
- **(a) `init`**: `init` é keyword reservada; `initDecl` só casa em posição de `member`. Sem ambiguidade com chamada de função (não há receptor).
- **(c) conformances**: o `:` após o nome do tipo é inequívoco (não há outra produção com `IDENT genericParams? ":"` em posição de declaração). O parser de `class` distingue superclasse (1ª) de trait (demais) por posição, sem lookahead.

### 3.4 Adequação ao parser descendente
Todas as produções são LL(1) por FIRST-set. `initDecl` entra no despacho de `_member` por `Tag.kwInit` (k=1). A lista de conformances é um laço `( "," type )*` — sem recursão à esquerda.

### 3.5 Reconciliação
- `grammar.ebnf` §8 (`member`, `enumMember`, `structDecl`, `classDecl`, `extensionDecl`, `operatorDecl`) atualizada; remover marcas `(DEFER)` de conformance e de `assoc`.
- `ast.asdl`: `+ InitDecl`; `GuardLetStmt += expr? condition`; `StructDecl/ExtensionDecl += type* traits`; `ClassDecl += type* traits` (já tem `superclass`).
- Delta tree-sitter (`tree-sitter-ita`) fica fora de escopo (registrar em `grammar-delta`, como spec 004).

### 3.6 O que sobra para a semântica (Fase 3)
Restrições **não** expressáveis por CFG, deferidas ao binder/type-checker:
- `struct` com `init` explícito → a política itaiana é memberwise sintetizado; a Fase 3 decide entre sintetizar/avisar/rejeitar (ruling §10).
- Superclasse de `class` deve ser uma `class` (não trait); traits devem existir e ser traits.
- `condition` do `guard let` deve ser `Bool` e pode referenciar o binding recém-desembrulhado.

---

## §9 Checklist de completude (Apêndice A)

- [ ] `parser` — `initDecl`, guard-let `condition`, listas de conformance, sem recursão à esquerda `[A.8]`
- [ ] `inter` — `InitDecl` é nova classe de nó `sealed` (dump determinístico) `[A.5]`
- [ ] `ast.asdl` ↔ `ast.dart` em sincronia (materialização à mão, P11)
- [ ] `grammar.ebnf` §Syntactic reconciliada; `GRAMMAR.md` como referência
- [ ] **corpus de conformância** cobre os casos novos (`.tu` → `.ast`)
- [ ] `dart analyze` limpo; `make test` verde

## §10 Compatibilidade, migração e alternativas

- **Breaking change?** Não. Só **amplia** o que parseia; nenhum `.tu` válido hoje muda de árvore.
- **Rulings de dono cravados** (parte da Frente C):
  - **`init`:** `struct` = construtor **memberwise sintetizado** (sem `init` explícito, concisão); `class` = `init` **explícito** quando há estado a validar/normalizar. O parser aceita `InitDecl` nos corpos roteados por `_typeBody` (struct/class/trait/extension/actor/impl); `enum` tem corpo próprio (`enumMember`) e **não** despacha `init`. `pub init` é preservado na AST (B1); a política por-kind (memberwise vs. explícito) e de visibilidade é da Fase 3.
  - **Conformances:** **inline** (`struct P: Trait`) **e** `impl Trait for T` coexistem — declaração-de-intenção vs. retrofit.
- **Alternativas descartadas:** exigir `init` em `struct` (menos itaiano — cerimônia desnecessária); modelar conformance só via `impl` (perde a ergonomia inline que o oracle já tem).

## §11 Critérios de aceite (viram casos de conformância)

- **CA1** — `class Animal { init(name: String) { self.name = name } }` ⟶ `(class "Animal" (init (params (param "name" (type String))) (block (expr-stmt (= (member (self) "name") (id name))))))`.
- **CA2** — `guard let v = opt && v > 0 else { return }` ⟶ `(guard-let (bind "v") (id opt) (cond (> (id v) (int 0))) (else (block (return))))` — `condition` presente e distinta do `value`.
- **CA3** — `struct Point: Eq { x: Int }` ⟶ `StructDecl.traits = [Eq]`; dump `(struct "Point" (traits (type Eq)) (field "x" (type Int)))`.
- **CA4** — `class Dog: Animal, Barker { }` ⟶ `superclass = Animal`, `traits = [Barker]`; dump `(class "Dog" (extends (type Animal)) (traits (type Barker)))`.
- **CA5** — `extension Int: Ord { }` ⟶ `ExtensionDecl.target = Int`, `traits = [Ord]`.
- **CA6** — `struct S { async fn tick() => 0 }` ⟶ membro `async fn` representado (`asyncMarker = async`), gramática reconciliada.
- **CA7** — `guard let v = opt else { return }` (sem `&&`) ⟶ `condition == null` (não regride a forma existente).

## §7-nota — Débitos de codegen (Fase 7), do review `dart-vm-expert`

A modelagem é forward-compatible com o Kernel (nenhum campo parse-only faltando); estes são **débitos de codegen**, não de AST, a resolver quando a emissão→Kernel existir:
1. **`init`:** hoistar `self.field = e` do body para `FieldInitializer` do Kernel (campo `let` → `Field` `final`; a lista de inicializadores é o único lugar válido para inicializar `final`).
2. **`init` política const/factory por-kind** — deriva na Fase 3 via side-table (ADR-0004), sem campo de parse.
3. **`extension T: Trait`:** `Extension` clássico do Kernel não tem `implements` — baixar como `extension type` (Dart 3, tem `implements`) ou witness/dispatch.
4. **`struct`:** o Kernel não tem "value type" — vira `Class` comum; a semântica de valor (cópia, `==`/`hashCode` estrutural, copy-with) é inteiramente codegen (não vem de graça da VM).

## Definition of Done

- [ ] CAs cobertos por casos `.tu`→`.ast` no corpus, verdes via `itac parse --dump`.
- [ ] `InitDecl`, `condition`, `traits` materializados em `ast.dart` a partir do `ast.asdl` (à mão, P11).
- [ ] `grammar.ebnf` reconciliada com o parser; sem marcas `(DEFER)` obsoletas.
- [ ] Constitution check sem conflito aberto (§0.5) + code review de identidade (`ita-visionary`) aplicado.
- [ ] `make test` + `dart analyze` verdes.
