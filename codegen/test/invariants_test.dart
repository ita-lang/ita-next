// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
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
// nó com dois pais:** o verify é **opt-in NOSSO** — a VM não o roda. Provado
// empiricamente (2026-07-29): com o verify DESLIGADO e um `InstanceGet` reusado
// nas duas pontas de um range, o `.dill` foi gerado, **rodou, e imprimiu a saída
// CORRETA** — nenhuma outra camada percebeu. O invariante era a única defesa.
//
// 🔴 A justificativa aqui dizia também *"`verifyComponent` não tem chamador em
// todo o `pkg/`"*. Era ALUCINAÇÃO (há 5). A prova empírica acima continua de pé
// — ela foi feita com o verify desligado —, mas o argumento que a acompanhava
// não era verificável. Ver `invariants.dart`.

import 'package:kernel/ast.dart' as k;
import 'package:kernel/kernel.dart' show loadComponentFromBinary;

import 'package:ita_next_codegen/compile.dart' show platformDillPath;
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
  {
    // ------------------------------------------------------------------------
    // Os SEIS sítios que a LISTA-BRANCA não olhava (até 2026-07-29).
    // ------------------------------------------------------------------------
    //
    // Cada um destes punha `dynamic` REAL no `.dill` com o invariante VERDE, e
    // o `ConstantExpression` não era hipótese: acontecia em TODO default de
    // parâmetro, e o `default_saltavel.tu` imprimia o golden CERTO com 6
    // violações dentro. A regra agora é UM `visitDynamicType`, e o que este
    // bloco prova é que ela alcança o que 5 overrides à mão não alcançavam.
    //
    // Se um dia alguém trocar o override por sítios explícitos de novo, é aqui
    // que o RED aparece.
    final caixa = k.Class(name: 'Caixa', fileUri: _uri);
    final tipoCaixa = k.InterfaceType(caixa, k.Nullability.nonNullable);
    final campo = k.Field.immutable(k.Name('x'),
        type: tipoCaixa, fileUri: _uri)
      ..fileOffset = 20;
    caixa.addField(campo);
    final metodo = k.Procedure(
      k.Name('m'),
      k.ProcedureKind.Method,
      k.FunctionNode(k.Block([]), returnType: const k.VoidType()),
      fileUri: _uri,
    );
    caixa.addProcedure(metodo);

    final sitios = <String, k.Expression>{
      // 1. o construtor tem `[this.type = const DynamicType()]` por default
      'ConstantExpression': k.ConstantExpression(k.IntConstant(1)),
      'AsExpression': k.AsExpression(k.NullLiteral(), const k.DynamicType()),
      'IsExpression': k.IsExpression(k.NullLiteral(), const k.DynamicType()),
      'InstanceGet.resultType': k.InstanceGet(
        k.InstanceAccessKind.Instance,
        k.NullLiteral(),
        k.Name('x'),
        resultType: const k.DynamicType(),
        interfaceTarget: campo,
      ),
      'InstanceInvocation.functionType': k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        k.NullLiteral(),
        k.Name('m'),
        k.Arguments([]),
        interfaceTarget: metodo,
        functionType: k.FunctionType(
            const [], const k.DynamicType(), k.Nullability.nonNullable),
      ),
    };
    for (final e in sitios.entries) {
      final lib = _lib(
        [_fn('main', k.Block([k.ExpressionStatement(e.value)]))],
        classes: [caixa],
      );
      final v = checkInvariants([lib]);
      check(v.any((x) => x.contains('ADR-0013') && x.contains('dynamic')),
          '`dynamic` em ${e.key} é ACUSADO');
    }
    {
      // 6. `namedParameters` — o furo mais caro dos seis, porque o Itá baixa
      // TUDO como named required (ruling spec 013 §12-3): o `_hasDynamic`
      // antigo olhava `returnType` e `positionalParameters`, e não a única
      // espécie de parâmetro que a linguagem produz.
      final lib = _lib([
        _fn(
          'main',
          k.Block([
            k.VariableDeclaration('f',
                type: k.FunctionType(
                  const [],
                  const k.VoidType(),
                  k.Nullability.nonNullable,
                  namedParameters: [
                    k.NamedType('p', const k.DynamicType(), isRequired: true),
                  ],
                ),
                initializer: k.NullLiteral())
              ..fileOffset = 30,
          ]),
        ),
      ]);
      check(checkInvariants([lib]).any((x) => x.contains('ADR-0013')),
          '`dynamic` em FunctionType.namedParameters é ACUSADO');
    }
    {
      // E o outro lado: um `ConstantExpression` TIPADO passa. Sem este caso a
      // regra poderia estar acusando todo default e os testes acima passariam.
      final lib = _lib([
        _fn(
          'main',
          k.Block([
            k.ExpressionStatement(
                k.ConstantExpression(k.IntConstant(1), tipoCaixa)),
          ]),
        ),
      ], classes: [caixa]);
      check(checkInvariants([lib]).isEmpty,
          'ConstantExpression TIPADO passa (o conserto, não a acusação)');
    }
  }
  {
    // A violação tem de ser ACIONÁVEL: um `DynamicType` é `const` e canônico —
    // a mesma instância em todo o programa —, então quem dá o endereço é o
    // caminho até ele, não o nó.
    final lib = _lib([
      _fn(
        'alvo',
        k.Block([
          k.VariableDeclaration('porta',
              type: const k.VoidType(),
              initializer: k.ConstantExpression(k.IntConstant(8080)))
            ..fileOffset = 1455,
        ]),
      ),
    ]);
    final v = checkInvariants([lib]);
    check(v.length == 1 && v.first.contains('porta'),
        'a violação nomeia o BINDER (`porta`), não só o tipo do nó');
    check(v.isNotEmpty && v.first.contains('ConstantExpression'),
        'a violação nomeia o SÍTIO (`ConstantExpression`)');
    check(v.isNotEmpty && v.first.contains('1455'),
        'a violação nomeia o OFFSET, para achá-lo na fonte');
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

  print('');
  print('checkTypeConsistency — o TIPO do receptor autoriza o alvo:');
  {
    // ------------------------------------------------------------------------
    // O RED do bug 4, sintético — e ele PRECISA ser sintético.
    // ------------------------------------------------------------------------
    //
    // No corpus não cabe: um `.tu` que produza `interfaceTarget` errado teria de
    // vir de um emitter defeituoso, e o emitter corrigido não o produz mais. O
    // fixture `match_produto.tu` prova o caminho CERTO; este prova que a régua
    // ainda acusa o ERRADO. Sem os dois, o gate poderia virar `return []` e
    // ninguém notaria.
    //
    // Precisa do platform: o `NaiveTypeChecker` monta `CoreTypes(component)` e
    // uma `ClassHierarchy`, que resolvem `dart:core`.
    final platform = loadComponentFromBinary(platformDillPath());

    k.Class comCampo(String nome, String campo) {
      final cls = k.Class(
        name: nome,
        fileUri: _uri,
        supertype: k.Supertype(
          platform.libraries
              .firstWhere((l) => l.importUri.toString() == 'dart:core')
              .classes
              .firstWhere((c) => c.name == 'Object'),
          const [],
        ),
      );
      cls.addField(k.Field.immutable(k.Name(campo),
          type: const k.VoidType(), fileUri: _uri));
      return cls;
    }

    final ponto = comCampo('Ponto', 'x');
    final caixa = comCampo('Caixa', 'x'); // MESMO nome de campo — o ponto todo
    final campoErrado = caixa.fields.single;

    // `Ponto().x` com `interfaceTarget` de `Caixa.x`. Passa no `verifyComponent`
    // (que só confere `name == interfaceTarget.name`), passa no LOAD, e roda
    // certo no JIT — o dispatch é por selector. Só quebra em AOT.
    final lib = _lib([
      _fn(
        'main',
        k.Block([
          k.ExpressionStatement(k.InstanceGet(
            k.InstanceAccessKind.Instance,
            k.ConstructorInvocation(
              k.Constructor(
                k.FunctionNode(k.EmptyStatement(),
                    returnType: const k.VoidType()),
                name: k.Name(''),
                fileUri: _uri,
              )..parent = ponto,
              k.Arguments([]),
            ),
            k.Name('x'),
            interfaceTarget: campoErrado,
            resultType: const k.VoidType(),
          )),
        ]),
      ),
    ], classes: [ponto, caixa]);

    platform.libraries.add(lib);
    platform.adoptChildren();
    platform.computeCanonicalNames();

    final v = checkTypeConsistency(platform);
    check(v.any((x) => x.contains('not accessible')),
        'alvo da CLASSE ERRADA é ACUSADO (o bug 4, que o verify não pega)');
    check(v.any((x) => x.contains('Caixa') && x.contains('Ponto')),
        'a violação nomeia as DUAS classes (alvo e receptor)');
  }

  print('');
  print('checkNumericStaticTypes — o Itá não tem `num`:');
  {
    // O RED do bug 7. O `NaiveTypeChecker` NÃO pega este caso — ele ignora o
    // `functionType` justamente nos operadores especializados
    // (`type_checker.dart:1427`) —, então esta régua é a única defesa.
    final platform = loadComponentFromBinary(platformDillPath());
    final num_ = platform.libraries
        .firstWhere((l) => l.importUri.toString() == 'dart:core')
        .classes
        .firstWhere((c) => c.name == 'num');
    final mais = num_.procedures.firstWhere((p) => p.name.text == '+');

    k.Library comRetorno(k.DartType ret) => _lib([
          _fn(
            'main',
            k.Block([
              k.ExpressionStatement(k.InstanceInvocation(
                k.InstanceAccessKind.Instance,
                k.IntLiteral(1),
                mais.name,
                k.Arguments([k.IntLiteral(2)]),
                interfaceTarget: mais,
                functionType: k.FunctionType(
                  [k.InterfaceType(num_, k.Nullability.nonNullable)],
                  ret,
                  k.Nullability.nonNullable,
                ),
              )..fileOffset = 77),
            ]),
          ),
        ]);

    // A assinatura CRUA de `num::+` é `num Function(num)` — é exatamente o que
    // `computeFunctionType` devolvia, e o que punha `num` no `.dill`.
    final cru = comRetorno(k.InterfaceType(num_, k.Nullability.nonNullable));
    final v = checkNumericStaticTypes([cru]);
    check(v.length == 1, '`Int + Int : num` é ACUSADO (${v.length} violação)');
    check(v.isNotEmpty && v.first.contains('77'),
        'a violação nomeia o OFFSET');

    final int_ = platform.libraries
        .firstWhere((l) => l.importUri.toString() == 'dart:core')
        .classes
        .firstWhere((c) => c.name == 'int');
    final especializado =
        comRetorno(k.InterfaceType(int_, k.Nullability.nonNullable));
    check(checkNumericStaticTypes([especializado]).isEmpty,
        '`Int + Int : int` passa (a régua não é um `fail` disfarçado)');
  }

  print('');
  print('checkOrderIndependence — ordem textual não importa:');
  {
    // ------------------------------------------------------------------------
    // O RED que parecia impossível — e a razão de a régua receber o emissor.
    // ------------------------------------------------------------------------
    //
    // Provar que este gate ACUSA exigiria um emitter com o defeito, e o emitter
    // está corrigido. Guardar um mutante versionado apodrece; injetar falha no
    // caminho de produção é pior. A saída é injetar o EMISSOR: a régua chama o
    // que lhe derem, o runner dá o `emitProgram` real, e aqui se dá um dublê
    // que só falha sob ordem revertida — exatamente o que o emitter antigo
    // fazia. O gate deixa de provar a si mesmo por fé.
    final decls = ['A', 'B', 'C'];

    // Dublê fiel ao bug 5: só sabe emitir se `A` vier primeiro. Era esta a
    // forma do emitter até 2026-07-29 — a `Class` era registrada depois dos
    // campos, então toda aresta apontando "para a frente" ICEava.
    List<Violation> comEmissorSensivelAOrdem() => checkOrderIndependence(
          decls,
          () {
            if (decls.first != 'A') {
              throw StateError('ice-codegen-type-unemitted-struct');
            }
          },
        );

    final v = comEmissorSensivelAOrdem();
    check(v.length == 1, 'emissor sensível à ordem é ACUSADO (${v.length})');
    check(v.isNotEmpty && v.first.contains('unemitted'),
        'a violação carrega a falha do emissor (o ICE que ele deu)');
    check(decls.first == 'A' && decls.last == 'C',
        'a lista é RESTAURADA mesmo quando a régua acusa');

    // Emissor indiferente à ordem — o que se espera do emitter corrigido.
    check(checkOrderIndependence(decls, () {}).isEmpty,
        'emissor indiferente à ordem passa (não é `fail` disfarçado)');

    // Anti-vacuidade: lista IMUTÁVEL não pode dar verde. É o modo de falha que
    // deixaria o gate acumulando tick sem cobertura nenhuma.
    final imutavel = List<String>.unmodifiable(['A', 'B']);
    final vac = checkOrderIndependence(imutavel, () {});
    check(vac.length == 1 && vac.first.contains('não testou nada'),
        'lista IMUTÁVEL é acusada como vacuosa, não aprovada em silêncio');

    // Lista de 1 elemento não tem ordem para variar — passa sem alarde, senão
    // todo fixture de uma declaração só viraria falso-positivo.
    check(checkOrderIndependence(['A'], () {}).isEmpty,
        'lista de 1 elemento passa (não há ordem a testar)');
  }

  print('');
  print('checkSerializedLibraries — só as libs do PROGRAMA no `.dill`:');
  {
    // Esta régua nunca teve RED — ficou 3 dias no golden-runner sem que nada
    // provasse que ela acusa. Um invariante que nunca acusa é indistinguível de
    // um invariante quebrado, e é a premissa deste arquivo inteiro.
    final comPlatform = k.Component(libraries: [
      k.Library(Uri.parse('dart:core'), fileUri: _uri),
      k.Library(Uri.parse('app:///main.dart'), fileUri: _uri),
    ]);
    final v = checkSerializedLibraries(comPlatform);
    check(v.length == 1, 'lib do platform no `.dill` é ACUSADA');
    check(v.isNotEmpty && v.first.contains('dart:core'),
        'a violação nomeia a lib intrusa');

    final soPrograma = k.Component(
        libraries: [k.Library(Uri.parse('app:///main.dart'), fileUri: _uri)]);
    check(checkSerializedLibraries(soPrograma).isEmpty,
        '`.dill` só com o programa passa');
  }

  print(_fails == 0
      ? '\nInvariantes: TODOS OS CHECKS VERDES ✅'
      : '\nInvariantes: $_fails CHECK(S) VERMELHO(S) ❌');
  if (_fails > 0) throw StateError('$_fails checks falharam');
}
