// ===========================================================================
// ast.dart — Nós da AST do Itá (Fase 2, spec 004).
// ===========================================================================
//
// Materialização À MÃO do `compiler/docs/spec/ast.asdl` (P11 / ADR-0010: zero
// codegen em build-time — nada de `build_runner`). O ASDL é a fonte de verdade
// humana; ESTE arquivo é a fonte de verdade do compilador. Mantenha os dois em
// sincronia.
//
// Hierarquias `sealed` (CI 5.2.1): cada sum vira uma `sealed class` cujo
// `switch` é exaustivo de graça — a semântica e as análises (Fases 4–6) herdam
// a exaustividade. Products viram classes `final` simples.
//
// Span (M1): TODO nó de sum carrega `offset`+`length` byte-precisos (reusa o
// `Token` da Fase 1). Forward-compat: vira `fileOffset` do Kernel (stack traces
// DWARF em AOT; source-maps em JS). Products não carregam span (sub-estruturas).
// ===========================================================================

// ---------------------------------------------------------------------------
// Raiz.
// ---------------------------------------------------------------------------

/// Nó base de toda a AST. Carrega o span (offset+length) no fonte.
sealed class AstNode {
  final int offset;
  final int length;
  const AstNode(this.offset, this.length);
}

/// Programa = sequência de itens de topo (declarações e, em escopo de módulo,
/// os `Stmt` que o Itá permite: bindings `let`/`var`, expr-stmts). Por isso o
/// corpo é `List<AstNode>` (supertipo comum de [Decl] e [Stmt]).
final class Program extends AstNode {
  final List<AstNode> body;
  Program(this.body, super.offset, super.length);
}

// ===========================================================================
// Declarações (§2).
// ===========================================================================

sealed class Decl extends AstNode {
  const Decl(super.offset, super.length);
}

/// `fn`, `async fn`, `stream fn`; também usada como MÉTODO de corpo de tipo
/// (com `static`/`override`). Assinatura sem corpo (`body == null`) = trait.
final class FnDecl extends Decl {
  final bool isPublic;
  final bool isStatic;
  final bool isOverride;
  final AsyncMarker asyncMarker;
  final String name;
  final List<GenericParam> generics;
  final List<Param> params;
  final TypeNode? returnType;
  final FnBody? body;
  FnDecl(
    this.isPublic,
    this.isStatic,
    this.isOverride,
    this.asyncMarker,
    this.name,
    this.generics,
    this.params,
    this.returnType,
    this.body,
    super.offset,
    super.length,
  );
}

/// Campo de tipo: `x: Int`, `var count: Int = 0`. Membro de struct/class/actor.
final class FieldDecl extends Decl {
  final bool isPublic;
  final bool isMutable;
  final String name;
  final TypeNode type;
  final Expr? defaultValue;
  FieldDecl(
    this.isPublic,
    this.isMutable,
    this.name,
    this.type,
    this.defaultValue,
    super.offset,
    super.length,
  );
}

final class StructDecl extends Decl {
  final bool isPublic;
  final String name;
  final List<GenericParam> generics;
  final List<Decl> members; // FieldDecl | FnDecl, em ordem-fonte (CA2)
  StructDecl(
    this.isPublic,
    this.name,
    this.generics,
    this.members,
    super.offset,
    super.length,
  );
}

final class ClassDecl extends Decl {
  final bool isPublic;
  final String name;
  final List<GenericParam> generics;
  final TypeNode? superclass;
  final List<Decl> members;
  ClassDecl(
    this.isPublic,
    this.name,
    this.generics,
    this.superclass,
    this.members,
    super.offset,
    super.length,
  );
}

final class EnumDecl extends Decl {
  final bool isPublic;
  final String name;
  final List<GenericParam> generics;
  final List<EnumCase> cases;
  final List<Decl> members; // métodos do enum ADT
  EnumDecl(
    this.isPublic,
    this.name,
    this.generics,
    this.cases,
    this.members,
    super.offset,
    super.length,
  );
}

final class TraitDecl extends Decl {
  final bool isPublic;
  final String name;
  final List<GenericParam> generics;
  final List<Decl> members;
  TraitDecl(
    this.isPublic,
    this.name,
    this.generics,
    this.members,
    super.offset,
    super.length,
  );
}

final class ImplDecl extends Decl {
  final TypeNode? trait; // `impl Trait for T` vs `impl T`
  final TypeNode target;
  final List<Decl> members;
  ImplDecl(this.trait, this.target, this.members, super.offset, super.length);
}

final class ExtensionDecl extends Decl {
  final TypeNode target;
  final List<Decl> members;
  ExtensionDecl(this.target, this.members, super.offset, super.length);
}

final class ActorDecl extends Decl {
  final bool isPublic;
  final String name;
  final List<Decl> members;
  ActorDecl(this.isPublic, this.name, this.members, super.offset, super.length);
}

final class OperatorDecl extends Decl {
  final String symbol;
  final Fixity fixity;
  final int? precedence;
  final FnDecl fn;
  OperatorDecl(
    this.symbol,
    this.fixity,
    this.precedence,
    this.fn,
    super.offset,
    super.length,
  );
}

final class ImportDecl extends Decl {
  final ImportClause clause;
  final String module;
  ImportDecl(this.clause, this.module, super.offset, super.length);
}

/// Placeholder de recuperação N2 (M2): enxertado no lugar de uma declaração
/// que não parseou. A árvore permanece total e bem-tipada.
final class ErrorDecl extends Decl {
  final String message;
  ErrorDecl(this.message, super.offset, super.length);
}

// ===========================================================================
// Statements (§3).
// ===========================================================================

sealed class Stmt extends AstNode {
  const Stmt(super.offset, super.length);
}

final class LetStmt extends Stmt {
  final bool isVar; // `let` (false) vs `var` (true)
  final Pattern target;
  final TypeNode? type;
  final Expr value;
  LetStmt(
    this.isVar,
    this.target,
    this.type,
    this.value,
    super.offset,
    super.length,
  );
}

final class ReturnStmt extends Stmt {
  final Expr? value;
  ReturnStmt(this.value, super.offset, super.length);
}

final class IfStmt extends Stmt {
  final Expr cond;
  final Block then;
  final Else? orElse;
  IfStmt(this.cond, this.then, this.orElse, super.offset, super.length);
}

final class GuardStmt extends Stmt {
  final Expr cond;
  final Block orElse;
  GuardStmt(this.cond, this.orElse, super.offset, super.length);
}

final class GuardLetStmt extends Stmt {
  final Pattern target;
  final Expr value;
  final Block orElse;
  GuardLetStmt(
    this.target,
    this.value,
    this.orElse,
    super.offset,
    super.length,
  );
}

final class WhileStmt extends Stmt {
  final Expr cond;
  final Block body;
  WhileStmt(this.cond, this.body, super.offset, super.length);
}

final class ForStmt extends Stmt {
  final bool isAwait;
  final Pattern target;
  final Expr iterable;
  final Block body;
  ForStmt(
    this.isAwait,
    this.target,
    this.iterable,
    this.body,
    super.offset,
    super.length,
  );
}

final class BreakStmt extends Stmt {
  BreakStmt(super.offset, super.length);
}

final class ContinueStmt extends Stmt {
  ContinueStmt(super.offset, super.length);
}

final class EmitStmt extends Stmt {
  final Expr value;
  EmitStmt(this.value, super.offset, super.length);
}

final class ExprStmt extends Stmt {
  final Expr expr;
  ExprStmt(this.expr, super.offset, super.length);
}

/// Bare-block em posição de statement (CA13). Envolve o nó estrutural [Block].
final class BlockStmt extends Stmt {
  final Block block;
  BlockStmt(this.block, super.offset, super.length);
}

final class ErrorStmt extends Stmt {
  final String message;
  ErrorStmt(this.message, super.offset, super.length);
}

/// Bloco `{ … }` — nó estrutural de 1ª classe (NÃO é um [Stmt]). As construções
/// que exigem chaves (`if`/`while`/`for`/`guard`/corpo de `fn`/closure) o
/// referenciam diretamente — a obrigatoriedade das chaves fica no tipo. Um
/// bare-block em posição de statement é [BlockStmt].
final class Block extends AstNode {
  final List<Stmt> stmts;
  Block(this.stmts, super.offset, super.length);
}

// ===========================================================================
// Expressões (§4). O DUMP usa o símbolo do operador como tag.
// ===========================================================================

sealed class Expr extends AstNode {
  const Expr(super.offset, super.length);
}

final class IntLit extends Expr {
  final int value;
  IntLit(this.value, super.offset, super.length);
}

final class FloatLit extends Expr {
  final double value;
  FloatLit(this.value, super.offset, super.length);
}

/// String (interpolada ou não): partes ordenadas em parse-time (M3).
final class Str extends Expr {
  final List<StrPart> parts;
  Str(this.parts, super.offset, super.length);
}

final class BoolLit extends Expr {
  final bool value;
  BoolLit(this.value, super.offset, super.length);
}

final class NilLit extends Expr {
  NilLit(super.offset, super.length);
}

final class Ident extends Expr {
  final String name;
  Ident(this.name, super.offset, super.length);
}

final class SelfExpr extends Expr {
  SelfExpr(super.offset, super.length);
}

/// Operador binário; `op` (`+`, `*`, `**`, `==`, `<`, `&&`, `||`, `??`, `|>`,
/// `>>`, …) é a tag do dump.
final class Binary extends Expr {
  final String op;
  final Expr left;
  final Expr right;
  Binary(this.op, this.left, this.right, super.offset, super.length);
}

/// Prefixo-operador; `op` = `neg` (`-`) ou `!`. (`await`/`spawn`/`panic` são
/// nós próprios — alvos Kernel distintos.)
final class Unary extends Expr {
  final String op;
  final Expr operand;
  Unary(this.op, this.operand, super.offset, super.length);
}

/// `await e` — mapeia para `AwaitExpression` do Kernel.
final class Await extends Expr {
  final Expr operand;
  Await(this.operand, super.offset, super.length);
}

/// `spawn e` — dispara um isolate.
final class Spawn extends Expr {
  final Expr operand;
  Spawn(this.operand, super.offset, super.length);
}

/// `panic e` — mapeia para `Throw` do Kernel.
final class Panic extends Expr {
  final Expr operand;
  Panic(this.operand, super.offset, super.length);
}

final class Assign extends Expr {
  final String op; // `=`, `+=`, `-=`, `*=`, `/=`
  final Expr target;
  final Expr value;
  Assign(this.op, this.target, this.value, super.offset, super.length);
}

final class Call extends Expr {
  final Expr callee;
  final List<Arg> args; // ordem-fonte (M6)
  Call(this.callee, this.args, super.offset, super.length);
}

final class Member extends Expr {
  final Expr receiver;
  final String name;
  Member(this.receiver, this.name, super.offset, super.length);
}

final class OptChain extends Expr {
  final Expr receiver;
  final String name;
  OptChain(this.receiver, this.name, super.offset, super.length);
}

final class Index extends Expr {
  final Expr receiver;
  final Expr index;
  Index(this.receiver, this.index, super.offset, super.length);
}

final class TupleIndex extends Expr {
  final Expr receiver;
  final int index;
  TupleIndex(this.receiver, this.index, super.offset, super.length);
}

final class ForceUnwrap extends Expr {
  final Expr operand;
  ForceUnwrap(this.operand, super.offset, super.length);
}

final class Try extends Expr {
  final Expr operand;
  Try(this.operand, super.offset, super.length);
}

final class CopyWith extends Expr {
  final Expr receiver;
  final List<FieldInit> fields;
  CopyWith(this.receiver, this.fields, super.offset, super.length);
}

final class Closure extends Expr {
  final AsyncMarker asyncMarker;
  final bool hasExplicitParams; // `() => …` explícito vs `{ $0 }` implícito
  final List<Param> params;
  final TypeNode? returnType; // `(x) -> Int => …`
  final FnBody body;
  Closure(
    this.asyncMarker,
    this.hasExplicitParams,
    this.params,
    this.returnType,
    this.body,
    super.offset,
    super.length,
  );
}

final class IfExpr extends Expr {
  final Expr cond;
  final Block then;
  final Block orElse;
  IfExpr(this.cond, this.then, this.orElse, super.offset, super.length);
}

final class MatchExpr extends Expr {
  final Expr scrutinee;
  final List<MatchArm> arms;
  MatchExpr(this.scrutinee, this.arms, super.offset, super.length);
}

final class TupleExpr extends Expr {
  final List<Expr> elements; // >= 2 (M7)
  TupleExpr(this.elements, super.offset, super.length);
}

final class ListExpr extends Expr {
  final List<Expr> elements;
  ListExpr(this.elements, super.offset, super.length);
}

final class MapExpr extends Expr {
  final List<MapEntryNode> entries;
  MapExpr(this.entries, super.offset, super.length);
}

final class RangeExpr extends Expr {
  final bool inclusive; // `..=` (true) vs `..` (false)
  final Expr start;
  final Expr end;
  RangeExpr(this.inclusive, this.start, this.end, super.offset, super.length);
}

final class EnumShorthand extends Expr {
  final String variant;
  EnumShorthand(this.variant, super.offset, super.length);
}

final class ErrorExpr extends Expr {
  final String message;
  ErrorExpr(this.message, super.offset, super.length);
}

// ===========================================================================
// Tipos (§5).
// ===========================================================================

sealed class TypeNode extends AstNode {
  const TypeNode(super.offset, super.length);
}

final class NamedType extends TypeNode {
  final String name;
  final List<TypeNode> args;
  NamedType(this.name, this.args, super.offset, super.length);
}

final class OptionalType extends TypeNode {
  final TypeNode inner;
  OptionalType(this.inner, super.offset, super.length);
}

final class MutType extends TypeNode {
  final TypeNode inner;
  MutType(this.inner, super.offset, super.length);
}

final class FunctionType extends TypeNode {
  final bool isAsync;
  final List<TypeNode> params;
  final TypeNode ret;
  FunctionType(this.isAsync, this.params, this.ret, super.offset, super.length);
}

final class TupleType extends TypeNode {
  final List<TypeNode> elements; // >= 2
  TupleType(this.elements, super.offset, super.length);
}

final class ErrorType extends TypeNode {
  final String message;
  ErrorType(this.message, super.offset, super.length);
}

// ===========================================================================
// Patterns (§6).
// ===========================================================================

sealed class Pattern extends AstNode {
  const Pattern(super.offset, super.length);
}

final class BindPattern extends Pattern {
  final String name;
  BindPattern(this.name, super.offset, super.length);
}

final class WildcardPattern extends Pattern {
  WildcardPattern(super.offset, super.length);
}

final class LiteralPattern extends Pattern {
  final Expr literal;
  LiteralPattern(this.literal, super.offset, super.length);
}

final class EnumPattern extends Pattern {
  final String variant;
  final List<Pattern> subpatterns;
  EnumPattern(this.variant, this.subpatterns, super.offset, super.length);
}

final class ListPattern extends Pattern {
  final List<Pattern> elements; // RestPattern aparece inline
  ListPattern(this.elements, super.offset, super.length);
}

final class RecordPattern extends Pattern {
  final List<FieldPattern> fields; // `{ x, y }`
  RecordPattern(this.fields, super.offset, super.length);
}

final class StructPattern extends Pattern {
  final String typeName;
  final List<FieldPattern> fields;
  final bool hasRest; // `..` no final
  StructPattern(
    this.typeName,
    this.fields,
    this.hasRest,
    super.offset,
    super.length,
  );
}

final class RangePattern extends Pattern {
  final bool inclusive;
  final Expr start;
  final Expr end;
  RangePattern(this.inclusive, this.start, this.end, super.offset, super.length);
}

final class RestPattern extends Pattern {
  final String? name; // `..t` (com nome) ou `..` (sem)
  RestPattern(this.name, super.offset, super.length);
}

final class ErrorPattern extends Pattern {
  final String message;
  ErrorPattern(this.message, super.offset, super.length);
}

// ===========================================================================
// Produtos compartilhados (sem span próprio — sub-estruturas).
// ===========================================================================

/// Parâmetro genérico: `T`, `T: Ord`, `T: A + B`.
final class GenericParam {
  final String name;
  final List<TypeNode> bounds;
  const GenericParam(this.name, this.bounds);
}

/// Parâmetro de função: label externo opcional, nome, tipo, default.
final class Param {
  final String? label;
  final String name;
  final TypeNode? type;
  final Expr? defaultValue;
  const Param(this.label, this.name, this.type, this.defaultValue);
}

/// Variante de enum ADT: `None`, `Some(v: T)`.
final class EnumCase {
  final String name;
  final List<Param> payload;
  const EnumCase(this.name, this.payload);
}

/// Braço de `match`: pattern + guard `if` opcional + corpo `=> expr`.
final class MatchArm {
  final Pattern pattern;
  final Expr? guard;
  final Expr body;
  const MatchArm(this.pattern, this.guard, this.body);
}

/// Argumento de chamada: posicional (`label == null`) ou nomeado.
final class Arg {
  final String? label;
  final Expr value;
  const Arg(this.label, this.value);
}

/// Membro de `import { a as b }`.
final class ImportMember {
  final String name;
  final String? alias;
  const ImportMember(this.name, this.alias);
}

/// Entrada de map literal `{ k: v }`.
final class MapEntryNode {
  final Expr key;
  final Expr value;
  const MapEntryNode(this.key, this.value);
}

/// Inicializador de campo em copy-with / struct-literal: `x: 1`.
final class FieldInit {
  final String name;
  final Expr value;
  const FieldInit(this.name, this.value);
}

/// Campo de struct/record-pattern: `x` (bind homônimo) ou `x: subpat`.
final class FieldPattern {
  final String name;
  final Pattern? pattern; // null = bind ao próprio nome
  const FieldPattern(this.name, this.pattern);
}

// --- Sub-produtos selados ---------------------------------------------------

/// Parte de string interpolada (M3), em ordem-fonte.
sealed class StrPart {
  const StrPart();
}

final class StrLit extends StrPart {
  final String value; // escapes já decodificados
  const StrLit(this.value);
}

final class StrInterp extends StrPart {
  final Expr expr;
  const StrInterp(this.expr);
}

/// Corpo de função/closure: `=> expr` ou `=> { block }` / `{ block }`.
sealed class FnBody {
  const FnBody();
}

final class ExprBody extends FnBody {
  final Expr e;
  const ExprBody(this.e);
}

final class BlockBody extends FnBody {
  final Block b;
  const BlockBody(this.b);
}

/// Cláusula de `import` (ES6, 3 formas).
sealed class ImportClause {
  const ImportClause();
}

final class ImportNamed extends ImportClause {
  final List<ImportMember> members;
  const ImportNamed(this.members);
}

final class ImportStar extends ImportClause {
  final String alias;
  const ImportStar(this.alias);
}

final class ImportBare extends ImportClause {
  const ImportBare();
}

/// Ramo `else` de um `if`-statement: else-if (outro `if`) ou bloco.
sealed class Else {
  const Else();
}

final class ElseIf extends Else {
  final Stmt ifStmt; // sempre um IfStmt
  const ElseIf(this.ifStmt);
}

final class ElseBlock extends Else {
  final Block block;
  const ElseBlock(this.block);
}

// --- Enums ------------------------------------------------------------------

/// Marcador de assincronia (M5) — mapeia para `AsyncMarker` do Kernel.
/// `syncStar` fica de fora: o Itá não expõe sintaxe de gerador lazy.
enum AsyncMarker { sync, async, asyncStar }

/// Fixidez de um operador custom.
enum Fixity { prefix, infix, postfix }
