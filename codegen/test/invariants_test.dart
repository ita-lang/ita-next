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

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:ita_next_codegen/compile.dart' show platformDillPath;
import 'package:ita_next_codegen/invariants.dart';
import 'harness.dart';

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
  final h = Harness('Invariantes');
  print('harness — o botão de vermelho funciona?');
  h.selfTest();
  print('');

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
    h.check(v.length == 1, 'nó em dois pais é ACUSADO (${v.length} violação)');
    h.check(v.isNotEmpty && v.first.contains('IntLiteral'),
        'a mensagem nomeia o TIPO do nó compartilhado');
    h.check(v.isNotEmpty && v.first.contains('42'),
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
    h.check(checkNoSharedNodes([lib]).isEmpty,
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
    h.check(v.any((x) => x.contains('ADR-0013')),
        '`dynamic` em VariableDeclaration é ACUSADO');
  }
  {
    final lib = _lib([
      _fn('main', k.Block([k.ExpressionStatement(k.NullLiteral())])),
    ]);
    h.check(checkInvariants([lib]).isEmpty, 'árvore sã passa (sem falso-positivo)');
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
      h.check(v.any((x) => x.contains('ADR-0013') && x.contains('dynamic')),
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
      h.check(checkInvariants([lib]).any((x) => x.contains('ADR-0013')),
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
      h.check(checkInvariants([lib]).isEmpty,
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
    h.check(v.length == 1 && v.first.contains('porta'),
        'a violação nomeia o BINDER (`porta`), não só o tipo do nó');
    h.check(v.isNotEmpty && v.first.contains('ConstantExpression'),
        'a violação nomeia o SÍTIO (`ConstantExpression`)');
    h.check(v.isNotEmpty && v.first.contains('1455'),
        'a violação nomeia o OFFSET, para achá-lo na fonte');
  }

  print('');
  print('checkNoSyntheticClasses — CA10, custo zero:');
  {
    final cls = k.Class(name: 'Wrapper', fileUri: _uri);
    final lib = _lib([], classes: [cls]);
    h.check(checkNoSyntheticClasses([lib], {'Ponto'}).length == 1,
        'classe sem decl correspondente é ACUSADA');
    h.check(checkNoSyntheticClasses([lib], {'Wrapper'}).isEmpty,
        'classe DECLARADA passa');
  }
  {
    final v = k.Class(name: 'Forma\$circulo', fileUri: _uri);
    final lib = _lib([], classes: [v]);
    h.check(checkNoSyntheticClasses([lib], {'Forma'}).isEmpty,
        'subclasse de variante (`Forma\$circulo`) passa se `Forma` é declarado');
    h.check(checkNoSyntheticClasses([lib], {'Outro'}).length == 1,
        '`X\$y` com `X` NÃO declarado ainda é acusado (a régua segue fechada)');
  }
  {
    final lib = _lib([], classes: [k.Class(name: 'ItaPanic', fileUri: _uri)]);
    h.check(checkNoSyntheticClasses([lib], const {}).isEmpty,
        'classe de RUNTIME da allowlist passa');
  }

  print('');
  print('checkExistentialZeroNode — CA11, travessia `any` de fonte local:');
  {
    // O corpus REAL não tem como produzir um box: a fronteira do ADR-0017 §3(a)
    // é o não-objetivo 2 desta spec — *"Box de built-in em fronteira `any` →
    // M5"* —, e a F5 recusa antes com `conformance-on-builtin-unsupported`.
    // Então o defeituoso é construído À MÃO. Sem isso a régua não teria como
    // ficar vermelha, e um gate que só se viu verde é indistinguível de um gate
    // removido.
    final pato = ast.StructDecl(false, 'Pato', [], [], [], 0, 4);
    final fala = ast.TraitDecl(false, 'Fala', [], [], 0, 4);
    final fonte = NamedType(pato, TypeKind.struct_);
    final alvo = NamedType(fala, TypeKind.trait_);

    // DOIS sítios, porque a régua olha a forma que o AST daquele sítio produz:
    // `p` é um `Ident` (emite `VariableGet`), `Pato(...)` é um `Call` (emite
    // `ConstructorInvocation`). O que é legítimo num é interposição no outro.
    final sitio = ast.Ident('p', 42, 1);
    final sitioCall = ast.Call(ast.Ident('Pato', 60, 4), [], 64, 60, 11);
    final coercions = {
      sitio: CoercionInfo(fonte, alvo),
      sitioCall: CoercionInfo(fonte, alvo),
    };

    final patoCls = k.Class(name: 'Pato', fileUri: _uri);
    final patoCtor = k.Constructor(k.FunctionNode(k.EmptyStatement()),
        name: k.Name(''), fileUri: _uri);
    patoCls.addConstructor(patoCtor);
    final daFonte = {patoCls};

    // (1) O BOX do ADR-0017 §3(a): `Fala$Pato(p)` no sítio da travessia — mesma
    // FORMA que o `Call` legítimo teria, e só a classe o denuncia.
    final boxCls = k.Class(name: 'Fala\$Pato', fileUri: _uri);
    final boxCtor = k.Constructor(k.FunctionNode(k.EmptyStatement()),
        name: k.Name(''), fileUri: _uri);
    boxCls.addConstructor(boxCtor);
    final comBox = checkExistentialZeroNode(
      {
        sitioCall: (
          no: k.ConstructorInvocation(boxCtor, k.Arguments([])),
          classesDaFonte: daFonte,
        )
      },
      coercions,
    );
    h.check(comBox.violations.length == 1, 'BOX na travessia é ACUSADO');
    h.check(comBox.violations.first.contains('60'),
        'a violação nomeia o OFFSET do sítio, para achá-lo na fonte');

    // (2) A metade da FORMA — tudo que ENVOLVE a expressão. Os três primeiros
    // são exatamente os que o `default: continue` da primeira versão desta régua
    // aprovava em silêncio, enquanto a prosa dizia cobri-los.
    final interpostos = <String, k.Expression>{
      'cast': k.AsExpression(
          k.NullLiteral(), k.InterfaceType(boxCls, k.Nullability.nonNullable)),
      'teste de runtime': k.IsExpression(
          k.NullLiteral(), k.InterfaceType(boxCls, k.Nullability.nonNullable)),
      'helper static': k.StaticInvocation(
          _helperDeBox(), k.Arguments([])),
      'Let com temporário': () {
        final tmp = k.VariableDeclaration('tmp', initializer: k.NullLiteral());
        return k.Let(tmp, k.VariableGet(tmp));
      }(),
      'BlockExpression': k.BlockExpression(k.Block([]), k.NullLiteral()),
    };
    for (final e in interpostos.entries) {
      final r = checkExistentialZeroNode(
        {sitio: (no: e.value, classesDaFonte: daFonte)},
        coercions,
      );
      h.check(r.violations.length == 1,
          'INTERPOSTO (${e.key}) sobre um `Ident` é ACUSADO');
    }

    // (3) A régua NÃO é um `fail` disfarçado: a construção do PRÓPRIO tipo-fonte
    // no sítio é a expressão, não um box. `ouve(Pato(nome: "x"))` é legal.
    h.check(
        checkExistentialZeroNode(
          {
            sitioCall: (
              no: k.ConstructorInvocation(patoCtor, k.Arguments([])),
              classesDaFonte: daFonte,
            )
          },
          coercions,
        ).violations.isEmpty,
        'construir o PRÓPRIO tipo-fonte no sítio PASSA (não é box)');

    // (4) Leitura de variável — o caso comum, e o que o corpus exercita.
    h.check(
        checkExistentialZeroNode(
          {
            sitio: (
              no: k.VariableGet(k.VariableDeclaration('p')),
              classesDaFonte: daFonte,
            )
          },
          coercions,
        ).violations.isEmpty,
        '`VariableGet` no sítio PASSA — é o upcast grátis');

    // (5) A identidade é por `k.Class`, NÃO por nome (R1). Uma classe HOMÔNIMA
    // da fonte é outra classe, e passar aqui seria a redecisão com chave mais
    // fraca que fez 5 dos 8 bugs de 2026-07-29.
    final homonima = k.Class(name: 'Pato', fileUri: _uri);
    final homCtor = k.Constructor(k.FunctionNode(k.EmptyStatement()),
        name: k.Name(''), fileUri: _uri);
    homonima.addConstructor(homCtor);
    h.check(
        checkExistentialZeroNode(
          {
            sitioCall: (
              no: k.ConstructorInvocation(homCtor, k.Arguments([])),
              classesDaFonte: daFonte,
            )
          },
          coercions,
        ).violations.length ==
            1,
        'classe HOMÔNIMA da fonte é ACUSADA — a chave é identidade, não lexema');

    // (6) Kind de AST que o mapa não conhece reprova VERMELHO (R5). `ListExpr`
    // hoje não chega ao emitter (desugar), e é justamente o caso: fatia nova
    // reprova até declarar a forma que emite.
    final sitioDesconhecido = ast.ListExpr([], 80, 2);
    h.check(
        checkExistentialZeroNode(
          {
            sitioDesconhecido: (
              no: k.VariableGet(k.VariableDeclaration('p')),
              classesDaFonte: daFonte,
            )
          },
          {sitioDesconhecido: CoercionInfo(fonte, alvo)},
        ).violations.length ==
            1,
        'kind de AST fora do mapa é ACUSADO (falha FECHADA, não silêncio)');

    // (7) Anti-vacuidade (R12): a régua DIZ quantos sítios viu. Sem este número
    // o runner não teria como distinguir "nenhuma violação" de "nada a violar",
    // e apagar a travessia de todos os fixtures deixaria o CA11 verde.
    h.check(checkExistentialZeroNode(const {}, const {}).exercitou == 0,
        'corpus sem travessia ⟹ `exercitou == 0` (não conta como prova)');
    h.check(comBox.exercitou == 1, 'um sítio inspecionado ⟹ `exercitou == 1`');

    // (8) Sítio registrado que a nº7 não marcou é bug NOSSO de propagação —
    // e cala se não for acusado.
    h.check(
        checkExistentialZeroNode(
          {
            sitio: (
              no: k.VariableGet(k.VariableDeclaration('p')),
              classesDaFonte: daFonte,
            )
          },
          const {},
        ).violations.length ==
            1,
        'travessia sem entrada na nº7 é ACUSADA (não silenciada)');

    // (9) As quatro guardas dizem quatro frases distintas (R13) — duas guardas
    // com a mesma mensagem são indistinguíveis no relatório E na asserção.
    final prefixos = {
      comBox.violations.first.split(':').first,
      checkExistentialZeroNode(
              {sitio: (no: interpostos['cast']!, classesDaFonte: daFonte)},
              coercions)
          .violations
          .first
          .split(':')
          .first,
      checkExistentialZeroNode(
              {
                sitioDesconhecido: (
                  no: k.VariableGet(k.VariableDeclaration('p')),
                  classesDaFonte: daFonte,
                )
              },
              {sitioDesconhecido: CoercionInfo(fonte, alvo)})
          .violations
          .first
          .split(':')
          .first,
      checkExistentialZeroNode(
              {
                sitio: (
                  no: k.VariableGet(k.VariableDeclaration('p')),
                  classesDaFonte: daFonte,
                )
              },
              const {})
          .violations
          .first
          .split(':')
          .first,
    };
    h.check(prefixos.length == 4,
        'as 4 guardas do CA11 dizem 4 frases distintas, uma cada (R13)');
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
    h.check(v.any((x) => x.contains('mixedInType')), 'mixin é ACUSADO');
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
    h.check(v.any((x) => x.contains('dart:core')),
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
    h.check(checkConformanceTraps([lib]).isEmpty,
        'conformance a trait do USUÁRIO passa');
  }

  print('');
  print('checkInvariants — os SEIS ramos que nunca haviam acusado:');
  {
    // ------------------------------------------------------------------------
    // Cobertura medida em 2026-07-29: estes seis ramos tinham ZERO hits nas 5
    // suítes. O corpus não produz `DynamicInvocation`/`DynamicGet`/`DynamicSet`
    // (bom) nem alvo desligado (bom) — então a ACUSAÇÃO deles nunca rodou, e um
    // `return` acidental dentro de qualquer um passaria despercebido para
    // sempre. Régua que nunca acusa é indistinguível de régua removida.
    // ------------------------------------------------------------------------
    final alvo = k.Class(name: 'Alvo', fileUri: _uri);
    final metodo = k.Procedure(
      k.Name('m'),
      k.ProcedureKind.Method,
      k.FunctionNode(k.Block([]), returnType: const k.VoidType()),
      fileUri: _uri,
    );
    alvo.addProcedure(metodo);

    final dinamicos = <String, k.Expression>{
      'DynamicInvocation': k.DynamicInvocation(
        k.DynamicAccessKind.Dynamic,
        k.NullLiteral(),
        k.Name('m'),
        k.Arguments([]),
      )..fileOffset = 11,
      'DynamicGet': k.DynamicGet(
        k.DynamicAccessKind.Dynamic,
        k.NullLiteral(),
        k.Name('x'),
      )..fileOffset = 12,
      'DynamicSet': k.DynamicSet(
        k.DynamicAccessKind.Dynamic,
        k.NullLiteral(),
        k.Name('x'),
        k.NullLiteral(),
      )..fileOffset = 13,
    };
    for (final e in dinamicos.entries) {
      final lib = _lib(
        [_fn('main', k.Block([k.ExpressionStatement(e.value)]))],
        classes: [alvo],
      );
      final v = checkInvariants([lib]);
      h.check(v.any((x) => x.contains(e.key)),
          '`${e.key}` é ACUSADO (ADR-0013: faltou interfaceTarget)');
    }

    // `interfaceTarget`/`target` DESLIGADO. `k.Reference()` sem nó é
    // exatamente o que o Kernel deixa passar e a VM converte em dispatch
    // dinâmico — imprime o mesmo e envenena a TFA.
    {
      final lib = _lib([
        _fn(
          'main',
          k.Block([
            k.ExpressionStatement(k.InstanceInvocation(
              k.InstanceAccessKind.Instance,
              k.NullLiteral(),
              k.Name('m'),
              k.Arguments([]),
              interfaceTarget: metodo,
              functionType: k.FunctionType(
                  const [], const k.VoidType(), k.Nullability.nonNullable),
            )
              ..interfaceTargetReference = k.Reference()
              ..fileOffset = 14),
          ]),
        ),
      ], classes: [alvo]);
      h.check(
          checkInvariants([lib])
              .any((x) => x.contains('sem interfaceTarget ligado')),
          '`InstanceInvocation` com alvo DESLIGADO é ACUSADO');
    }
    {
      final lib = _lib([
        _fn(
          'main',
          k.Block([
            k.ExpressionStatement(
                k.StaticInvocation.byReference(k.Reference(), k.Arguments([]))
                  ..fileOffset = 15),
          ]),
        ),
      ], classes: [alvo]);
      h.check(
          checkInvariants([lib]).any((x) => x.contains('sem target ligado')),
          '`StaticInvocation` com target DESLIGADO é ACUSADO');
    }
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
    h.check(v.any((x) => x.contains('not accessible')),
        'alvo da CLASSE ERRADA é ACUSADO (o bug 4, que o verify não pega)');
    h.check(v.any((x) => x.contains('Caixa') && x.contains('Ponto')),
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
    h.check(v.length == 1, '`Int + Int : num` é ACUSADO (${v.length} violação)');
    h.check(v.isNotEmpty && v.first.contains('77'),
        'a violação nomeia o OFFSET');

    final int_ = platform.libraries
        .firstWhere((l) => l.importUri.toString() == 'dart:core')
        .classes
        .firstWhere((c) => c.name == 'int');
    final especializado =
        comRetorno(k.InterfaceType(int_, k.Nullability.nonNullable));
    h.check(checkNumericStaticTypes([especializado]).isEmpty,
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
    final v = checkOrderIndependence(decls, () {
      if (decls.first != 'A') {
        throw StateError('ice-codegen-type-unemitted-struct');
      }
    });
    h.check(v.violations.length == 1,
        'emissor sensível à ordem é ACUSADO (${v.violations.length})');
    h.check(v.violations.isNotEmpty && v.violations.first.contains('unemitted'),
        'a violação carrega a falha do emissor (o ICE que ele deu)');
    h.check(decls.first == 'A' && decls.last == 'C',
        'a lista é RESTAURADA mesmo quando a régua acusa');

    // Emissor indiferente à ordem — o que se espera do emitter corrigido.
    final ok = checkOrderIndependence(decls, () {});
    h.check(ok.violations.isEmpty && ok.exercitou,
        'emissor indiferente à ordem passa E conta como exercitado');

    // ------------------------------------------------------------------------
    // As DUAS vacuidades, e por que precisam de mensagens distintas.
    // ------------------------------------------------------------------------
    //
    // Até 2026-07-29 as duas diziam "não testou nada", e o RED assertava
    // `contains('não testou nada')`. Resultado: o teste atingia SEMPRE a A, a
    // guarda B ficou INALCANÇÁVEL por dias, e o relatório dizia verde. Asserção
    // não-discriminante mantém caminho morto vivo — foi o mutante M7.

    // A: a lista nem aceita escrita.
    final vacA = checkOrderIndependence(List<String>.unmodifiable(['A', 'B']), () {});
    h.check(vacA.violations.length == 1 && vacA.violations.first.contains('vacuidade-A'),
        'lista IMUTÁVEL ⟹ vacuidade-A (a reversão nem aconteceu)');
    h.check(!vacA.exercitou, 'vacuidade-A não conta como exercitada');

    // B: a escrita funciona e a ordem NÃO MUDA — elementos idênticos. Este
    // caminho existia e nunca havia sido percorrido por teste nenhum.
    final mesmo = Object();
    final vacB = checkOrderIndependence([mesmo, mesmo], () {});
    h.check(vacB.violations.length == 1 && vacB.violations.first.contains('vacuidade-B'),
        'reversão SEM EFEITO ⟹ vacuidade-B (o caminho que estava morto)');
    h.check(!vacB.exercitou, 'vacuidade-B não conta como exercitada');

    // Lista de 1 elemento: não é violação — não há ordem a testar. Mas também
    // NÃO conta como exercício, senão 11 fixtures do corpus provariam o letrec
    // sem ter o que permutar.
    final um = checkOrderIndependence(['A'], () {});
    h.check(um.violations.isEmpty && !um.exercitou,
        'lista de 1 elemento passa, mas NÃO conta como exercitada');
  }

  print('');
  print('checkBreakTargets — labels não atravessam fronteira de função:');
  {
    // ------------------------------------------------------------------------
    // RED **SINTÉTICO, e tem de ser** — nenhum `.tu` legal chega aqui.
    // ------------------------------------------------------------------------
    //
    // A F4 já barra `break` dentro de closure (`resolver.dart` zera `_inLoop`
    // em fronteira de função), e o emitter salva/zera o `_loops` no `_closure`.
    // Logo o estado que este invariante persegue só se constrói à mão — que é a
    // mesma alavanca do RED do bug 4, e a resposta à R10: quando o RED parece
    // impossível, injete a dependência ou construa o defeituoso.
    //
    // O que ele pega, se algum caminho novo de emissão esquecer a disciplina:
    // um `BreakStatement` cujo `LabeledStatement` alvo vive em OUTRO
    // `FunctionNode`. Isso mata a SERIALIZAÇÃO (o `BinaryPrinter` zera o
    // `_labelIndexer` por função e depois faz `!`), não o verify — que não tem
    // `visitBreakStatement` nenhum.
    final alvoExterno = k.LabeledStatement(k.EmptyStatement())..fileOffset = 55;

    // `main() { L: { ... (){ break L; } ... } }` — o break vive DENTRO de uma
    // closure e aponta para o label de fora dela.
    final quebrado = _lib([
      _fn(
        'main',
        k.Block([
          alvoExterno
            ..body = k.Block([
              k.ExpressionStatement(k.FunctionExpression(
                k.FunctionNode(
                  k.Block([k.BreakStatement(alvoExterno)..fileOffset = 60]),
                  returnType: const k.VoidType(),
                ),
              )),
            ]),
        ]),
      ),
    ]);
    final v = checkBreakTargets([quebrado]);
    h.check(v.length == 1,
        'break cruzando fronteira de função é ACUSADO (${v.length})');
    h.check(v.isNotEmpty && v.first.contains('não atravessam fronteira'),
        'a violação diz POR QUE, não só que');

    // Contraponto 1: o mesmo `break`, sem a closure no meio — legítimo.
    final alvoOk = k.LabeledStatement(k.EmptyStatement())..fileOffset = 70;
    final sao = _lib([
      _fn(
        'main',
        k.Block([
          alvoOk..body = k.Block([k.BreakStatement(alvoOk)..fileOffset = 71]),
        ]),
      ),
    ]);
    h.check(checkBreakTargets([sao]).isEmpty,
        'break para label que o ENVOLVE passa (não é `fail` disfarçado)');

    // Contraponto 2: label IRMÃO já fechado não vale — se o escopo só
    // acumulasse sem remover, este caso passaria em silêncio.
    final irmao = k.LabeledStatement(k.EmptyStatement())..fileOffset = 80;
    final depois = k.LabeledStatement(k.EmptyStatement())..fileOffset = 81;
    final fora = _lib([
      _fn(
        'main',
        k.Block([
          irmao..body = k.EmptyStatement(),
          depois..body = k.Block([k.BreakStatement(irmao)..fileOffset = 82]),
        ]),
      ),
    ]);
    h.check(checkBreakTargets([fora]).length == 1,
        'break para label IRMÃO (já fechado) é ACUSADO');
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
    h.check(v.length == 1, 'lib do platform no `.dill` é ACUSADA');
    h.check(v.isNotEmpty && v.first.contains('dart:core'),
        'a violação nomeia a lib intrusa');

    final soPrograma = k.Component(
        libraries: [k.Library(Uri.parse('app:///main.dart'), fileUri: _uri)]);
    h.check(checkSerializedLibraries(soPrograma).isEmpty,
        '`.dill` só com o programa passa');
  }

  print('');
  print('checkSourcesRegistered — a `Source` que o alvo AOT exige:');
  {
    // R5: gate novo nasce com o RED que ele efetivamente pega — e este entrou no
    // golden-runner sem um, repetindo o erro documentado três blocos acima.
    //
    // As três causas têm mensagem distinta (R13) porque o conserto de cada uma é
    // outro: `fileUri` vazia é o emitter; ausência no mapa é o caller que não
    // passou `sources:`; lineStarts vazio é fonte registrada sem conteúdo.
    final lib = k.Library(Uri.parse('app:///main.dart'), fileUri: _uri);

    final semEntrada = k.Component(libraries: [lib]);
    final v = checkSourcesRegistered(semEntrada, [lib]);
    h.check(v.length == 1, 'lib fora de `uriToSource` é ACUSADA');
    h.check(v.isNotEmpty && v.first.contains('DWARF'),
        'a violação nomeia o alvo que MORRE (AOT), não o que degrada (JIT)');

    final semLineStarts = k.Component(libraries: [lib])
      ..uriToSource[_uri] =
          k.Source.emptySource(const <int>[], lib.importUri, _uri);
    h.check(checkSourcesRegistered(semLineStarts, [lib]).length == 1,
        'fonte registrada SEM lineStarts é ACUSADA (o span que o CA9 pede)');

    final vazia =
        k.Library(Uri.parse('app:///vazio.dart'), fileUri: Uri.parse(''));
    h.check(
        checkSourcesRegistered(k.Component(libraries: [vazia]), [vazia])
                .length ==
            1,
        '`fileUri` VAZIA é ACUSADA (é ela que vira o `uri_cstr` do dwarf)');

    final ok = k.Component(libraries: [lib])
      ..uriToSource[_uri] =
          k.Source.emptySource(const <int>[0], lib.importUri, _uri);
    h.check(checkSourcesRegistered(ok, [lib]).isEmpty,
        'lib com `Source` e lineStarts não-vazio PASSA');
  }

  h.finish();
}

/// Um `Procedure` static plausível como helper de box — o wrapper SEM classe
/// nova, que é o caso que o CA10 não vê e que o `default: continue` da primeira
/// versão do CA11 aprovava em silêncio.
k.Procedure _helperDeBox() {
  final lib = k.Library(Uri.parse('app:///main.dart'), fileUri: _uri);
  final p = k.Procedure(
    k.Name('ita\$boxFala'),
    k.ProcedureKind.Method,
    k.FunctionNode(k.EmptyStatement()),
    fileUri: _uri,
    isStatic: true,
  );
  lib.addProcedure(p);
  return p;
}
