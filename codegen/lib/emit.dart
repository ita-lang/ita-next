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

/// Emite as libs do programa [check] (F5+F6-verde) e o `Procedure` de `main`,
/// resolvendo o interop enumerado `dart:core::print` (§8.2) contra o [platform]
/// carregado. O `finalizeProgram` fixa o `main` como `Component.mainMethod`.
///
/// [sourceUri] vira o `fileUri` dos nós (forward-compat span→stack-trace); o
/// default cobre o uso à mão / testes.
({List<k.Library> libs, k.Procedure main}) emitProgram(
  CheckResult check,
  k.Component platform, {
  Uri? sourceUri,
}) {
  final fileUri = sourceUri ?? Uri.parse('file:///main.tu');
  final libUri = Uri.parse('app:///main.dart');

  final emitter = _Emitter(
    check,
    _resolvePrintRef(platform),
    _resolveArithOps(platform),
    _resolveCmpOps(platform),
    _resolveEqualsOps(platform),
    _resolveCoreTypes(platform),
    fileUri,
  );
  final main = emitter.emitMain();
  final lib = k.Library(libUri, fileUri: fileUri)..addProcedure(main);
  return (libs: [lib], main: main);
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
  return {
    ast.BinaryOp.add: op('+'),
    ast.BinaryOp.sub: op('-'), // binário; o unário é `unary-` (names.dart:55) — não colide
    ast.BinaryOp.mul: op('*'),
    ast.BinaryOp.div: op('~/'), // NÃO `/` (devolve double) — ver docstring
    ast.BinaryOp.mod: op('%'),
  };
}

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
    const StringType(): iface('String'),
    const BoolType(): iface('bool'),
    const VoidType(): const k.VoidType(),
  };
}

class _Emitter {
  final CheckResult check;
  final k.Reference printRef;

  /// `dart:core::num` operators (add/sub/mul/div→`~/`/mod), resolvidos 1× do
  /// platform. A `Str` interpolada NÃO precisa deles — a conversão para String é
  /// da VM (`StringBase._interpolate`), não uma call que emitimos.
  final Map<ast.BinaryOp, k.Procedure> arithOps;

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

  _Emitter(
    this.check,
    this.printRef,
    this.arithOps,
    this.cmpOps,
    this.equalsOps,
    this.coreTypes,
    this.fileUri,
  );

  /// Acha o `fn main` no topo e o emite. CA1: só `main` é suportado no topo;
  /// qualquer outro item (incl. `fn` do usuário) → ICE.
  k.Procedure emitMain() {
    ast.FnDecl? main;
    for (final item in check.program.body) {
      if (item is ast.FnDecl && item.name == 'main') {
        if (main != null) _ice('main-duplicate', item);
        main = item;
      } else {
        _ice('toplevel-${item.runtimeType}', item);
      }
    }
    if (main == null) {
      // Rede de segurança do scaffold — no modo build o driver (B3) pega isto
      // antes como `missing-main` (§12-5), fora da emissão.
      throw CodegenIce(
        'ice-codegen-missing-main',
        check.program.offset,
        check.program.length,
      );
    }
    return _fnMain(main);
  }

  k.Procedure _fnMain(ast.FnDecl fn) {
    if (fn.params.isNotEmpty) _ice('main-arity', fn);
    if (fn.generics.isNotEmpty) _ice('main-generic', fn);
    if (fn.asyncMarker != ast.AsyncMarker.sync) _ice('main-async', fn);

    final block = switch (fn.body) {
      ast.BlockBody b => _block(b.b),
      ast.ExprBody _ => _ice('expr-body', fn), // `=> expr` fica p/ depois
      null => _ice('abstract-fn', fn), // assinatura sem corpo (trait)
    };

    return k.Procedure(
      k.Name('main'),
      k.ProcedureKind.Method,
      k.FunctionNode(block, returnType: const k.VoidType()),
      isStatic: true,
      fileUri: fileUri,
    )..fileOffset = fn.offset;
  }

  k.Block _block(ast.Block b) =>
      k.Block([for (final s in b.stmts) _stmt(s)])..fileOffset = b.offset;

  k.Statement _stmt(ast.Stmt s) => switch (s) {
        ast.ExprStmt e =>
          k.ExpressionStatement(_expr(e.expr))..fileOffset = e.offset,
        ast.LetStmt l => _let(l),
        _ => _ice('stmt-${s.runtimeType}', s),
      };

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

  k.Expression _expr(ast.Expr e) => switch (e) {
        ast.Call c => _call(c),
        ast.Str s => _str(s),
        ast.IntLit i => k.IntLiteral(i.value)..fileOffset = i.offset,
        ast.BoolLit b => k.BoolLiteral(b.value)..fileOffset = b.offset,
        ast.Binary b => _binary(b),
        ast.IfExpr f => _ifExpr(f),
        ast.Ident id => _ident(id),
        _ => _ice('expr-${e.runtimeType}', e),
      };

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

  /// Tipo da F5 → `DartType` do Kernel, pela tabela [coreTypes] (os quatro do
  /// chão). [span] é o nó que porta o tipo (o `LetStmt`), para o ICE apontar. Todo
  /// tipo fora dos quatro → `ice-codegen-type-<Tipo>` (§7.8) — NUNCA `dynamic`.
  k.DartType _emitType(Type type, ast.AstNode span) =>
      coreTypes[type] ?? _ice('type-${type.runtimeType}', span);

  /// Despacha o `Binary` pela FAMÍLIA do operador — cada família tem alvo Kernel
  /// distinto (spec 006 §5: o enum é TAG sintática, o nó é derivado por tipos):
  ///
  ///   - add/sub/mul/div/mod → `InstanceInvocation` de `num` (§7.4-a);
  ///   - lt/gt/le/ge         → `InstanceInvocation` de `num`, SÓ receptor numérico;
  ///   - eq/ne               → `EqualsCall` / `Not(EqualsCall)` (`==` é especial);
  ///   - and/or              → `LogicalExpression` (curto-circuito é do nó);
  ///   - pow/coalesce/pipe/compose → ICE (desugaring/call de fatia posterior).
  k.Expression _binary(ast.Binary b) {
    if (arithOps.containsKey(b.op)) return _numOp(b, arithOps[b.op]!);
    if (cmpOps.containsKey(b.op)) return _compare(b);
    if (b.op == ast.BinaryOp.eq || b.op == ast.BinaryOp.ne) return _equals(b);
    if (b.op == ast.BinaryOp.and || b.op == ast.BinaryOp.or) return _logical(b);
    return _ice('binary-${b.op.name}', b); // pow, ??, |>, >>
  }

  /// §7.4-a: operador de `dart:core::num` (aritmético OU comparação de ordem) →
  /// `InstanceInvocation`, com `interfaceTarget` + `functionType` resolvidos — o
  /// Kernel os exige (sem eles cairia em `DynamicInvocation`). O `name` sai do
  /// próprio `Procedure` (`+`/`~/`/`<`/…), então casa por construção com o
  /// `interfaceTarget`. `functionType` = `num Function(num)` (aritmético) ou
  /// `bool Function(num)` (comparação) — o `getStaticTypeInternal` do nó lê o
  /// `returnType` daí, logo o tipo estático fica correto sem esforço extra.
  k.Expression _numOp(ast.Binary b, k.Procedure op) => k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        _expr(b.left),
        op.name,
        k.Arguments([_expr(b.right)]),
        interfaceTarget: op,
        functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      )..fileOffset = b.offset;

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
  /// quatro escalares; receptor fora da [equalsOps] → ICE (`cmp-on-<Tipo>`).
  k.Expression _equals(ast.Binary b) {
    final leftType = check.exprTypes[b.left];
    final op = equalsOps[leftType];
    if (op == null) _ice('cmp-on-${leftType.runtimeType}', b);
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

  /// CA1: só o callee-CHÃO (`GroundRes('print')`) → dispatch ESTÁTICO
  /// (`StaticInvocation`). Chamada a `fn` do usuário (`TopLevelRes`) fica p/ depois.
  k.Expression _call(ast.Call c) {
    final callee = c.callee;
    if (callee is! ast.Ident) _ice('call-nonident', c);
    final res = check.resolution[callee];
    if (res is! GroundRes) _ice('call-nonground', c);
    if (res.name != 'print') _ice('ground-${res.name}', c);
    // `opOffset` (o `(` da invocação) é o span do call — o stack trace aponta
    // p/ o seletor, não p/ o início do receptor (doutrina de span da AST).
    return k.StaticInvocation.byReference(printRef, _args(c))
      ..fileOffset = c.opOffset;
  }

  /// CA1: `print` é 1 posicional `String` (§12-4). Labels (a reordenação por
  /// slot da nº5) são fatia posterior.
  k.Arguments _args(ast.Call c) {
    final positional = <k.Expression>[];
    for (final a in c.args) {
      if (a.label != null) _ice('named-arg', a.value);
      positional.add(_expr(a.value));
    }
    return k.Arguments(positional);
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
