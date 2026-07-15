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

/// Um parâmetro: tipo **+ label + tem-default** (spec 011, item 0).
///
/// ⚠️ **O livro NÃO cobre parâmetro nomeado.** 6.3.1 modela param como **produto
/// cartesiano** (`s × t → r`) — **posição pura** —, e o Alg. 6.16 assume unário.
/// Param nomeado é superfície do Itá (`arg ::= ( IDENT ":" )? expression`), e a
/// regra é nossa. Lacuna declarada.
class ParamType {
  final Type type;

  /// O nome pelo qual o call-site o chama. `null` = posicional puro.
  final String? label;

  /// Tem default ⟹ **omissível** no call-site.
  final bool hasDefault;

  const ParamType(this.type, {this.label, this.hasDefault = false});

  /// ⚠️ **Só o TIPO.** `label` e `hasDefault` são **carregados** aqui (o
  /// `_matchArgs` precisa deles) mas **não equiparam** — carregar ≠ equiparar.
  ///
  /// **A gramática é quem decide, e já decidiu:** `type ::= "(" ( type ( ","
  /// type )* )? ")" ( "->" type )?` — o slot é **`type`**, não `param`. Logo
  /// `(x: Int) -> Int` **não parseia**: label não tem como entrar num tipo-função.
  /// Se ele participasse do `==`, o tipo de `fn dobro(x: Int) -> Int` seria
  /// **inexprimível na linguagem** — o compilador carregaria por dentro uma
  /// distinção que a superfície não sabe dizer. Isso é P4 ao contrário.
  ///
  /// O estrago concreto de tê-los aqui: `_topLevelType` dá `label: 'x'` e o tipo
  /// anotado `(Int) -> Int` nasce `positional` (`label: null`) ⟹ **nenhuma função
  /// nomeada casava com um tipo-função anotado, jamais** — ordem superior só
  /// funcionava com closure. O `unify.dart` já documentava a linha certa
  /// (*"label/default são da declaração e não participam da equivalência
  /// estrutural"*): eram duas noções de igualdade no mesmo arquivo, uma negando a
  /// outra.
  ///
  /// Quem quer label/default é o [sameSignature] — override e conformance
  /// comparam **declarações**, não tipos.
  @override
  bool operator ==(Object other) => other is ParamType && other.type == type;
  @override
  int get hashCode => type.hashCode;
  @override
  String toString() => label == null ? '$type' : '$label: $type';
}

/// 6.3.1: `s → t`. `isAsync` espelha `FunctionType.isAsync` da AST.
///
/// ⚠️ **[params] carrega LABEL e DEFAULT** — e não carregava. O buraco produzia
/// **programa errado em silêncio**, não só lacuna de tipo:
///
/// ```
/// fn div(num: Int, den: Int) -> Int => num
/// div(den: 2, num: 10)   // ⟶ SEM ERRO, e liga num=2, den=10
/// ```
///
/// Os args ligavam **por posição** e os labels eram **decorativos e mentiam**.
/// Também: `fn f(x: Int = 1)` chamada `f()` dava `arity-mismatch` FALSO, e
/// `f(zz: 1)` (label inexistente) passava.
///
/// ⚠️ Aqui dizia *"é pré-condição do memberwise, que é **sempre chamado por
/// label** (ruling do dono 2026-07-15)"*. **Esse ruling não existe** — rastreado
/// em ADR-0012, spec 011 §12 e nas memórias: o "memberwise exige label?" é
/// **pergunta levada ao dono, sem resposta**. Era conclusão escrita na voz dele.
/// Ruling fabricado no código é da família do P4: **o código reivindica autoridade
/// que não tem**, e o próximo leitor não tem como saber.
///
/// O que **é** ruling do dono: *"ordem obrigatória, defaults saltáveis; o label
/// **confirma**, não reordena"*. Hoje `P(1, 2)` tipa — e a decisão de o proibir
/// vale para **toda chamada**, não só o memberwise, porque `_paramType` dá
/// `label: p.label ?? p.name` a todo param e a gramática **não tem opt-out** (o
/// `_` do Swift não parseia). **Lacuna declarada, do dono.**
final class FunctionType extends Type {
  final List<ParamType> params;
  final Type ret;
  final bool isAsync;

  /// O **prefixo ∀** desta assinatura — os quantificadores, **na ordem
  /// DECLARADA**.
  ///
  /// **6.5.4 é literal:** o tipo de `length` **É** `∀α. list(α) → integer` —
  /// *"Uma expressão de tipo contendo um símbolo ∀ será referenciada
  /// informalmente como um 'tipo polimórfico'"*. O prefixo é **parte do tipo**,
  /// não algo a recomputar varrendo-o.
  ///
  /// Em ML o prefixo é **computado** por generalização (Alg. 6.16: *"Ligue
  /// quaisquer variáveis de tipo que permanecerem sem restrições em s → t por
  /// quantificadores ∀"*). O Itá **recusa let-generalization** (§4.4) ⟹ o prefixo
  /// é **escrito pelo usuário**: `FnDecl.generics` / `TypeInfo.generics`. A ordem
  /// vem de graça, e é a única honesta — qualquer outra seria **inventada pelo
  /// compilador** (P4).
  ///
  /// ⚠️ **O que fica FORA do prefixo é RÍGIDO e não se instancia.** Era o buraco
  /// do `_freeParams`, que reconstruía a lista varrendo a assinatura: ele pegava
  /// o `T` da CLASSE dona quando o receptor era `Box<T>` dentro do próprio corpo
  /// ⟹ rígido virava buraco ⟹ `self.set(x: 5)` **tipava**. Rígido × flexível
  /// (skolem × unificação) é da literatura, não do Dragon — cujo Alg. 6.16 é
  /// prenex/top-level (ML, sem classes) e por isso **nunca** encara binder
  /// aninhado (classe genérica × método genérico). Fonte: Peyton Jones,
  /// Vytiniotis, Weirich & Shields, *"Practical type inference for arbitrary-rank
  /// types"*, JFP 17(1), 2007, §4; OutsideIn(X), JFP 21, 2011.
  final List<TypeParamType> quantifiers;

  const FunctionType(
    this.params,
    this.ret, {
    this.isAsync = false,
    this.quantifiers = const [],
  });

  /// Atalho para quem só tem tipos (closures, `Ops`, testes). Prefixo ∀ vazio por
  /// default: closure **não tem** quantificador (sem let-generalization, §4.4).
  FunctionType.positional(
    List<Type> types,
    this.ret, {
    this.isAsync = false,
    this.quantifiers = const [],
  }) : params = [for (final t in types) ParamType(t)];

  /// ⚠️ O prefixo entra **porque ele É parte do tipo** (6.5.4: o tipo de `length`
  /// *é* `∀α. list(α) → integer`) — `∀T. T → T` e `Int → Int` são tipos distintos
  /// de facto, e o `==` responde *"é o mesmo tipo?"*.
  ///
  /// A comparação é **SINTÁTICA — não α-equivalente** (6.5.4: *"Variáveis ligadas
  /// podem ser renomeadas, desde que todas as ocorrências … sejam renomeadas"*).
  /// Logo é **incompleta mas sound**: pode dizer "diferentes" para dois tipos que
  /// só diferem no NOME do quantificador, mas **nunca** iguala o que difere. Quem
  /// precisa da α-equivalência é o [sameSignature].
  ///
  /// (O `override-signature-mismatch` **não** depende disto: o [sameSignature]
  /// compara `quantifiers.length` na **primeira linha** e pega a troca sozinho.
  /// Dizer que ele dependia era doc a inventar uma razão para uma decisão certa.)
  @override
  bool operator ==(Object other) =>
      other is FunctionType &&
      other.isAsync == isAsync &&
      other.ret == ret &&
      _listEq(other.params, params) &&
      _listEq(other.quantifiers, quantifiers);
  @override
  int get hashCode =>
      Object.hash(Object.hashAll(params), ret, isAsync, Object.hashAll(quantifiers));
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
    // A substituição troca o TIPO; label e default são da DECLARAÇÃO e não
    // dependem de type-args — atravessam intactos.
    //
    // **O prefixo ∀ também atravessa intacto, e captura NÃO ocorre**: o domínio
    // desta substituição é param-DA-CLASSE e o contradomínio são os `recv.args` —
    // os dois vêm de FORA do método, logo nenhum quantificador do prefixo pode ser
    // capturado. Quem remove o prefixo é o `instantiate` (Alg. 6.16), e só ele.
    // (O Dragon não discute captura: os ∀ dele são prenex e a generalização só
    // acontece em definições.)
    FunctionType n => FunctionType(
      [
        for (final p in n.params)
          ParamType(
            substitute(p.type, s),
            label: p.label,
            hasDefault: p.hasDefault,
          ),
      ],
      substitute(n.ret, s),
      isAsync: n.isAsync,
      quantifiers: n.quantifiers,
    ),
    TupleType n => TupleType([for (final e in n.elements) substitute(e, s)]),
    _ => t, // básicos, Never, Error
  };
}

/// `a ≡α b` — duas assinaturas são **a mesma a menos de renomeação das
/// variáveis LIGADAS**.
///
/// **6.5.4 licencia, e exige, exatamente isto:** *"Variáveis ligadas podem ser
/// renomeadas, desde que todas as ocorrências … sejam renomeadas"*. O `==` do
/// [FunctionType] é **sintático** — compara os [TypeParamType] do prefixo por
/// identidade de (dono, nome) —, e o dono de um quantificador é **a `FnDecl` que o
/// declarou**. Logo, para
///
/// ```
/// class A { fn ident<T>(x: T) -> T => x }
/// class D : A { override fn ident<T>(x: T) -> T => x }
/// ```
///
/// os dois `T` são `TypeParamType(A.ident, 'T')` e `TypeParamType(D.ident, 'T')` —
/// **diferentes** — e o `==` diria "assinaturas distintas". Seria
/// `override-signature-mismatch` num override **perfeito**, e o usuário não teria
/// conserto: não há como escrever "o mesmo `T` daquela outra decl".
///
/// A regra de override (e a de conformance de trait) é *"a mesma assinatura"*, e
/// *mesma* aqui é **α-equivalência**, não igualdade de nós. É por isso que esta
/// função existe e o `==` não muda: o `==` responde *"é o mesmo tipo?"* (e aí
/// `fn f<T>(x: Int)` **não** é `fn f(x: Int)` — sem o prefixo no `==`, a troca
/// passaria); esta responde *"uma cumpre a promessa da outra?"*.
/// A régua das duas noções — quem compara o quê:
///
/// | Noção | Compara | `label` | `hasDefault` |
/// | :-- | :-- | :-: | :-: |
/// | `==` de **TIPO** (`unify`, `_isSubtype`, anotação) | dois **tipos** | não | não |
/// | [sameSignature] (override / conformance) | duas **declarações** | **sim** | **sim** |
bool sameSignature(FunctionType a, FunctionType b) {
  if (a.quantifiers.length != b.quantifiers.length) return false;
  if (!_sameParamDecls(a.params, b.params)) return false;
  if (a.quantifiers.isEmpty) return a == b;
  // Renomeia o prefixo de `b` para o de `a`, **posicionalmente** — que é o que
  // "renomear todas as ocorrências" quer dizer quando os dois prefixos são
  // listas ordenadas.
  final renamed = substitute(b, {
    for (var i = 0; i < b.quantifiers.length; i++)
      b.quantifiers[i]: a.quantifiers[i],
  }) as FunctionType;
  // O `substitute` preserva o prefixo intacto (a captura não o alcança), então o
  // prefixo de `renamed` ainda é o de `b` — trocá-lo aqui é o último passo da
  // renomeação, não um atalho.
  return a ==
      FunctionType(
        renamed.params,
        renamed.ret,
        isAsync: renamed.isAsync,
        quantifiers: a.quantifiers,
      );
}

/// O que o `==` de [ParamType] **não** compara, porque é da DECLARAÇÃO: o `label`
/// e o `hasDefault`. Aqui compara — é o lado da promessa.
///
/// **`label`:** foi o item 0 da 011 (`div(den: 2, num: 10)` ligando por posição
/// em silêncio). Um override que **renomeia** o label quebra quem chama por nome.
///
/// **`hasDefault`:** o ruling é `≤` não pode mentir (009 §4.2b), e a direção é
/// contra-intuitiva — quem chama via `A` **não** quebra (a assinatura de `A` tem o
/// default). Quebra **quem chama via `D`**: `d.f()` dá `missing-argument`, e `f()`
/// é aceito pela API de `A` ⟹ **`D` não faz tudo que um `A` faz**. Das três
/// disciplinas candidatas — idêntico / default livre / contravariante (pode
/// ADICIONAR, não REMOVER) —, "livre" cai sozinha (o mesmo objeto responderia
/// diferente conforme o tipo **estático** da referência, sem marca sintática), e
/// as outras duas **dizem erro** ⟹ entailment, não escolha.
///
/// Hoje é **idêntico**, por monotonia: restringir agora e relaxar depois preserva
/// todo programa válido. *Pode um override ADICIONAR default?* fica aberto — é o
/// único ponto que a disciplina contravariante mudaria, e é este.
bool _sameParamDecls(List<ParamType> a, List<ParamType> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].label != b[i].label || a[i].hasDefault != b[i].hasDefault) {
      return false;
    }
  }
  return true;
}

// --- helpers ----------------------------------------------------------------

bool _listEq(List<Object> a, List<Object> b) {
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
