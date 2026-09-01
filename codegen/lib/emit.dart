// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// emit.dart — o EMITTER da F7 (B2, CA1 mínimo). Anda o `CheckResult`
// (F5+F6-verde) e produz o `Component`: a AST REAL do Itá → Dart Kernel.
//
// ESCOPO: o **CA1** (`fn main() { print("olá, ${1 + 1}") }`, spec 013 §11) +
// a §7.4-a (interpolação, literais `Int`, aritmética de `Int`). Qualquer nó fora
// disso vira **ICE honesto** (`ice-codegen-*` com o nome do nó, §7.8) — NUNCA
// `dynamic`, NUNCA silêncio (ADR-0013). O mapa nó→Kernel:
//
//   FnDecl `main` (aridade 0, Void) → Procedure static top-level (mainMethod)
//   BlockBody                        → Block            (ExprBody → ICE)
//   ExprStmt                         → ExpressionStatement
//   Call(callee ⇒ GroundRes('print'))→ StaticInvocation.byReference(dart:core::print)
//   Str SEM interp                   → StringLiteral
//   Str COM interp                   → StringConcatenation (a parte não-String
//                                       ganha `toString()` implícito da VM — o nó
//                                       NÃO o representa; Grupo B)
//   IntLit                           → IntLiteral
//   BoolLit                          → BoolLiteral
//   Binary add/sub/mul/div/mod (Int) → InstanceInvocation de dart:core::num
//                                       (div → `~/`; pow → ICE)
//   Binary lt/gt/le/ge (Int/Float)   → InstanceInvocation de dart:core::num
//                                       (`<`/`>`/`<=`/`>=`; receptor não-numérico → ICE)
//   Binary eq/ne                     → EqualsCall / Not(EqualsCall) — `==` é nó
//                                       ESPECIAL no Kernel (não InstanceInvocation);
//                                       `interfaceTarget` = o `==` do tipo do receptor
//                                       (Int→num::==, String→String::==, Bool→Object::==)
//   Binary and/or                    → LogicalExpression (curto-circuito é do nó, Grupo B)
//   IfExpr (forma booleana)          → ConditionalExpression(cond, then, orElse, staticType)
//                                       (if-let, `binding != null` → ICE — fatia do `match`)
//
// O `print` é resolvido no [platform] carregado (a receita do `hello.dart`); o
// handoff do B1 é o callee: um `Ident` cuja `check.resolution[ident]` é a
// `GroundRes('print')` da F4 (`binding/scope.dart`).

import 'package:kernel/ast.dart' as k;
// `Substitution.fromInterfaceType` (`type_algebra.dart:584`) — a receita do §7.2
// da spec 012 para instanciar o `functionType`/`resultType` dos membros
// genéricos de `dart:core`. Ver [_groundReceiver].
import 'package:kernel/type_algebra.dart' show Substitution;

import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// ICE de codegen (§7.8): impossibilidade INTERNA da emissão. A F7 **não tem
/// erro de usuário** — sua entrada é programa F5+F6-verde. Se isto dispara sobre
/// corpus, é bug de fase anterior que vazou, não input malformado.
class CodegenIce implements Exception {
  /// `ice-codegen-*`, EN kebab-case, com o nome do nó que abortou.
  final String code;
  final int offset;
  final int length;

  CodegenIce(this.code, this.offset, this.length);

  @override
  String toString() => 'ice: $code @$offset+$length';
}

Never _ice(String suffix, ast.AstNode node) =>
    throw CodegenIce('ice-codegen-$suffix', node.offset, node.length);

/// O que uma variante de `enum` SELADO virou (§7.4-c): a subclasse, seu
/// construtor, os campos do payload por NOME, e — só para variante sem payload —
/// o singleton estático.
/// **Um sítio de travessia existencial** (CA11): o nó que a emissão pôs ali, e
/// as `k.Class` que ela associou ao tipo-FONTE.
///
/// As classes vêm juntas porque só o emitter as conhece por IDENTIDADE —
/// `_classes` e `_variants` são `Map.identity` sobre a decl. Deixar o invariante
/// recomputá-las pelo NOME (`enclosingClass.name == decl.name`) seria a R1:
/// grafia não é injetiva, e além disso o nome nem casaria — `Forma.circulo(1.0)`
/// constrói a classe da VARIANTE, não a do enum.
typedef Travessia = ({k.Expression no, Set<k.Class> classesDaFonte});

class _Variant {
  final k.Class cls;
  final k.Constructor ctor;
  final Map<String, k.Field> fields;
  final k.Field? singleton;
  const _Variant(this.cls, this.ctor, this.fields, this.singleton);
}

/// Emite as libs do programa [check] (F5+F6-verde) e o `Procedure` de `main`,
/// resolvendo o interop enumerado `dart:core::print` (§8.2) contra o [platform]
/// carregado. O `finalizeProgram` fixa o `main` como `Component.mainMethod`.
///
/// [sourceUri] vira o `fileUri` dos nós (forward-compat span→stack-trace); o
/// default cobre o uso à mão / testes.
({
  List<k.Library> libs,
  k.Procedure main,
  Map<ast.Expr, Travessia> travessias,
}) emitProgram(
  CheckResult check,
  k.Component platform, {
  Uri? sourceUri,
}) {
  final fileUri = sourceUri ?? Uri.parse('file:///main.tu');
  final libUri = Uri.parse('app:///main.dart');

  // A `Library` nasce ANTES do emitter porque `k.Name` a exige para todo nome
  // que começa com `_` (ver `_memberName`).
  final lib = k.Library(libUri, fileUri: fileUri);
  final emitter = _Emitter(
    check,
    _resolvePrintRef(platform),
    _resolveArithOps(platform),
    _resolveFloatDiv(platform),
    _resolveNegOp(platform),
    _resolveCmpOps(platform),
    _resolveEqualsOps(platform),
    _resolveCoreTypes(platform),
    _resolveGroundTargets(platform),
    _dartCoreClass(platform, 'Object'),
    lib,
    fileUri,
  );
  final emitted = emitter.emitTopLevel();
  for (final c in emitted.classes) {
    lib.addClass(c);
  }
  for (final p in emitted.procedures) {
    lib.addProcedure(p);
  }
  return (
    libs: [lib],
    main: emitted.main,
    travessias: emitter.travessias,
  );
}

/// Acha `dart:core::print` no platform carregado (receita do `hello.dart` /
/// `generate_dill.dart` do oracle). Único built-in de I/O do chão (§7.6).
k.Reference _resolvePrintRef(k.Component platform) {
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  return dartCore.procedures
      .firstWhere((p) => p.name.text == 'print')
      .reference;
}

/// Resolve os aritméticos de `Int` da `_primitiveOps` (add/sub/mul/div/mod) →
/// o `Procedure` do operador no platform, de onde saem `interfaceTarget` +
/// `functionType` (o Kernel os exige non-nullable; sem eles a chamada cairia em
/// `DynamicInvocation`).
///
/// ⚠️ **Os operadores aritméticos de `int` são HERDADOS de `dart:core::num`** —
/// `int` só sobrescreve o `unary-` (int.dart:311). `+`/`-`/`*`/`%`/`/`/`~/` vivem
/// em `num` (num.dart:110-172), logo o interfaceTarget é o membro de `num` —
/// exatamente o que a CFE emitiria para `1 + 1`.
///
/// ⚠️ **A CONVENÇÃO DE DIVISÃO DO ITÁ É TRUNCADA** (N1, decidido por delegação
/// do dono em 2026-07-29 — registrado na spec 001 §5).
///
/// O Dart mistura DUAS convenções, e o Itá tinha pegado uma de cada:
///
/// | | `-7 ? 3` | convenção |
/// |---|---|---|
/// | `~/`          | `-2` | truncado (para zero) |
/// | `%`           | `2`  | **euclidiano** (resto nunca negativo) |
/// | `.remainder()`| `-1` | truncado |
///
/// Com `~/` + `%`, a identidade fundamental QUEBRAVA:
/// `(-7 / 3) * 3 + (-7 % 3)` dava **-4**, não -7. Não era escolha de design —
/// era um método de cada convenção, pegos separadamente.
///
/// O próprio SDK diz qual é o par coerente, verbatim (`num.dart:164-165`):
/// *"Then `a ~/ b` corresponds to `a.remainder(b)` such that
/// `a == (a ~/ b) * b + a.remainder(b)`"*.
///
/// **Truncado e não floored/euclidiano**, por três razões nesta ordem: (1) a
/// meta-diretriz da casa é o Swift (ADR-0016 §A) e Swift é truncado
/// (`-7 % 3 == -1`); (2) custo de emissão ZERO — floored exigiria aritmética
/// própria, abrindo frente de divergência com o dart2js que o ADR-0005 vigia;
/// (3) é a convenção de C, C++, Java, C#, Go, Rust e Swift.
///
/// **O custo, declarado:** `i % n` pode ser NEGATIVO. Índice circular sobre
/// valor possivelmente negativo precisa de cuidado explícito — o mesmo custo
/// que C, Java e Swift têm, e o oposto de Python.
///
/// ⚠️ **`div` (`/`) do Itá é `Int → Int`** (F5 `_primitiveOps`), mas o
/// `num operator /` devolve **`double`** (num.dart:155). A divisão inteira que
/// devolve `int` é o `~/` (`num operator ~/`, num.dart:172). Por isso
/// `BinaryOp.div → ~/`, senão o resultado vazaria como `double` (quebra de tipo
/// e de paridade). Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/num.dart`.
Map<ast.BinaryOp, k.Procedure> _resolveArithOps(k.Component platform) {
  final num = _dartCoreClass(platform, 'num');
  k.Procedure op(String symbol) => num.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Operator && p.name.text == symbol,
      );
  // `remainder` é MÉTODO, não operador — e é de propósito que ele seja o alvo
  // do `%` do Itá. Ver a nota sobre a convenção truncada, logo abaixo.
  k.Procedure metodo(String nome) => num.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Method && p.name.text == nome,
      );
  return {
    ast.BinaryOp.add: op('+'),
    ast.BinaryOp.sub: op('-'), // binário; o unário é `unary-` (names.dart:55) — não colide
    ast.BinaryOp.mul: op('*'),
    ast.BinaryOp.div: op('~/'), // o de **Int**; o de Float é `/` — ver [_resolveFloatDiv]
    // **`%` do Itá é TRUNCADO — `remainder`, não o `%` do Dart** (N1, decidido
    // por delegação em 2026-07-29; ver a nota de convenção acima do mapa).
    ast.BinaryOp.mod: metodo('remainder'),
  };
}

/// O `/` de `dart:core::num` — o alvo do `div` quando os operandos são **Float**.
///
/// `div` é o ÚNICO aritmético cujo alvo Kernel depende do TIPO, porque a tabela
/// da F5 (`check.dart:65-68`) o admite nas DUAS formas:
///
///     div: (Int, Int) -> Int      ⟹  `~/`  (`num operator ~/` devolve **int**)
///     div: (Float, Float) -> Float ⟹  `/`   (`num operator /` devolve **double**)
///
/// Emitir `~/` para Float faria `7.0 / 2.0` render **3**, não `3.5` — o tipo
/// estático mentiria sobre o valor. É a MESMA armadilha que o `~/` de Int fecha,
/// na direção oposta: cada um dos dois operadores é o errado para o outro tipo.
/// Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/num.dart:155` (`/`) e `:172` (`~/`).
k.Procedure _resolveFloatDiv(k.Component platform) =>
    _dartCoreClass(platform, 'num').procedures.firstWhere(
          (p) => p.kind == k.ProcedureKind.Operator && p.name.text == '/',
        );

/// O `unary-` de `dart:core::num` — nome DEDICADO (`names.dart:55`) para não
/// colidir com a subtração binária. É também o único aritmético que `int`
/// sobrescreve em vez de herdar (`int.dart:311`). Ver [_Emitter._unary].
k.Procedure _resolveNegOp(k.Component platform) =>
    _dartCoreClass(platform, 'num').procedures.firstWhere(
          (p) => p.kind == k.ProcedureKind.Operator && p.name.text == 'unary-',
        );

/// Resolve as comparações de ORDEM (`<`/`>`/`<=`/`>=`) → o `Procedure` do
/// operador em `dart:core::num` — **mesma receita/mesmo `InstanceInvocation` dos
/// aritméticos** (herdados por `int`/`double`). Os quatro vivem em `num`
/// (num.dart:217/224/231/238, devolvem `bool`); o `interfaceTarget` +
/// `functionType` saem daí (`bool Function(num)`). Fonte: SDK pinado
/// `.dart-sdk/3.12.2/.../core/num.dart`.
///
/// ⚠️ Só valem para receptor NUMÉRICO. `String < String` **não existe** no
/// Kernel (`String` não declara `<`); a F5 só cobra `comparison-type-mismatch`
/// (tipos iguais), não "tem operador". Um `<` de receptor não-numérico é ICE
/// (`ice-codegen-cmp-on-<Tipo>`) — nunca emitir um `<` que a VM rejeita.
Map<ast.BinaryOp, k.Procedure> _resolveCmpOps(k.Component platform) {
  final num = _dartCoreClass(platform, 'num');
  k.Procedure op(String symbol) => num.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Operator && p.name.text == symbol,
      );
  return {
    ast.BinaryOp.lt: op('<'),
    ast.BinaryOp.gt: op('>'),
    ast.BinaryOp.le: op('<='),
    ast.BinaryOp.ge: op('>='),
  };
}

/// Resolve o alvo do `==` (`EqualsCall.interfaceTarget`) POR TIPO de receptor.
/// `==` é nó ESPECIAL no Kernel (`EqualsCall`, expressions.dart:2471) e o
/// `interfaceTarget` é o `operator ==` **de interface** do tipo estático do
/// receptor — o que a CFE grava para `l == r` non-null:
///
///   - `Int`  → `num::==`    (`int` NÃO declara `==`; herda de `num`, num.dart:47)
///   - `Float`→ `num::==`    (idem `double`)
///   - `String`→ `String::==` (declara o seu, string.dart:244)
///   - `Bool` → `Object::==`  (`bool` NÃO declara `==`; herda de `Object`, object.dart:53)
///
/// A F5 aceita `l == r` de QUALQUER par de tipos idênticos, mas o emitter só sabe
/// baixar estes quatro escalares; receptor fora da tabela → ICE (o operando já
/// seria intraduzível). Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/`.
Map<Type, k.Procedure> _resolveEqualsOps(k.Component platform) {
  k.Procedure eqOf(String className) =>
      _dartCoreClass(platform, className).procedures.firstWhere(
            (p) => p.kind == k.ProcedureKind.Operator && p.name.text == '==',
          );
  final numEq = eqOf('num');
  return {
    const IntType(): numEq,
    const FloatType(): numEq,
    const StringType(): eqOf('String'),
    const BoolType(): eqOf('Object'),
  };
}

k.Class _dartCoreClass(k.Component platform, String name) {
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  return dartCore.classes.firstWhere((c) => c.name == name);
}

/// Os tipos do CHÃO que a F7 sabe baixar (§7.4-a + `let`): os básicos `Int`/
/// `String`/`Bool` → `InterfaceType` **non-nullable** (ADR-0013) das classes de
/// `dart:core` resolvidas do [platform] (mesma receita do `print`/`num`); `Void`
/// → `VoidType`. A tabela é keyed pelos `Type` da F5 — que têm `==`/`hashCode`
/// de valor (`type.dart:82-128`), logo `const IntType()` casa qualquer `IntType`.
///
/// Tudo fora destes quatro é ICE honesto (`ice-codegen-type-<Tipo>`): o Kernel
/// exige `VariableDeclaration.type` non-nullable, e sem imagem aqui só sobraria
/// `dynamic` — a porta dos fundos que o ADR-0013 tranca.
Map<Type, k.DartType> _resolveCoreTypes(k.Component platform) {
  k.DartType iface(String name) =>
      k.InterfaceType(_dartCoreClass(platform, name), k.Nullability.nonNullable);
  return {
    const IntType(): iface('int'),
    const FloatType(): iface('double'), // `Float` do Itá ≡ `double` do Dart (IEEE-754 binary64)
    const StringType(): iface('String'),
    const BoolType(): iface('bool'),
    const VoidType(): const k.VoidType(),
  };
}

/// **A FORMA do chão** (spec 012 §4.1) — as três que têm `.length`/`[]`.
///
/// Espelha o `_groundShape` da F5 (`check.dart:2336-2345`), e é derivada do
/// **TIPO** que ela provou (side-table nº1), nunca do lexema do receptor: é a
/// chave injetiva que a R1 exige. `Result` e `Option` ficam de fora de propósito
/// — não são chão, e o segundo sequer tem classe no `.dill` (ver [_emitType]).
enum _GroundShape { list, map, string }

/// Os alvos de `dart:core` do chão, resolvidos 1× do platform (§7.2 da spec 012).
///
/// **Enumerado, não descoberto** — Art. IV: a interop `dart:` desta fatia é
/// `dart:core::{List,String,Map}::{length,[],+}` e mais nada. Uma resolução por
/// busca ("acha um membro chamado X no receptor") transformaria a tabela FECHADA
/// da spec 012 §4.1 numa lista-branca aberta — o gate cuja falha-padrão é OK.
///
/// ⚠️ **`length` é GETTER, não field** nas três (`list.dart:408`,
/// `string.dart:224`, `map.dart:460` do pin 3.12.2) — `procedures` com
/// `ProcedureKind.Getter`, não `fields`. Procurar em `fields` devolveria
/// `StateError` de `firstWhere` na primeira compilação.
///
/// `Map` não tem `+` (o `dart:core::Map` não declara operador de união), e por
/// isso ele não está aqui: a F5 já reprova `m1 + m2` com `no-operator-for-types`
/// (`check.dart:1688`, ramo List-concat só admite `BuiltinKind.list`).
///
/// ⚠️ **`plus[string]` está nesta tabela por EMISSÃO, não por classificação.**
/// `String + String` é operador **primitivo** para a F5 — vive em
/// `_primitiveOps` (`check.dart:55`), na mesma lista de `Int+Int`, e não no
/// `_groundField`/`_index` que definem o chão; a tabela FECHADA da spec 012 §4.1
/// o omite corretamente. O que a spec 012 §7.2 exige, e faltava, é que ele tenha
/// **alvo dirigido por tipo** como qualquer outro: classificar o operador não é
/// o mesmo que escolher o `interfaceTarget`, e foi nessa lacuna que o `num::+`
/// sobre `String` morou. Não ler este mapa como se fosse a tabela do chão.
typedef _GroundTargets = ({
  Map<_GroundShape, k.Class> classes,
  Map<_GroundShape, k.Procedure> length,
  Map<_GroundShape, k.Procedure> index,
  Map<_GroundShape, k.Procedure> plus,
});

_GroundTargets _resolveGroundTargets(k.Component platform) {
  k.Procedure getter(k.Class c, String name) => c.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Getter && p.name.text == name,
      );
  k.Procedure op(k.Class c, String symbol) => c.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Operator && p.name.text == symbol,
      );
  final list = _dartCoreClass(platform, 'List');
  final map = _dartCoreClass(platform, 'Map');
  final string = _dartCoreClass(platform, 'String');
  return (
    classes: {
      _GroundShape.list: list,
      _GroundShape.map: map,
      _GroundShape.string: string,
    },
    length: {
      _GroundShape.list: getter(list, 'length'),
      _GroundShape.map: getter(map, 'length'),
      _GroundShape.string: getter(string, 'length'),
    },
    index: {
      _GroundShape.list: op(list, '[]'),
      _GroundShape.map: op(map, '[]'),
      _GroundShape.string: op(string, '[]'),
    },
    plus: {
      _GroundShape.list: op(list, '+'),
      _GroundShape.string: op(string, '+'),
    },
  );
}

class _Emitter {
  final CheckResult check;
  final k.Reference printRef;

  /// `dart:core::num` operators (add/sub/mul/div→`~/`/mod), resolvidos 1× do
  /// platform. A `Str` interpolada NÃO precisa deles — a conversão para String é
  /// da VM (`StringBase._interpolate`), não uma call que emitimos.
  final Map<ast.BinaryOp, k.Procedure> arithOps;

  /// O `/` de `num` — alvo do `div` quando os operandos são **Float**. Ver
  /// [_resolveFloatDiv]: o `~/` de [arithOps] devolveria `int` e o tipo estático
  /// mentiria sobre o valor (`7.0 / 2.0` renderia 3).
  final k.Procedure floatDiv;

  /// O `unary-` de `num` — alvo do `-x`. Ver [_unary]: **não** é o `-` binário.
  final k.Procedure negOp;

  /// Comparações de ORDEM (`<`/`>`/`<=`/`>=`) → operador de `dart:core::num`,
  /// resolvidos 1×. Mesmo `InstanceInvocation` dos aritméticos. Ver [_resolveCmpOps].
  final Map<ast.BinaryOp, k.Procedure> cmpOps;

  /// `==` por tipo de receptor (Int/Float→`num::==`, String→`String::==`,
  /// Bool→`Object::==`), para o `interfaceTarget` do `EqualsCall`. Ver
  /// [_resolveEqualsOps].
  final Map<Type, k.Procedure> equalsOps;

  /// Os tipos do chão (`Int`/`String`/`Bool`/`Void`) → `DartType`, resolvidos 1×
  /// do platform. Ver [_resolveCoreTypes].
  final Map<Type, k.DartType> coreTypes;

  /// `List`/`Map`/`String` de `dart:core` + os `length`/`[]`/`+` deles (spec 012
  /// §7.2), resolvidos 1×. Ver [_resolveGroundTargets].
  final _GroundTargets ground;

  /// A `Library` do programa — necessária para nomes privados (ver [_memberName]).
  final k.Library lib;
  final Uri fileUri;

  /// **A 2ª side-table (LT-F7b): `binder → VariableDeclaration`-Kernel.** É da
  /// EMISSÃO — Nystrom §11.4, off-the-node e descartável —, campo de instância
  /// deste visitor. POPULADA quando `_let` baixa a decl (`_kernelDecls[binder] =
  /// varDecl`), CONSULTADA no uso (`_ident` → `VariableGet`).
  ///
  /// Chave `Map.identity` (não `==`): o binder é o `BindPattern` (`ast.dart:634`),
  /// que é o objeto para o qual o `LocalRes.binder` da F4 aponta (`scope.dart:45`)
  /// e a chave de `binderTypes` (nº6). Homônimos em escopos distintos são nós
  /// DISTINTOS — só a identidade os separa (mesma disciplina da `resolution`).
  ///
  /// ⚠️ Débito D4: no destructuring a chave vira `(binder, fieldName)` — fatia
  /// futura; hoje só `BindPattern` (uma variável, um binder).
  final Map<Object, k.VariableDeclaration> _kernelDecls = Map.identity();

  /// **`FnDecl` → `Procedure`** — o alvo do `StaticInvocation`. Preenchida no
  /// passo 1 de [emitTopLevel] (assinaturas) e consultada no passo 2 (corpos),
  /// que é o que faz recursão e forward-reference funcionarem.
  ///
  /// A chave é `Map.identity` pela mesma razão das outras: é o nó que a
  /// `TopLevelRes.decl` da F4 aponta, e identidade é o que separa homônimos.
  final Map<ast.FnDecl, k.Procedure> _procedures = Map.identity();

  /// A raiz implícita de toda `Class` que emitimos (§8.2 — `dart:core::Object` é
  /// interop ENUMERADO). O Kernel exige `supertype` non-null em classe concreta.
  final k.Class objectClass;

  /// **`StructDecl`/`ClassDecl` → `Class`**, e os dois satélites que a emissão de
  /// uso precisa: o `Constructor` (alvo do `ConstructorInvocation`) e os `Field`
  /// por nome (alvo do `InstanceGet`).
  ///
  /// Preenchidos no passo 1 de [emitTopLevel] — junto das assinaturas de `fn`, e
  /// pelo mesmo motivo: um `fn` pode receber/devolver um tipo declarado ABAIXO
  /// dele, e a `InterfaceType` precisa da `Class` já existindo.
  final Map<ast.AstNode, k.Class> _classes = Map.identity();
  final Map<ast.AstNode, k.Constructor> _constructors = Map.identity();
  final Map<ast.AstNode, Map<String, k.Field>> _fields = Map.identity();

  /// A classe de RUNTIME do `panic` (§7.4-f) — materializada sob demanda por
  /// [_panicCtor], para que programa sem `panic` não a carregue no `.dill`.
  k.Class? _panicClass;
  k.Constructor? _panicConstructor;

  /// **`EnumDecl` → variante → o que ela virou** (gabarito SELADO, §7.4-c).
  /// Vazio para enum sem payload, que usa constantes em [_fields].
  final Map<ast.AstNode, Map<String, _Variant>> _variants = Map.identity();

  /// **`TraitDecl` → requisito → `Procedure` abstrato** (§7.4-d). O conformer
  /// implementa cada um; o dispatch existencial aponta para eles.
  final Map<ast.AstNode, Map<String, k.Procedure>> _traitMembers = Map.identity();

  /// Métodos de instância emitidos, por tipo — o alvo do `v.metodo()`.
  final Map<ast.AstNode, Map<String, k.Procedure>> _methods = Map.identity();

  /// Corpos de método pendentes — emitidos no passo 2, junto dos de `fn`.
  final List<(ast.FnDecl, k.Procedure)> _methodBodies = [];

  /// Pilha de laços ABERTOS — o alvo de `break`/`continue`. Ver [_while].
  final List<({k.LabeledStatement brk, k.LabeledStatement cont, bool usedBrk, bool usedCont})> _loops = [];

  /// As subclasses de variante, na ordem de criação — entram na `Library` junto
  /// da base, e o CA10 as reconhece pelo prefixo `<Tipo>$`.
  final List<k.Class> _sealedVariants = [];

  /// **Membros que `impl`/`extension` contribuem ao tipo alvo** (ADR-0017 §1:
  /// *"todos os membros de conformance dentro dela — os vindos de
  /// `impl`/`extension` inclusive, como procedures comuns"*).
  ///
  /// Chave é a **decl do alvo** (identidade), não o nome: `extension Ponto` e um
  /// `struct Ponto` de outro escopo são tipos diferentes, e casar por lexema
  /// seria a redecisão com chave mais fraca que a R1 proíbe.
  final Map<ast.AstNode, List<ast.Decl>> _membrosDeExtensao = Map.identity();

  /// **Os sítios de travessia existencial → o nó que a emissão pôs lá** (CA11).
  ///
  /// Chave é o `ast.Expr` que cruzou para slot-trait, segundo a **nº7**; valor é
  /// a expressão Kernel emitida. Quem lê é o `checkExistentialZeroNode`, e o que
  /// ele cobra é que a emissão NÃO tenha interposto nada — *"fonte é sempre
  /// local ⟹ **zero nó emitido** (upcast é grátis)"* (spec 013 §7, side-table
  /// nº7).
  final Map<ast.Expr, Travessia> travessias = Map.identity();

  /// As `k.Class` que a emissão associou ao tipo-FONTE de uma travessia — a
  /// classe da decl e, quando ela é `enum`, também as das suas VARIANTES.
  ///
  /// Conjunto VAZIO quando a fonte não é nominal, e isso é falha fechada de
  /// propósito: built-in em slot `any` não chega à emissão — a F5 o recusa antes
  /// com `conformance-on-builtin-unsupported` (é o não-objetivo 2 da spec 013,
  /// *"Box de built-in em fronteira `any` → M5"*). Se chegar, o
  /// `checkExistentialZeroNode` acusa em vez de calar.
  Set<k.Class> _classesDaFonte(Type fonte) {
    if (fonte is! NamedType) return const {};
    final decl = fonte.decl;
    return {
      if (_classes[decl] case final c?) c,
      for (final v in _variants[decl]?.values ?? const <_Variant>[]) v.cls,
    };
  }

  /// **Cada `init` → o `Constructor` que ele produziu**, por identidade da decl.
  ///
  /// `_constructors` guarda só o PRIMÁRIO por tipo, e desde o CA3 um tipo tem
  /// mais de um construtor. A ponte do call-site até o certo é a
  /// `ResolvedCall.initTarget` — a F5 escolheu, isto apenas encontra.
  final Map<ast.InitDecl, k.Constructor> _initCtors = Map.identity();

  /// As conformances que `impl Trait for T`/`extension T : Trait` acrescentam.
  /// Vão para o `implementedTypes` do alvo, junto das declaradas no corpo.
  final Map<ast.AstNode, List<ast.TypeNode>> _traitsDeExtensao = Map.identity();

  /// Os **defaults** de cada trait: nome do método → o `Procedure` STATIC que
  /// carrega o corpo UMA vez (ADR-0017 §2, ruling R3: *"(iii) stub+static"*).
  final Map<ast.AstNode, Map<String, k.Procedure>> _traitDefaults = Map.identity();

  /// Corpos de default a emitir no passo 2, com a variável que substitui `self`.
  /// Separado de [_methodBodies] porque estes emitem sob [_selfComoVar].
  final List<(ast.FnDecl, k.Procedure, k.VariableDeclaration)> _defaultBodies = [];

  /// **Quando não-nulo, `self` na AST vira leitura DESTA variável**, em vez de
  /// `ThisExpression`. É a peça que permite ao corpo de um default virar um
  /// `static`: dentro dele não há `this`, e o receptor chega por parâmetro.
  ///
  /// Um campo em vez de um parâmetro de `_expr` porque `self` pode aparecer em
  /// qualquer profundidade da árvore, e enfiar o contexto em toda assinatura de
  /// `_expr`/`_stmt` espalharia por ~40 sítios uma informação que vale para uma
  /// subárvore inteira. É salvo-e-restaurado no único lugar que o liga.
  k.VariableDeclaration? _selfComoVar;

  /// O runtime de `Result` (§7.4-c), sob demanda — ver [_resultRuntime].
  ({k.Class base, k.Constructor okCtor, k.Field okValue, k.Constructor errCtor, k.Field errValue})?
      _resultParts;
  List<k.Class> _resultClasses = const [];

  _Emitter(
    this.check,
    this.printRef,
    this.arithOps,
    this.floatDiv,
    this.negOp,
    this.cmpOps,
    this.equalsOps,
    this.coreTypes,
    this.ground,
    this.objectClass,
    this.lib,
    this.fileUri,
  );

  /// Nome de MEMBRO (campo, método) — **não** `k.Name(x)` cru.
  ///
  /// No Kernel, nome iniciado por `_` é PRIVADO e exige a `Library` que o
  /// declara: `Name(x)` sem ela estoura `Null check operator used on a null
  /// value` (`names.dart:40`) — um crash com stack trace, nem sequer um ICE.
  ///
  /// ⚠️ **No Itá o `_` não significa privado** — visibilidade é `pub`
  /// (`isPublic`), não convenção de sublinhado. Um campo `_x` é só um nome, e
  /// passar a library preserva esse nome; a privacidade Dart resultante é inócua
  /// (o programa é uma library só). O que NÃO se pode é deixar o crash de pé.
  k.Name _memberName(String name) =>
      k.Name(name, name.startsWith('_') ? lib : null);

  /// Emite os itens top-level em **DOIS PASSOS** — e a ordem não é estilo, é
  /// exigência do **letrec de módulo** (§0.5-3, o mesmo que a F4 implementa):
  ///
  ///   1. **assinaturas** — todo `FnDecl` vira um `Procedure` (params + retorno,
  ///      corpo vazio), registrado em [_procedures];
  ///   2. **corpos** — só então cada corpo é emitido.
  ///
  /// Um passo único quebraria em duas formas que o Itá permite: **recursão**
  /// (`fn fat(n) => fat(n-1)` precisa do próprio alvo antes de o corpo existir) e
  /// **forward-reference** (`main` chamando uma `fn` declarada ABAIXO dela). O
  /// `StaticInvocation.targetReference` é non-nullable — não há como "preencher
  /// depois".
  ///
  /// `main` é achado por nome; sua existência e assinatura já foram validadas
  /// pelo DRIVER (`compile.dart::checkMain`, §12-5) — os ICEs aqui são rede
  /// contra chamada direta da lib, não diagnóstico de usuário.
  ({
    List<k.Class> classes,
    List<k.Procedure> procedures,
    k.Procedure main,
  }) emitTopLevel() {
    final fns = <ast.FnDecl>[];
    final structs = <ast.StructDecl>[];
    final enums = <ast.EnumDecl>[];
    final classes = <ast.ClassDecl>[];
    final traits = <ast.TraitDecl>[];
    for (final item in check.program.body) {
      switch (item) {
        case ast.FnDecl f:
          fns.add(f);
        case ast.StructDecl s:
          structs.add(s);
        case ast.EnumDecl e:
          enums.add(e);
        case ast.ClassDecl c:
          classes.add(c);
        case ast.TraitDecl t:
          traits.add(t);
        // `impl`/`extension` NÃO viram entidade no Kernel: os membros deles são
        // roteados para dentro da `Class` do alvo (ADR-0017 §1, merge-na-Class),
        // e é isso que faz o dispatch ser o mesmo de um membro inline — a vtable
        // da VM, sem tabela nossa. Emitir uma `Class` própria ou marcar
        // `isExtensionMember` daria outro dispatch, e o `verifier.dart:686-693`
        // ainda exigiria um descriptor de extensão na library.
        case ast.ExtensionDecl e:
          _coletaRetrofit(e.target, e.members, e.traits, e);
        case ast.ImplDecl i:
          _coletaRetrofit(
            i.target,
            i.members,
            // `impl Trait for T` conforma; `impl T` só acrescenta membros.
            i.trait == null ? const [] : [i.trait!],
            i,
          );
        default:
          _ice('toplevel-${item.runtimeType}', item); // `let` global
      }
    }

    // **Retrofit que não chega a lugar nenhum reprova.** Só `_struct` e `_class`
    // consomem `_membrosDeExtensao`; um `extension` sobre `enum` seria coletado
    // aqui e nunca emitido — o membro sumiria em SILÊNCIO, e `e.metodo()`
    // morreria com `NoSuchMethodError` em runtime, três fases depois da causa.
    // A completude de `implementedTypes` é 100% nossa (ADR-0017 §1: *"o verifier
    // **não confere nada**"*), então a guarda tem de ser aqui.
    for (final e in _membrosDeExtensao.entries) {
      final alvo = e.key;
      if (alvo is! ast.StructDecl && alvo is! ast.ClassDecl) {
        _ice('retrofit-on-${alvo.runtimeType}', alvo);
      }
      // ⚠️ **`InitDecl` de retrofit tem dono, e não é o `_addMethods`.** Ele
      // filtra `m is! ast.FnDecl` e DESCARTA o resto; quem emite os `init` de
      // `extension` é o `_addExtensionInits`, chamado por `_struct`/`_class`.
      // Enquanto essa dupla não existiu (CA6 → CA3), o `InitDecl` caía no
      // `continue` e sumia: `P(diagonal: 7)` morria com `NoSuchMethodError`, e
      // em `class` o arg ia para o construtor do CORPO — um `Bool` gravado em
      // campo `Int`, num `.dill` que passa no verify porque `verifyComponent` é
      // well-formedness, **não** type-checking (`verifier.dart:127-129`).
    }

    // ── Passo 1a-i — SHELLS de TODOS os tipos, antes de qualquer membro ──────
    //
    // ⚠️ **É a mesma cura que o passo 1b/2 já dá para `fn`, generalizada.** O
    // grafo de declarações de módulo é CÍCLICO por construção (`struct No {
    // prox: No? }` não tem ordem topológica), então uma passada linear sobre ele
    // só funciona por acidente da ordem — e a F4 provou o contrário: *"two-pass
    // no módulo (letrec): declara TODOS os nomes top-level, depois resolve os
    // corpos ⟹ ordem textual NÃO IMPORTA"* (`resolver.dart:71-75`).
    //
    // Até 2026-07-29 a emissão refutava esse teorema: os tipos saíam em ordem
    // fixa por espécie (traits → structs → enums → classes), e cada `_struct`
    // registrava `_classes[decl]` só na ÚLTIMA linha, depois de já ter emitido
    // os tipos dos campos. Programas legais ICEavam:
    //
    //   struct Peca { cor: Cor, n: Int }   // enum vem depois de struct: SEMPRE
    //   enum Cor { vermelho, azul }        //   ice-codegen-type-unemitted-enum
    //
    //   struct A { b: B }                  // B declarado abaixo
    //   struct B { n: Int }                //   ice-codegen-type-unemitted-struct
    //
    // O nome do ICE já denunciava a origem: `unemitted` nomeia ESTADO DO
    // EMISSOR, não construção da linguagem — logo é bug nosso, não fronteira.
    for (final t in traits) {
      _shell(t, t.name, isAbstract: true);
    }
    for (final s in structs) {
      _shell(s, s.name);
    }
    for (final e in enums) {
      // Enum com payload vira classe SELADA (abstrata) + uma subclasse por
      // variante; sem payload é classe concreta de constantes.
      _shell(e, e.name, isAbstract: e.cases.any((c) => c.payload.isNotEmpty));
    }
    for (final c in classes) {
      _shell(c, c.name);
    }

    // ── Passo 1a-ii — MEMBROS, com o grafo inteiro já visível ────────────────
    //
    // Traits primeiro ainda: o `implementedTypes` do conformer lê `isAbstract`,
    // que o shell já fixou, mas os REQUISITOS (`_traitMembers`) são preenchidos
    // aqui e o `_addMethods` do conformer os consulta.
    for (final t in traits) {
      _trait(t);
    }
    for (final s in structs) {
      _struct(s);
    }
    for (final e in enums) {
      _enum(e);
    }
    for (final c in classes) {
      _class(c);
    }
    // Passo 1b — assinaturas de `fn` (nada de corpo ainda).
    for (final fn in fns) {
      _procedures[fn] = _fnSignature(fn);
    }
    // Passo 2 — corpos, já podendo referenciar qualquer assinatura.
    for (final fn in fns) {
      _fnBody(fn, _procedures[fn]!);
    }
    for (final (m, proc) in _methodBodies) {
      _fnBody(m, proc);
    }
    // Corpos de default: emitidos com `self` LIGADO ao parâmetro do static.
    // Salvo-e-restaurado (em vez de só limpar no fim) porque um corpo de default
    // nunca aninha outro, mas deixar o campo sujo faria o próximo `_fnBody`
    // comum emitir `VariableGet(self)` no lugar de `this` — e isso é o tipo de
    // bug que roda igual até o primeiro método de struct depois de um trait.
    for (final (m, proc, selfVar) in _defaultBodies) {
      final anterior = _selfComoVar;
      _selfComoVar = selfVar;
      _fnBody(m, proc);
      _selfComoVar = anterior;
    }

    final main = fns.where((f) => f.name == 'main').firstOrNull;
    if (main == null) {
      throw CodegenIce(
        'ice-codegen-missing-main',
        check.program.offset,
        check.program.length,
      );
    }
    return (
      classes: [
        for (final s in structs) _classes[s]!,
        for (final e in enums) _classes[e]!,
        for (final c in classes) _classes[c]!,
        for (final t in traits) _classes[t]!,
        ..._sealedVariants,
        // O runtime do `panic` entra SÓ se algum corpo o materializou.
        if (_panicClass != null) _panicClass!,
        ..._resultClasses,
      ],
      procedures: [for (final fn in fns) _procedures[fn]!],
      main: _procedures[main]!,
    );
  }

  /// `enum` COM payload → **classe selada + uma subclasse por variante**
  /// (§7.4-c: *sum type*), o gabarito que o `match` destrói por `IsExpression`.
  ///
  /// Base `abstract`, cada variante uma subclasse com os campos do payload
  /// (`final`, como em `struct` — variante é valor). Variante SEM payload dentro
  /// de um enum selado ganha subclasse **e** um `static final` singleton: sem
  /// ele, `.ponto` alocaria um objeto novo a cada uso e a comparação por
  /// identidade quebraria — mas o `match` usa `IsExpression`, então o singleton
  /// é economia, não correção.
  ///
  /// ⚠️ **`SuperInitializer` é OBRIGATÓRIO aqui**, diferente do `struct`: lá o
  /// supertype é `Object` e o Kernel sintetiza a chamada; aqui a superclasse é a
  /// nossa base, e o construtor dela precisa ser invocado explicitamente.
  ///
  /// ⚠️ **Nome sintético com `$`** (`Forma$circulo`): o Itá reserva `$` para
  /// sintéticos — o próprio desugaring gera binders `$x0` —, então não colide com
  /// nome de usuário. O oracle usa `_` (`Forma_circulo`), que um `struct
  /// Forma_circulo` colidiria em silêncio.
  void _enumSealed(ast.EnumDecl decl) {
    final base = _classes[decl]!; // shell do passo 1a-i, já `isAbstract`
    final baseCtor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    base.addConstructor(baseCtor);

    final variants = <String, _Variant>{};
    for (final c in decl.cases) {
      final vCls = k.Class(
        name: '${decl.name}\$${c.name}',
        fileUri: fileUri,
        // ⚠️ `base.asThisSupertype` NÃO serve aqui: ele lê `enclosingLibrary`,
        // e a base ainda não foi anexada à `Library` (isso só acontece no fim
        // de `emitTopLevel`). O `Supertype` direto não depende do enclosing —
        // e sem type-params na base, é exatamente o mesmo valor.
        supertype: k.Supertype(base, const []),
      )..fileOffset = decl.offset;

      final fields = <String, k.Field>{};
      final params = <k.VariableDeclaration>[];
      final initializers = <k.Initializer>[];
      for (final p in c.payload) {
        if (p.name.startsWith('_')) _ice('enum-private-payload-${c.name}', decl);
        final type = p.type == null
            ? _ice('enum-payload-untyped-${c.name}', decl)
            : _emitType(check.annotations[p.type!] ?? const ErrorType(), decl);
        final field = k.Field.immutable(
          _memberName(p.name),
          type: type,
          fileUri: fileUri,
        )..fileOffset = p.offset;
        vCls.addField(field);
        fields[p.name] = field;

        // ⚠️ **O `initializer` NÃO pode faltar.** Este era o único dos cinco
        // sítios de default que lia `p.defaultValue` só para decidir
        // `isRequired` e **descartava a expressão**. A F5 permite saltar
        // (`hasDefault: p.defaultValue != null`), então `.circulo()` compilava
        // e a VM entregava **`null` num named non-nullable**: o programa
        // imprimia `raio null` para um `Int`, violando a nullity-invariant
        // ("nil só sob `T?`") sem uma linha de diagnóstico.
        //
        // Os outros quatro sítios (`_methodSignature`, `_initCtor`, `_struct`,
        // `_fnSignature`) sempre chamaram `_constDefault`. Este ficou de fora —
        // e nenhum fixture tinha variante de enum COM default.
        final def = p.defaultValue;
        final param = k.VariableDeclaration(
          p.label ?? p.name,
          type: type,
          isRequired: def == null,
          initializer: def == null ? null : _constDefault(def, type, decl),
        )..fileOffset = p.offset;
        params.add(param);
        initializers.add(k.FieldInitializer(field, k.VariableGet(param)));
      }
      // O super vem DEPOIS dos campos: é a ordem que o Kernel espera.
      initializers.add(k.SuperInitializer(baseCtor, k.Arguments.empty()));

      final vCtor = k.Constructor(
        k.FunctionNode(
          k.EmptyStatement(),
          namedParameters: params,
          returnType: const k.VoidType(),
        ),
        name: k.Name(''),
        initializers: initializers,
        fileUri: fileUri,
      )..fileOffset = decl.offset;
      vCls.addConstructor(vCtor);

      // Variante sem payload: singleton, para `.ponto` não alocar por uso.
      k.Field? singleton;
      if (c.payload.isEmpty) {
        singleton = k.Field.immutable(
          _memberName(c.name),
          type: k.InterfaceType(vCls, k.Nullability.nonNullable),
          initializer: k.ConstructorInvocation(vCtor, k.Arguments([])),
          isStatic: true,
          isFinal: true,
          fileUri: fileUri,
        )..fileOffset = decl.offset;
        base.addField(singleton);
      }

      variants[c.name] = _Variant(vCls, vCtor, fields, singleton);
      _sealedVariants.add(vCls);
    }

    _classes[decl] = base;
    _constructors[decl] = baseCtor;
    _variants[decl] = variants;
  }

  /// A variante SELADA que um pattern nomeia, **no enum do SUBJECT**.
  ///
  /// ⚠️ Antes isto procurava em TODOS os enums emitidos e devolvia o primeiro
  /// que casasse o nome — e dois enums com uma variante homônima (`A.par` e
  /// `B.par`) faziam o segundo `match` usar a subclasse do PRIMEIRO. O `.dill`
  /// compilava, passava no verify, e explodia em runtime:
  /// *"type 'B$par' is not a subtype of type 'A$par' in type cast"*. Nome de
  /// variante é único DENTRO de um enum, não entre enums — a chave tem de
  /// incluir o tipo do escrutínio.
  _Variant? _sealedOf(ast.EnumPattern p, Type subjectType) {
    if (subjectType is! NamedType) return null;
    return _variants[subjectType.decl]?[p.variant];
  }

  /// `.variante` (enum do usuário, sem payload) → `StaticGet` da constante.
  ///
  /// O tipo vem da nº1 — é o esperado que a F5 fez descer (`.variante` é forma
  /// *checking-only*, **spec 010 §4.1**: sem contexto ela nem tipa). Daí sai a
  /// decl, e da decl a `Class` que o passo 1a registrou.
  k.Expression _variantConst(ast.EnumShorthand s) {
    final type = check.exprTypes[s];
    if (type is! NamedType) _ice('variant-on-${type.runtimeType}', s);
    // Enum SELADO: a variante sem payload é o singleton da subclasse.
    final sealed = _variants[type.decl]?[s.variant];
    if (sealed != null) {
      final singleton = sealed.singleton;
      if (singleton == null) _ice('variant-needs-payload-${s.variant}', s);
      return k.StaticGet(singleton)..fileOffset = s.offset;
    }
    final field = _fields[type.decl]?[s.variant];
    if (field == null) _ice('variant-unknown-${s.variant}', s);
    return k.StaticGet(field)..fileOffset = s.offset;
  }

  /// `.variante(args)` → `ConstructorInvocation` da SUBCLASSE da variante.
  ///
  /// A F5 tipou o callee com a assinatura sintética da variante
  /// (`check.dart::_variantCtor`) e gravou o **slot** da nº5 — então os args
  /// entram named, pelos nomes do payload, exatamente como no `init` memberwise
  /// de `struct`.
  k.Expression _variantCall(ast.Call c, ast.EnumShorthand callee) {
    final type = check.exprTypes[c];
    // `Result` é do CHÃO (BuiltinType): `.ok(v)`/`.err(e)` constroem as classes
    // de runtime, não subclasses de uma decl do usuário.
    if (type is BuiltinType && type.kind == BuiltinKind.result) {
      final rt = _resultRuntime();
      final ctor = switch (callee.variant) {
        'ok' => rt.okCtor,
        'err' => rt.errCtor,
        _ => _ice('result-variant-${callee.variant}', c),
      };
      if (c.args.length != 1) _ice('result-arity', c);
      return k.ConstructorInvocation(
        ctor,
        k.Arguments([_expr(c.args.single.value)]),
      )..fileOffset = c.opOffset;
    }
    if (type is! NamedType) _ice('variant-call-on-${type.runtimeType}', c);
    final decl = type.decl;
    final v = _variants[decl]?[callee.variant];
    if (v == null) _ice('variant-call-unknown-${callee.variant}', c);

    final call = check.resolvedCalls[c];
    if (call == null) _ice('variant-call-unresolved', c);
    if (decl is! ast.EnumDecl) _ice('variant-call-nondecl', c);
    final payload =
        decl.cases.where((x) => x.name == callee.variant).single.payload;
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('variant-call-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = slot[i];
      if (pi < 0 || pi >= payload.length) _ice('variant-call-slot-range', c);
      final p = payload[pi];
      named.add(k.NamedExpression(p.label ?? p.name, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    return k.ConstructorInvocation(v.ctor, k.Arguments([], named: named))
      ..fileOffset = c.opOffset;
  }

  /// O default de um param → **`ConstantExpression`**, não a expressão comum.
  ///
  /// ⚠️ **A VM exige que default de parâmetro seja CONSTANTE**, e o nó tem de
  /// dizê-lo: emitir um `IntLiteral` cru faz a VM morrer no load com
  /// *"Not a constant expression: unexpected kernel tag SpecializedIntLiteral"*.
  /// Não é o verifier que reprova — é o carregador, em RUNTIME, depois de tudo
  /// passar. Foi assim que este caso apareceu.
  ///
  /// A restrição é do Dart e não tem contorno barato: é o preço de deixar a VM
  /// materializar o default (Grupo B) em vez de a F7 duplicar a expressão por
  /// call-site.
  ///
  /// Literais entram; qualquer outra expressão vira ICE HONESTO
  /// (`default-not-const`), porque a alternativa — materializar no call-site —
  /// é uma decisão de emissão que a §7.4-a **não** tomou (ela escolheu named +
  /// Grupo B, ruling §12-3).
  ///
  /// ⚠️ **O [type] é OBRIGATÓRIO, e é o do parâmetro** (CLAUDE.md R4: o tipo do
  /// nó emitido é IGUAL ao que a F5 provou). O 2º parâmetro de
  /// `ConstantExpression` tem default `const DynamicType()`
  /// (`pkg/kernel/…/expressions.dart:5084`) — omiti-lo punha `dynamic` REAL no
  /// `.dill` em todo default de parâmetro, contra o ADR-0013, e **rodando
  /// igual**: o `default_saltavel.tu` imprimia o golden certo com 6 violações
  /// dentro. Só o invariante de `visitDynamicType` viu (2026-07-29).
  ///
  /// Vem do parâmetro, e não do `Constant`, por causa do `nil`: `NullConstant`
  /// sozinho não diz de QUAL `T?` ele é o vazio.
  k.Expression _constDefault(ast.Expr e, k.DartType type, ast.AstNode span) {
    final constant = switch (e) {
      ast.IntLit n => k.IntConstant(n.value),
      ast.FloatLit n => k.DoubleConstant(n.value),
      ast.BoolLit n => k.BoolConstant(n.value),
      ast.NilLit _ => k.NullConstant(),
      // `Str` SEM interpolação é literal; com interpolação não é constante.
      ast.Str s when s.parts.every((p) => p is ast.StrLit) => k.StringConstant([
          for (final p in s.parts)
            if (p is ast.StrLit) p.value,
        ].join()),
      _ => _ice('default-not-const-${e.runtimeType}', span),
    };
    return k.ConstantExpression(constant, type)..fileOffset = e.offset;
  }

  /// `trait` → **`abstract class`**; requisito → `Procedure` ABSTRATO (§7.4-d).
  ///
  /// É a base do dispatch existencial: `any Fala` vira `InterfaceType` do trait,
  /// e `v.som()` vira `InstanceInvocation` com `interfaceTarget` no procedure
  /// abstrato. **A vtable é Grupo B** — a VM resolve; nós só declaramos a forma.
  ///
  /// ⚠️ **A travessia `any` de fonte LOCAL é ZERO NÓ** (CA11, ADR-0017 §5): um
  /// `Pato` que conforma `Fala` já É um `Fala` no Kernel (está em
  /// `implementedTypes`), então passar um ao outro não emite box, cast nem
  /// wrapper. É o que o invariante de custo zero vigia.
  void _trait(ast.TraitDecl decl) {
    if (decl.generics.isNotEmpty) _ice('trait-generic', decl);

    final cls = _classes[decl]!; // shell do passo 1a-i, já `isAbstract`

    final requisitos = <String, k.Procedure>{};
    final defaults = <String, k.Procedure>{};
    for (final m in decl.members) {
      if (m is! ast.FnDecl) _ice('trait-member-${m.runtimeType}', decl);

      // O `Procedure` ABSTRATO sai sempre — inclusive para quem tem default. É
      // ele que dá o `interfaceTarget` do dispatch existencial: `any Saudavel`
      // vira `InterfaceType` do trait, e a VM resolve por vtable (Grupo B).
      // Sem o abstrato, um conformer que só herda o default não teria membro
      // nenhum visível na interface.
      final proc = _methodSignature(m, decl, isAbstract: true);
      cls.addProcedure(proc);
      requisitos[m.name] = proc;

      // Sem corpo é REQUISITO e acabou aqui.
      if (m.body == null) continue;

      // ---- default: o corpo vira um `static` do trait (ADR-0017 §2) ---------
      //
      // ⚠️ **Duas listas de params, dois objetos.** Um `VariableDeclaration` só
      // pode ter um pai no Kernel, então o abstrato e o static NÃO podem
      // compartilhar os seus. `_methodSignature` é chamado de novo de propósito
      // — e por último, porque é ele que deixa `_kernelDecls[p]` apontando para
      // o param do STATIC, que é onde o corpo vai ler.
      final assinatura = _methodSignature(m, decl, isAbstract: false);

      // `self` é o primeiro POSICIONAL. Tipo: o próprio trait — dentro do
      // static ele é o **join** dos conformers, então `self.nome()` ali é
      // chamada polimórfica. É o preço que o ADR aceita por ter o corpo 1×.
      final selfVar = k.VariableDeclaration(
        'self',
        type: k.InterfaceType(cls, k.Nullability.nonNullable),
      )..fileOffset = m.offset;

      final estatico = k.Procedure(
        // `_` na frente: o static é detalhe de implementação, e `_memberName`
        // o torna PRIVADO da biblioteca. Nada no programa do usuário o chama —
        // só os stubs que emitimos.
        _memberName('_${decl.name}\$${m.name}'),
        k.ProcedureKind.Method,
        k.FunctionNode(
          null, // corpo no passo 2, sob `_selfComoVar`
          positionalParameters: [selfVar],
          namedParameters: assinatura.function.namedParameters,
          returnType: assinatura.function.returnType,
        ),
        isStatic: true,
        fileUri: fileUri,
      )..fileOffset = m.offset;
      cls.addProcedure(estatico);
      defaults[m.name] = estatico;
      _defaultBodies.add((m, estatico, selfVar));
    }

    _classes[decl] = cls;
    _traitMembers[decl] = requisitos;
    _traitDefaults[decl] = defaults;
  }

  /// A assinatura de um método (de `trait`, `struct` ou `class`) → `Procedure`
  /// de instância. Mesma forma do `fn` top-level, menos o `isStatic`: params
  /// **named** (§12-3), retorno da anotação, `this` implícito.
  k.Procedure _methodSignature(
    ast.FnDecl fn,
    ast.AstNode owner, {
    required bool isAbstract,
  }) {
    if (fn.generics.isNotEmpty) _ice('method-generic', owner);
    if (fn.asyncMarker != ast.AsyncMarker.sync) _ice('method-async', owner);

    final named = <k.VariableDeclaration>[];
    for (final p in fn.params) {
      final type = check.binderTypes[p] ??
          (p.type == null ? null : check.annotations[p.type!]);
      if (type == null) _ice('method-param-untyped', owner);
      final def = p.defaultValue;
      final ktype = _emitType(type, owner);
      final decl = k.VariableDeclaration(
        p.label ?? p.name,
        type: ktype,
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, ktype, owner),
      )..fileOffset = p.offset;
      _kernelDecls[p] = decl;
      named.add(decl);
    }

    final returnType = fn.returnType == null
        ? const k.VoidType()
        : _emitType(check.annotations[fn.returnType!] ?? const VoidType(), owner);

    return k.Procedure(
      _memberName(fn.name),
      k.ProcedureKind.Method,
      k.FunctionNode(
        null, // corpo no passo 2 (ou nenhum, se abstrato)
        namedParameters: named,
        returnType: returnType,
      ),
      isAbstract: isAbstract,
      fileUri: fileUri,
    )..fileOffset = fn.offset;
  }

  /// `class` → `Class` de REFERÊNCIA, com `init` EXPLÍCITO (§7.4-c, **CA3**).
  ///
  /// **`class` nunca ganha memberwise** (ADR-0012 §A-1): sem `init` no corpo ela
  /// é INCONSTRUÍVEL, e é esse contraste com `struct` que dá conteúdo ao P2 — o
  /// glifo escolhe entre valor e referência, e cada um paga um preço diferente.
  ///
  /// Campo `var` baixa MUTÁVEL (`Field.mutable`, com setter), diferente do
  /// `struct`, onde o ruling §12-1 obriga todos a `final`. É a diferença
  /// observável entre os dois: referência pode mutar, valor não.
  ///
  /// ⚠️ **O corpo do `init` vira `initializers`, não statements** — e a razão é
  /// dura: no Kernel, campo `final` **só** pode ser atribuído em `initializers`;
  /// atribuí-lo no corpo é malformado. O Itá escreve `self.saldo = inicial`
  /// dentro do `init`, então cada `ExprStmt(Assign(Member(self, campo), e))` é
  /// convertido em `FieldInitializer`.
  ///
  /// A conversão exige que o corpo seja **só** atribuições a `self` — qualquer
  /// outro statement vira ICE (`init-body-<T>`). Não é preguiça: `FieldInitializer`
  /// roda ANTES do corpo, então misturar lógica entre as atribuições mudaria a
  /// ORDEM de avaliação em silêncio. Enquanto a fatia que ordena isso não existe,
  /// a restrição é declarada em vez de adivinhada.
  void _class(ast.ClassDecl decl) {
    if (decl.generics.isNotEmpty) _ice('class-generic', decl);

    // ⚠️ **O papel vem do KIND, não da POSIÇÃO** (ruling do dono, 2026-07-15).
    // O parser põe o 1º type após `:` em `superclass` — split posicional, e
    // portanto reversível —, mas `class Robo : Fala` tem um TRAIT ali. Quem
    // decide é o kind: trait ⟹ conformance; `class` ⟹ herança (fatia futura).
    final superType = decl.superclass;
    // O retrofit entra JUNTO das conformances do corpo: para o Kernel não há
    // diferença entre `class Robo : Fala` e `impl Fala for Robo`, e é essa
    // indistinguibilidade que o CA6 cobra ("despacha igual a inline").
    final conformances = <ast.TypeNode>[
      ...decl.traits,
      ...?_traitsDeExtensao[decl],
    ];
    if (superType != null) {
      final t = check.annotations[superType];
      final isTrait = t is NamedType &&
          check.types.of(t.decl)?.kind == TypeKind.trait_;
      if (!isTrait) _ice('class-superclass', decl); // herança real: fatia própria
      conformances.insert(0, superType);
    }

    final info = check.types.of(decl);
    if (info == null) _ice('class-untyped', decl);
    final fieldInfos = info.fields;
    if (fieldInfos == null) _ice('class-nofields', decl);

    final cls = _classes[decl]!; // shell do passo 1a-i
    cls.implementedTypes.addAll(_traitSupertypes(conformances, decl));

    final byName = <String, k.Field>{};
    for (final f in fieldInfos) {
      if (f.name.startsWith("_")) _ice("class-private-field", decl);
      final type = _emitType(f.type, decl);
      // `var` → mutável (tem setter); `let` → final. O sanitize confere a
      // coerência `isFinal ⟺ sem setter` depois.
      final field = f.isMutable
          ? k.Field.mutable(_memberName(f.name), type: type, fileUri: fileUri)
          : k.Field.immutable(_memberName(f.name), type: type, fileUri: fileUri);
      field.fileOffset = f.decl.offset;
      cls.addField(field);
      byName[f.name] = field;
    }
    _classes[decl] = cls;
    _fields[decl] = byName;

    final inits = [
      for (final m in decl.members)
        if (m is ast.InitDecl) m,
    ];
    // O primário é o `init` do CORPO, quando existe: *"`struct` usa construtor
    // **memberwise sintetizado** (sem `init` explícito — concisão); `class` usa
    // `init` **explícito**"* (ADR-0012 §A-1) — não há memberwise a preservar
    // aqui.
    //
    // **Dois `init` no CORPO seguem ICE, e a fronteira é real** — medido em
    // 2026-08-10: `class C { init(a:) init(b:) }` atravessa a F5 inteira e chega
    // aqui. O `duplicate-init` desta fatia compara os candidatos de `extension`
    // contra o primário e NÃO cobre este caso; o `info.init` guarda um só, e o
    // outro é descartado em silêncio lá.
    //
    // Fica como ICE com catraca (`ice_class_multi_init.tu`) e não como emissão
    // porque decidir isto é ruling, não fatia: dois `init` no corpo com labels
    // distintos é **overload de construtor**, e o ruling do dono cobre método —
    // *"o Itá não tem overload de método"* (spec 011 §12-4). Construtor não
    // estava na frase. Fecha-se quando o dono disser se a porta abre (e aí vira
    // mais um `Constructor` nomeado, o mecanismo já está aqui) ou fecha (e aí é
    // `duplicate-init` na F5, estendido ao corpo).
    if (inits.length > 1) _ice('class-multi-init', decl);
    final extInits = (_membrosDeExtensao[decl] ?? const <ast.Decl>[])
        .whereType<ast.InitDecl>();
    if (inits.isEmpty && extInits.isEmpty) {
      // Inconstruível por construção (ADR-0012 §A-1) — a F5 acusa `no-init` no
      // USO, então um programa verde nunca chega aqui sem init.
      _ice('class-no-init', decl);
    }

    // **`class` construída SÓ por `extension` é legal, e de propósito.** A F5
    // abre a porta com `cands.isNotEmpty` (e não `> 1`) porque, sem memberwise,
    // um único `init` de extension É o construtor — fechar aqui seria *"fechar a
    // porta e trancar a saída"*, o pecado que o `copywith-on-custom-init`
    // acusa. Nesse caso não há primário, e todo call-site chega com
    // `initTarget` preenchido.
    if (inits.isNotEmpty) {
      _constructors[decl] = _initCtor(inits.single, cls, byName, decl);
    }
    _addExtensionInits(decl, cls, byName);
    final metodos = _addMethods(
      decl,
      cls,
      [...decl.members, ...?_membrosDeExtensao[decl]],
    );
    _addDefaultStubs(decl, cls, conformances, metodos);
  }

  /// O `init` explícito → `Constructor`, com o corpo convertido em
  /// `initializers`. Ver [_class] para a razão.
  ///
  /// [nome] vazio = construtor NÃO-nomeado (`P(...)`), que é o **primário**: o
  /// memberwise do `struct` ou o `init` do corpo da `class`. Os vindos de
  /// `extension` são nomeados — ver [_nomeDeInit].
  k.Constructor _initCtor(
    ast.InitDecl init,
    k.Class cls,
    Map<String, k.Field> byName,
    ast.AstNode decl, {
    String nome = '',
  }) {
    final params = <k.VariableDeclaration>[];
    for (final p in init.params) {
      // A nº6 (`binderTypes`) cobre binders de `let`/`match`/param de `fn`, mas
      // não os do `init` — para eles a fonte é a ANOTAÇÃO, que o `init` sempre
      // exige (não há inferência de param aqui).
      final type = check.binderTypes[p] ??
          (p.type == null ? null : check.annotations[p.type!]);
      if (type == null) _ice('init-param-untyped', decl);
      final def = p.defaultValue;
      final ktype = _emitType(type, decl);
      final param = k.VariableDeclaration(
        p.label ?? p.name,
        type: ktype,
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, ktype, decl),
      )..fileOffset = p.offset;
      _kernelDecls[p] = param;
      params.add(param);
    }

    final initializers = <k.Initializer>[];
    for (final s in init.body.stmts) {
      // O ÚNICO formato aceito: `self.campo = <expr>`. As duas recusas são
      // fatias DIFERENTES — um `let` no corpo do `init` e um `self.x += 1` não
      // se fecham com o mesmo trabalho —, então têm códigos diferentes. Até
      // 2026-07-29 as duas diziam `init-body-<T>` e um fixture cobriria as duas
      // (R13): o sufixo vem de hierarquias distintas da AST, mas a catraca da
      // R7 casa pelo código, não pelo que ele interpola.
      if (s is! ast.ExprStmt) _ice('init-body-stmt-${s.runtimeType}', decl);
      final e = s.expr;
      if (e is! ast.Assign || e.op != ast.AssignOp.assign) {
        _ice('init-body-expr-${e.runtimeType}', decl);
      }
      final target = e.target;
      if (target is! ast.Member || target.receiver is! ast.SelfExpr) {
        _ice('init-target-${target.runtimeType}', decl);
      }
      final field = byName[target.name];
      if (field == null) _ice('init-field-${target.name}', decl);
      initializers.add(
        k.FieldInitializer(field, _expr(e.value))..fileOffset = s.offset,
      );
    }

    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        namedParameters: params,
        returnType: const k.VoidType(),
      ),
      name: k.Name(nome),
      initializers: initializers,
      fileUri: fileUri,
    )..fileOffset = init.offset;
    cls.addConstructor(ctor);
    _initCtors[init] = ctor;
    return ctor;
  }

  /// **Qual `Constructor` esta construção chama** — a F5 já decidiu.
  ///
  /// `ResolvedCall.initTarget` é a escolha dela (por labels, `_labelsFit`);
  /// ausente ⟹ primário. A F7 **não** re-casa labels aqui: seria refazer no
  /// lexema uma decisão já tomada com a tabela de tipos, que é a
  /// redecisão-com-chave-mais-fraca da R1 — e, como o `slot` da mesma
  /// `ResolvedCall` vem do `init` escolhido, discordar dela poria os args no
  /// construtor errado sem que nada ficasse malformado.
  /// `null` ⟹ o construtor não foi emitido, e o ICE é do CHAMADOR — é lá que os
  /// códigos são literais e a R13 consegue distinguir `struct` de `class`.
  k.Constructor? _ctorDaChamada(ast.Call c, ast.Decl decl) {
    final alvo = check.resolvedCalls[c]?.initTarget;
    if (alvo != null) return _initCtors[alvo];
    return _constructors[decl];
  }

  /// O nome Kernel de um `init` de `extension`, derivado dos **labels**.
  ///
  /// `init(diagonal: Int)` → `init$diagonal`. Nunca do índice na lista: a ordem
  /// de coleta é a ordem TEXTUAL das `extension`, e permutar declarações
  /// renomearia construtores no `.dill` — a R2 cobra que essa permutação seja
  /// inobservável, e um golden de stdout não veria a diferença.
  ///
  /// Os labels bastam para ser único porque o `duplicate-init` da F5 recusa dois
  /// candidatos com a mesma lista deles.
  ///
  /// ⚠️ **`label ?? name`, como em todo o resto do arquivo.** `Param.label` só
  /// guarda o label EXPLÍCITO (`fn f(externo interno: Int)`); quando ele falta,
  /// o label É o nome — não é param posicional. Com `label ?? '_'`, `init(ate:)`
  /// e `init(unica:)` viravam ambos `init$_`, e quem pegou foi o verify
  /// (*"already bound to Reference"*) — o `duplicate-init` da F5 não vê, porque
  /// lá os labels estão certos e as duas listas são distintas.
  String _nomeDeInit(ast.InitDecl init) =>
      'init\$${[for (final p in init.params) p.label ?? p.name].join('\$')}';

  /// Os `init` de `extension` do alvo → um `Constructor` adicional cada
  /// (**CA3**, 2ª cláusula; ADR-0016 §B: *"`extensionInits` acumulam como
  /// **adicionais**, com precedência do `init` do corpo"*).
  ///
  /// A precedência do corpo é posicional e já está paga: quem chama passou pelo
  /// `_initCandidates` da F5, que põe o primário em primeiro e devolve o
  /// `initTarget` do vencedor. Aqui só se emite — a escolha não é refeita.
  void _addExtensionInits(
    ast.AstNode decl,
    k.Class cls,
    Map<String, k.Field> byName,
  ) {
    for (final m in _membrosDeExtensao[decl] ?? const <ast.Decl>[]) {
      if (m is! ast.InitDecl) continue;
      _initCtor(m, cls, byName, decl, nome: _nomeDeInit(m));
    }
  }

  /// `enum` SEM payload → **`Class` com uma constante por variante** (§7.4-c).
  ///
  /// Cada variante vira um `static final` inicializado com o construtor privado
  /// da própria classe, então **cada uma é um objeto único** — e é isso que faz
  /// o `match` funcionar por igualdade de identidade (`Object::==`) sem precisar
  /// de tag, índice ou `IsExpression`.
  ///
  /// ⚠️ **Variante COM payload não chega aqui** — não porque a emissão não
  /// saiba, mas porque a **F5 não sabe CONSTRUIR uma**: `.circulo(raio: 2)` dá
  /// `cannot-infer` (o `_call` não resolve callee `EnumShorthand` com args).
  /// Sem construção não há valor a destruir, então o gabarito de classe selada +
  /// subclasse por variante (§7.4-e) espera essa fatia da F5. O ICE aqui nomeia
  /// a lacuna em vez de emitir uma classe que ninguém consegue instanciar.
  void _enum(ast.EnumDecl decl) {
    if (decl.generics.isNotEmpty) _ice('enum-generic', decl);
    if (decl.members.isNotEmpty) _ice('enum-methods', decl); // métodos: fatia própria

    // **DOIS gabaritos, por decisão da §7.4-c** — e a diferença não é
    // otimização: enum sem payload é um conjunto FECHADO de constantes, e
    // representá-lo como classe selada custaria uma alocação e um `is` por uso,
    // para modelar uma escolha que já é decidível por identidade.
    if (decl.cases.any((c) => c.payload.isNotEmpty)) {
      _enumSealed(decl);
      return;
    }

    final cls = _classes[decl]!; // shell do passo 1a-i
    final selfType = k.InterfaceType(cls, k.Nullability.nonNullable);

    // Construtor sem args: só existe para dar identidade a cada constante.
    final ctor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    cls.addConstructor(ctor);

    final byName = <String, k.Field>{};
    for (final c in decl.cases) {
      final field = k.Field.immutable(
        _memberName(c.name),
        type: selfType,
        initializer: k.ConstructorInvocation(ctor, k.Arguments([])),
        isStatic: true,
        isFinal: true,
        fileUri: fileUri,
      )..fileOffset = decl.offset;
      cls.addField(field);
      byName[c.name] = field;
    }

    _classes[decl] = cls;
    _constructors[decl] = ctor;
    _fields[decl] = byName; // aqui os "campos" são as CONSTANTES das variantes
  }

  /// `struct` → `Class` com **todos os campos `final`** e um `Constructor`
  /// memberwise de params **named** (§7.4-c).
  ///
  /// **Todos final é RULING, não otimização** (§12-1, dono 2026-07-16): struct é
  /// imutável SEMPRE — campo `var` em struct já morre na F5
  /// (`mut-field-on-struct`). É o que torna a cópia-valor INOBSERVÁVEL: valor
  /// imutável não tem identidade a perder, então representar `struct` por
  /// referência no Kernel não quebra P2. Sem o ruling, a mesma emissão MATARIA o
  /// P2 em silêncio — o `.dill` faria sharing onde a linguagem promete cópia.
  ///
  /// O `Constructor` recebe `EmptyStatement` como corpo e faz o trabalho nos
  /// `initializers` (`FieldInitializer` por campo) — a forma que o Kernel exige
  /// para campo `final`, que não pode ser atribuído no corpo.
  ///
  /// **Sem `SuperInitializer` explícito**: o supertype é `Object`, cujo
  /// construtor não tem argumentos, e o Kernel o sintetiza. (Se um dia houver
  /// herança real — `class` com superclasse —, ele passa a ser obrigatório.)
  void _struct(ast.StructDecl decl) {
    if (decl.generics.isNotEmpty) _ice('struct-generic', decl); // ∀ é fatia própria

    final info = check.types.of(decl);
    if (info == null) _ice('struct-untyped', decl);
    final fieldInfos = info.fields;
    if (fieldInfos == null) _ice('struct-nofields', decl);
    // `init` do CORPO é a fatia do `init` explícito — hoje só o memberwise.
    if (info.initFromBody) _ice('struct-init-explicit', decl);

    // O shell já existe (passo 1a-i) — aqui só se preenche.
    // **CONFORMANCE** (§7.4-d): o trait entra em `implementedTypes`, e é isso
    // que faz `Pato` JÁ SER um `Fala` no Kernel — a travessia existencial de
    // fonte local vira **zero nó** (CA11). Sem isto, passar um `Pato` para
    // `any Fala` exigiria box.
    final cls = _classes[decl]!;
    // Corpo + retrofit na MESMA lista (ADR-0017 §1): `struct P : Ord` e
    // `impl Ord for P` produzem o mesmo `implementedTypes`.
    final conformances = <ast.TypeNode>[
      ...decl.traits,
      ...?_traitsDeExtensao[decl],
    ];
    cls.implementedTypes.addAll(_traitSupertypes(conformances, decl));

    final byName = <String, k.Field>{};
    final params = <k.VariableDeclaration>[];
    final initializers = <k.Initializer>[];
    for (final f in fieldInfos) {
      // ⚠️ **Campo iniciado por `_` não tem imagem no memberwise.** No Itá o `_`
      // é só um nome (visibilidade é `pub`), mas no Dart um NAMED PARAMETER não
      // pode ser privado: o param sai manglado (`_x@21090877`) e nenhum
      // call-site o casa — a VM morre em runtime com `NoSuchMethodError`, DEPOIS
      // de o verifier aprovar o `.dill`. Fronteira honesta até haver mangling de
      // nome (o par campo-privado × param-público é decidível, mas é fatia
      // própria). Sem esta guarda, o erro cai no usuário como crash da VM.
      if (f.name.startsWith('_')) _ice('struct-private-field', decl);
      final field = k.Field.immutable(
        _memberName(f.name),
        type: _emitType(f.type, decl),
        fileUri: fileUri,
      )..fileOffset = f.decl.offset;
      cls.addField(field);
      byName[f.name] = field;

      // **CA2 — o default do campo vira `VariableDeclaration.initializer`, e
      // QUEM O MATERIALIZA É A VM** (§7.4-a, Grupo B). A F7 não duplica a
      // expressão por call-site: ela a emite UMA vez, no param, e o call-site
      // que salta simplesmente não manda o named.
      //
      // É o que fecha a decisão de named-params (§12-3): o slot da nº5
      // implementa *"ordem obrigatória, defaults saltáveis"* — `P(x: 1)` salta o
      // `y` —, e o posicional do Dart só corta do FIM. Com named, saltar é não
      // mandar; com posicional, a F7 teria de materializar o default aqui.
      //
      // O default NÃO pode referenciar `self` (o Kernel não tem `this` em
      // default) — a F6 já barra com `self-in-field-default`, então aqui a
      // expressão é sempre auto-contida.
      final defaultValue = f.decl.defaultValue;
      final ktype = _emitType(f.type, decl);
      final param = k.VariableDeclaration(
        f.name,
        type: ktype,
        isRequired: defaultValue == null,
        initializer: defaultValue == null
            ? null
            : _constDefault(defaultValue, ktype, decl),
      )..fileOffset = f.decl.offset;
      params.add(param);
      initializers.add(k.FieldInitializer(field, k.VariableGet(param)));
    }

    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        namedParameters: params,
        // ⚠️ **`returnType` EXPLÍCITO.** O default do `FunctionNode` é
        // `DynamicType` — e um construtor com retorno `dynamic` viola o ADR-0013
        // sem mudar NADA no que o programa imprime. Foi exatamente assim que os
        // invariantes o pegaram, na primeira execução desta fatia. O oracle
        // (`ita/compiler/lib/codegen/codegen.dart:948`) também o omite: é o caso
        // literal de "portar a LIÇÃO, não o estilo" que a §11 manda.
        returnType: const k.VoidType(),
      ),
      name: k.Name(''), // construtor NÃO-nomeado: `P(...)`
      initializers: initializers,
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    cls.addConstructor(ctor);

    _classes[decl] = cls;
    _constructors[decl] = ctor;
    _fields[decl] = byName;
    // O memberwise acima é o primário e **sobrevive** ao retrofit — *"a extension
    // é o glifo que diz 'estou ADICIONANDO, não substituindo'"* (ADR-0016 §B).
    // Vem depois de `_fields` porque o corpo de cada `init` resolve `self.campo`
    // por `byName`.
    _addExtensionInits(decl, cls, byName);
    final metodos = _addMethods(
      decl,
      cls,
      [...decl.members, ...?_membrosDeExtensao[decl]],
    );
    _addDefaultStubs(decl, cls, conformances, metodos);
  }

  /// A `k.Class` VAZIA de uma decl, registrada em `_classes` antes dos membros.
  ///
  /// O shell existe para que o grafo cíclico seja construível: um campo pode
  /// mencionar um tipo que ainda não teve os membros emitidos, e o
  /// `InterfaceType` só precisa da IDENTIDADE da `Class`, não do conteúdo dela.
  /// `isAbstract` entra aqui — e não depois — porque o `_traitSupertypes` do
  /// conformer o lê para distinguir trait de superclasse.
  k.Class _shell(ast.AstNode decl, String name, {bool isAbstract = false}) {
    final cls = k.Class(
      name: name,
      isAbstract: isAbstract,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    )..fileOffset = decl.offset;
    _classes[decl] = cls;
    return cls;
  }

  /// Roteia um `impl`/`extension` para a decl do tipo ALVO (ADR-0017 §1).
  ///
  /// O alvo sai da side-table nº4 (`annotations`), não do texto: `extension Int`
  /// e `extension MeuInt` só se distinguem pelo tipo que a F5 resolveu. Alvo que
  /// não é tipo NOMEADO do usuário é fronteira declarada — retrofit sobre
  /// built-in é o não-objetivo 2 da spec 013, gated até a F5 parar de recusá-lo
  /// (`conformance-on-builtin-unsupported`).
  void _coletaRetrofit(
    ast.TypeNode target,
    List<ast.Decl> members,
    List<ast.TypeNode> traits,
    ast.AstNode at,
  ) {
    final tipo = check.annotations[target];
    // Sem catraca, e a razão é ORDEM (R10), não impossibilidade: alvo não-nomeado
    // é built-in (`extension Int`), e a F5 o recusa antes com
    // `conformance-on-builtin-unsupported` — o não-objetivo 2 da spec 013. Vira
    // alcançável quando esse erro cair, e a catraca nasce NAQUELA fatia.
    if (tipo is! NamedType) _ice('retrofit-target-nonnamed', at);
    final alvo = tipo.decl;
    (_membrosDeExtensao[alvo] ??= []).addAll(members);
    (_traitsDeExtensao[alvo] ??= []).addAll(traits);
  }

  /// Os `trait` que uma decl conforma → `Supertype`, para `implementedTypes`.
  ///
  /// O trait tem de estar emitido (o passo 1 os faz ANTES de tudo). Um alvo que
  /// não seja `trait` é `class`-como-superclasse ou erro de fase anterior.
  List<k.Supertype> _traitSupertypes(List<ast.TypeNode> traits, ast.AstNode at) {
    final out = <k.Supertype>[];
    for (final t in traits) {
      final type = check.annotations[t];
      if (type is! NamedType) _ice('conformance-nonnamed', at);
      final cls = _classes[type.decl];
      if (cls == null) _ice('conformance-unemitted', at);
      if (!cls.isAbstract) _ice('conformance-nontrait', at);
      out.add(k.Supertype(cls, const []));
    }
    return out;
  }

  /// Métodos de instância de um `struct`/`class` → `Procedure` DENTRO da `Class`.
  ///
  /// ⚠️ **Todos dentro da `Class`, inclusive os de conformance** (§7.4-d): é o que
  /// faz o dispatch existencial funcionar por vtable (Grupo B) em vez de por
  /// tabela nossa. A nº3/`origin` diria quem contribuiu (inline × `impl` ×
  /// `extension`); hoje só inline chega aqui — `impl`/`extension` é o CA6.
  /// Devolve os métodos por nome — o chamador precisa deles para saber o que o
  /// conformer JÁ define antes de [_addDefaultStubs] preencher o resto.
  Map<String, k.Procedure> _addMethods(
    ast.AstNode owner,
    k.Class cls,
    List<ast.Decl> members,
  ) {
    final byName = <String, k.Procedure>{};
    for (final m in members) {
      // ⚠️ Este `continue` **descarta**, e o que sobra em `members` mudou: desde
      // o CA6 a lista traz os membros de `impl`/`extension` junto com os do
      // corpo. Para os do corpo, "já foram" é verdade (campo veio de
      // `fieldInfos`, `init` veio de `inits`); para os do retrofit, quem garante
      // é a guarda de `retrofit-init` no passo 1 — `FieldDecl` a F5 já barra
      // antes (`extension-field-unsupported`). Membro de retrofit que não seja
      // `FnDecl` some AQUI, em silêncio, se aquela guarda não o pegar primeiro.
      if (m is! ast.FnDecl) continue;
      final proc = _methodSignature(m, owner, isAbstract: false);
      cls.addProcedure(proc);
      byName[m.name] = proc;
      _methodBodies.add((m, proc));
    }
    _methods[owner] = byName;
    return byName;
  }

  /// **O STUB por conformer** — a outra metade do (iii) do ADR-0017 §2.
  ///
  /// Para cada default do trait que este conformer **não** sobrescreveu, emite
  /// `fn f(...) => _Trait$f(this, ...)`. O corpo real mora uma vez só, no static
  /// do trait; aqui fica uma delegação de uma linha.
  ///
  /// **Por que o stub existe, em vez de o conformer só herdar:** `implements`
  /// do Kernel **não herda corpo**. Sem o stub, a classe conformaria a interface
  /// sem prover o membro — e o `.dill` ficaria malformado ou a chamada morreria
  /// em runtime. É a mesma razão pela qual `mixedInType` não serve: quem achata
  /// mixin é um transformer do CFE que o Itá bypassa.
  ///
  /// Conformer que SOBRESCREVE não entra aqui (é a 2ª cláusula do CA5): o
  /// método dele já está em [byName], e o stub o sobrescreveria de volta —
  /// invertendo o que o `override` do usuário pediu.
  void _addDefaultStubs(
    ast.AstNode owner,
    k.Class cls,
    List<ast.TypeNode> traits,
    Map<String, k.Procedure> byName,
  ) {
    for (final t in traits) {
      final type = check.annotations[t];
      if (type is! NamedType) continue; // `_traitSupertypes` já acusou
      final defaults = _traitDefaults[type.decl];
      if (defaults == null) continue;

      for (final e in defaults.entries) {
        if (byName.containsKey(e.key)) continue; // o conformer sobrescreveu
        final estatico = e.value;

        // Params FRESCOS: os do static já têm pai. O stub recebe os mesmos
        // nomes/tipos e os repassa por named, na ordem que o Kernel casa por
        // NOME (não por posição) — então basta um `NamedExpression` por param.
        final repasse = <k.VariableDeclaration>[];
        final args = <k.NamedExpression>[];
        for (final p in estatico.function.namedParameters) {
          final copia = k.VariableDeclaration(
            p.name,
            type: p.type,
            isRequired: p.isRequired,
            // O default vive no param do STATIC; duplicá-lo aqui criaria duas
            // fontes para o mesmo valor. O stub sempre passa o argumento.
          )..fileOffset = estatico.fileOffset;
          repasse.add(copia);
          args.add(k.NamedExpression(p.name!, k.VariableGet(copia)));
        }

        final chamada = k.StaticInvocation(
          estatico,
          k.Arguments([k.ThisExpression()], named: args),
        )..fileOffset = estatico.fileOffset;

        final isVoid = estatico.function.returnType is k.VoidType;
        final stub = k.Procedure(
          _memberName(e.key),
          k.ProcedureKind.Method,
          k.FunctionNode(
            k.Block([
              isVoid
                  ? (k.ExpressionStatement(chamada)
                    ..fileOffset = estatico.fileOffset)
                  : (k.ReturnStatement(chamada)
                    ..fileOffset = estatico.fileOffset),
            ])..fileOffset = estatico.fileOffset,
            namedParameters: repasse,
            returnType: estatico.function.returnType,
          ),
          fileUri: fileUri,
        )..fileOffset = estatico.fileOffset;
        cls.addProcedure(stub);
        byName[e.key] = stub;
      }
    }
    _methods[owner] = byName;
  }

  /// A ASSINATURA de um `fn` top-level → `Procedure` **static** com corpo vazio.
  ///
  /// **Params baixam como `named` REQUIRED** — decisão da §7.4-a, confirmada pelo
  /// dono no §12-3. A razão é a regra do Itá, não preferência: o `_matchArgs`
  /// implementa *"ordem obrigatória, defaults saltáveis"* ⟹ `f(a, b=2, c)` aceita
  /// `f(a:1, c:3)`, saltando o param **do meio**; o posicional do Dart só corta do
  /// FIM (`requiredParameterCount`). Named é a única forma que preserva isso sem a
  /// F7 materializar defaults por call-site — com named, o default vive no
  /// `VariableDeclaration.initializer` e **a VM o materializa** (Grupo B).
  ///
  /// O nome do param no Kernel é o **label** (`p.label ?? p.name`): é por ele que
  /// o call-site chama, e é o que o matching named do Kernel casa. O corpo não se
  /// importa — referencia a `VariableDeclaration` por OBJETO (`VariableGet(decl)`),
  /// via [_kernelDecls], nunca por nome.
  k.Procedure _fnSignature(ast.FnDecl fn) {
    if (fn.generics.isNotEmpty) _ice('fn-generic', fn); // ∀ é fatia própria
    if (fn.asyncMarker != ast.AsyncMarker.sync) _ice('fn-async', fn); // §12-2

    final named = <k.VariableDeclaration>[];
    for (final p in fn.params) {
      final type = check.binderTypes[p];
      if (type == null) _ice('param-untyped', fn);
      // Default de param de `fn` é a MESMA peça do default de campo (§7.4-a,
      // ruling §12-3): `ConstantExpression` no `initializer`, e a VM
      // materializa. É o que permite `f(a: 1, c: 3)` saltar o `b` do MEIO —
      // o posicional do Dart só corta do fim.
      final def = p.defaultValue;
      final ktype = _emitType(type, fn);
      final decl = k.VariableDeclaration(
        p.label ?? p.name,
        type: ktype,
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, ktype, fn),
      )..fileOffset = p.offset;
      _kernelDecls[p] = decl; // o binder da F4 para um param É o próprio `Param`
      named.add(decl);
    }

    final returnType = fn.returnType == null
        ? const k.VoidType()
        : _emitType(check.annotations[fn.returnType!] ?? const VoidType(), fn);

    return k.Procedure(
      k.Name(fn.name),
      k.ProcedureKind.Method,
      k.FunctionNode(
        null, // corpo entra no passo 2
        namedParameters: named,
        returnType: returnType,
      ),
      isStatic: true,
      fileUri: fileUri,
    )..fileOffset = fn.offset;
  }

  /// O CORPO (passo 2). `=> expr` (RD-1: só a seta rende) vira `return expr` num
  /// `fn` que devolve valor, e mero `ExpressionStatement` num `Void` — onde um
  /// `return` de valor seria Kernel malformado.
  void _fnBody(ast.FnDecl fn, k.Procedure proc) {
    final isVoid = proc.function.returnType is k.VoidType;
    proc.function.body = switch (fn.body) {
      ast.BlockBody b => _block(b.b),
      ast.ExprBody e => k.Block([
          isVoid
              ? (k.ExpressionStatement(_expr(e.e))..fileOffset = e.e.offset)
              : (k.ReturnStatement(_expr(e.e))..fileOffset = e.e.offset),
        ])..fileOffset = fn.offset,
      null => _ice('abstract-fn', fn), // assinatura sem corpo (trait)
    };
    proc.function.body!.parent = proc.function;
  }

  k.Block _block(ast.Block b) =>
      k.Block([for (final s in b.stmts) _stmt(s)])..fileOffset = b.offset;

  k.Statement _stmt(ast.Stmt s) => switch (s) {
        ast.ExprStmt e =>
          k.ExpressionStatement(_expr(e.expr))..fileOffset = e.offset,
        ast.LetStmt l => _let(l),
        // `return` sem valor sob `-> T` não-Void não chega aqui, e a garantia
        // é da **F5**: `check.dart` acusa `return-without-value` (verbatim do
        // sítio: *"a direção inversa não era checada por ninguém"*). A direção
        // oposta (`return e` num Void) é o `_check` contra `Void`, no mesmo
        // `case`.
        //
        // 🔴 Este comentário dizia que a garantia era da **F6** (`missing-return`,
        // nº8). Era FANTASMA: `missing-return` é sobre o FIM do corpo (JLS
        // §8.4.7) e um `return` nu satisfaz o predicado. `fn f() -> Int
        // { return }` atravessava tudo verde e imprimia `null` num `Int`.
        // Corrigido em 2026-07-29, nas duas pontas: a garantia passou a existir
        // e a citação passou a apontar para quem a dá (R11).
        ast.ReturnStmt r => k.ReturnStatement(
            r.value == null ? null : _expr(r.value!),
          )..fileOffset = r.offset,
        ast.IfStmt f => _ifStmt(f),
        ast.WhileStmt w => _while(w),
        // `break`/`continue` sem label — o Kernel os quer com um `target`, e o
        // `ContinueSwitchStatement` é outra coisa. Ver [_loopControl].
        ast.BreakStmt b => _loopControl(b, isBreak: true),
        ast.ContinueStmt c => _loopControl(c, isBreak: false),
        _ => _ice('stmt-${s.runtimeType}', s),
      };

  /// `while` → `WhileStatement` (§7.4-e). Sem ele a linguagem **não tem
  /// iteração nenhuma** — o `for` é gated pela spec 012.
  ///
  /// ⚠️ **`break`/`continue` do Kernel exigem um ALVO.** Não existe `break`
  /// solto: `BreakStatement` recebe um `LabeledStatement`. E não existe
  /// `ContinueStatement` para laço — o `ContinueSwitchStatement` é outra coisa.
  /// O gabarito é o mesmo que a CFE usa:
  ///
  ///     L_break: while (c) { L_cont: { …corpo… } }
  ///       break    → BreakStatement(L_break)
  ///       continue → BreakStatement(L_cont)   // sai do CORPO, não do laço
  ///
  /// Os labels só são MATERIALIZADOS se o corpo os usar — um `while` sem
  /// `break`/`continue` sai como o nó puro, sem envelope. É o que evita dois nós
  /// por laço em todo programa que não precisa deles.
  k.Statement _while(ast.WhileStmt n) {
    final brk = k.LabeledStatement(null);
    final cont = k.LabeledStatement(null);
    _loops.add((brk: brk, cont: cont, usedBrk: false, usedCont: false));

    final body = _block(n.body);
    final frame = _loops.removeLast();

    // ⚠️ `LabeledStatement.body` é um CAMPO (`late Statement body`), não um
    // setter — atribuí-lo direto NÃO estabelece o `parent`. Só o construtor o
    // faz (`this.body = body..parent = this`). Fazer `label..body = x` deixa a
    // árvore com parent pendente, e o verify reprova com "Incorrect parent
    // pointer" — foi assim que este bug apareceu. Daí o `..parent =` explícito.
    k.Statement wrap(k.LabeledStatement label, k.Statement inner) {
      label.body = inner;
      inner.parent = label;
      return label..fileOffset = n.offset;
    }

    final inner = frame.usedCont ? wrap(cont, body) : body;
    final loop = k.WhileStatement(_expr(n.cond), inner)..fileOffset = n.offset;
    return frame.usedBrk ? wrap(brk, loop) : loop;
  }

  /// `break`/`continue` → `BreakStatement` para o label do laço mais interno.
  /// Ver [_while] para por que os dois viram `break` no Kernel.
  k.Statement _loopControl(ast.Stmt s, {required bool isBreak}) {
    if (_loops.isEmpty) {
      // Fora de laço — a F5/F6 deveria barrar; aqui é rede.
      _ice(isBreak ? 'break-outside-loop' : 'continue-outside-loop', s);
    }
    final i = _loops.length - 1;
    final f = _loops[i];
    _loops[i] = (
      brk: f.brk,
      cont: f.cont,
      usedBrk: f.usedBrk || isBreak,
      usedCont: f.usedCont || !isBreak,
    );
    return k.BreakStatement(isBreak ? f.brk : f.cont)..fileOffset = s.offset;
  }

  /// `if` STATEMENT → `IfStatement` (§7.4-e: *"nós diretos do Kernel"*).
  ///
  /// ⚠️ **Não confundir com o `if`-EXPR.** RD-1: só `=>` rende valor, então
  /// `if c => a else b` é a EXPRESSÃO (→ `ConditionalExpression`) e `if c { … }`
  /// é o STATEMENT (→ `IfStatement`, com blocos que não rendem). São nós
  /// diferentes do Kernel porque são construtos diferentes da linguagem — e o
  /// statement é a forma mais comum, que faltava.
  ///
  /// `else if` encadeia: o `ElseIf` carrega outro `IfStmt`, e a recursão o
  /// resolve como `otherwise` — a mesma forma que a cadeia teria escrita à mão.
  k.Statement _ifStmt(ast.IfStmt n) {
    final orElse = switch (n.orElse) {
      null => null,
      ast.ElseBlock e => _block(e.block),
      ast.ElseIf e => _stmt(e.ifStmt),
    };
    return k.IfStatement(_expr(n.cond), _block(n.then), orElse)
      ..fileOffset = n.offset;
  }

  /// `let`/`var` local COM valor e alvo `BindPattern` → uma `VariableDeclaration`
  /// no `Block` (o verifier a exige filha DIRETA de `Block`, `verifier.dart:1152`).
  ///
  ///   - `name`        = o `BindPattern.name`;
  ///   - `type`        = `_emitType` do tipo do binder (nº6) — non-nullable,
  ///                     ADR-0013; sem ela o Kernel poria `dynamic` (`type.dart`
  ///                     default do `VariableStatement`);
  ///   - `initializer` = emit do `value` (baixado ANTES de registrar o binder —
  ///                     um `let x = x` cairia em `ident-unbound`, não em silêncio);
  ///   - `isFinal`     = `!isVar` (`let`→final, `var`→mutável).
  ///
  /// ⚠️ **O `isFinal` de um LOCAL não interage com o passe `isFinal⟺setter` do
  /// sanitize:** aquele passe só reescreve `k.Field` (`sanitize.dart:83`), que tem
  /// `setterReference`; um `VariableStatement` local não é `Field` — o
  /// `OffsetNormalizer` NUNCA força `final` num `var` local. O `isFinal` que
  /// gravamos aqui é o que sai no `.dill`.
  ///
  /// ICE honesto para o resto (§7.8): `let` sem `value` (a forma `let x`), alvo
  /// não-`BindPattern` (destructuring/`_` — chave `(binder,fieldName)` é fatia
  /// futura), binder sem tipo (não devia, em programa verde).
  k.Statement _let(ast.LetStmt l) {
    final value = l.value;
    if (value == null) _ice('let-no-init', l); // `let x` / `var x: T`
    final target = l.target;
    if (target is! ast.BindPattern) {
      _ice('let-target-${target.runtimeType}', l); // destructuring / wildcard
    }
    final type = check.binderTypes[target];
    if (type == null) _ice('let-untyped', l); // binder sem tipo na nº6
    // `initializer` PRIMEIRO — antes de registrar o binder (auto-referência
    // vira ICE, não binding acidental).
    final init = _expr(value);
    final varDecl = k.VariableDeclaration(
      target.name,
      initializer: init,
      type: _emitType(type, l),
      isFinal: !l.isVar, // `let` → final; `var` → mutável (P1/P2)
    )..fileOffset = target.offset;
    _kernelDecls[target] = varDecl;
    return varDecl;
  }

  /// **PRÉ-CONDIÇÃO DA F7: a F5 tipou este nó.**
  ///
  /// A nº1 é *"total"* — mas total sobre o que a F5 **VISITOU**, e o contrato
  /// não carrega esse domínio. A F5 não desce em três regiões (`check.dart`:
  /// `case ast.InitDecl(): break;`, idem `OperatorDecl`, e defaults de payload
  /// de `EnumCase`), e a F7 **emite o corpo do `init`**. `Map[k]` devolve `null`
  /// para "ausente" e para "nunca visitado" com a mesma cara, e o emitter
  /// absorvia o `null` em silêncio:
  ///
  ///   - `_arithOpFor(op, null)`: `null is FloatType` é `false` ⟹ `div` vira
  ///     `~/`. `init(a: Float, b: Float) { self.r = a / b }` emitia **divisão
  ///     inteira sobre doubles** — e o `.dill` resultante **SEGFAULTA a VM**
  ///     (verificado 2026-07-29), não é só resultado errado;
  ///   - `_especializa(declared, null, _)` cai no declarado ⟹ o `num` do bug 7
  ///     volta, e o `checkNumericStaticTypes` não roda no `itac build`.
  ///
  /// Uma linha converte "artefato errado em silêncio" em **lacuna declarada**,
  /// que é a doutrina da casa: o ICE nomeia o nó e o offset, e quem o vir sabe
  /// que a região não foi tipada. Não conserta a F5 — **declara** que ela falta,
  /// que é o que separa uma cerca honesta de um crash.
  ///
  /// ⚠️ `untyped` nomeia ESTADO DO EMISSOR, e a spec 013 §7.8 é literal sobre
  /// o que isso significa: *"ICE em corpus é bug de fase anterior que vazou"*.
  /// Logo nenhum fixture pode `EXPECT-ICE` isto — ele existe para morrer quando
  /// a fase de cima aprender a visitar a região.
  k.Expression _expr(ast.Expr e) {
    if (!check.exprTypes.containsKey(e)) {
      _ice('untyped-${e.runtimeType}', e);
    }
    final out = _exprInner(e);
    // **CA11 — o sítio da travessia existencial fica registrado.** A nº7 diz
    // ONDE um valor cruzou para slot-trait (ADR-0017 §5); este mapa diz o que a
    // emissão pôs lá. Nada é decidido aqui: a F7 emite a expressão como emitiria
    // em qualquer outro contexto, e é exatamente isso que o
    // `checkExistentialZeroNode` cobra depois.
    //
    // Sem este registro o CA11 não teria como ser verificado no sítio — só
    // globalmente (via CA10, "nenhuma classe sintética"), o que deixaria passar
    // um box feito sem classe nova: um `AsExpression`, um helper static.
    final coercao = check.coercions[e];
    if (coercao != null) {
      travessias[e] = (no: out, classesDaFonte: _classesDaFonte(coercao.source));
    }
    return out;
  }

  k.Expression _exprInner(ast.Expr e) => switch (e) {
        ast.Call c => _call(c),
        ast.Str s => _str(s),
        ast.IntLit i => k.IntLiteral(i.value)..fileOffset = i.offset,
        ast.FloatLit f => k.DoubleLiteral(f.value)..fileOffset = f.offset,
        ast.BoolLit b => k.BoolLiteral(b.value)..fileOffset = b.offset,
        // `nil` → `null` NATIVO. Não é `Option.none`: não existe classe para
        // construir (§7.4-c). A [nullity-invariant] segue intacta do outro lado
        // — `""`/`0`/`[]` continuam VALORES, e só `nil` é ausência.
        ast.NilLit n => k.NullLiteral()..fileOffset = n.offset,
        ast.Binary b => _binary(b),
        ast.IfExpr f => _ifExpr(f),
        ast.Ident id => _ident(id),
        ast.Assign a => _assign(a),
        ast.Member m => _member(m),
        // O chão da spec 012: literais de coleção e indexação. `xs.length` e
        // `xs + ys` não aparecem aqui — o primeiro é desviado dentro do
        // `_member`, o segundo dentro do `_binary`, porque ambos compartilham o
        // nó com construções que não são do chão.
        ast.ListExpr l => _listExpr(l),
        ast.MapExpr m => _mapExpr(m),
        ast.Index i => _index(i),
        ast.MatchExpr m => _matchExpr(m),
        ast.Unary u => _unary(u),
        ast.Panic p => _panic(p),
        ast.Try t => _try(t),
        // `self` → `this`. Só aparece dentro de método/`init`, e a F4 já o
        // resolveu (`SelfRes`) — chegar aqui fora de um deles seria bug de fase
        // anterior, não input ruim.
        //
        // **Exceção: o corpo de um default de trait.** Ele é emitido como
        // `static` (ADR-0017 §2), onde `this` não existe e o receptor é o
        // primeiro parâmetro. `_selfComoVar` diz qual.
        ast.SelfExpr s => _selfComoVar == null
            ? (k.ThisExpression()..fileOffset = s.offset)
            : (k.VariableGet(_selfComoVar!)..fileOffset = s.offset),
        // `.none` como VALOR (`EnumShorthand`) sob contexto opcional → `null`.
        // Aparece no desugar de `?.`, cujo braço-vazio rende `.none`, não `nil`.
        // Mesma emissão do `nil` porque é a mesma coisa: `Option` ≡ `T?`, e a
        // variante vazia é a ausência nativa (§7.4-c, custo zero).
        //
        // Fora de contexto opcional é variante de enum DO USUÁRIO — outra fatia.
        ast.EnumShorthand s
            when s.variant == 'none' && check.exprTypes[s] is OptionalType =>
          k.NullLiteral()..fileOffset = s.offset,
        // `.variante` de enum do usuário (sem payload) → a CONSTANTE estática.
        ast.EnumShorthand s => _variantConst(s),
        ast.Closure c => _closure(c),
        ast.Capture c => _capture(c),
        _ => _ice('expr-${e.runtimeType}', e),
      };

  /// `&f` → **eta-expansão** (ADR-0020, decisão 1).
  ///
  /// Uma `fn` do Itá baixa com parâmetros **named required** (ruling spec 013
  /// §12-3 — é o que faz *"defaults saltáveis do meio"* funcionar); um valor de
  /// tipo-função é **posicional**. São ABIs diferentes e o Kernel não converte
  /// uma na outra, então a captura vira uma closure que adapta:
  ///
  ///     &dobro   ⟹   (v) => dobro(x: v)
  ///
  /// O glifo `&` é o que torna esse custo **escrito** em vez de inferido: a
  /// alocação existe, e ela aparece no fonte. Swift e Rust fazem a mesma
  /// conversão em silêncio — o Itá escolheu Elixir (Art. II), onde a captura é
  /// marcada no sítio.
  ///
  /// Isto é literalmente emissão de closure: **depende de LT-F7c**, e é por isso
  /// que a ordem do ADR-0020 §11 não era preferência.
  k.Expression _capture(ast.Capture c) {
    final alvo = c.target;
    if (alvo is! ast.Ident) _ice('capture-nonident', c);
    final res = check.resolution[alvo];
    if (res is! TopLevelRes) _ice('capture-nonresolved', c);
    final decl = res.decl;
    if (decl is! ast.FnDecl) _ice('capture-nonfn', c);
    final target = _procedures[decl];
    if (target == null) _ice('capture-unemitted', c);

    final tipo = check.exprTypes[c];
    if (tipo is! FunctionType) _ice('capture-untyped', c);
    final emitido = _emitType(tipo, c);
    if (emitido is! k.FunctionType) _ice('capture-nonfntype', c);

    // Os params do THUNK são posicionais; os args da chamada interna são NAMED,
    // pelo nome que a assinatura emitida usa (`p.label ?? p.name`) — o mesmo
    // acoplamento F5×F7 que o `conformer_label.tu` pina.
    final nomes = target.function.namedParameters;
    if (nomes.length != emitido.positionalParameters.length) {
      _ice('capture-arity', c);
    }
    final params = <k.VariableDeclaration>[];
    final args = <k.NamedExpression>[];
    for (var i = 0; i < emitido.positionalParameters.length; i++) {
      final p = k.VariableDeclaration(
        '#cap$i',
        type: emitido.positionalParameters[i],
        isFinal: true,
      )..fileOffset = c.offset;
      params.add(p);
      args.add(k.NamedExpression(nomes[i].name!, k.VariableGet(p))
        ..fileOffset = c.offset);
    }

    final chamada = k.StaticInvocation(target, k.Arguments([], named: args))
      ..fileOffset = c.offset;
    final isVoid = emitido.returnType is k.VoidType;
    return k.FunctionExpression(
      k.FunctionNode(
        k.Block([
          isVoid
              ? (k.ExpressionStatement(chamada)..fileOffset = c.offset)
              : (k.ReturnStatement(chamada)..fileOffset = c.offset),
        ])..fileOffset = c.offset,
        positionalParameters: params,
        requiredParameterCount: params.length,
        returnType: emitido.returnType,
      )..fileOffset = c.offset,
    )..fileOffset = c.offset;
  }

  /// `Closure` → **`FunctionExpression`** (§7.4-b).
  ///
  /// ⚠️ **Os parâmetros saem da nº1, NÃO da AST.** A closure implícita
  /// (`aplica() { 7 }`, trailing closure sem `$k`) chega com `params` VAZIO e a
  /// F5 lhe dá a aridade ESPERADA (`_closureAgainst`, `check.dart:2653-2656`:
  /// *"não há binder a ligar"*). Montar de `c.params` emitiria uma closure
  /// 0-ária com tipo estático `(int) -> int` — e nem o verifier nem o
  /// `NaiveTypeChecker` conferem aridade de `FunctionInvocation`, então isso
  /// rodaria até estourar na VM. É a R1 pura: a F7 traduz da side-table.
  ///
  /// ⚠️ **`_loops` é salvo e zerado.** Este é o primeiro construto do emitter
  /// com fronteira de função aninhada, e `break`/`continue` NÃO atravessam
  /// função: o `binary.md` é normativo — *"Labels are not in scope across
  /// function boundaries"* — e o `BinaryPrinter` zera o `_labelIndexer` ao
  /// entrar num `FunctionNode`. Sem isto, um `break` dentro de closure mataria a
  /// SERIALIZAÇÃO com um `Null check operator` do vendor: depois do verify,
  /// depois dos invariantes, sem span do `.tu`. Com isto, cai no
  /// `break-outside-loop` que já existe e já aponta a linha.
  ///
  /// (A F4 já barra `break` em closure — `resolver.dart` zera `_inLoop` em
  /// fronteira de função —, então isto é rede, não diagnóstico primário. Rede
  /// que custa duas linhas e evita um erro ilegível.)
  k.Expression _closure(ast.Closure c) {
    if (c.asyncMarker != ast.AsyncMarker.sync) _ice('closure-async', c);
    final type = check.exprTypes[c];
    if (type is! FunctionType) _ice('closure-untyped', c);

    // Label e default em param de closure PARSEIAM (`paramList`) e a F5 os
    // DESCARTA ao montar o tipo (`FunctionType.positional`). Baixar em silêncio
    // faria o `.tu` dizer uma coisa e o `.dill` outra — ICE nomeado até haver
    // ruling (ADR-0020 §6 registra que a superfície admite os dois).
    for (final p in c.params) {
      if (p.label != null) _ice('closure-param-label', c);
      if (p.defaultValue != null) _ice('closure-param-default', c);
    }
    if (c.params.isNotEmpty && c.params.length != type.params.length) {
      _ice('closure-arity-mismatch', c);
    }

    final params = <k.VariableDeclaration>[];
    for (var i = 0; i < type.params.length; i++) {
      final decl = k.VariableDeclaration(
        i < c.params.length ? c.params[i].name : '#arg$i',
        type: _emitType(type.params[i].type, c),
        isFinal: true,
      )..fileOffset = i < c.params.length ? c.params[i].offset : c.offset;
      if (i < c.params.length) _kernelDecls[c.params[i]] = decl;
      params.add(decl);
    }

    final ret = _emitType(type.ret, c);
    final isVoid = ret is k.VoidType;
    final salvos = List.of(_loops);
    _loops.clear();
    final k.Statement corpo;
    switch (c.body) {
      case ast.BlockBody b:
        corpo = _block(b.b);
      case ast.ExprBody e:
        corpo = k.Block([
          isVoid
              ? (k.ExpressionStatement(_expr(e.e))..fileOffset = e.e.offset)
              : (k.ReturnStatement(_expr(e.e))..fileOffset = e.e.offset),
        ])..fileOffset = c.offset;
    }
    _loops
      ..clear()
      ..addAll(salvos);

    return k.FunctionExpression(
      k.FunctionNode(
        corpo,
        positionalParameters: params,
        requiredParameterCount: params.length,
        returnType: ret,
      )..fileOffset = c.offset,
    )..fileOffset = c.offset;
  }

  /// Uso de nome LOCAL (`x` em `${x}` ou `x + 1`) → `VariableGet` da decl baixada
  /// pela 2ª side-table. O `interfaceTarget`/tipo estático saem do próprio
  /// `VariableDeclaration.type` (`VariableGet.getStaticTypeInternal`), Grupo B.
  ///
  /// Só `LocalRes` (F4) é CA aqui: `TopLevelRes` (chamar/ler `fn`/global como
  /// valor), `SelfRes` e `GroundRes` fora de callee ficam p/ depois → ICE.
  /// Binder resolvido mas sem decl no mapa = bug NOSSO (não `dynamic`) → ICE.
  k.Expression _ident(ast.Ident id) {
    final res = check.resolution[id];
    if (res is! LocalRes) _ice('ident-nonlocal', id); // TopLevel/Self/Ground
    final decl = _kernelDecls[res.binder];
    if (decl == null) _ice('ident-unbound', id); // binder verde sem decl baixada
    return k.VariableGet(decl)..fileOffset = id.offset;
  }

  /// Atribuição a uma variável LOCAL (`=`, `+=`, `-=`, `*=`, `/=`) → `VariableSet`.
  ///
  /// **É a outra metade do P1.** O `let`/`var` já baixava com o `isFinal` certo
  /// (§7.4-b), mas até aqui `var` compilava e **não mutava**: o glifo prometia
  /// mutação e a emissão não entregava.
  ///
  /// **A imutabilidade já foi cobrada pela F5** (`assign-to-immutable`, spec 014
  /// §1 — só binder `var` é slot legal), então não há re-checagem aqui. Se um
  /// `let` chegasse, seria bug de fase anterior — e o `isFinal=true` do próprio
  /// `VariableDeclaration` faria o verifier reprovar o `.dill`.
  ///
  /// **Composto** (`n += 1`) baixa como a forma expandida `n = n + 1`: o Kernel
  /// não tem nó de atribuição composta, e a F5 já validou os tipos pela MESMA
  /// tabela `_primitiveOps` (`check.dart:1629-1634` mapeia `AssignOp`→`BinaryOp`).
  /// O `/=` passa pelo [_arithOpFor] como qualquer `div` — a armadilha
  /// `~/`×`/` não pode ser fechada numa forma e reaberta na outra.
  ///
  /// ⚠️ O `VariableSet` do Kernel **rende o valor**; o `Assign` do Itá rende
  /// **`Void`** (spec 014 §12-2). Não há conflito: ele só aparece sob `ExprStmt`,
  /// e o `ExpressionStatement` descarta. Um `let y = (n = 2)` não chega aqui — a
  /// F5 o tiparia `Void` e o `let` seria erro.
  ///
  /// Alvo que não é `Ident` local (campo, índice) → ICE: `p.campo = 1` é a fatia
  /// de struct/class, `xs[i] = v` depende da 012.
  k.Expression _assign(ast.Assign a) {
    final target = a.target;
    // **`obj.campo = v` → `InstanceSet`** — a mutação de REFERÊNCIA (P2). Só
    // `class` chega aqui com campo mutável: em `struct` todo campo é `final`
    // (ruling §12-1) e a F5 já barrou com `assign-to-immutable`. O compound
    // (`c.n += 1`) reusa o mesmo caminho do local, lendo antes com `InstanceGet`.
    if (target is ast.Member) return _assignMember(a, target);
    if (target is! ast.Ident) _ice('assign-target-${target.runtimeType}', a);
    final res = check.resolution[target];
    if (res is! LocalRes) _ice('assign-nonlocal', a); // global/campo: fatia própria
    final decl = _kernelDecls[res.binder];
    if (decl == null) _ice('assign-unbound', a);

    final binop = switch (a.op) {
      ast.AssignOp.assign => null,
      ast.AssignOp.addAssign => ast.BinaryOp.add,
      ast.AssignOp.subAssign => ast.BinaryOp.sub,
      ast.AssignOp.mulAssign => ast.BinaryOp.mul,
      ast.AssignOp.divAssign => ast.BinaryOp.div,
    };

    final k.Expression value;
    if (binop == null) {
      value = _expr(a.value);
    } else {
      // `_arithAlvo`, não `_arithOpFor` cru: o alvo do `+` depende do TIPO,
      // e `s += "x"` sobre `String` gravava `num::+` — ver [_arithAlvo].
      final t = _arithAlvo(binop, check.exprTypes[target], a);
      value = k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        k.VariableGet(decl)..fileOffset = target.offset,
        t.op.name,
        k.Arguments([_expr(a.value)]),
        interfaceTarget: t.op,
        functionType: t.fnType,
      )..fileOffset = a.offset;
    }
    return k.VariableSet(decl, value)..fileOffset = a.offset;
  }

  /// `obj.campo = v` (e `+=` e cia.) → `InstanceSet`.
  ///
  /// ⚠️ **O RECEPTOR É HOISTADO EM TEMPORÁRIO** (`Let $r = recv in …`), e essa é
  /// a única construção que satisfaz as duas exigências ao mesmo tempo:
  ///
  ///   - `checkNoSharedNodes` — no Kernel todo nó tem UM pai, então a leitura e
  ///     a escrita não podem compartilhar a mesma instância de receptor;
  ///   - **avaliar uma vez** — `f().n += 1` tem de chamar `f()` UMA vez.
  ///
  /// Até 2026-07-29 aqui havia `k.Expression receiver() => _expr(target.receiver)`
  /// chamado DUAS vezes, com o comentário *"uma leitura NOVA por uso"* — e ele
  /// estava certo sobre o motivo (dois pais) e errado sobre a cura. Re-emitir a
  /// subárvore satisfaz o invariante da árvore e **cria** dupla execução: o
  /// remédio de um invariante virou o bug 6. Nenhum golden o via, porque todo
  /// fixture usava receptor puro (`c.n`), onde duplicar só custa nós.
  ///
  /// É a regra do Dragon §2.8.4 (Fig. 2.44/2.45): o subendereço é computado uma
  /// vez, num temporário, e o valor-L passa a referir o temporário. Vale para
  /// todo valor-L composto — `a[i] op= v` (DOIS temporários: `a` e `i`), `??=`,
  /// `++` — e sobretudo para o **copy-with `p.{x: 1}`**, ainda não emitido, que
  /// leria o receptor uma vez POR CAMPO não-mencionado.
  ///
  /// Receptor puro também é hoistado: distinguir puro de efeituoso aqui seria
  /// uma análise nova, e o `Let` extra é apagado pela VM. Uniformidade é a
  /// defesa — a exceção é que reabre o buraco.
  k.Expression _assignMember(ast.Assign a, ast.Member target) {
    final resolved = check.resolvedMembers[target];
    if (resolved == null) _ice('assign-member-unresolved', a);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('assign-member-on-${owner.runtimeType}', a);
    final field = _fields[owner.decl]?[target.name];
    if (field == null) _ice('assign-member-${target.name}', a);

    final recv = k.VariableDeclaration(
      null, // sintético: sem nome de usuário
      initializer: _expr(target.receiver),
      type: _emitType(owner, a),
      isFinal: true,
    )..fileOffset = target.receiver.offset;
    k.Expression receiver() =>
        k.VariableGet(recv)..fileOffset = target.receiver.offset;

    final binop = switch (a.op) {
      ast.AssignOp.assign => null,
      ast.AssignOp.addAssign => ast.BinaryOp.add,
      ast.AssignOp.subAssign => ast.BinaryOp.sub,
      ast.AssignOp.mulAssign => ast.BinaryOp.mul,
      ast.AssignOp.divAssign => ast.BinaryOp.div,
    };

    final k.Expression value;
    if (binop == null) {
      value = _expr(a.value);
    } else {
      // Mesma resolução do compound de local (ver [_arithAlvo]): `c.s += "x"`
      // sobre um campo `String` gravava `num::+` e morria em AOT.
      final t = _arithAlvo(binop, check.exprTypes[target], a);
      value = k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        k.InstanceGet(
          k.InstanceAccessKind.Instance,
          receiver(),
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = target.opOffset,
        t.op.name,
        k.Arguments([_expr(a.value)]),
        interfaceTarget: t.op,
        functionType: t.fnType,
      )..fileOffset = a.offset;
    }

    final set = k.InstanceSet(
      k.InstanceAccessKind.Instance,
      receiver(),
      field.name,
      value,
      interfaceTarget: field,
    )..fileOffset = a.offset;
    return k.Let(recv, set)..fileOffset = a.offset;
  }

  /// Tipo da F5 → `DartType` do Kernel, pela tabela [coreTypes] (os quatro do
  /// chão). [span] é o nó que porta o tipo (o `LetStmt`), para o ICE apontar. Todo
  /// tipo fora dos quatro → `ice-codegen-type-<Tipo>` (§7.8) — NUNCA `dynamic`.
  k.DartType _emitType(Type type, ast.AstNode span) {
    // **`Option<T>` ≡ `T?` → NULLABLE NATIVO do Kernel** (§7.4-c, spec 009 §8.4).
    // Não há classe `Option` no `.dill`: o opcional é a MESMA `DartType` do
    // interno com `Nullability.nullable`. É o CA10 — *custo zero* — e é o motivo
    // de o Itá poder ter `Option` sem pagar por ele: a Dart VM já tem nulidade
    // no sistema de tipos, e usá-la é herdar o Grupo B inteiro (unboxing,
    // null-check elidido pela TFA) em vez de reimplementá-lo.
    //
    // A idempotência (`T??` ≡ `T?`) vem de graça: o smart constructor `optional`
    // da F5 (`type.dart:211`) já a garante, então nunca chega um duplo aqui.
    if (type is OptionalType) {
      final inner = _emitType(type.inner, span);
      // `Void?` não tem imagem (e a F5 não o produz) — `withDeclaredNullability`
      // sobre `VoidType` devolveria algo sem sentido em vez de falhar.
      if (inner is k.VoidType) _ice('type-optional-void', span);
      return inner.withDeclaredNullability(k.Nullability.nullable);
    }
    // Tipo NOMINAL (`struct`/`class`) → `InterfaceType` da `Class` que o passo 1a
    // já registrou. Chega aqui antes da tabela porque `NamedType` carrega a decl,
    // não um valor — nenhuma chave fixa o alcançaria.
    // `Result<T,E>` → a classe de runtime (§7.4-c). Materializa sob demanda: uma
    // `fn` que DEVOLVE `Result` já precisa da classe, mesmo que o corpo ainda não
    // tenha construído nenhum.
    //
    // ⚠️ Os type-args são DESCARTADOS aqui — `ItaResult` é não-genérico e o
    // payload é `Object`. Não é preguiça: a emissão ainda não baixa type-params
    // (`fn-generic` é ICE), e usar `dynamic` para fingir genericidade violaria o
    // ADR-0013. `Object` perde precisão sem perder soundness, e o `as` do
    // destructuring devolve o tipo que a F5 provou. Quando ∀ nascer, `ItaResult`
    // ganha os dois type-params e este descarte sai.
    if (type is BuiltinType && type.kind == BuiltinKind.result) {
      return k.InterfaceType(_resultRuntime().base, k.Nullability.nonNullable);
    }
    // **`List<E>` / `Map<K,V>` → o `InterfaceType` GENÉRICO de `dart:core`**
    // (spec 012 §8.1: *"`List`/`String`/`Map` do Itá baixam para
    // `dart:core::List`/`String`/`Map` nativos"*). Diferente do `Result` logo
    // acima, os type-args **não** são descartados: são o que faz o `.length`
    // devolver `int` em vez de `E`, e o que o `Substitution.fromInterfaceType`
    // consome em [_groundReceiver]. Descartá-los aqui reabriria, na primeira
    // indexação, o mesmo furo do `interfaceTarget` genérico.
    if (type is BuiltinType &&
        (type.kind == BuiltinKind.list || type.kind == BuiltinKind.map)) {
      final shape = type.kind == BuiltinKind.list
          ? _GroundShape.list
          : _GroundShape.map;
      // A aridade vem da F5 (`type.dart:67-72`), e é ela que decide quantos
      // args o `InterfaceType` quer. Um descasamento aqui não é input ruim: é
      // `BuiltinType` construído errado por uma fase nossa, e o Kernel o
      // aceitaria em silêncio para explodir na substituição.
      //
      // Prefixo `ground-` e não `type-`: o fallback lá embaixo já é
      // `type-<runtimeType>`, e dois `_ice` com o mesmo prefixo interpolado são
      // um código só para a catraca (R13) — `make assertions` cobra.
      if (type.args.length != builtinArity[type.kind]) {
        _ice('ground-arity-${type.kind.name}-${type.args.length}', span);
      }
      return k.InterfaceType(
        ground.classes[shape]!,
        k.Nullability.nonNullable,
        [for (final a in type.args) _emitType(a, span)],
      );
    }
    if (type is NamedType) {
      // ∀ é fatia própria. **Sem catraca, e a razão é ORDEM, não impossibilidade
      // (R10):** para chegar aqui é preciso um `NamedType` com args, cuja decl
      // é genérica — e ela é emitida antes, parando em `struct-generic` /
      // `class-generic` / `enum-generic`. Verificado: `let c: Caixa<Int>` sobre
      // `struct Caixa<T>` devolve `ice-codegen-struct-generic`, nunca este. A
      // catraca deste nasce na fatia que emitir a decl genérica —
      // `ice_generic_struct.tu` registra o par.
      if (type.args.isNotEmpty) _ice('type-generic', span);
      final cls = _classes[type.decl];
      if (cls == null) _ice('type-unemitted-${type.kind.name}', span);
      return k.InterfaceType(cls, k.Nullability.nonNullable);
    }
    // **Tipo-função → `k.FunctionType` POSICIONAL** (spec 013 §7.4-b,
    // ADR-0020 §1), e o `_closureSynth` da F5 diz o mesmo verbatim: *"Closure é
    // posicional pura — a superfície não tem label ali"* (`check.dart:1079`).
    //
    // ⚠️ **Posicional, nunca `namedParameters`** — e o motivo não é gosto: a
    // gramática do tipo é `type ::= "(" type ("," type)* ")" "->" type`
    // (`grammar.ebnf:353`), onde o slot é **`type`**, não `param`. A anotação
    // resolve para `FunctionType.positional` (`collect.dart:717`).
    //
    // O ruling spec 013 §12-3 (*tudo named required*) decide os params de
    // **`fn`**, não o tipo-função — aplicá-lo aqui foi a citação-por-associação
    // que a revisão adversarial pegou no plano desta fatia. Se `namedParameters`
    // fosse usado, o call-site emitiria `NamedExpression('$0', …)` contra um
    // param que se chama outra coisa: `NoSuchMethodError` em runtime, e nenhum
    // gate veria — nem o verifier (não tem `visitFunctionInvocation`) nem o
    // `NaiveTypeChecker` (não confere aridade nem nome de `FunctionInvocation`).
    //
    // O `requiredParameterCount` cai no default (= `positionalParameters.length`,
    // `types.dart:1104-1113`), que é o certo: como VALOR, uma função tem aridade
    // fixa — defaults são do sítio de declaração e não sobrevivem à travessia.
    if (type is FunctionType) {
      if (type.isAsync) _ice('type-fn-async', span); // §12-2, fatia da async
      // ∀. **Sem catraca, pelo mesmo motivo do `type-generic` acima — mais um:**
      // a gramática não tem anotação de tipo-função quantificada. `let f:
      // <T>(T) -> T` morre no parser com `parse-error: expected-type`, então
      // `quantifiers` não chega aqui pela superfície; e capturar uma `fn`
      // genérica com `&f` para aqui antes, em `fn-generic`. Alcançável quando ∀
      // nascer E a gramática ganhar a forma — duas fatias, não um impedimento.
      if (type.quantifiers.isNotEmpty) _ice('type-fn-generic', span);
      return k.FunctionType(
        [for (final p in type.params) _emitType(p.type, span)],
        _emitType(type.ret, span),
        k.Nullability.nonNullable,
      );
    }
    return coreTypes[type] ?? _ice('type-${type.runtimeType}', span);
  }

  /// Despacha o `Binary` pela FAMÍLIA do operador — cada família tem alvo Kernel
  /// distinto (spec 006 §5: o enum é TAG sintática, o nó é derivado por tipos):
  ///
  ///   - add/sub/mul/div/mod → `InstanceInvocation` de `num` (§7.4-a);
  ///   - lt/gt/le/ge         → `InstanceInvocation` de `num`, SÓ receptor numérico;
  ///   - eq/ne               → `EqualsCall` / `Not(EqualsCall)` (`==` é especial);
  ///   - and/or              → `LogicalExpression` (curto-circuito é do nó);
  ///   - pow/coalesce/pipe/compose → ICE (desugaring/call de fatia posterior).
  k.Expression _binary(ast.Binary b) {
    if (arithOps.containsKey(b.op)) {
      // **UM ponto de decisão para as três formas do operador** — `a + b`,
      // `a += b` e `c.a += b`. Ver [_arithAlvo]: a régua já existia para o `div`
      // (o `~/` de Int × o `/` de Float), escrita verbatim em
      // `conformance/codegen/var_assign.tu:13-15` — *"a armadilha `~/` (Int) ×
      // `/` (Float) não pode ser fechada numa forma e reaberta na outra"* —, e
      // o `+` a violava porque o desvio do chão nasceu ACIMA do resolvedor
      // comum em vez de DENTRO dele.
      final t = _arithAlvo(b.op, check.exprTypes[b.left], b);
      return k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        _expr(b.left),
        t.op.name,
        k.Arguments([_expr(b.right)]),
        interfaceTarget: t.op,
        functionType: t.fnType,
      )..fileOffset = b.offset;
    }
    if (cmpOps.containsKey(b.op)) return _compare(b);
    if (b.op == ast.BinaryOp.eq || b.op == ast.BinaryOp.ne) return _equals(b);
    if (b.op == ast.BinaryOp.and || b.op == ast.BinaryOp.or) return _logical(b);
    // **`f >> g` → closure de composição** (spec 007 §12-C).
    //
    // A F3 costumava fazer isto, e por isso a composição não sintetizava: a
    // closure dela nascia com parâmetro SEM anotação. Retido como núcleo, o nó
    // chega aqui com o tipo que a F5 provou — e a closure sai já tipada.
    //
    //     f >> g   ⟹   ($c) => g(f($c))
    //
    // Os dois operandos são emitidos como VALORES (cada um já é uma closure ou
    // uma captura `&f`), e a chamada de cada um é `FunctionInvocation` — o mesmo
    // nó do §7.4-b, porque aqui eles são valores de função, não callees
    // estáticos.
    if (b.op == ast.BinaryOp.compose) {
      final tipo = check.exprTypes[b];
      if (tipo is! FunctionType) _ice('compose-untyped', b);
      final emitido = _emitType(tipo, b);
      if (emitido is! k.FunctionType) _ice('compose-nonfntype', b);
      final tf = check.exprTypes[b.left];
      final tg = check.exprTypes[b.right];
      if (tf is! FunctionType || tg is! FunctionType) _ice('compose-operand', b);

      final param = k.VariableDeclaration(
        '#c',
        type: emitido.positionalParameters.single,
        isFinal: true,
      )..fileOffset = b.offset;

      // `f($c)` — `f` é valor, logo `FunctionInvocation`.
      final chamaF = k.FunctionInvocation(
        k.FunctionAccessKind.FunctionType,
        _expr(b.left),
        k.Arguments([k.VariableGet(param)..fileOffset = b.offset]),
        functionType: _emitType(tf, b) as k.FunctionType,
      )..fileOffset = b.offset;

      final chamaG = k.FunctionInvocation(
        k.FunctionAccessKind.FunctionType,
        _expr(b.right),
        k.Arguments([chamaF]),
        functionType: _emitType(tg, b) as k.FunctionType,
      )..fileOffset = b.offset;

      return k.FunctionExpression(
        k.FunctionNode(
          k.Block([k.ReturnStatement(chamaG)..fileOffset = b.offset])
            ..fileOffset = b.offset,
          positionalParameters: [param],
          requiredParameterCount: 1,
          returnType: emitido.returnType,
        )..fileOffset = b.offset,
      )..fileOffset = b.offset;
    }
    return _ice('binary-${b.op.name}', b); // pow, ??, |>
  }

  /// A regra do `div` mora AQUI e em nenhum outro lugar — `n / 2` e `n /= 2`
  /// baixam pelo mesmo caminho, senão a armadilha do `~/`×`/` seria fechada numa
  /// forma e reaberta na outra.
  k.Procedure _arithOpFor(ast.BinaryOp op, Type? leftType) {
    if (op != ast.BinaryOp.div) return arithOps[op]!;
    return leftType is FloatType ? floatDiv : arithOps[ast.BinaryOp.div]!;
  }

  /// §7.4-a: operador de `dart:core::num` (aritmético OU comparação de ordem) →
  /// `InstanceInvocation`, com `interfaceTarget` + `functionType` resolvidos — o
  /// Kernel os exige (sem eles cairia em `DynamicInvocation`). O `name` sai do
  /// próprio `Procedure` (`+`/`~/`/`<`/…), então casa por construção com o
  /// `interfaceTarget`.
  ///
  /// ⚠️ **O `returnType` é ESPECIALIZADO com o tipo que a F5 provou** — não a
  /// assinatura declarada de `num`. Até 2026-07-29 esta função gravava
  /// `op.function.computeFunctionType(...)` cru, com o comentário *"o tipo
  /// estático fica correto sem esforço extra"*. O nó de fato lê o `returnType`
  /// daí (`InstanceInvocation.getStaticTypeInternal`, `expressions.dart:1958`),
  /// mas o valor estava ERRADO: os ops de `int` moram em `num`, cuja assinatura
  /// é `num operator +(num)` (`num.dart:110`), então `Int + Int` gravava **num**.
  /// Preenchido não é correto (CLAUDE.md R4).
  ///
  /// O custo não aparece rodando: a VM **descarta** este campo
  /// (`SkipDartType(); // read function_type` no `kernel_binary_flowgraph.cc`),
  /// então JIT imprime igual. Quem o consome é a TFA em AOT — e o unboxing só
  /// concede `kInt` a subtipo de `int`, que `num` não é. Toda a aritmética do
  /// Itá ficava boxed no binário final. O `.dill` também ficava inconsistente
  /// CONSIGO MESMO: `TypeEnvironment.getTypeOfSpecialCasedBinaryOperator`
  /// (`type_environment.dart:217`) diz `int`, o campo dizia `num`.
  ///
  /// Fonte do tipo é a nº1 (`exprTypes`), não uma reimplementação da regra do
  /// Dart: a F5 já resolveu, e a F7 traduz. `div` de `Int` já estava certo por
  /// acidente — `~/` devolve `int` na assinatura (`num.dart:172`).
  k.Expression _numOp(ast.Binary b, k.Procedure op) => k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        _expr(b.left),
        op.name,
        k.Arguments([_expr(b.right)]),
        interfaceTarget: op,
        functionType: _especializa(
          op.function.computeFunctionType(k.Nullability.nonNullable),
          check.exprTypes[b],
          b,
        ),
      )..fileOffset = b.offset;

  /// O `functionType` declarado, com o `returnType` trocado pelo tipo PROVADO.
  ///
  /// Só o retorno muda: os parâmetros continuam sendo os do membro real de `num`
  /// (é o `interfaceTarget` que a VM resolve), e mexer neles descasaria o nó do
  /// alvo. Sem tipo provado — o que não deve acontecer em entrada F5-verde — cai
  /// no declarado, que é o comportamento antigo: degradar é melhor que mentir um
  /// tipo inventado.
  k.FunctionType _especializa(
    k.FunctionType declared,
    Type? provado,
    ast.AstNode span,
  ) {
    if (provado == null) return declared;
    return k.FunctionType(
      declared.positionalParameters,
      _emitType(provado, span),
      declared.declaredNullability,
      namedParameters: declared.namedParameters,
      typeParameters: declared.typeParameters,
      requiredParameterCount: declared.requiredParameterCount,
    );
  }

  /// Comparação de ORDEM (`<`/`>`/`<=`/`>=`) → `InstanceInvocation` de `num`, mas
  /// **só se o receptor for numérico**. `String < String` passa a F5
  /// (`comparison-type-mismatch` só cobra tipos IGUAIS) mas NÃO existe no Kernel
  /// — emiti-lo faria a VM rejeitar. Receptor não-`Int`/`Float` → ICE honesto
  /// (`ice-codegen-cmp-on-<Tipo>`, §7.8), nunca um `<` inválido.
  k.Expression _compare(ast.Binary b) {
    final leftType = check.exprTypes[b.left];
    if (leftType is! IntType && leftType is! FloatType) {
      _ice('cmp-on-${leftType.runtimeType}', b);
    }
    return _numOp(b, cmpOps[b.op]!);
  }

  /// `==`/`!=` → `EqualsCall` (nó ESPECIAL do Kernel para `==` non-null,
  /// expressions.dart:2471) / `Not(EqualsCall)` — a própria doc do `Not`
  /// (`:3164`) diz que `!=` é desugarado assim. O `interfaceTarget` é o `==` de
  /// interface do tipo do RECEPTOR ([equalsOps]); `functionType` (`bool
  /// Function(Object)`) sai do mesmo `Procedure`, e o `getStaticTypeInternal` do
  /// nó lê seu `returnType` (`bool`).
  ///
  /// A F5 aceita `l == r` de qualquer par idêntico, mas só sabemos baixar os
  /// quatro escalares; receptor fora da [equalsOps] → ICE (`eq-on-<Tipo>`).
  ///
  /// ⚠️ **O código era `cmp-on-<Tipo>` até 2026-07-29 — o MESMO de [_compare],
  /// com a mesma interpolação.** Duas fronteiras com um código só: o
  /// `ice_cmp_on_string.tu` cobre a de [_compare], esta ficava sem catraca, e
  /// nada ficaria vermelho quando o `==` estrutural nascesse (R13 + R7). O nome
  /// ainda mentia sobre o caminho — este é o de igualdade, não o de ordem.
  k.Expression _equals(ast.Binary b) {
    final leftType = check.exprTypes[b.left];
    // **`enum` SEM payload compara por IDENTIDADE** — cada variante é um
    // `static final` único, então `Object::==` é a semântica certa e completa.
    //
    // ⚠️ **`struct` NÃO entra aqui**, e a distinção é de PRINCÍPIO: struct é
    // VALOR (P2), logo `p1 == p2` tem de ser igualdade ESTRUTURAL (campo a
    // campo) — usar identidade faria duas cópias iguais compararem `false`, que
    // é exatamente a semântica de referência que o `struct` existe para negar.
    // O `==` estrutural sintetizado é fatia própria (§8.2 já o prevê); até lá,
    // ICE honesto em vez de uma resposta errada em silêncio.
    final op = leftType is NamedType && leftType.kind == TypeKind.enum_
        ? equalsOps[const BoolType()] // `Object::==`
        : equalsOps[leftType];
    if (op == null) _ice('eq-on-${leftType.runtimeType}', b);
    final call = k.EqualsCall(
      _expr(b.left),
      _expr(b.right),
      functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      interfaceTarget: op,
    )..fileOffset = b.offset;
    return b.op == ast.BinaryOp.ne
        ? (k.Not(call)..fileOffset = b.offset)
        : call;
  }

  /// `&&`/`||` → `LogicalExpression` (expressions.dart:3231). O **curto-circuito
  /// é semântica do NÓ** (a VM o baixa para desvios no flowgraph) — não emitimos
  /// nada além da variante `AND`/`OR`; é Grupo B. Static type = `bool`
  /// (`getStaticTypeInternal`), garantido pela F5 (`not-bool` nos operandos).
  k.Expression _logical(ast.Binary b) {
    final logOp = b.op == ast.BinaryOp.and
        ? k.LogicalExpressionOperator.AND
        : k.LogicalExpressionOperator.OR;
    return k.LogicalExpression(_expr(b.left), logOp, _expr(b.right))
      ..fileOffset = b.offset;
  }

  /// `if SUBJECT => then else orElse` na **forma booleana** (`binding == null`,
  /// ast.dart:510) → `ConditionalExpression(cond, then, orElse, staticType)`
  /// (expressions.dart:3293). Ramos são EXPRESSÕES (RD-1, `=>`), `else`
  /// obrigatório → sempre há `otherwise`. O `staticType` (posicional obrigatório;
  /// o nó o devolve cru em `getStaticTypeInternal`) é o tipo do PRÓPRIO `IfExpr`
  /// = o join dos ramos que a F5 computou (`check.exprTypes[n]`), baixado por
  /// [_emitType] — non-nullable, ADR-0013; fora dos quatro do chão → ICE.
  ///
  /// **if-let** (`binding != null`) é desembrulho de PATTERN → ICE
  /// (`ice-codegen-if-let`), fatia do `match`. A F5 já o barra na síntese
  /// (`_ifExpr` → `_cannotInfer`), mas o guard aqui mantém a honestidade §7.8.
  k.Expression _ifExpr(ast.IfExpr n) {
    if (n.binding != null) _ice('if-let', n);
    final staticType = check.exprTypes[n];
    if (staticType == null) _ice('if-untyped', n); // defensivo: F5 é total (§7-4)
    return k.ConditionalExpression(
      _expr(n.subject),
      _expr(n.then),
      _expr(n.orElse),
      _emitType(staticType, n),
    )..fileOffset = n.offset;
  }

  /// Chamada → dispatch ESTÁTICO (`StaticInvocation`), nas duas formas que a F4
  /// distingue pelo callee:
  ///
  ///   - `GroundRes('print')` → o built-in do chão (§7.6), 1 posicional `String`;
  ///   - `TopLevelRes(FnDecl)` → `fn` do usuário, args **named** pelo slot da nº5.
  ///
  /// `TopLevelRes` para algo que não é `FnDecl` (construtor de struct/class) é
  /// fatia própria — ICE honesto, não um alvo chutado.
  k.Expression _call(ast.Call c) {
    final callee = c.callee;
    // `.variante(args)` — construção de variante de enum SELADO.
    if (callee is ast.EnumShorthand) return _variantCall(c, callee);
    // **`v.metodo(args)` — DISPATCH DE INSTÂNCIA** (§7.4-d). Quando o receptor é
    // `any Trait`, o `interfaceTarget` é o procedure ABSTRATO do trait e a VM
    // resolve por vtable (Grupo B) — é o CA4. Quando é um tipo concreto, aponta
    // o procedure da própria classe.
    if (callee is ast.Member) return _methodCall(c, callee);
    if (callee is! ast.Ident) _ice('call-nonident', c); // valor-função: §7.4-b
    final res = check.resolution[callee];
    // `opOffset` (o `(` da invocação) é o span do call — o stack trace aponta
    // p/ o seletor, não p/ o início do receptor (doutrina de span da AST).
    if (res is GroundRes) {
      if (res.name != 'print') _ice('ground-${res.name}', c);
      return k.StaticInvocation.byReference(printRef, _groundArgs(c))
        ..fileOffset = c.opOffset;
    }
    if (res is TopLevelRes) {
      final decl = res.decl;
      // **Nome de TIPO em posição de chamada é CONSTRUÇÃO** — `P(x: 1)` não é
      // uma função que devolve `P`, é o `init` memberwise (§7.4-c). A F5 já o
      // trata assim (`_constructorType`), e aqui vira `ConstructorInvocation`.
      if (decl is ast.StructDecl) {
        final ctor = _ctorDaChamada(c, decl);
        if (ctor == null) _ice('call-unemitted-struct', c);
        return k.ConstructorInvocation(ctor, _initArgs(c, decl))
          ..fileOffset = c.opOffset;
      }
      // `class` — mesma forma, mas os "params" são os do `init` EXPLÍCITO, não
      // os campos: `class` nunca tem memberwise (ADR-0012 §A-1).
      if (decl is ast.ClassDecl) {
        final ctor = _ctorDaChamada(c, decl);
        if (ctor == null) _ice('call-unemitted-class', c);
        return k.ConstructorInvocation(ctor, _classInitArgs(c, decl))
          ..fileOffset = c.opOffset;
      }
      if (decl is! ast.FnDecl) _ice('call-toplevel-${decl.runtimeType}', c);
      final target = _procedures[decl];
      // Assinatura não emitida = bug NOSSO no passo 1, não input ruim.
      if (target == null) _ice('call-unemitted-fn', c);
      return k.StaticInvocation(target, _userArgs(c, decl))
        ..fileOffset = c.opOffset;
    }
    // **Chamada de VALOR-FUNÇÃO** (`f(v)` com `f` local de tipo-função) →
    // `FunctionInvocation` (§7.4-b).
    //
    // ⚠️ **`FunctionInvocation`, não `LocalFunctionInvocation`.** O doc do
    // `FunctionAccessKind.FunctionType` descreve literalmente este caso: *"An
    // access to the 'call' method on an expression whose static type is a
    // function type"*. O irmão `LocalFunctionInvocation` faz
    // `variable.parent as FunctionDeclaration` — **cast duro** — e a TFA o
    // chama em AOT (`summary_collector.dart::visitLocalFunctionInvocation`);
    // com um `let f = closure` (parent = `Block`) isso quebra o build AOT com
    // CastError. JIT não vê, dart2js não vê. Não é "roda igual": quebra um alvo
    // inteiro, e só nele.
    //
    // `InstanceInvocation` de `call` nem é construtível honestamente: exige um
    // `Procedure interfaceTarget`, e não existe `Procedure call` num tipo-função.
    //
    // O `functionType` é NULLABLE no nó e vira `dynamic` quando ausente — um
    // `dynamic` **calculado**, que não põe nó `DynamicType` na árvore e por isso
    // o `visitDynamicType` NÃO veria. Daí o ICE em vez do `??`.
    if (res is LocalRes) {
      final decl = _kernelDecls[res.binder];
      if (decl == null) _ice('call-value-unbound', c);
      final tipo = check.exprTypes[c.callee];
      if (tipo is! FunctionType) _ice('call-value-untyped', c);
      final emitido = _emitType(tipo, c);
      if (emitido is! k.FunctionType) _ice('call-value-nonfn', c);
      final positional = <k.Expression>[];
      for (final a in c.args) {
        // Valor-função é POSICIONAL (ADR-0020 §1): o label não sobrevive à
        // travessia para valor, e a F5 não o produz aqui.
        if (a.label != null) _ice('call-value-named-arg', a.value);
        positional.add(_expr(a.value));
      }
      if (positional.length != emitido.positionalParameters.length) {
        _ice('call-value-arity', c);
      }
      return k.FunctionInvocation(
        k.FunctionAccessKind.FunctionType,
        k.VariableGet(decl)..fileOffset = c.callee.offset,
        k.Arguments(positional),
        functionType: emitido,
      )..fileOffset = c.opOffset;
    }
    _ice('call-${res.runtimeType}', c); // Self (método) — fatia própria
  }

  /// `print` é 1 posicional `String` (§12-4) — o chão não tem labels.
  k.Arguments _groundArgs(ast.Call c) {
    final positional = <k.Expression>[];
    for (final a in c.args) {
      if (a.label != null) _ice('named-arg', a.value);
      positional.add(_expr(a.value));
    }
    return k.Arguments(positional);
  }

  /// Args de `fn` do usuário → **named**, montados pela **side-table nº5**.
  ///
  /// `slot[i]` é o índice do PARÂMETRO que o argumento `i` preenche — e isso não
  /// é recuperável aqui: `Arg.label` é nullable, e a regra "ordem obrigatória,
  /// defaults saltáveis" permite `f(a:1, c:3)` saltar o param do MEIO. Sem o slot,
  /// a F7 teria de re-rodar o `_matchArgs` da F5.
  ///
  /// O nome de cada `NamedExpression` é o do `VariableDeclaration` do param
  /// (= o label) — casar por nome é como o Kernel resolve named
  /// (`verifier.dart:1337-1354`), então derivá-lo do MESMO objeto que a
  /// assinatura usou é o que garante que os dois lados não divirjam.
  k.Arguments _userArgs(ast.Call c, ast.FnDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('call-unresolved', c); // nº5 ausente em programa verde
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('call-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final paramIndex = slot[i];
      if (paramIndex < 0 || paramIndex >= decl.params.length) {
        _ice('call-slot-range', c);
      }
      final paramDecl = _kernelDecls[decl.params[paramIndex]];
      if (paramDecl == null) _ice('call-param-unemitted', c);
      named.add(k.NamedExpression(paramDecl.name!, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    // Params SALTADOS (default) não entram — a VM materializa o default a partir
    // do `initializer`. Hoje `param-default` é ICE, então a lista é sempre total.
    return k.Arguments([], named: named);
  }

  /// Args do `init` memberwise → **named**, pelos NOMES DOS CAMPOS.
  ///
  /// Difere do [_userArgs] num ponto que importa: o `init` sintetizado não tem
  /// `Param` de AST — seus "params" são os campos (`TypeInfo.fields`, nº2), e é
  /// a ordem DELES que o `slot` da nº5 indexa. Por isso a resolução do nome vai
  /// à lista de campos, não a `decl.params`.
  k.Arguments _initArgs(ast.Call c, ast.StructDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('init-unresolved', c);
    final fieldInfos = check.types.of(decl)?.fields;
    if (fieldInfos == null) _ice('init-nofields', c);
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('init-slot-arity', c);

    // **O que o slot indexa depende de QUAL `init` foi escolhido.** O memberwise
    // não tem AST — seus "params" são os campos —, mas um `init` de `extension`
    // tem `params` próprios, e a nº5 os indexou. Ler campos aqui ligaria
    // `P(diagonal: 7)` ao campo de índice 0.
    final alvo = call.initTarget;
    if (alvo != null) return _argsDeInit(c, alvo, slot);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final fieldIndex = slot[i];
      if (fieldIndex < 0 || fieldIndex >= fieldInfos.length) {
        _ice('init-slot-range', c);
      }
      named.add(
        k.NamedExpression(fieldInfos[fieldIndex].name, _expr(c.args[i].value))
          ..fileOffset = c.args[i].value.offset,
      );
    }
    return k.Arguments([], named: named);
  }

  /// **`e?` — o `Try`, e o único gabarito com FLUXO NÃO-LOCAL** (§7.4-e, **CA8**).
  ///
  /// É o núcleo do *zero try/catch* (P7): o `?` marca no CARACTERE EXATO onde a
  /// propagação acontece. A ausência de marca significa que nada propaga — o
  /// oposto do try/catch, onde a ausência significa "isto pode lançar".
  ///
  /// A semântica é `match e { .ok($v) => $v, .err($e) => return .err($e) }`, e o
  /// `return` está DENTRO de uma expressão (`let x = f()?`). No Kernel isso pede
  /// **`BlockExpression`** — `Block` de statements + a `value` que ele rende:
  ///
  ///     BlockExpression(
  ///       Block([
  ///         var #try = <operando>;
  ///         if (#try is ItaResult$err) return ItaResult$err(#try.value);
  ///       ]),
  ///       (#try as ItaResult$ok).value as T,
  ///     )
  ///
  /// ⚠️ O `ReturnStatement` sai da FUNÇÃO envolvente, não do bloco — que é
  /// exatamente o early-return que o `?` promete. A F5 já garantiu o contrato
  /// (`try-outside-result-fn` exige `Result` no retorno da fn; `error-type-mismatch`
  /// exige `E` IDÊNTICO, sem `From`), então aqui não há o que re-checar.
  ///
  /// ⚠️ O `.err` é RECONSTRUÍDO, não repassado: `ItaResult$err(#try.value)`. O
  /// objeto de origem tem tipo `Result<T₁,E>` e o de destino `Result<T₂,E>` —
  /// mesmo `E`, `T` diferente. Como o payload é `Object` e só o `E` importa no
  /// caminho de erro, reconstruir é o que mantém o tipo do retorno honesto.
  k.Expression _try(ast.Try t) {
    final rt = _resultRuntime();
    final value = check.exprTypes[t];
    if (value == null) _ice('try-untyped', t);

    final tmp = k.VariableDeclaration(
      '#try',
      initializer: _expr(t.operand),
      type: k.InterfaceType(rt.base, k.Nullability.nonNullable),
      isFinal: true,
    )..fileOffset = t.offset;

    final errCls = rt.errCtor.enclosingClass;
    final okCls = rt.okCtor.enclosingClass;
    k.Expression payload(k.Class cls, k.Field field) => k.InstanceGet(
          k.InstanceAccessKind.Instance,
          k.AsExpression(
            k.VariableGet(tmp),
            k.InterfaceType(cls, k.Nullability.nonNullable),
          )..fileOffset = t.offset,
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = t.offset;

    return k.BlockExpression(
      k.Block([
        tmp,
        k.IfStatement(
          k.IsExpression(
            k.VariableGet(tmp),
            k.InterfaceType(errCls, k.Nullability.nonNullable),
          )..fileOffset = t.offset,
          k.ReturnStatement(
            k.ConstructorInvocation(
              rt.errCtor,
              k.Arguments([payload(errCls, rt.errValue)]),
            )..fileOffset = t.offset,
          )..fileOffset = t.offset,
          null,
        )..fileOffset = t.offset,
      ])..fileOffset = t.offset,
      // O caminho feliz: o payload do `.ok`, estreitado para o `T` que a F5 provou.
      k.AsExpression(payload(okCls, rt.okValue), _emitType(value, t))
        ..fileOffset = t.offset,
    )..fileOffset = t.offset;
  }

  /// `panic(msg)` → `Throw` de um `ItaPanic` (§7.4-f, **CA9**).
  ///
  /// **Zero try/catch na linguagem (P7) ⟹ NADA o captura.** O isolate morre, o
  /// stderr recebe a mensagem, e o exit code é ≠ 0 — na VM/AOT vale **255**
  /// (`runtime/bin/error_exit.h::kErrorExitCode`), no JS/Node vale **1**. A
  /// paridade do ADR-0005 cobre só a PROPRIEDADE ("exit ≠ 0"); o VALOR diverge, e
  /// o CA9 o marca DIVERGE-DOCUMENTADO. Por isso o fixture assere `EXPECT-EXIT`
  /// no valor da VM e o runner só roda a VM — declarar isso é o que impede o
  /// número 255 de virar promessa dos três alvos.
  ///
  /// A classe é criada **sob demanda**: programa sem `panic` não carrega
  /// `ItaPanic` no `.dill`. Isso mantém o gate de custo zero honesto — o
  /// invariante `checkNoSyntheticClasses` conhece este nome e só o tolera aqui.
  k.Expression _panic(ast.Panic p) =>
      k.Throw(k.ConstructorInvocation(_panicCtor(), k.Arguments([_expr(p.operand)])))
        ..fileOffset = p.offset;

  /// O runtime de **`Result<T,E>`** (§7.4-c: *"`Result` → classe, payload nos
  /// dois lados"*), materializado sob demanda como `ItaResult` selado +
  /// `ItaResult$ok` / `ItaResult$err`.
  ///
  /// ⚠️ **Por que classe, e `Option` não.** `Option<T>` ≡ `T?` tem equivalente
  /// NATIVO no Kernel (nulidade), então custa zero. `Result` carrega payload nos
  /// DOIS lados — não há tipo nativo que represente "ou T ou E" sem perder um
  /// deles. Aqui a classe é o preço mínimo, não uma escolha de conveniência.
  ///
  /// Os campos são `dynamic`? **Não.** São `Object`: o `Result` do Itá é
  /// genérico e a emissão ainda não baixa type-params (`fn-generic` é ICE), mas
  /// `dynamic` violaria o ADR-0013 e o invariante o pegaria. `Object` é honesto
  /// — perde precisão, não soundness — e o `as` no destructuring devolve o tipo
  /// certo, que a F5 já provou.
  ({k.Class base, k.Constructor okCtor, k.Field okValue, k.Constructor errCtor, k.Field errValue})
      _resultRuntime() {
    final existing = _resultParts;
    if (existing != null) return existing;

    final objectType = k.InterfaceType(objectClass, k.Nullability.nonNullable);
    final base = k.Class(
      name: 'ItaResult',
      isAbstract: true,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    );
    final baseCtor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    );
    base.addConstructor(baseCtor);

    ({k.Class cls, k.Constructor ctor, k.Field field}) side(String name) {
      final cls = k.Class(
        name: 'ItaResult\$$name',
        fileUri: fileUri,
        supertype: k.Supertype(base, const []),
      );
      final field = k.Field.immutable(
        k.Name('value'),
        type: objectType,
        fileUri: fileUri,
      );
      cls.addField(field);
      final param = k.VariableDeclaration('value', type: objectType);
      final ctor = k.Constructor(
        k.FunctionNode(
          k.EmptyStatement(),
          positionalParameters: [param],
          returnType: const k.VoidType(),
        ),
        name: k.Name(''),
        initializers: [
          k.FieldInitializer(field, k.VariableGet(param)),
          k.SuperInitializer(baseCtor, k.Arguments.empty()),
        ],
        fileUri: fileUri,
      );
      cls.addConstructor(ctor);
      return (cls: cls, ctor: ctor, field: field);
    }

    final ok = side('ok');
    final err = side('err');
    _resultClasses = [base, ok.cls, err.cls];
    return _resultParts = (
      base: base,
      okCtor: ok.ctor,
      okValue: ok.field,
      errCtor: err.ctor,
      errValue: err.field,
    );
  }

  /// Materializa (uma vez) a `class ItaPanic { final String message; … }` com um
  /// `toString()` que devolve `panic: <msg>` — é o `toString` que a VM chama ao
  /// imprimir a exceção não-capturada, e sem ele o stderr traria
  /// `Instance of 'ItaPanic'` em vez da mensagem que o dev escreveu.
  ///
  /// ⚠️ O `toString` é `StringConcatenation` de partes **já-String**, não um
  /// `DynamicInvocation('toString')` como o oracle faz (`codegen.dart:1168`):
  /// aquele nó é exatamente o que o ADR-0013 proíbe, e o invariante do runner o
  /// pegaria. Portar a LIÇÃO, não o estilo.
  k.Constructor _panicCtor() {
    final existing = _panicConstructor;
    if (existing != null) return existing;

    final stringType = _emitType(const StringType(), check.program);
    final cls = k.Class(
      name: 'ItaPanic',
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    );
    final field = k.Field.immutable(
      k.Name('message'),
      type: stringType,
      fileUri: fileUri,
    );
    cls.addField(field);

    final param = k.VariableDeclaration('message', type: stringType);
    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        positionalParameters: [param],
        returnType: const k.VoidType(),
      ),
      name: k.Name(''),
      initializers: [k.FieldInitializer(field, k.VariableGet(param))],
      fileUri: fileUri,
    );
    cls.addConstructor(ctor);

    cls.addProcedure(
      k.Procedure(
        k.Name('toString'),
        k.ProcedureKind.Method,
        k.FunctionNode(
          k.ReturnStatement(
            k.StringConcatenation([
              k.StringLiteral('panic: '),
              k.InstanceGet(
                k.InstanceAccessKind.Instance,
                k.ThisExpression(),
                k.Name('message'),
                interfaceTarget: field,
                resultType: stringType,
              ),
            ]),
          ),
          returnType: stringType,
        ),
        isStatic: false,
        fileUri: fileUri,
      ),
    );

    _panicClass = cls;
    return _panicConstructor = ctor;
  }

  /// Unário: `-x` e `!b`.
  ///
  /// ⚠️ **O `-` unário NÃO é o `-` binário.** No Kernel o nome do operador é
  /// `unary-` (`names.dart:55`), justamente para não colidir com a subtração —
  /// e é o ÚNICO aritmético que `int` sobrescreve em vez de herdar de `num`
  /// (`int.dart:311`). Resolvê-lo pela tabela dos binários daria o alvo errado.
  ///
  /// `!b` → `Not`, o mesmo nó que o `!=` usa por baixo.
  k.Expression _unary(ast.Unary u) {
    final operand = _expr(u.operand);
    switch (u.op) {
      case ast.UnaryOp.not:
        return k.Not(operand)..fileOffset = u.offset;
      case ast.UnaryOp.neg:
        final type = check.exprTypes[u.operand];
        if (type is! IntType && type is! FloatType) {
          _ice('neg-on-${type.runtimeType}', u);
        }
        final op = negOp;
        // Mesmo defeito e mesma cura do `_numOp`: `negOp` é o `unary-` de `num`
        // (`num.dart:190`), que devolve `num` na assinatura — e `int` tem
        // override próprio (`int.dart:311`) que este caminho não usa. O tipo
        // provado pela F5 é a fonte (R4).
        return k.InstanceInvocation(
          k.InstanceAccessKind.Instance,
          operand,
          op.name,
          k.Arguments([]),
          interfaceTarget: op,
          functionType: _especializa(
            op.function.computeFunctionType(k.Nullability.nonNullable),
            check.exprTypes[u],
            u,
          ),
        )..fileOffset = u.offset;
    }
  }

  /// `match` sobre **`Option`/`T?`** → nós PRIMITIVOS (§7.4-e).
  ///
  /// ⚠️ **TRAVA DURA:** os pattern-nodes do Dart 3 (`IfCaseStatement`,
  /// `PatternSwitchStatement`, `PatternVariableDeclaration`) são **CFE-internos e
  /// PROIBIDOS** no `.dill` cru — a VM os trata na mesma cláusula do
  /// `ForInStatement` no `kernel_binary_flowgraph.cc` (*"removed by the constant
  /// evaluator"* → `UNREACHABLE()`). Logo o `match` baixa para
  /// `EqualsNull`/`Not`/`ConditionalExpression`/`Let`, e nada mais.
  ///
  /// **RD-1 decide a forma:** `MatchExpr` é EXPRESSÃO (todo braço é `=> expr`, e
  /// só a seta rende) ⟹ **right-fold de `ConditionalExpression`**. A forma-bloco
  /// (cadeia de `IfStatement` com o subject em block-var, não `Let` — regra
  /// dart2js do ADR-0005) é do `match`-statement, que não existe na AST.
  ///
  /// **O subject é avaliado UMA vez.** Ele entra num `Let` antes do fold: sem
  /// isso, `match f() { … }` chamaria `f()` uma vez por teste de braço — efeito
  /// colateral duplicado, e nenhum golden de valor puro perceberia.
  ///
  /// **O ÚLTIMO braço não ganha teste** — vira o `otherwise` do fold. É sound
  /// porque a **F6 já provou exaustividade** (Maranget, spec 014 §4); a §7.4-e é
  /// explícita: *"exaustividade e unreachable são F6 — a F7 confia"*. Sem essa
  /// garantia haveria de sobrar um `throw` de fim-de-cadeia.
  ///
  /// **Família `Option`/`T?`** (a desta fatia): `.none` → `EqualsNull(subject)`;
  /// `.some(x)` → `Not(EqualsNull(subject))` com `x` ligado ao subject. Custo
  /// zero — nenhuma classe `Option` participa (CA10).
  ///
  /// O bind precisa do **`as`**: `x: T` é non-nullable (ADR-0013) e o subject é
  /// `T?`. O Kernel cru **não tem flow-promotion** — o que o Dart faria por
  /// análise, aqui é um nó explícito.
  k.Expression _matchExpr(ast.MatchExpr n) {
    final subjectType = check.exprTypes[n.scrutinee];
    // Famílias com gabarito HOJE: `Option`/`T?` e ESCALAR (Int/Float/String/Bool,
    // incluindo `range` sobre Int). Enum-com-payload, produto (`struct`/record) e
    // `List` (gated pela 012) têm gabarito PRÓPRIO na §7.4-e — cada uma é fatia.
    final isOption = subjectType is OptionalType;
    final isEnum = subjectType is NamedType;
    final isResult =
        subjectType is BuiltinType && subjectType.kind == BuiltinKind.result;
    final isScalar = subjectType is IntType ||
        subjectType is FloatType ||
        subjectType is StringType ||
        subjectType is BoolType;
    if (!isOption && !isScalar && !isEnum && !isResult) {
      _ice('match-on-${subjectType.runtimeType}', n);
    }
    final staticType = check.exprTypes[n];
    if (staticType == null) _ice('match-untyped', n);
    if (n.arms.isEmpty) _ice('match-no-arms', n); // F6 não deixa passar

    // `subjectType` é non-null a partir daqui: os dois testes acima já o
    // exigiram, e o `_ice` é `Never` — mas a promoção não alcança por serem
    // booleanos intermediários, então o nome local a fixa.
    final scrutType = subjectType!;
    // Só a família `Option` desembrulha; escalar liga o subject inteiro.
    final innerType = isOption
        ? _emitType((scrutType as OptionalType).inner, n)
        : _emitType(scrutType, n);
    final subject = k.VariableDeclaration(
      '#subject',
      initializer: _expr(n.scrutinee),
      type: _emitType(scrutType, n),
      isFinal: true,
    )..fileOffset = n.scrutinee.offset;

    // Right-fold: o último braço é o `otherwise`, os demais viram testes.
    k.Expression result = _armBody(n.arms.last, subject, innerType, scrutType);
    for (var i = n.arms.length - 2; i >= 0; i--) {
      final arm = n.arms[i];
      result = k.ConditionalExpression(
        _armTest(arm, subject, scrutType),
        _armBody(arm, subject, innerType, scrutType),
        result,
        _emitType(staticType, n),
      )..fileOffset = arm.body.offset;
    }
    return k.Let(subject, result)..fileOffset = n.offset;
  }

  /// O TESTE de um braço, por FAMÍLIA de pattern (§7.4-e):
  ///
  ///   - `.none`/`.some(_)` (Option) ⟹ `subject == null` / `!= null`;
  ///   - **literal escalar** ⟹ `EqualsCall(subject, literal)` — o mesmo nó
  ///     ESPECIAL que o `==` binário usa, com `interfaceTarget` pelo tipo;
  ///   - **range** (Int) ⟹ `subject >= lo && subject <(=) hi`, dois
  ///     `InstanceInvocation` de `num` sob um `LogicalExpression`;
  ///   - `_`/binder puro ⟹ casa sempre.
  k.Expression _armTest(
    ast.MatchArm arm,
    k.VariableDeclaration subject,
    Type subjectType,
  ) {
    if (arm.guard != null) _ice('match-guard', arm.pattern); // fatia própria
    final pattern = arm.pattern;
    switch (pattern) {
      case ast.EnumPattern p:
        // `Result` → teste de CLASSE contra a subclasse de runtime.
        if (subjectType is BuiltinType &&
            subjectType.kind == BuiltinKind.result) {
          final rt = _resultRuntime();
          final cls = switch (p.variant) {
            'ok' => rt.okCtor.enclosingClass,
            'err' => rt.errCtor.enclosingClass,
            // `-test-`: este é o sítio do TESTE de classe. O bind do payload
            // recusa a mesma variante desconhecida em `_armBody`, com o código
            // `result-pattern-bind-` — dois trabalhos distintos, e o `.variant`
            // vem do mesmo domínio nos dois, então um código só colidiria de
            // fato (R13).
            _ => _ice('result-pattern-test-${p.variant}', p),
          };
          return k.IsExpression(
            k.VariableGet(subject),
            k.InterfaceType(cls, k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }
        // `Option` → nulidade nativa. **Guardado pelo TIPO**, e é o guard que
        // faz a regra estar certa: até 2026-07-29 estas duas linhas testavam só
        // o LEXEMA, antes de olhar o subject, e `enum Estado { none, ativo }`
        // compilava `e == null` — sempre falso, em SILÊNCIO, porque o golden
        // imprime o braço seguinte sem reclamar de nada (CLAUDE.md R1).
        if (subjectType is OptionalType) {
          final isNull = k.EqualsNull(k.VariableGet(subject))
            ..fileOffset = p.offset;
          if (p.variant == 'none') return isNull;
          if (p.variant == 'some') return k.Not(isNull)..fileOffset = p.offset;
          _ice('option-pattern-${p.variant}', p);
        }
        // Variante de enum DO USUÁRIO **sem payload** → compara com a CONSTANTE
        // (identidade): cada variante é um objeto único, então `Object::==`
        // decide sem tag nem `IsExpression`. Com payload seria classe selada +
        // `IsExpression` — mas a F5 ainda não constrói uma (ver [_enum]).
        if (subjectType is NamedType) {
          // Enum SELADO → teste de CLASSE. `IsExpression` é o gabarito da
          // §7.4-e para sum type, e vale igual para variante com e sem payload
          // (o singleton existe por economia, não para o teste).
          final v = _variants[subjectType.decl]?[p.variant];
          if (v != null) {
            return k.IsExpression(
              k.VariableGet(subject),
              k.InterfaceType(v.cls, k.Nullability.nonNullable),
            )..fileOffset = p.offset;
          }
          // `-variant-`: a variante do enum do usuário traz payload e não é
          // selada. O sítio de `_armBody` que recusa sub-pattern ANINHADO é
          // outra fatia (`match-payload-nested-`).
          if (p.subpatterns.isNotEmpty) {
            _ice('match-payload-variant-${p.variant}', p);
          }
          final field = _fields[subjectType.decl]?[p.variant];
          if (field == null) _ice('match-unknown-variant-${p.variant}', p);
          final eq = equalsOps[const BoolType()]!; // `Object::==` — o de identidade
          return k.EqualsCall(
            k.VariableGet(subject),
            k.StaticGet(field),
            functionType:
                eq.function.computeFunctionType(k.Nullability.nonNullable),
            interfaceTarget: eq,
          )..fileOffset = p.offset;
        }
        _ice('match-variant-${p.variant}', p);

      case ast.LiteralPattern p:
        // O literal e o subject têm o MESMO tipo (a F5 cobra
        // `pattern-type-mismatch`), então o alvo do `==` sai do tipo do subject.
        final op = equalsOps[subjectType];
        if (op == null) _ice('match-eq-on-${subjectType.runtimeType}', p);
        return k.EqualsCall(
          k.VariableGet(subject),
          _expr(p.literal),
          functionType:
              op.function.computeFunctionType(k.Nullability.nonNullable),
          interfaceTarget: op,
        )..fileOffset = p.offset;

      case ast.RangePattern p:
        // A F5 já garantiu Int nos três (`_checkRangePattern`), e o parser já
        // garantiu que os endpoints são LITERAIS — não há expressão a avaliar
        // duas vezes aqui.
        if (subjectType is! IntType) _ice('match-range-on-${subjectType.runtimeType}', p);
        k.Expression cmp(ast.BinaryOp op, ast.Expr bound) {
          final proc = cmpOps[op]!;
          return k.InstanceInvocation(
            k.InstanceAccessKind.Instance,
            k.VariableGet(subject),
            proc.name,
            k.Arguments([_expr(bound)]),
            interfaceTarget: proc,
            functionType:
                proc.function.computeFunctionType(k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }

        // `1..10` é EXCLUSIVO no fim; `1..=10` inclui. O parser distingue pelo
        // token (`..` × `..=`), e trocar os dois aqui seria um off-by-one que
        // roda liso e erra na borda — exatamente o que o golden pega.
        return k.LogicalExpression(
          cmp(ast.BinaryOp.ge, p.start),
          k.LogicalExpressionOperator.AND,
          cmp(p.inclusive ? ast.BinaryOp.le : ast.BinaryOp.lt, p.end),
        )..fileOffset = p.offset;

      case ast.StructPattern p:
        // **PRODUTO** (§7.4-e): o subject JÁ é do tipo — não há variante a
        // testar, então o pattern não faz teste de CLASSE. Ele testa só os
        // campos que trazem um sub-pattern com teste (literal, range), e a
        // conjunção deles é o teste do braço. `Ponto { x: a, y: b }` (só binds)
        // casa SEMPRE ⟹ `true`, e a F6 é quem garante que isso não deixa braço
        // seguinte inalcançável.
        if (subjectType is! NamedType) {
          _ice('match-struct-on-${subjectType.runtimeType}', p);
        }
        final byName = _fields[subjectType.decl];
        if (byName == null) _ice('match-struct-unemitted', p);
        k.Expression? test;
        for (final f in p.fields) {
          final sub = f.pattern;
          if (sub == null) {
            // `Ponto { x }` — shorthand. A F4 o declara incapaz (débito D4), e
            // ele nem chega aqui em programa verde; o ICE é rede.
            _ice('match-struct-shorthand-${f.name}', p);
          }
          if (sub is ast.BindPattern || sub is ast.WildcardPattern) continue;
          final field = byName[f.name];
          if (field == null) _ice('match-struct-field-${f.name}', p);
          final one = _fieldTest(subject, field, sub);
          test = test == null
              ? one
              : (k.LogicalExpression(
                  test,
                  k.LogicalExpressionOperator.AND,
                  one,
                )..fileOffset = p.offset);
        }
        return test ?? k.BoolLiteral(true);

      // `_` e binder puro casam qualquer coisa — só chegam como último braço em
      // programa F6-verde (senão os seguintes seriam unreachable), mas o teste
      // honesto é `true`, não uma suposição.
      case ast.WildcardPattern _:
      case ast.BindPattern _:
        return k.BoolLiteral(true);

      default:
        _ice('match-pattern-${pattern.runtimeType}', pattern);
    }
  }

  /// Os campos emitidos do tipo do ESCRUTÍNIO, para um `StructPattern`.
  ///
  /// ⚠️ **Resolve pela DECL do subject, nunca pelo `p.typeName`.** Até
  /// 2026-07-29 esta função varria `_classes` inteira comparando strings, com
  /// esta justificativa escrita ao lado: *"resolver por nome é seguro porque a
  /// F5 já cobrou que o pattern casa com o tipo do escrutínio
  /// (`pattern-type-mismatch`)"*.
  ///
  /// **A garantia não existe.** A F5 roteia `StructPattern` para
  /// `_bindFieldPatterns(n.fields, t, n)` e **nunca lê `typeName`** — o campo
  /// está anotado como IGNORADO na própria memória da F6. Consequência:
  /// `match p { Caixa { x: a } }` sobre um `Ponto` emitia `InstanceGet` com
  /// `interfaceTarget` de `Caixa.x`. Passa no `verifyComponent` (ele só confere
  /// `name == interfaceTarget.name`, `isInstanceMember` e `enclosingClass !=
  /// null`), passa no LOAD, e **roda certo no JIT**, porque o dispatch é por
  /// selector via inline cache. Quebra em AOT, onde a TFA poda pelo cone da
  /// classe do interface target — e a interseção do cone de `Ponto` com o de
  /// `Caixa` é vazia.
  ///
  /// O tipo do subject é dado da F5 (nº1) e chega aqui por parâmetro. Usá-lo é
  /// a regra: a F7 traduz, não redecide (CLAUDE.md R1).
  ///
  /// O `typeName` do pattern deixa de ter papel na emissão. Cobrá-lo contra o
  /// subject é diagnóstico de USUÁRIO, e portanto da F5 — enquanto ela não o
  /// lê, o mismatch é aceito em silêncio pelas duas fases, e isso está na fila
  /// de pendências, não escondido aqui.
  Map<String, k.Field>? _structFieldsFor(Type subjectType) {
    if (subjectType is! NamedType) return null;
    return _fields[subjectType.decl];
  }

  /// O teste de UM campo de `struct` em pattern: o valor do campo contra o
  /// sub-pattern. Reusa os mesmos gabaritos das famílias escalares — literal vira
  /// `EqualsCall`, range vira `>=` && `<(=)` — só que o receptor é
  /// `subject.campo` em vez do subject.
  k.Expression _fieldTest(
    k.VariableDeclaration subject,
    k.Field field,
    ast.Pattern sub,
  ) {
    // ⚠️ **Uma leitura NOVA por uso.** No Kernel cada nó tem UM pai; reusar a
    // mesma instância em dois lugares (o `>=` e o `<` de um range) monta uma
    // árvore com dois pais para o mesmo filho, e o `verifyComponent` reprova com
    // *"Incorrect parent pointer"*. Foi assim que este bug apareceu — o gate
    // CA12 o pegou antes de qualquer execução.
    k.Expression read() => k.InstanceGet(
          k.InstanceAccessKind.Instance,
          k.VariableGet(subject),
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = sub.offset;

    switch (sub) {
      case ast.LiteralPattern p:
        // O alvo do `==` sai do tipo do CAMPO — não do subject, que é o struct.
        final op = _equalsForKernelType(field.type);
        if (op == null) _ice('match-field-eq-${field.name.text}', p);
        return k.EqualsCall(
          read(),
          _expr(p.literal),
          functionType:
              op.function.computeFunctionType(k.Nullability.nonNullable),
          interfaceTarget: op,
        )..fileOffset = p.offset;

      case ast.RangePattern p:
        k.Expression cmp(ast.BinaryOp op, ast.Expr bound) {
          final proc = cmpOps[op]!;
          return k.InstanceInvocation(
            k.InstanceAccessKind.Instance,
            read(),
            proc.name,
            k.Arguments([_expr(bound)]),
            interfaceTarget: proc,
            functionType:
                proc.function.computeFunctionType(k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }

        return k.LogicalExpression(
          cmp(ast.BinaryOp.ge, p.start),
          k.LogicalExpressionOperator.AND,
          cmp(p.inclusive ? ast.BinaryOp.le : ast.BinaryOp.lt, p.end),
        )..fileOffset = p.offset;

      default:
        // Pattern ANINHADO (`Ret { origem: Ponto { x: 0 } }`) é fatia própria:
        // exigiria compor testes sobre um receptor que já é um `InstanceGet`.
        _ice('match-field-${sub.runtimeType}', sub);
    }
  }

  /// O `operator ==` para um tipo já-Kernel (o do campo). Espelha a [equalsOps],
  /// que é keyed pelos `Type` da F5 — aqui só temos o `DartType`.
  k.Procedure? _equalsForKernelType(k.DartType type) {
    if (type is! k.InterfaceType) return null;
    return switch (type.classNode.name) {
      'int' || 'double' => equalsOps[const IntType()],
      'String' => equalsOps[const StringType()],
      'bool' => equalsOps[const BoolType()],
      _ => null,
    };
  }

  /// O CORPO de um braço, com o bind do payload quando houver.
  ///
  /// `.some(x)` liga `x` ao subject **desembrulhado** (`as T`); `.none` e `_`
  /// não ligam nada. Um `BindPattern` no topo (`match x { y => … }`) liga o
  /// subject inteiro, ainda opcional.
  k.Expression _armBody(
    ast.MatchArm arm,
    k.VariableDeclaration subject,
    k.DartType innerType,
    Type subjectType,
  ) {
    final pattern = arm.pattern;
    // **PRODUTO**: cada campo com bind vira `InstanceGet` direto do subject —
    // sem `as`, porque não houve estreitamento: o subject já É do tipo.
    if (pattern is ast.StructPattern) {
      final byName = _structFieldsFor(subjectType);
      if (byName == null) _ice('match-struct-body-unemitted', pattern);
      // Declarar ANTES de emitir o corpo (a lição do enum-com-payload: emitir
      // primeiro deixa todo uso em `ident-unbound`).
      final binds = <k.VariableDeclaration>[];
      for (final f in pattern.fields) {
        final sub = f.pattern;
        if (sub is! ast.BindPattern) continue; // literal/range: só testam
        final field = byName[f.name];
        if (field == null) _ice('match-struct-bind-${f.name}', pattern);
        final bind = k.VariableDeclaration(
          sub.name,
          initializer: k.InstanceGet(
            k.InstanceAccessKind.Instance,
            k.VariableGet(subject),
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          type: field.type,
          isFinal: true,
        )..fileOffset = sub.offset;
        _kernelDecls[sub] = bind;
        binds.add(bind);
      }
      k.Expression body = _expr(arm.body);
      for (var i = binds.length - 1; i >= 0; i--) {
        body = k.Let(binds[i], body)..fileOffset = binds[i].fileOffset;
      }
      return body;
    }
    // `Result`: `.ok(v)`/`.err(e)` ligam o payload lido da subclasse de runtime.
    //
    // ⚠️ **O guard é o TIPO do subject, não o lexema + uma flag global.** Até
    // 2026-07-29 a condição era `variant == 'ok' || variant == 'err'` mais
    // `_resultParts != null` — e `_resultParts` é cache do PROGRAMA INTEIRO,
    // materializado por qualquer `Result` em qualquer lugar. O efeito:
    // `enum Resposta { ok, falha }` compilava DIFERENTE conforme outra função,
    // não relacionada, mencionasse `Result` — emitia `as ItaResult$ok` sobre um
    // `Resposta`. A emissão de uma declaração dependendo de outra é a marca da
    // redecisão com chave fraca (CLAUDE.md R1).
    if (pattern is ast.EnumPattern &&
        subjectType is BuiltinType &&
        subjectType.kind == BuiltinKind.result) {
      if (pattern.variant != 'ok' && pattern.variant != 'err') {
        _ice('result-pattern-bind-${pattern.variant}', pattern);
      }
      final rt = _resultRuntime();
      final isOk = pattern.variant == 'ok';
      final field = isOk ? rt.okValue : rt.errValue;
      final cls = (isOk ? rt.okCtor : rt.errCtor).enclosingClass;
      if (pattern.subpatterns.length != 1) _ice('result-pattern-arity', pattern);
      final sub = pattern.subpatterns.single;
      if (sub is ast.WildcardPattern) return _expr(arm.body);
      if (sub is! ast.BindPattern) {
        _ice('result-payload-${sub.runtimeType}', sub);
      }
      // O tipo do binder vem da nº6 (a F5 o computou de `Result<T,E>`); o campo
      // é `Object`, então o `as` o estreita para o que a F5 provou.
      final bindType = check.binderTypes[sub];
      if (bindType == null) _ice('result-bind-untyped', sub);
      final bind = k.VariableDeclaration(
        sub.name,
        initializer: k.AsExpression(
          k.InstanceGet(
            k.InstanceAccessKind.Instance,
            k.AsExpression(
              k.VariableGet(subject),
              k.InterfaceType(cls, k.Nullability.nonNullable),
            )..fileOffset = sub.offset,
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          _emitType(bindType, sub),
        )..fileOffset = sub.offset,
        type: _emitType(bindType, sub),
        isFinal: true,
      )..fileOffset = sub.offset;
      _kernelDecls[sub] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    // Enum SELADO com payload: `.circulo(r)` liga `r` ao campo, lido do subject
    // já ESTREITADO por `as`. O `as` é necessário porque o Kernel cru não tem
    // flow-promotion — o `is` do teste não estreita o tipo estático aqui.
    if (pattern is ast.EnumPattern && _sealedOf(pattern, subjectType) != null) {
      final v = _sealedOf(pattern, subjectType)!;
      final payload = v.fields.keys.toList();
      if (pattern.subpatterns.length > payload.length) {
        _ice('match-payload-arity-${pattern.variant}', pattern);
      }
      // ⚠️ **Os binds são DECLARADOS antes de o corpo ser emitido.** Emitir
      // primeiro (o que eu fiz na primeira versão) faz todo uso do binder cair
      // em `ice-codegen-ident-unbound`: o `_ident` consulta `_kernelDecls`, e o
      // registro ainda não existia. Mesma disciplina do `_let`, ao contrário —
      // lá o initializer vem antes DE PROPÓSITO (`let x = x` tem de falhar);
      // aqui o payload não pode se referenciar, então declarar primeiro é seguro.
      final binds = <k.VariableDeclaration>[];
      for (var i = 0; i < pattern.subpatterns.length; i++) {
        final sub = pattern.subpatterns[i];
        if (sub is ast.WildcardPattern) continue;
        if (sub is! ast.BindPattern) {
          // aninhado: fatia própria
          _ice('match-payload-nested-${sub.runtimeType}', sub);
        }
        final field = v.fields[payload[i]]!;
        final bind = k.VariableDeclaration(
          sub.name,
          initializer: k.InstanceGet(
            k.InstanceAccessKind.Instance,
            // O `as` é necessário: o Kernel cru não tem flow-promotion, então o
            // `is` do teste não estreitou o tipo estático do subject.
            k.AsExpression(
              k.VariableGet(subject),
              k.InterfaceType(v.cls, k.Nullability.nonNullable),
            )..fileOffset = sub.offset,
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          type: field.type,
          isFinal: true,
        )..fileOffset = sub.offset;
        _kernelDecls[sub] = bind;
        binds.add(bind);
      }
      k.Expression body = _expr(arm.body);
      // De trás para frente: cada bind embrulha o corpo num `Let`.
      for (var i = binds.length - 1; i >= 0; i--) {
        body = k.Let(binds[i], body)..fileOffset = binds[i].fileOffset;
      }
      return body;
    }
    // `.some(x)` liga o subject DESEMBRULHADO — e só existe sob `Option`.
    // O guard de tipo é o mesmo da correção do `_armTest`: sem ele, uma
    // variante do usuário chamada `some` cairia aqui.
    if (pattern is ast.EnumPattern &&
        pattern.variant == 'some' &&
        subjectType is OptionalType) {
      if (pattern.subpatterns.length != 1) _ice('match-some-arity', pattern);
      final sub = pattern.subpatterns.single;
      if (sub is ast.WildcardPattern) return _expr(arm.body); // `.some(_)`
      if (sub is! ast.BindPattern) {
        _ice('match-some-${sub.runtimeType}', sub); // aninhado: fatia própria
      }
      final bind = k.VariableDeclaration(
        sub.name,
        // O `as` é o que o Kernel cru exige — não há flow-promotion aqui.
        initializer: k.AsExpression(k.VariableGet(subject), innerType)
          ..fileOffset = sub.offset,
        type: innerType,
        isFinal: true,
      )..fileOffset = sub.offset;
      _kernelDecls[sub] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    if (pattern is ast.BindPattern) {
      final bind = k.VariableDeclaration(
        pattern.name,
        initializer: k.VariableGet(subject),
        type: subject.type,
        isFinal: true,
      )..fileOffset = pattern.offset;
      _kernelDecls[pattern] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    return _expr(arm.body); // `.none`, `_`
  }

  /// `v.metodo(args)` → `InstanceInvocation` (§7.4-d, **CA4**).
  ///
  /// O `interfaceTarget` sai do TIPO ESTÁTICO do receptor, que é o que a nº3
  /// (`resolvedMembers.ownerType`) guarda:
  ///
  ///   - receptor `any Fala` ⟹ o procedure ABSTRATO do trait. A VM resolve por
  ///     **vtable** (Grupo B) — dois conformers distintos numa lista heterogênea
  ///     respondem cada um o seu, sem tabela nossa;
  ///   - receptor concreto (`Pato`) ⟹ o procedure da própria classe.
  ///
  /// A escolha entre os dois **não é nossa**: é o tipo estático que decide, e a
  /// F5 já o computou. Apontar sempre o concreto quebraria o existencial;
  /// apontar sempre o abstrato pagaria dispatch onde não precisa.
  k.Expression _methodCall(ast.Call c, ast.Member callee) {
    final resolved = check.resolvedMembers[callee];
    if (resolved == null) _ice('method-unresolved', c);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('method-on-${owner.runtimeType}', c);
    final proc =
        _methods[owner.decl]?[callee.name] ?? _traitMembers[owner.decl]?[callee.name];
    if (proc == null) _ice('method-unemitted-${callee.name}', c);

    final call = check.resolvedCalls[c];
    if (call == null) _ice('method-call-unresolved', c);
    // ⚠️ **Os nomes dos named-args saem do procedure do TIPO ESTÁTICO** — que,
    // sob `any Trait`, é o REQUISITO ABSTRATO, não o método do conformer. Isso
    // só é são porque as duas fases derivam o nome da MESMA expressão:
    //
    //   F5 `collect.dart:645`  →  `label: p.label ?? p.name`  (o que
    //                              `_sameParamDecls` compara em conformance)
    //   F7 `_fnSignature`      →  `p.label ?? p.name`         (o nome Kernel)
    //
    // Divergiu ⟹ a F5 acusa `trait-member-signature-mismatch` e a F7 nem roda.
    // O acoplamento **não está em spec nenhuma**; quem o segura é o
    // `conformer_label.tu`, que usa labels iguais com nomes internos diferentes
    // — o caso que prova que a ponte é o label. Mexeu num lado, leia o outro.
    final params = proc.function.namedParameters;
    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = call.slot[i];
      if (pi < 0 || pi >= params.length) _ice('method-slot-range', c);
      named.add(k.NamedExpression(params[pi].name!, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }

    return k.InstanceInvocation(
      k.InstanceAccessKind.Instance,
      _expr(callee.receiver),
      proc.name,
      k.Arguments([], named: named),
      interfaceTarget: proc,
      functionType: proc.function.computeFunctionType(k.Nullability.nonNullable),
    )..fileOffset = callee.opOffset;
  }

  /// Args do `init` EXPLÍCITO de uma `class` → named, pelos params do `init`.
  ///
  /// Difere do [_initArgs] do `struct` num ponto que é o próprio ADR-0012 §A-1:
  /// lá os "params" são os CAMPOS (memberwise sintetizado); aqui são os params
  /// que o usuário escreveu no `init` — que podem não ter relação 1:1 com os
  /// campos. `Conta(inicial: 100)` inicializa `saldo` e `ativa`.
  k.Arguments _classInitArgs(ast.Call c, ast.ClassDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('class-init-unresolved', c);
    // O escolhido pela F5 primeiro; sem ele, o do corpo — que é o primário e o
    // único que a `class` tinha antes do CA3.
    final init = call.initTarget ??
        decl.members.whereType<ast.InitDecl>().firstOrNull;
    if (init == null) _ice('class-init-missing', c);
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('class-init-slot-arity', c);
    return _argsDeInit(c, init, slot);
  }

  /// Args contra os params de um `init` **explícito** (corpo ou `extension`).
  ///
  /// O `slot` da nº5 indexa `init.params`, e o nome que vai no `NamedExpression`
  /// é o LABEL — o mesmo que o `_initCtor` deu ao `VariableDeclaration`. Se as
  /// duas pontas discordassem, o Kernel não reclamaria: `Arguments.named` casa
  /// por nome e um named que não existe no alvo passa pelo verify.
  /// ⚠️ **Um sítio, um código.** Este caminho serve `struct` e `class`, e o
  /// `_ice` abaixo é literal de propósito: interpolar o kind (`'$kind-init-…'`)
  /// esconde o código da régua da R13, que passa a ver os dois caminhos como um
  /// — foi o que o `make assertions` acusou quando esta função nasceu.
  k.Arguments _argsDeInit(ast.Call c, ast.InitDecl init, List<int> slot) {
    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = slot[i];
      if (pi < 0 || pi >= init.params.length) _ice('init-explicito-slot-range', c);
      final p = init.params[pi];
      named.add(k.NamedExpression(p.label ?? p.name, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    return k.Arguments([], named: named);
  }

  /// `p.x` → `InstanceGet` do getter do campo (§7.4-c).
  ///
  /// O `interfaceTarget` é o próprio `k.Field` — a nº3 (`resolvedMembers`) diz
  /// QUAL decl o membro é, e o `origin` diria quem o contribuiu (inline,
  /// `extension`, `impl`). Campo é sempre `ownDecl` por construção — `extension`
  /// não adiciona armazenamento —, então aqui basta a decl do receptor.
  ///
  /// Só campo de `struct`: método (`p.metodo()`) e `class` são fatias próprias →
  /// ICE honesto. O membro do CHÃO (`.length` de List/Map/String) é desviado
  /// antes, para [_groundLength].
  k.Expression _member(ast.Member m) {
    // **O chão vem ANTES da nº3, e não por precedência: a F5 NÃO POPULA a nº3
    // para ele.** `check.dart:2411-2412`, verbatim:
    //
    //     final ground = _groundField(recv, n.name);
    //     if (ground != null) return ground;
    //
    // — devolve o tipo e RETORNA, sem chegar ao `_lookup` que grava
    // `resolvedMembers[n] = r` (`:2437`). Por construção: `_lookup` só sabe de
    // `NamedType`, e `List`/`Map`/`String` são `BuiltinType`/`StringType`.
    //
    // Consultar a nº3 primeiro, como este método fazia até 2026-08-31, dava
    // `null` → `ice-codegen-member-unresolved`, que MENTE duas vezes: nomeia
    // estado do emissor (a R7 proíbe até pendurar catraca nele) e diz "não
    // resolveu" sobre um acesso que a F5 resolveu — por outra tabela.
    final shape = _shapeOf(check.exprTypes[m.receiver]);
    if (shape != null) {
      final getter = ground.length[shape]!;
      // O lexema comparado é o do membro da PLATAFORMA, não um literal solto: é
      // a exceção fechada da R1 (vocabulário externo ao programa do usuário), e
      // o tipo já guardou antes — o `shape` decide, o nome só refina.
      if (m.name == getter.name.text) return _groundLength(m, shape, getter);
      // Fronteira INALCANÇÁVEL hoje, e a razão é ORDEM (R10), não impedimento: a
      // F5 já reprova membro fora da tabela fechada do chão com `unknown-member`
      // (`check.dart:2428-2432`; CA5 da spec 012 §11, fixture
      // `conformance/check/`), então nada com receptor-chão e nome≠`length`
      // chega aqui. Vira alcançável quando o chão ganhar um segundo membro — e a
      // catraca nasce NESSA fatia.
      _ice('ground-member-${m.name}', m);
    }
    final resolved = check.resolvedMembers[m];
    if (resolved == null) _ice('member-unresolved', m);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('member-on-${owner.runtimeType}', m);
    final field = _fields[owner.decl]?[m.name];
    if (field == null) _ice('member-nonfield-${m.name}', m); // método/estático
    return k.InstanceGet(
      k.InstanceAccessKind.Instance,
      _expr(m.receiver),
      _memberName(m.name),
      interfaceTarget: field,
      resultType: _emitType(resolved.type, m),
    )..fileOffset = m.opOffset;
  }

  // ==========================================================================
  // O CHÃO (spec 012) — `.length` / `[]` / `+` de `List`/`Map`/`String`
  // ==========================================================================

  /// A FORMA do chão de um tipo **provado pela F5** (side-table nº1), ou `null`.
  ///
  /// Espelha o `_groundShape` dela (`check.dart:2336-2345`) e é a chave de tudo
  /// que vem abaixo. Chave é o TIPO, nunca o lexema do receptor — é a R1: a F7
  /// não redecide o que é uma `List`, ela traduz o que a F5 provou.
  _GroundShape? _shapeOf(Type? t) => switch (t) {
        BuiltinType(kind: BuiltinKind.list) => _GroundShape.list,
        BuiltinType(kind: BuiltinKind.map) => _GroundShape.map,
        StringType() => _GroundShape.string,
        _ => null,
      };

  /// O receptor de um acesso ao chão: a expressão emitida **uma vez** + a
  /// substituição que instancia os membros genéricos de `dart:core`.
  ///
  /// ⚠️ **É aqui que mora a diferença entre funcionar e passar no verify.** Os
  /// membros são declarados em `List<E>`/`Map<K,V>`, e emitir o `functionType`
  /// como vem produz DOIS `problem`s no `verifyComponent` —
  /// *"Type parameter 'E' referenced out of scope"* + *"referenced from static
  /// context"* (`verifier.dart:1495-1511`) — mais o
  /// `assert(functionType.typeParameters.isEmpty)` de `expressions.dart:1912`.
  /// A doc dos próprios campos é normativa e verbatim: `resultType` *"includes
  /// substituted type parameters from the static receiver type"*
  /// (`expressions.dart:558-571`); `functionType` *"includes substituted type
  /// parameters from the static receiver type and generic type arguments"*
  /// (`:1869-1883`).
  ///
  /// O `_especializa` dos aritméticos **não serve aqui**: ele troca só o
  /// `returnType`, e `List<E>::+` tem `E` no PARÂMETRO. Substituição inteira.
  ///
  /// A nulidade combina sozinha: `visitTypeParameterType` faz
  /// `withDeclaredNullability(combineNullabilitiesForSubstitution(...))`
  /// (`type_algebra.dart:1076-1088`), então `Map<K,V>::[]`, que devolve `V?`,
  /// vira `int?` com `V := int` — literalmente o `T?` do Itá, o CA10.
  ///
  /// `_expr(recv)` roda **uma vez** (R3): o resultado é o campo `expr` do record,
  /// e cada chamador o usa uma só vez na árvore que monta.
  ({k.Expression expr, Substitution sub}) _groundReceiver(
    ast.Expr recv,
    _GroundShape shape,
    ast.AstNode span,
  ) {
    final tipo = check.exprTypes[recv];
    // Pré-condição da porta (R11): o chamador já chamou `_shapeOf` sobre o mesmo
    // tipo, então isto só falha se a nº1 mudar entre as duas leituras — bug
    // nosso, não input ruim.
    if (tipo == null) _ice('ground-receiver-untyped-${shape.name}', span);
    final iface = _emitType(tipo, span);
    if (iface is! k.InterfaceType) _ice('ground-receiver-nonclass', span);
    // Os dois `_ice` acima, e os quatro de [_listExpr]/[_mapExpr], nomeiam
    // ESTADO DO EMISSOR — e por isso ficam **deliberadamente sem catraca**: a
    // R7 recusa fixture que *espere* um defeito nosso, e alcançá-los exigiria
    // uma `_shapeOf` que dissesse `list` sobre um tipo que o `_emitType` não
    // baixa como `InterfaceType`. As duas leituras vêm da mesma nº1, no mesmo
    // nó, com dois statements de distância. São asserções de fase, não
    // fronteiras da linguagem.
    return (
      expr: _expr(recv),
      sub: Substitution.fromInterfaceType(iface),
    );
  }

  /// `xs.length` → `InstanceGet` do GETTER de `dart:core` (§7.2 da spec 012).
  ///
  /// `length` é getter nas três formas, não field (`list.dart:408`,
  /// `string.dart:224`, `map.dart:460` do pin 3.12.2) — e `Procedure.getterType`
  /// (`members.dart:1305-1310`) é `signatureType?.returnType ?? function
  /// .returnType`, isto é, o `int` declarado. Substituí-lo é inócuo para
  /// `length` (não menciona `E`), e é feito assim mesmo, porque a doc do campo
  /// não abre exceção por membro: `resultType` *"includes substituted type
  /// parameters from the static receiver type"* (`expressions.dart:558-571`).
  /// Um atalho aqui seria a semente do próximo membro do chão que mencione `E`.
  k.Expression _groundLength(
    ast.Member m,
    _GroundShape shape,
    k.Procedure getter,
  ) {
    final r = _groundReceiver(m.receiver, shape, m);
    return k.InstanceGet(
      k.InstanceAccessKind.Instance,
      r.expr,
      getter.name,
      interfaceTarget: getter,
      resultType: r.sub.substituteType(getter.getterType),
    )..fileOffset = m.opOffset;
  }

  /// `xs[i]` / `m[k]` / `s[i]` → `InstanceInvocation` do `operator []`.
  ///
  /// O tipo do nó **não** é um campo próprio: `InstanceInvocation` não tem
  /// `resultType` (esse é do `InstanceGet`), e o `getStaticTypeInternal` lê
  /// `functionType.returnType` (`expressions.dart:1958-1960`). Errar o
  /// `functionType` aqui não é cosmético — é o tipo estático do nó.
  ///
  /// ⚠️ `Map<K,V>::[]` recebe **`Object?`**, não `K` (`map.dart:270`), e a doc
  /// `:263-269` avisa verbatim que *"a lookup using this operator cannot
  /// distinguish between a key not being in the map, and the key being there
  /// with a `null` value"*.
  ///
  /// ⚠️⚠️ **Dizer que o Itá "herda" essa ambiguidade seria transferir o sujeito.**
  /// Ela é NOSSA, e a diferença importa: o `[]` de `Map` devolve `optional(V)`
  /// (`check.dart:2363`), e `?` é MODIFICADOR idempotente — `T?? = T?` (ruling da
  /// spec 009 §12-1, smart constructor em `type.dart:212-216`). Então para
  /// `V = Int?` os dois casos colapsam **no tipo do Itá**, não no do Dart.
  /// Medido em 2026-09-01, `{"presente": nil} : Map<String, Int?>`:
  ///
  ///     length = 1
  ///     presente: vazio      ← a chave EXISTE
  ///     ausente:  vazio
  ///
  /// O mapa tem uma entrada que o programa não consegue observar. O chão é
  /// FECHADO e não tem `containsKey`, então nada aqui a desempata. É dívida
  /// DECLARADA na errata da spec 012 §4.1, com o fixture `chao_map_nil.tu`
  /// congelando o comportamento — e não um limite do Dart que a gente repassa.
  ///
  /// **Out-of-bounds: a emissão não põe guarda** — ruling do dono registrado na
  /// spec 012 §0.6. O `[]` nativo já faz o bounds-check como intrínseco (Grupo
  /// B) e lança; o throw sobe sem nada o capturar (P7) e vira panic. Ver
  /// `chao_oob.tu`.
  k.Expression _index(ast.Index n) {
    final shape = _shapeOf(check.exprTypes[n.receiver]);
    if (shape == null) {
      // Receptor fora do chão. **Sem catraca, por ORDEM (R10):** medido em
      // 2026-08-31, `5[0]` para na F5 com `unknown-member` (exit 65) — o
      // `_index` dela devolve `ErrorType` para shape desconhecido (Decisão 2b da
      // spec 012). É a ordem certa: erro de usuário antes de ICE. Fica aqui como
      // falha no desconhecido (R5), nunca um `[]` que a VM rejeitaria.
      _ice('index-on-${check.exprTypes[n.receiver].runtimeType}', n);
    }
    final r = _groundReceiver(n.receiver, shape, n);
    final op = ground.index[shape]!;
    return k.InstanceInvocation(
      k.InstanceAccessKind.Instance,
      r.expr,
      op.name,
      k.Arguments([_expr(n.index)]),
      interfaceTarget: op,
      functionType:
          r.sub.substituteType(op.computeSignatureOrFunctionType()) as k.FunctionType,
    )..fileOffset = n.opOffset;
  }

  /// **O ÚNICO sítio que escolhe o alvo de um operador aritmético.** Chamado por
  /// `_binary` (`a + b`), `_assign` (`a += b`) e `_assignMember` (`c.a += b`).
  ///
  /// 🔴 **A unificação é o achado, não um detalhe de organização.** A história,
  /// em duas rodadas do mesmo bug:
  ///
  /// 1. O alvo do `+` era escolhido pela TAG SINTÁTICA do operador, então
  ///    `"a" + "b"` gravava `interfaceTarget = num::+` com `functionType =
  ///    String Function(num)`. Verde no JIT, verde no JS, *"Attempt to execute
  ///    code removed by (TFA)"* em AOT — a TFA conclui que `String` nunca
  ///    satisfaz `num` e poda o corpo. Fixture `chao_string_concat.tu`.
  /// 2. A primeira correção pôs o desvio **dentro de `_binary`**, e `s += "b"`
  ///    seguiu quebrado: o compound tem despacho próprio e chamava
  ///    `_arithOpFor` cru. O programa é LEGAL — a `_primitiveOps` da F5 admite
  ///    `(String, String) → String` (`check.dart:55`) e o compound consulta a
  ///    MESMA tabela (`check.dart:2100`). Fixtures `chao_string_compound.tu` e
  ///    `chao_string_compound_campo.tu`.
  ///
  /// A régua violada já estava escrita no corpus, para o outro operador que tem
  /// o mesmo formato de armadilha — `conformance/codegen/var_assign.tu:13-15`,
  /// verbatim: *"`/=` passa pelo MESMO despacho por tipo que o `/` binário. A
  /// armadilha `~/` (Int) × `/` (Float) não pode ser fechada numa forma e
  /// reaberta na outra"*. O `div` a respeitava porque `_arithOpFor` sempre foi
  /// compartilhado; o `+` a violou porque o desvio do chão nasceu ACIMA do
  /// resolvedor comum. Agora nasce dentro.
  ({k.Procedure op, k.FunctionType fnType}) _arithAlvo(
    ast.BinaryOp binop,
    Type? alvo,
    ast.AstNode span,
  ) {
    final shape = _shapeOf(alvo);
    if (binop == ast.BinaryOp.add && shape != null) {
      final op = ground.plus[shape];
      // `Map` não tem `+` em `dart:core`. **Sem catraca, por ORDEM (R10):**
      // medido em 2026-08-31, `m1 + m2` para na F5 com `no-operator-for-types`
      // (exit 65) — o ramo List-concat dela (`check.dart:1688`) só admite
      // `BuiltinKind.list`. Vira alcançável se `dart:core::Map` ganhar `+`, ou
      // se a F5 passar a admitir união de mapas.
      if (op == null) _ice('arith-plus-on-${shape.name}', span);
      final iface = _emitType(alvo!, span);
      if (iface is! k.InterfaceType) _ice('arith-receiver-nonclass', span);
      return (
        op: op,
        fnType: Substitution.fromInterfaceType(iface)
            .substituteType(op.computeSignatureOrFunctionType()) as k.FunctionType,
      );
    }
    // Fora do chão, o receptor tem de ser NUMÉRICO — a régua que faltava, e o
    // motivo de o `+` de `String` ter sobrevivido a 30 runs verdes. É o gêmeo do
    // `cmp-on-<Tipo>` de [_compare].
    //
    // **Sem catraca, por ORDEM (R10):** medido em 2026-08-31, `true - false`
    // para na F5 com `no-operator-for-types` (exit 65) e nunca chega aqui — que
    // é a ordem CERTA, erro de usuário antes de ICE. Vira alcançável se a F5
    // passar a admitir aritmético sobre um tipo que o emitter não baixa.
    if (alvo is! IntType && alvo is! FloatType) {
      _ice('arith-on-${alvo.runtimeType}', span);
    }
    final op = _arithOpFor(binop, alvo);
    return (
      op: op,
      // R4: o tipo do composto é o do ALVO — `n += 1` sobre `Int` rende `Int`,
      // não `num`. Mesma cura do `_numOp`.
      fnType: _especializa(
        op.function.computeFunctionType(k.Nullability.nonNullable),
        alvo,
        span,
      ),
    );
  }


  /// O `BuiltinType` de um literal de coleção, **desembrulhando o `T?`**.
  ///
  /// 🔴 **Sem o desembrulho isto era ICE sobre programa LEGAL** — a violação da
  /// R6, não uma fronteira. `let xs: List<Int>? = [1, 2]` passa a F5 (medido em
  /// 2026-09-01: `itac check` exit 0) e dava
  /// `ice-codegen-list-literal-typed-OptionalType`.
  ///
  /// A legalidade é **decisão escrita** da F5, não acidente —
  /// `check.dart:2801-2802`, verbatim: *"`T?` desembrulha para validar e descer:
  /// `let xs: List<Int>? = [1]` é legal (subsunção `T ≤ T?`) e o `?` não muda o
  /// que os elementos são"*. Ela desembrulha para validar (`:2804`, `final
  /// landed = expected is OptionalType ? expected.inner : expected`) e então
  /// grava o **`expected` inteiro** (`:2848`), com o `?`. Quem lê a nº1 aqui tem
  /// de fazer o mesmo desembrulho, ou lê um tipo que a F5 nunca prometeu ser o
  /// do container.
  ///
  /// **Não fere a R4.** O nó Kernel de um literal é `List<E>` non-nullable —
  /// não existe `ListLiteral` nullable —, e é a mesma subsunção `T ≤ T?` que a
  /// F5 invoca que autoriza o valor a ocupar um slot opcional. O que a R4 proíbe
  /// é ALARGAR o tipo (gravar `num` onde a F5 provou `Int`); aqui o tipo emitido
  /// é o mais preciso dos dois.
  BuiltinType _literalShape(ast.Expr e, BuiltinKind querido) {
    final bruto = check.exprTypes[e];
    final tipo = bruto is OptionalType ? bruto.inner : bruto;
    if (tipo is! BuiltinType || tipo.kind != querido) {
      // Prefixo LITERAL, não interpolado: `make assertions` lê o código do
      // `_ice(` na fonte, e um que comece com `${...}` fica invisível para a
      // régua — sítio que ela deixa de vigiar é sítio sem catraca possível.
      _ice('literal-typed-${querido.name}-${tipo.runtimeType}', e);
    }
    return tipo;
  }

  /// `[a, b, c]` → `ListLiteral` (binary.md tag 49).
  ///
  /// ⚠️ **`isConst: false` SEMPRE**, e não é higiene de campo: `isConst: true`
  /// serializa como `Tag.ConstListLiteral` (58, `ast_to_binary.dart:2154`), da
  /// família que a VM declara *"internal to the front end and removed by the
  /// constant evaluator"*. Diferente do `IntLiteral` em default de parâmetro
  /// — que passou pelo verify e matou a VM no LOAD —, **este o verify pega**:
  /// `if (afterConst && node.isConst && !inUnevaluatedConstant) problem(node,
  /// "Constant list literal.")` (`verifier.dart:1360-1362`), e o pré-requisito
  /// se sustenta no nosso pipeline (`afterConst => stage >=
  /// afterConstantEvaluation`, `verifier.dart:218`; o `finalize.dart:59,141`
  /// passa `afterModularTransformations`, posterior). Constante de verdade seria
  /// `ConstantExpression(ListConstant(...))`, outra fatia.
  ///
  /// ⚠️ `typeArgument` **defaulta para `const DynamicType()`**
  /// (`expressions.dart:4536`) — omiti-lo passaria pelo construtor e cairia no
  /// gate `visitDynamicType` (ADR-0013), que é a rede certa mas tarde demais
  /// para dizer por quê. O tipo vem da nº1, instanciado.
  ///
  /// O literal é **growable** nos três alvos por semântica de linguagem
  /// (`list.dart:26`: *"The default growable list, as created by `[]`"*) — não
  /// emitimos nada para consegui-lo.
  k.Expression _listExpr(ast.ListExpr e) {
    final tipo = _literalShape(e, BuiltinKind.list);
    if (tipo.args.length != 1) _ice('list-literal-arity-${tipo.args.length}', e);
    return k.ListLiteral(
      [for (final x in e.elements) _expr(x)],
      typeArgument: _emitType(tipo.args.single, e),
      isConst: false,
    )..fileOffset = e.offset;
  }

  /// `{k: v, …}` → `MapLiteral` (binary.md tag 50).
  ///
  /// Mesmas duas armadilhas do [_listExpr]: `isConst: true` reprova no verify
  /// (`verifier.dart:1380-1382`) e `keyType`/`valueType` defaultam para
  /// `DynamicType` (`expressions.dart:4667-4668`).
  ///
  /// `MapEntry` não é `Expression` e não tem tag nem `fileOffset` próprios
  /// (`binary.md:1144`) — por isso o `..fileOffset` mora só no literal.
  ///
  /// **Nunca `SetLiteral`**: o Itá não tem literal de conjunto, e a VM declara
  /// `kSetLiteral` como `UNREACHABLE()` (*"Set literals are currently desugared
  /// in the frontend"*). Um `{}` sem `:` é `MapExpr` vazio pela gramática, não
  /// um set.
  k.Expression _mapExpr(ast.MapExpr e) {
    final tipo = _literalShape(e, BuiltinKind.map);
    if (tipo.args.length != 2) _ice('map-literal-arity-${tipo.args.length}', e);
    return k.MapLiteral(
      [
        for (final entry in e.entries)
          k.MapLiteralEntry(_expr(entry.key), _expr(entry.value)),
      ],
      keyType: _emitType(tipo.args[0], e),
      valueType: _emitType(tipo.args[1], e),
      isConst: false,
    )..fileOffset = e.offset;
  }

  /// §7.4-a: `Str` COM interpolação → `StringConcatenation` (binary.md tag 36) —
  /// cada parte vira uma `Expression`: `StrLit` → `StringLiteral`; `StrInterp` →
  /// a `expr` emitida CRUA (o `Int` da interp entra como `IntLiteral`/
  /// `InstanceInvocation`).
  ///
  /// A conversão da parte não-`String` para `String` é **IMPLÍCITA na VM**, NÃO
  /// um `toString()` que emitimos: o próprio nó não a representa —
  /// `type_checker.dart:860-863` (`visitStringConcatenation`) só faz
  /// `forEach(visitExpression)` e devolve `String`, SEM `checkAssignable` dos
  /// elementos (contraste com `visitStaticSet`, `:853`); o `binary.md` §36 lista
  /// `List<Expression>` cru, sem tag de `toString` por elemento; e a VM baixa o
  /// nó para `StringBase._interpolate`/`_interpolateSingle`
  /// (`kernel_to_il.cc`, `FlowGraphBuilder::StringInterpolate`), que chama
  /// `toString()` em runtime. **Grupo B — não emitimos a conversão.**
  ///
  /// SEM interp o `Str` continua um `StringLiteral` puro (o `hello` não regride).
  k.Expression _str(ast.Str s) {
    final hasInterp = s.parts.any((p) => p is ast.StrInterp);
    if (!hasInterp) {
      final buf = StringBuffer();
      for (final part in s.parts) {
        if (part is ast.StrLit) buf.write(part.value);
      }
      return k.StringLiteral(buf.toString())..fileOffset = s.offset;
    }
    final parts = <k.Expression>[
      for (final part in s.parts)
        switch (part) {
          ast.StrLit l => k.StringLiteral(l.value)..fileOffset = s.offset,
          ast.StrInterp i => _expr(i.expr),
        },
    ];
    return k.StringConcatenation(parts)..fileOffset = s.offset;
  }
}
