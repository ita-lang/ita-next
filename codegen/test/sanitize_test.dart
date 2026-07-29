// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// RED→GREEN da LT-F7a (spec 013 §7.1(B)): os passes de saneamento.
//
// Este pacote NÃO usa `package:test` (o `kernel` vendorado força o
// `_fe_analyzer_shared 98`, que colide com o `analyzer` que o `package:test`
// puxa — ver a memória do projeto `kernel-vs-package-test-conflict`). O teste
// é um harness próprio: `main()` + asserts. Rodar com o dart PINADO:
//   ../.dart-sdk/3.12.2/dart-sdk/bin/dart run test/sanitize_test.dart
//
// RED  = o Component construído CRU pela API do pkg/kernel tem os defeitos.
// GREEN = após `sanitizeComponent`, todos são consertados.
//
// Reforços do W3 (dart-vm-expert, 2026-07-25): DOIS members com closures (o
// reset por member só é exercitado com ≥2) + assert do `fileOffset` PRIMÁRIO (o
// único offset que o verifier de fato cobra).

import 'package:kernel/kernel.dart';
import 'package:ita_next_codegen/sanitize.dart';

int _fails = 0;
void check(bool cond, String label) {
  print('  ${cond ? '✓' : '✗ FAIL:'} $label');
  if (!cond) _fails++;
}

/// Fabrica um Component no estado CRU que a API do `pkg/kernel` deixa por
/// default: DOIS members, cada um com 2 closures de id inválido (0); um Field
/// sem setter marcado não-final; um Field com setter marcado final; e offsets
/// no sentinela -1 (nada foi setado à mão).
({
  Component comp,
  List<FunctionExpression> clos1, // closures do member `m`
  List<FunctionExpression> clos2, // closures do member `n`
  Field noSetter,
  Field withSetter,
}) buildRaw() {
  final uri = Uri.parse('org-dartlang:///raw.tu');

  List<FunctionExpression> twoClosures() =>
      [FunctionExpression(FunctionNode(EmptyStatement())),
       FunctionExpression(FunctionNode(EmptyStatement()))];

  Procedure memberWith(String name, List<FunctionExpression> clos) => Procedure(
        Name(name),
        ProcedureKind.Method,
        FunctionNode(Block([for (final c in clos) ExpressionStatement(c)])),
        fileUri: uri,
      );

  final clos1 = twoClosures();
  final clos2 = twoClosures();

  // sem setter + isFinal=false (default) → malformado: deve virar final.
  final noSetter = Field.immutable(Name('a'), fileUri: uri);
  // com setter + isFinal=true → mataria o P2: deve virar não-final.
  final withSetter = Field.mutable(Name('b'), fileUri: uri, isFinal: true);

  final cls = Class(name: 'C', fileUri: uri)
    ..addField(noSetter)
    ..addField(withSetter)
    ..addProcedure(memberWith('m', clos1))
    ..addProcedure(memberWith('n', clos2));
  final lib = Library(uri, fileUri: uri)..addClass(cls);
  final comp = Component(libraries: [lib]);
  return (comp: comp, clos1: clos1, clos2: clos2, noSetter: noSetter, withSetter: withSetter);
}

void main() {
  final raw = buildRaw();
  final all = [...raw.clos1, ...raw.clos2];

  print('RED — o Component cru carrega os defeitos que a API deixa:');
  check(all.every((c) => c.id == LocalFunctionId.invalid),
      'as 4 closures nascem com id inválido (0)');
  check(raw.noSetter.setterReference == null && !raw.noSetter.isFinal,
      'Field sem setter nasce NÃO-final (Kernel malformado)');
  check(raw.withSetter.setterReference != null && raw.withSetter.isFinal,
      'Field com setter nasce final (mataria o P2 do `class`)');

  sanitizeComponent(raw.comp);

  print('GREEN — após o saneamento:');
  // ids ≥1 e distintos DENTRO de cada member
  check(raw.clos1.every((c) => c.id.toInt() >= 1) && raw.clos1[0].id != raw.clos1[1].id,
      'member `m`: closures com ids ≥1 e distintos (${raw.clos1.map((c) => c.id.toInt()).toList()})');
  check(raw.clos2.every((c) => c.id.toInt() >= 1) && raw.clos2[0].id != raw.clos2[1].id,
      'member `n`: closures com ids ≥1 e distintos (${raw.clos2.map((c) => c.id.toInt()).toList()})');
  // RESET por member: `n` reinicia em 1, repetindo os ids de `m`
  check(raw.clos2[0].id.toInt() == 1,
      'RESET por member: `n` reinicia em 1 (sem reset seria 3)');
  check(raw.clos1[0].id == raw.clos2[0].id && raw.clos1[1].id == raw.clos2[1].id,
      'os ids REPETEM entre members (chave é (member, id), não global)');
  // isFinal bidirecional
  check(raw.noSetter.isFinal, 'Field sem setter → final');
  check(!raw.withSetter.isFinal, 'Field com setter → NÃO-final (P2 preservado)');
  // offsets: primário (o que o verifier cobra) E secundários
  var badPrimary = false, badSecondary = false;
  raw.comp.accept(_OffsetAuditor(
    onBadPrimary: () => badPrimary = true,
    onBadSecondary: () => badSecondary = true,
  ));
  check(!badPrimary, 'nenhum fileOffset PRIMÁRIO sobrou em -1 (gate do verifier)');
  check(!badSecondary, 'nenhum offset secundário coberto sobrou em -1');

  raw.comp.computeCanonicalNames();
  final dill = writeComponentToBytes(raw.comp);
  check(dill.isNotEmpty, 'Component saneado serializa (${dill.length} bytes)');

  print(_fails == 0
      ? '\nLT-F7a saneamento: TODOS OS CHECKS VERDES ✅'
      : '\nLT-F7a saneamento: $_fails CHECK(S) VERMELHO(S) ❌');
  if (_fails > 0) throw StateError('$_fails checks falharam');
}

/// Audita offsets após o saneamento: o PRIMÁRIO (gate do verifier) e os
/// SECUNDÁRIOS que o [OffsetNormalizer] cobre.
class _OffsetAuditor extends RecursiveVisitor {
  final void Function() onBadPrimary;
  final void Function() onBadSecondary;
  _OffsetAuditor({required this.onBadPrimary, required this.onBadSecondary});
  static const int _no = TreeNode.noOffset;

  @override
  void defaultNode(Node node) {
    if (node is TreeNode && node.fileOffset == _no) onBadPrimary();
    if (node is Class && (node.startFileOffset == _no || node.fileEndOffset == _no)) onBadSecondary();
    if (node is Constructor && (node.startFileOffset == _no || node.fileEndOffset == _no)) onBadSecondary();
    if (node is Procedure && (node.fileStartOffset == _no || node.fileEndOffset == _no)) onBadSecondary();
    if (node is Field && node.fileEndOffset == _no) onBadSecondary();
    if (node is FunctionNode && node.fileEndOffset == _no) onBadSecondary();
    if (node is Block && node.fileEndOffset == _no) onBadSecondary();
    super.defaultNode(node);
  }
}
