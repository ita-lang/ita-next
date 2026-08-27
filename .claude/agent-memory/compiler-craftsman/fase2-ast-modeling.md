---
name: fase2-ast-modeling
description: Parecer técnico sobre a modelagem da AST canônica do Itá em Zephyr ASDL (Fase 2, spec 004) — blocker de boa-formação + ajustes forward-compat
metadata:
  type: project
---

# Modelagem AST Fase 2 — `compiler/docs/spec/ast.asdl` (revisão W1)

**Fato:** os 5 sums (`decl/stmt/expr/type/pattern`) + products representam TODOS os 23 CAs do
conformance-cases sem buraco de FORMA. Os problemas são de tipagem do ASDL e de campos forward-compat.

**Why:** revisão antes de materializar `ast.dart` (P11 zero-codegen: ASDL é fonte-de-verdade humana). Um
ASDL mal-formado força o autor de `ast.dart` a adivinhar — anula o propósito.

**How to apply:** ao materializar `ast.dart` ou revisar W3, cobrar estes pontos:

## Bloqueador (impede materialização fiel)
- **Tipos indefinidos `block`, `fnDecl`, `node`.** O ASDL referencia CONSTRUTORES como se fossem TIPOS.
  `Block(stmt*)` é variante do sum `stmt` (não existe tipo `block`); `FnDecl` é variante de `decl` (não
  existe `fnDecl`); `node` (em `Program(node* body)`) não é definido. Corrigir: promover `block` a product
  `block = (stmt* stmts) attributes(...)` (encoda "chaves obrigatórias" em if/while); `OperatorDecl.fn`
  tipar como `decl` ou product dedicado; `Program.body` ver Q2.

## Ajustes (antes de codegen/fases seguintes)
- **`Closure` sem `async_marker`** — contradiz o próprio design-note M5; codegen não distingue async closure
  (Kernel `AsyncMarker`). Falta também disambiguador params-implícitos (`{ $0 }`) vs `() =>` explícito
  (oracle tinha `hasExplicitParams`). `FnDecl` tem `async`; `Closure` não.
- **Op stringly-typed (`Binary`/`Unary`/`Assign(string op)`)** — FIEL a CI 6.2 (jlox usa Token operator),
  mas codegen→Kernel perde exaustividade: cada op tem lowering distinto (`**`→pow, `|>`→aplicação,
  `>>`→composição, `??`→null-check, `+=`→target=target+v). Recomendação: manter tag=símbolo no dump, mas
  modelar op como enum fechado (`BinaryOp`/`UnaryOp`/`AssignOp`) em `ast.dart` (restaura CI 5.3.2). PIOR:
  `await`/`spawn`/`panic` empacotados em `Unary(string op)` junto de `!`/`neg` — têm alvos Kernel
  radicalmente distintos (`AwaitExpression`/spawn-isolate/`Throw`). D4 (precedência unária) está certo, mas
  nível-de-parse ≠ nó-AST: recomendar nós distintos `Await`/`Spawn`/`Panic` (custo zero no dump).
- **`Program.body` via supertipo `AstNode`/`node*` é insound p/ exaustividade** — `AstNode` é raiz dos 5
  sums; `List<AstNode>` admite `expr`/`type`/`pattern` no topo (estados ilegais). DB/CI: regra-topo une
  exatamente decl+stmt (jlox `declaration*`, CI 8.1). Recomendar sum wrapper `item = Decl(decl) | Stmt(stmt)`
  (Python.asdl `mod = Module(stmt*)` funde decl em stmt — alternativa).
- **Campos forward-compat ausentes vs oracle/GRAMMAR (não exercidos pelos 23 CAs):** conformances inline de
  tipo (`struct P: Trait`), `init` de class (oracle `InitDecl`), `&&` extra do `guard let` (oracle
  `GuardLetStmt.condition`), `await race/all` (canto 6 — sem nó; se são forma sintática, faltam nós; se são
  call, o canto 6 é desnecessário), seção named-params `;` (oracle `namedParams`), `where` expr.
- **`IfExpr(block then, block orElse)` contradiz D1** — D1 proíbe última-expr-implícita, mas branch é
  `block` (não produz valor). `MatchExpr.arm.body` é `expr` (coerente). Definir mecanismo de valor do
  if-expr (branches `expr`? valor explícito?) + adicionar CA.
- **M4 parcial:** `IntLit(int value)`/`FloatLit(double)` perdem raw/radix (`0xFF`, `1_000`, bigint > 2^63).
  M4 pedia "preserva forma escrita (radix/raw)". Kernel tem `BigIntLiteral`. Considerar guardar lexema raw.
- **Menores:** `Error*` carrega só `message` (M2 diz "tokens descartados"; span já vem de attributes);
  dump de campo de `RecordPattern` = `(bind ..)` mas de `StructPattern` = `(field-pat ..)` p/ o mesmo
  product `fieldPattern` (uniformizar convenção no GREEN).

## OK (fiel — não mexer)
- **`Error*` por sum + attributes(offset,length)** (Q4): fiel a DB 4.1.4 (error productions) / CI 6.3.
  `ErrorType`/`ErrorPattern` SÃO necessários (erro pode ocorrer em type/pattern sem nular o pai). Correto.
- **`pub` omitido de `Impl/Extension/Import/Operator`Decl** — illegal-states-unrepresentable (D3). Bom uso do
  ASDL. (Inconsistência: `FnDecl.isStatic/isOverride` sempre presentes, sem sentido no topo — decidir
  validação-diferida uniforme.)
- **`Str(strPart* parts)`** (M3), **Int≠Float** como nós distintos (M4), **span via attributes** (M1),
  **`IfExpr` else obrigatório** (invariante de valor), **`decl* members`** (Q3, precedente Python.asdl:
  class-body = stmt* frouxo; legalidade de membro = check diferido, coerente com "AST representa, não valida").

**Fontes:** DB cap 4 (4.1.4 error productions); CI 5.2.2 (GenerateAst≈ASDL), 5.3.2 (Visitor/exaustividade),
6.2 (Binary com Token operator), 6.3 (panic mode), 8.1 (regra `declaration*`); Wang et al. 1997 / Python.asdl;
Kernel AsyncMarker/IntLiteral/StringConcatenation (via dart-vm-expert). Match-exhaustividade = Maranget 2007 (Fase 4+, fora daqui).
