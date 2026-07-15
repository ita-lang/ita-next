// ===========================================================================
// type.dart — Modelo de tipos do Itá (Fase 5, spec 009 §4.1).
// ===========================================================================
//
// Materialização À MÃO da spec `009-semantic-types` §4.1 (P11 / ADR-0010: zero
// codegen). Espelha as EXPRESSÕES DE TIPO do Dragon 6.3.1 — *"um tipo básico ou
// é formada pela aplicação de um operador chamado construtor de tipo"*: básico |
// nome | construtor aplicado | `→` função | `×` produto | variável de tipo.
//
// NÃO é o `TypeNode` da AST (`parser/ast.dart`): aquele é a ANOTAÇÃO que o
// usuário escreveu (sintaxe); este é o TIPO que a Fase 5 computa (semântica). A
// travessia entre os dois é `collect.dart` (A2).
//
// DUAS DECISÕES QUE O ORACLE NÃO FEZ, e são a causa de ele checar 4 regras em
// 1355 linhas (ADR-0013):
//  1. **`ErrorType` ≠ `TypeVar`.** O oracle funde os dois em `UnknownType`, que é
//     curinga nos DOIS sentidos (`resolved_type.dart:46`) ⟹ o checker nunca erra.
//     Aqui: `TypeVar` = "ainda não sei" (Dragon 6.5.4) e **deve** sumir até o fim
//     (senão `cannot-infer`); `ErrorType` = absorvente PÓS-erro-já-reportado
//     (anti-cascata). O bug não é ter um curinga — é dar semântica de `ErrorType`
//     a um "não sei".
//  2. **Struct/class/enum são UM construtor** (`NamedType` + `kind`), não três
//     classes com estrutura idêntica. O `kind` carrega valor-vs-referência (P2).
//
// IDENTIDADE (§4.2): **nominal** para user-types (por NÓ-DECL, não por string —
// lição da F4: o Kernel referencia por objeto); **estrutural** para construtores
// (`OptionalType`/`FunctionType`/`TupleType`).
// ===========================================================================

// Prefixado: a AST tem `NamedType`/`OptionalType`/`FunctionType`/`TupleType`/
// `ErrorType` como `TypeNode` (a ANOTAÇÃO que o usuário escreveu) e este arquivo
// tem os mesmos nomes como `Type` (o TIPO que a F5 computa). A colisão é
// esperada — são os mesmos conceitos em níveis diferentes. Precedente: o oracle
// faz igual (`semantic/type_resolver.dart:21`).
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;

/// Espécie de um [NamedType] — carrega **valor vs referência** (P2), que decide
/// `struct` final (§4.2b), `deeply-immutable` (§8.4) e o lowering da F7.
enum TypeKind { struct_, class_, enum_, trait_, actor_ }

/// Nome genérico **sem nó-decl** — a stdlib os usa e **nunca os declara**
/// (`enum Option`/`enum Result` não existem em lugar nenhum), então não cabem em
/// [NamedType], que exige `decl`.
///
/// - **`option`** (aridade 1): NÃO sobrevive à fatia A — `collect` reescreve
///   `Option<X>` → `OptionalType(X)` (§4.6, ruling do dono 2026-07-12:
///   `Option<T>` ≡ `T?`, alias canônico Swift-style).
/// - **`result`** (aridade 2): **sobrevive** — `Result<T,E>` **não tem
///   equivalente nativo** no Kernel (payload nos dois lados ⟹ classe no heap,
///   sempre; §8.4). Σ = `{ok(T), err(E)}`.
///
/// Trazê-los para cá **corrige um vazamento do oracle** (§7-3): lá eles moram no
/// `codegen.dart:683` (`_registerBuiltinTypes`), invisíveis à semântica e com os
/// type-args apagados para `const DynamicType()` — exatamente o que o ADR-0013
/// proíbe. Aqui os args são REAIS.
/// Builtins genéricos **sem nó-decl** — a stdlib os usa e nunca os declara.
///
/// `option` não sobrevive à fatia A (vira [OptionalType], alias do §4.6). Os
/// outros três sobrevivem: `result` porque não tem equivalente nativo no Kernel;
/// `list`/`map` porque são o **CHÃO** (spec 010 §4.6.1) — irredutíveis, têm de
/// tocar o Dart. Débito **forma-M5**: fechado, erra no desconhecido, destino
/// `.tu` escrito (`dart:` explícito no M5).
enum BuiltinKind { option, result, list, map }

/// Aridade de cada builtin — o `generic-arity-mismatch` da fatia A a consulta.
const builtinArity = {
  BuiltinKind.option: 1,
  BuiltinKind.result: 2,
  BuiltinKind.list: 1,
  BuiltinKind.map: 2,
};

sealed class Type {
  const Type();
}

// --- básicos (6.3.1) --------------------------------------------------------

final class IntType extends Type {
  const IntType();
  @override
  bool operator ==(Object other) => other is IntType;
  @override
  int get hashCode => 0x01;
  @override
  String toString() => 'Int';
}

final class FloatType extends Type {
  const FloatType();
  @override
  bool operator ==(Object other) => other is FloatType;
  @override
  int get hashCode => 0x02;
  @override
  String toString() => 'Float';
}

final class BoolType extends Type {
  const BoolType();
  @override
  bool operator ==(Object other) => other is BoolType;
  @override
  int get hashCode => 0x03;
  @override
  String toString() => 'Bool';
}

final class StringType extends Type {
  const StringType();
  @override
  bool operator ==(Object other) => other is StringType;
  @override
  int get hashCode => 0x04;
  @override
  String toString() => 'String';
}

/// 6.3.1: *"o último denota 'a ausência de um valor'"*.
final class VoidType extends Type {
  const VoidType();
  @override
  bool operator ==(Object other) => other is VoidType;
  @override
  int get hashCode => 0x05;
  @override
  String toString() => 'Void';
}

// --- nomes ------------------------------------------------------------------

/// User-type por **nó-decl** (`StructDecl`/`ClassDecl`/`EnumDecl`/`TraitDecl`/
/// `ActorDecl`), não por string — o oracle usa `StructType('Node')` e depois faz
/// `scope.lookup(name)` só para reencontrar o símbolo (sintoma de modelagem
/// errada). Identidade **nominal**: dois `NamedType` são iguais sse o `decl` é o
/// MESMO objeto e os `args` batem — o que resolve tipos recursivos (Dragon 6.3.1,
/// box *"Nomes de tipo e tipos recursivos"*: o grafo tem ciclos) sem recursão
/// infinita no `==`.
final class NamedType extends Type {
  final ast.AstNode decl;
  final List<Type> args;
  final TypeKind kind;
  const NamedType(this.decl, this.kind, [this.args = const []]);

  bool get isValue => kind == TypeKind.struct_;

  @override
  bool operator ==(Object other) =>
      other is NamedType &&
      identical(other.decl, decl) &&
      _listEq(other.args, args); // `kind` é função do `decl` — não entra no ==
  @override
  int get hashCode => Object.hash(identityHashCode(decl), Object.hashAll(args));
  @override
  String toString() =>
      args.isEmpty ? _declName(decl) : '${_declName(decl)}<${args.join(", ")}>';
}

/// Nome builtin sem decl (§4.1). Ver [BuiltinKind].
final class BuiltinType extends Type {
  final BuiltinKind kind;
  final List<Type> args;
  const BuiltinType(this.kind, [this.args = const []]);

  @override
  bool operator ==(Object other) =>
      other is BuiltinType && other.kind == kind && _listEq(other.args, args);
  @override
  int get hashCode => Object.hash(kind, Object.hashAll(args));
  @override
  String toString() =>
      args.isEmpty ? kind.name : '${kind.name}<${args.join(", ")}>';
}

// --- construtores -----------------------------------------------------------

/// `T?` — **construtor próprio**, não ADT (§4.6). `Option<T>` ≡ `T?` (ruling do
/// dono 2026-07-12), e o lowering é a **nullability nativa** do Kernel (§8.1:
/// `Option` boxed nunca desboxa, a TFA não faz escape analysis, e no dart2js o
/// box sobrevive).
///
/// **INVARIANTE — `inner` NUNCA é `OptionalType`.** `?` é MODIFICADOR, não
/// construtor (ruling do dono §12-7): `T?? = T?` por **idempotência**, como
/// `mut mut T = mut T`. Use [optional] — o smart constructor —, **inclusive em
/// substituição**: um `subst` estrutural ingênuo produziria `OptionalType(
/// OptionalType(X))` e quebraria o invariante em silêncio, e aí a F7 não teria
/// imagem (o Kernel tem **um** byte de `Nullability`, não dois).
///
/// O diagnóstico de `T??` escrito à mão (`redundant-optional`) é **sintático**,
/// sobre o `TypeNode` da AST — **nunca** aqui: se morasse no construtor,
/// dispararia em `compact<String?>`, que é programa legal (spec 009 §4.6).
final class OptionalType extends Type {
  final Type inner;
  const OptionalType._(this.inner);

  @override
  bool operator ==(Object other) => other is OptionalType && other.inner == inner;
  @override
  int get hashCode => Object.hash('?', inner);
  @override
  String toString() => '$inner?';
}

/// Smart constructor de [OptionalType] — **o único jeito de criar um**.
/// Idempotente: `optional(optional(T)) == optional(T)`.
/// `optional(Never)` continua `Never?` (um opcional que só pode ser `.none`);
/// `optional(ErrorType)` absorve (anti-cascata).
Type optional(Type inner) => switch (inner) {
  OptionalType _ => inner, // idempotência (§4.6)
  ErrorType _ => inner, // absorvente
  _ => OptionalType._(inner),
};

/// 6.3.1: `s → t`. `isAsync` espelha `FunctionType.isAsync` da AST.
final class FunctionType extends Type {
  final List<Type> params;
  final Type ret;
  final bool isAsync;
  const FunctionType(this.params, this.ret, {this.isAsync = false});

  @override
  bool operator ==(Object other) =>
      other is FunctionType &&
      other.isAsync == isAsync &&
      other.ret == ret &&
      _listEq(other.params, params);
  @override
  int get hashCode => Object.hash(Object.hashAll(params), ret, isAsync);
  @override
  String toString() =>
      '${isAsync ? "async " : ""}(${params.join(", ")}) -> $ret';
}

/// 6.3.1: produto `s × t`. Espelha o `TupleType` do ASDL (≥2 elementos —
/// **posicional só**; não há record literal nomeado na superfície). Lowering:
/// `RecordType` do Kernel (§8.4; retorno de record com exatamente 2 campos é
/// unboxed em AOT).
final class TupleType extends Type {
  final List<Type> elements;
  const TupleType(this.elements);

  @override
  bool operator ==(Object other) => other is TupleType && _listEq(other.elements, elements);
  @override
  int get hashCode => Object.hashAll(elements);
  @override
  String toString() => '(${elements.join(", ")})';
}

// --- bottom / incógnita / erro ----------------------------------------------

/// Bottom. **Lacuna no Dragon** (só tem `void` = "ausência de um valor"); fonte:
/// TAPL §15.4 + `NeverType` nativo do Kernel (tag 98).
///
/// É o tipo de `panic`/`return`/`break` como expressão (P3 — "tudo é expressão").
/// Regra: `join(Never, T) = T` (§4.3) — um braço que **diverge** não impõe
/// restrição sobre o tipo do resultado. Só `Never ≤ T`, nunca o inverso (§4.2b).
final class NeverType extends Type {
  const NeverType();
  @override
  bool operator ==(Object other) => other is NeverType;
  @override
  int get hashCode => 0x06;
  @override
  String toString() => 'Never';
}

/// Parâmetro de tipo **DECLARADO** — o `T` de `struct Box<T>`, a variável
/// **LIGADA** do 6.5.4 (*"O símbolo ∀ é o quantificador universal, e a variável
/// de tipo à qual ele é aplicado é considerada como estando **ligada** por ele"*).
///
/// **Não confundir com [TypeVar]**, e a diferença é a do próprio livro: *"em
/// cada uso de um tipo polimórfico, substituímos as variáveis ligadas por
/// **variáveis novas**"* — o `T` é a ligada (tem NOME, é declarada, vive na
/// assinatura); a nova/fresca é o `α` da unificação. Fundir os dois seria repetir
/// o erro do `UnknownType` do oracle noutro lugar.
///
/// Identidade **nominal por decl** (`GenericParam` não é `AstNode` — não tem
/// span; débito D4 da F4): o par (decl-dona, nome) identifica.
final class TypeParamType extends Type {
  final ast.AstNode owner; // a decl que o declarou (`struct Box<T>` → o StructDecl)
  final String name;
  const TypeParamType(this.owner, this.name);

  @override
  bool operator ==(Object other) =>
      other is TypeParamType &&
      identical(other.owner, owner) &&
      other.name == name;
  @override
  int get hashCode => Object.hash(identityHashCode(owner), name);
  @override
  String toString() => name; // `T` — é o que o usuário escreveu
}

/// "Ainda não sei" — a variável **NOVA** que a unificação cria a cada uso
/// (Dragon 6.5.4/6.5.5, Alg. 6.19 — **fatia D**). **Deve** estar resolvida no fim
/// do passe; se sobrou, é `cannot-infer` (ADR-0013) — **nunca** `dynamic`.
final class TypeVar extends Type {
  final int id;
  const TypeVar(this.id);
  @override
  bool operator ==(Object other) => other is TypeVar && other.id == id;
  @override
  int get hashCode => Object.hash('α', id);
  @override
  String toString() => 'α$id';
}

/// Absorvente **pós-erro-já-reportado** (anti-cascata; a AST é total, com nós
/// `Error*` — CI 11.5). Curinga nos DOIS sentidos (§4.2b) — que é **exatamente**
/// a propriedade do `UnknownType` do oracle. É por isso que ele **só pode nascer
/// depois de um erro reportado**: "não sei" é [TypeVar], não isto (ADR-0013).
final class ErrorType extends Type {
  const ErrorType();
  @override
  bool operator ==(Object other) => other is ErrorType;
  @override
  int get hashCode => 0x07;
  @override
  String toString() => '<error>';
}

// --- substituição -----------------------------------------------------------

/// Aplica a substituição [s] a [t] (Dragon 6.5.4: *"S(t) é o resultado de
/// substituir consistentemente todas as ocorrências de cada variável de tipo α
/// em t por S(α)"*).
///
/// ⚠️ **Passa pelo smart constructor [optional]** — condição de soundness do
/// invariante (§4.6-cond.1). Um map estrutural ingênuo produziria
/// `OptionalType(OptionalType(X))` e quebraria o invariante **em silêncio**, e aí
/// a F7 não teria imagem (o Kernel tem **um** byte de `Nullability`, não dois).
/// É o caso real da stdlib: `compact<T>(list: List<T?>)` com `T = String?`.
///
/// A idempotência aqui é **SILENCIOSA** (CA28b): ninguém escreveu dois glifos —
/// a substituição os produziu. O `redundant-optional` é de ANOTAÇÃO (fatia A).
Type substitute(Type t, Map<Type, Type> s) {
  if (s.isEmpty) return t;
  return switch (t) {
    TypeParamType _ || TypeVar _ => s[t] ?? t,
    OptionalType(:final inner) => optional(substitute(inner, s)), // ← smart ctor
    NamedType n => NamedType(
      n.decl,
      n.kind,
      [for (final a in n.args) substitute(a, s)],
    ),
    BuiltinType n =>
      BuiltinType(n.kind, [for (final a in n.args) substitute(a, s)]),
    FunctionType n => FunctionType(
      [for (final p in n.params) substitute(p, s)],
      substitute(n.ret, s),
      isAsync: n.isAsync,
    ),
    TupleType n => TupleType([for (final e in n.elements) substitute(e, s)]),
    _ => t, // básicos, Never, Error
  };
}

// --- helpers ----------------------------------------------------------------

bool _listEq(List<Type> a, List<Type> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _declName(ast.AstNode d) => switch (d) {
  ast.StructDecl n => n.name,
  ast.ClassDecl n => n.name,
  ast.EnumDecl n => n.name,
  ast.TraitDecl n => n.name,
  ast.ActorDecl n => n.name,
  _ => '?',
};
