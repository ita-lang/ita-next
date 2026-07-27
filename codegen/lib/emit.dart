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
//   Binary add/sub/mul/div/mod (Int) → InstanceInvocation de dart:core::num
//                                       (div → `~/`; pow/comparações/lógicos → ICE)
//
// O `print` é resolvido no [platform] carregado (a receita do `hello.dart`); o
// handoff do B1 é o callee: um `Ident` cuja `check.resolution[ident]` é a
// `GroundRes('print')` da F4 (`binding/scope.dart`).

import 'package:kernel/ast.dart' as k;

import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
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

k.Class _dartCoreClass(k.Component platform, String name) {
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  return dartCore.classes.firstWhere((c) => c.name == name);
}

class _Emitter {
  final CheckResult check;
  final k.Reference printRef;

  /// `dart:core::num` operators (add/sub/mul/div→`~/`/mod), resolvidos 1× do
  /// platform. A `Str` interpolada NÃO precisa deles — a conversão para String é
  /// da VM (`StringBase._interpolate`), não uma call que emitimos.
  final Map<ast.BinaryOp, k.Procedure> arithOps;
  final Uri fileUri;

  _Emitter(this.check, this.printRef, this.arithOps, this.fileUri);

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
        _ => _ice('stmt-${s.runtimeType}', s),
      };

  k.Expression _expr(ast.Expr e) => switch (e) {
        ast.Call c => _call(c),
        ast.Str s => _str(s),
        ast.IntLit i => k.IntLiteral(i.value)..fileOffset = i.offset,
        ast.Binary b => _binary(b),
        _ => _ice('expr-${e.runtimeType}', e),
      };

  /// §7.4-a: os aritméticos de `Int` (add/sub/mul/div/mod) → `InstanceInvocation`
  /// do operador de `dart:core::num` (herdado por `int`), com `interfaceTarget` +
  /// `functionType` resolvidos — o Kernel os exige (sem eles cairia em
  /// `DynamicInvocation`). `pow` (`**`), comparações (rendem `Bool`) e lógicos
  /// ficam FORA: ICE honesto por variante (fatia do `if`/`match` ou `intPow`).
  /// O `name` sai do próprio `Procedure` resolvido (`+`/`-`/`*`/`~/`/`%`), então
  /// casa por construção com o `interfaceTarget`.
  k.Expression _binary(ast.Binary b) {
    final op = arithOps[b.op];
    if (op == null) _ice('binary-${b.op.name}', b); // pow, ==, <, &&, ??, |>, >>
    return k.InstanceInvocation(
      k.InstanceAccessKind.Instance,
      _expr(b.left),
      op.name,
      k.Arguments([_expr(b.right)]),
      interfaceTarget: op,
      functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
    )..fileOffset = b.offset;
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
