// ============================================================================
// invariants_test.dart — os invariantes estruturais são LOAD-BEARING?
// ============================================================================
//
// Harness próprio (sem `package:test`). Rodar pelo Makefile: `make codegen-test`.
//
// Um invariante que nunca acusa é indistinguível de um invariante quebrado. Este
// arquivo constrói árvores DEFEITUOSAS de propósito e prova que cada regra as
// pega — e, do outro lado, que uma árvore sã passa (senão a regra seria só um
// `fail` disfarçado).
//
// ⚠️ **Por que isto não é redundante com o golden-runner.** Lá os invariantes
// rodam sobre o que o emitter PRODUZ hoje; aqui rodam sobre defeitos que o
// emitter ainda não comete. Sem estes testes, uma regra poderia parar de
// funcionar (um `visitChildren` esquecido, um `Set` trocado por `==`) e ninguém
// notaria enquanto nenhum bug real aparecesse.
//
// ⚠️ **E por que o `checkNoSharedNodes` existe, se o `verifyComponent` já pega
// nó com dois pais:** o verify é **opt-in NOSSO** — *"a VM não o roda"*
// (`verifyComponent` não tem chamador em todo o `pkg/`). Provado empiricamente
// (2026-07-29): com o verify DESLIGADO e um `InstanceGet` reusado nas duas
// pontas de um range, o `.dill` foi gerado, **rodou, e imprimiu a saída
// CORRETA** — nenhuma outra camada percebeu. O invariante era a única defesa.

import 'package:kernel/ast.dart' as k;

import 'package:ita_next_codegen/invariants.dart';

int _fails = 0;
void check(bool cond, String label) {
  print('  ${cond ? '✓' : '✗ FAIL:'} $label');
  if (!cond) _fails++;
}

final _uri = Uri.parse('org-dartlang:///main.tu');

k.Library _lib(List<k.Procedure> procedures, {List<k.Class> classes = const []}) {
  final lib = k.Library(Uri.parse('app:///main.dart'), fileUri: _uri);
  for (final p in procedures) {
    lib.addProcedure(p);
  }
  for (final c in classes) {
    lib.addClass(c);
  }
  return lib;
}

k.Procedure _fn(String name, k.Statement body) => k.Procedure(
      k.Name(name),
      k.ProcedureKind.Method,
      k.FunctionNode(body, returnType: const k.VoidType()),
      isStatic: true,
      fileUri: _uri,
    );

void main() {
  print('checkNoSharedNodes — árvore, não grafo:');
  {
    // O bug REAL de 2026-07-29, reduzido: um nó usado em DOIS lugares.
    final shared = k.IntLiteral(7)..fileOffset = 42;
    final lib = _lib([
      _fn(
        'main',
        k.Block([
          k.ExpressionStatement(k.StringConcatenation([shared, shared])),
        ]),
      ),
    ]);
    final v = checkNoSharedNodes([lib]);
    check(v.length == 1, 'nó em dois pais é ACUSADO (${v.length} violação)');
    check(v.isNotEmpty && v.first.contains('IntLiteral'),
        'a mensagem nomeia o TIPO do nó compartilhado');
    check(v.isNotEmpty && v.first.contains('42'),
        'a mensagem nomeia o OFFSET, para achá-lo na fonte');
  }
  {
    // Mesma forma, instâncias distintas: tem de passar. Sem este caso, a regra
    // poderia estar acusando qualquer árvore e os testes acima passariam igual.
    final lib = _lib([
      _fn(
        'main',
        k.Block([
          k.ExpressionStatement(k.StringConcatenation([
            k.IntLiteral(7)..fileOffset = 42,
            k.IntLiteral(7)..fileOffset = 42,
          ])),
        ]),
      ),
    ]);
    check(checkNoSharedNodes([lib]).isEmpty,
        'dois nós IGUAIS mas DISTINTOS passam (identidade, não `==`)');
  }

  print('');
  print('checkInvariants — ADR-0013 e alvos ligados:');
  {
    final lib = _lib([
      _fn(
        'main',
        k.Block([
          k.VariableDeclaration('x',
              type: const k.DynamicType(), initializer: k.NullLiteral())
            ..fileOffset = 10,
        ]),
      ),
    ]);
    final v = checkInvariants([lib]);
    check(v.any((x) => x.contains('ADR-0013')),
        '`dynamic` em VariableDeclaration é ACUSADO');
  }
  {
    final lib = _lib([
      _fn('main', k.Block([k.ExpressionStatement(k.NullLiteral())])),
    ]);
    check(checkInvariants([lib]).isEmpty, 'árvore sã passa (sem falso-positivo)');
  }

  print('');
  print('checkNoSyntheticClasses — CA10, custo zero:');
  {
    final cls = k.Class(name: 'Wrapper', fileUri: _uri);
    final lib = _lib([], classes: [cls]);
    check(checkNoSyntheticClasses([lib], {'Ponto'}).length == 1,
        'classe sem decl correspondente é ACUSADA');
    check(checkNoSyntheticClasses([lib], {'Wrapper'}).isEmpty,
        'classe DECLARADA passa');
  }
  {
    final v = k.Class(name: 'Forma\$circulo', fileUri: _uri);
    final lib = _lib([], classes: [v]);
    check(checkNoSyntheticClasses([lib], {'Forma'}).isEmpty,
        'subclasse de variante (`Forma\$circulo`) passa se `Forma` é declarado');
    check(checkNoSyntheticClasses([lib], {'Outro'}).length == 1,
        '`X\$y` com `X` NÃO declarado ainda é acusado (a régua segue fechada)');
  }
  {
    final lib = _lib([], classes: [k.Class(name: 'ItaPanic', fileUri: _uri)]);
    check(checkNoSyntheticClasses([lib], const {}).isEmpty,
        'classe de RUNTIME da allowlist passa');
  }

  print('');
  print('checkConformanceTraps — CA13, as 2 armadilhas do ADR-0017:');
  {
    // Armadilha 1: mixin. É lowering de *modular transformation* do CFE, que o
    // Itá BYPASSA — um `mixedInType` chegaria à VM sem ter sido achatado.
    final base = k.Class(name: 'M', fileUri: _uri);
    final cls = k.Class(name: 'C', fileUri: _uri)
      ..mixedInType = k.Supertype(base, const []);
    final lib = _lib([], classes: [base, cls]);
    final v = checkConformanceTraps([lib]);
    check(v.any((x) => x.contains('mixedInType')), 'mixin é ACUSADO');
  }
  {
    // Armadilha 2: `implements` sobre classe de `dart:core` — reabriria tipos
    // do platform. Simulado com uma lib de importUri `dart:core`.
    final coreLib = k.Library(Uri.parse('dart:core'), fileUri: _uri);
    final coreCls = k.Class(name: 'Comparable', fileUri: _uri);
    coreLib.addClass(coreCls);
    final cls = k.Class(
      name: 'Meu',
      fileUri: _uri,
      implementedTypes: [k.Supertype(coreCls, const [])],
    );
    final lib = _lib([], classes: [cls]);
    final v = checkConformanceTraps([lib]);
    check(v.any((x) => x.contains('dart:core')),
        '`implements` sobre `dart:core` é ACUSADO');
  }
  {
    // Conformance LEGÍTIMA (trait do usuário) passa — senão a regra seria um
    // `fail` disfarçado e o CA4 inteiro ficaria impossível.
    final trait = k.Class(name: 'Fala', isAbstract: true, fileUri: _uri);
    final cls = k.Class(
      name: 'Pato',
      fileUri: _uri,
      implementedTypes: [k.Supertype(trait, const [])],
    );
    final lib = _lib([], classes: [trait, cls]);
    check(checkConformanceTraps([lib]).isEmpty,
        'conformance a trait do USUÁRIO passa');
  }

  print(_fails == 0
      ? '\nInvariantes: TODOS OS CHECKS VERDES ✅'
      : '\nInvariantes: $_fails CHECK(S) VERMELHO(S) ❌');
  if (_fails > 0) throw StateError('$_fails checks falharam');
}
