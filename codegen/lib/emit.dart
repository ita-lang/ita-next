// emit.dart — o EMITTER da F7 (B2, CA1 mínimo). Anda o `CheckResult`
// (F5+F6-verde) e produz o `Component`: a AST REAL do Itá → Dart Kernel.
//
// ESCOPO: só o **CA1** (`fn main() { print("olá") }`, spec 013 §7.4/§7.6/§11).
// Qualquer nó fora do CA1 vira **ICE honesto** (`ice-codegen-*` com o nome do
// nó, §7.8) — NUNCA `dynamic`, NUNCA silêncio (ADR-0013). O mapa nó→Kernel:
//
//   FnDecl `main` (aridade 0, Void) → Procedure static top-level (mainMethod)
//   BlockBody                        → Block            (ExprBody → ICE)
//   ExprStmt                         → ExpressionStatement
//   Call(callee ⇒ GroundRes('print'))→ StaticInvocation.byReference(dart:core::print)
//   Str [só StrLit]                  → StringLiteral    (StrInterp → ICE)
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

  final emitter = _Emitter(check, _resolvePrintRef(platform), fileUri);
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

class _Emitter {
  final CheckResult check;
  final k.Reference printRef;
  final Uri fileUri;

  _Emitter(this.check, this.printRef, this.fileUri);

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
        _ => _ice('expr-${e.runtimeType}', e),
      };

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

  /// CA1: só `StrLit` (sem interpolação). `StrInterp` é `StringConcatenation`,
  /// fatia seguinte.
  k.Expression _str(ast.Str s) {
    final buf = StringBuffer();
    for (final part in s.parts) {
      switch (part) {
        case ast.StrLit l:
          buf.write(l.value);
        case ast.StrInterp _:
          _ice('str-interp', s);
      }
    }
    return k.StringLiteral(buf.toString())..fileOffset = s.offset;
  }
}
