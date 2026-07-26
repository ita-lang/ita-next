// Hello world da F7 (§7.4/§7.6, CA1 mínimo) — Passo A: emitir e RODAR um
// `.dill` à mão, provando a cadeia backend inteira (carregar platform → resolver
// `dart:core::print` → emitir → SANEAR+VERIFICAR (finalizeComponent) →
// serializar → a VM pinada imprime). Ainda NÃO parte da AST do Itá — isso é o
// Passo B. Receita do oracle `ita/compiler/docs/generate_dill.dart`.
//
// Uso (com o dart PINADO):
//   dart run bin/hello.dart <vm_platform.dill> <out.dill>
import 'dart:io';

import 'package:kernel/kernel.dart';
import 'package:ita_next_codegen/finalize.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('uso: dart run bin/hello.dart <vm_platform.dill> <out.dill>');
    exit(64);
  }
  final platformPath = args[0];
  final outPath = args[1];

  // 1. Carregar o platform e resolver `dart:core::print` (o interop enumerado
  //    do Art. II / spec 013 §8.2). O `platform` NÃO é descartado: ele vira a
  //    BASE do Component em `finalizeProgram` (o verify precisa dos membros do
  //    platform PRESENTES p/ resolver `print`). A VM relinca o seu próprio
  //    platform no load, então só o programa entra no `.dill` (Grupo B).
  final platform = loadComponentFromBinary(platformPath);
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  final printRef =
      dartCore.procedures.firstWhere((p) => p.name.text == 'print').reference;

  // 2. Construir a lib do programa: `fn main() { print("olá") }`.
  final fileUri = Uri.parse('file:///hello.tu');
  final libUri = Uri.parse('app:///hello.dart');
  final main = Procedure(
    Name('main'),
    ProcedureKind.Method,
    FunctionNode(
      Block([
        ExpressionStatement(
          StaticInvocation.byReference(
            printRef,
            Arguments([StringLiteral('olá')]),
          ),
        ),
      ]),
      returnType: const VoidType(),
    ),
    isStatic: true,
    fileUri: fileUri,
  );
  final lib = Library(libUri, fileUri: fileUri)..addProcedure(main);

  // 3. Finalizar CONTRA o platform (base do Component): saneia+verifica só o
  //    programa, resolve a ref a `dart:core::print`, serializa só o programa.
  final bytes = finalizeProgram(platform, [lib], mainMethod: main);
  File(outPath).writeAsBytesSync(bytes);
  stderr.writeln('gerado: $outPath (${bytes.length} bytes)');
}
