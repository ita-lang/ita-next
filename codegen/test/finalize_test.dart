// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// Pipeline de finalização end-to-end (LT-F7a). Harness próprio (sem
// `package:test` — ver `kernel-vs-package-test-conflict`). Rodar com o dart
// pinado: ../.dart-sdk/3.12.2/dart-sdk/bin/dart run test/finalize_test.dart
//
// Prova (1) que `finalizeComponent` (sanitize → canonical names →
// verifyComponent → serialize) roda sobre um Component com Fields inconsistentes,
// os CONSERTA e o verifier (gate CA12) ACEITA; e (2) — reforço do W3
// (dart-vm-expert, 2026-07-25) — que o gate é REAL: sem o saneamento o verifier
// REPROVA o mesmo Component (`isImmutable ⟺ !hasSetter`, verifier.dart:744-768),
// logo o pass do `isFinal` é load-bearing, não decorativo.

import 'dart:convert';

import 'package:kernel/kernel.dart';
import 'package:kernel/verifier.dart';
import 'package:ita_next_codegen/finalize.dart';
import 'harness.dart';

/// `fn main() {}` + uma `class C` com dois Fields INCONSISTENTES (o estado que a
/// API crua deixa): `x` mutável marcado `final`, `y` sem setter marcado
/// não-final. Ambos são Kernel malformado que o verifier reprova — até o
/// saneamento alinhar `isFinal` à existência de setter.
Component buildWithInconsistentFields() {
  final uri = Uri.parse('org-dartlang:///main.tu');
  final main = Procedure(
    Name('main'),
    ProcedureKind.Method,
    FunctionNode(Block([]), returnType: const VoidType()),
    isStatic: true,
    fileUri: uri,
  );
  final mut = Field.mutable(Name('x'), fileUri: uri, isFinal: true); // tem setter, mas final
  final imm = Field.immutable(Name('y'), fileUri: uri); // sem setter, isFinal=false (default)
  final cls = Class(name: 'C', fileUri: uri)
    ..addField(mut)
    ..addField(imm);
  final lib = Library(uri, fileUri: uri)
    ..addProcedure(main)
    ..addClass(cls);
  return Component(libraries: [lib])..setMainMethodAndMode(main.reference, true);
}

void main() {
  final h = Harness('LT-F7a pipeline');
  print('harness — o botão de vermelho funciona?');
  h.selfTest();
  print('');

  // (1) o pipeline conserta e o verify ACEITA.
  final comp = buildWithInconsistentFields();
  Object? err;
  var dillLen = 0;
  try {
    dillLen = finalizeComponent(comp).length;
  } catch (e) {
    err = e;
  }
  final cls = comp.libraries.first.classes.first;
  final mut = cls.fields.firstWhere((f) => f.name.text == 'x');
  final imm = cls.fields.firstWhere((f) => f.name.text == 'y');

  print('Pipeline de finalização (sanitize → verify → serialize):');
  h.check(err == null, 'verifyComponent ACEITA o `.dill` saneado (gate CA12)');
  if (err != null) print('    erro: $err');
  h.check(!mut.isFinal, 'Field com setter → NÃO-final após o pipeline (P2)');
  h.check(imm.isFinal, 'Field sem setter → final após o pipeline');
  h.check(dillLen > 0, 'serializa `.dill` fmt 130 ($dillLen bytes)');
  h.check(comp.mainMethod != null, 'Component.mainMethod preservado (entry `main`)');

  // (2) o gate é REAL: SEM saneamento, o verifier REPROVA os Fields inconsistentes.
  final raw = buildWithInconsistentFields();
  raw.computeCanonicalNames();
  var verifyRejected = false;
  try {
    verifyComponent(
      ItaVerifyTarget(),
      VerificationStage.afterModularTransformations,
      raw,
      skipPlatform: true,
    );
  } catch (_) {
    verifyRejected = true;
  }
  h.check(verifyRejected,
      'SEM saneamento, o verifier REPROVA o Field inconsistente (o pass é load-bearing)');

  // (3) `computeLineStarts` conta CODE UNITS da String, não bytes do arquivo.
  //
  // O achado de 2026-07-29: o trace do AOT em `panic_exit.tu` acusava a linha 22
  // e o `panic` está na 24 — cada não-ASCII acima dele vale 1 code unit e 2
  // bytes, e o `fileOffset` que a F1/F3 gravam conta code units. Um trace que
  // aponta a linha errada é pior que um sem linha: não diz que não sabe.
  //
  // O `checkSourcesRegistered` NÃO pega isto (as duas listas são não-vazias), e
  // o golden de stdout também não. Sem esta asserção, trocar `source.length` por
  // `utf8.encode(source).length` fica verde na suíte inteira.
  print('');
  print('computeLineStarts — code units da String, NÃO bytes do arquivo:');
  const primeira = '// ação'; // 7 code units, 9 bytes em UTF-8
  const fonte = '$primeira\npanic("x")\n';
  final starts = computeLineStarts(fonte);
  h.check(starts.first == 0, 'a 1ª linha começa em 0');
  h.check(starts.length == 3, 'duas quebras ⟹ três inícios de linha');
  h.check(starts[1] == primeira.length + 1,
      'a 2ª linha começa no code unit ${primeira.length + 1}');
  h.check(utf8.encode(primeira).length == 9,
      'a MESMA linha tem 9 BYTES — as duas unidades divergem no acento');
  h.check(starts[1] != utf8.encode(primeira).length + 1,
      'lineStarts NÃO conta bytes (era a linha errada no trace do AOT)');

  h.finish();
}
