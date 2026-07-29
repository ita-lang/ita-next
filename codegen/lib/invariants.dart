// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// invariants.dart — a camada INTENSIONAL do gate da F7 (spec 013 §11).
//
// O golden-runner é EXTENSIONAL: compara o que o programa imprime. Isso é
// necessário (só a execução prova as premissas do §8.1 sobre a VM — o
// curto-circuito do `LogicalExpression`, o `toString` implícito da
// interpolação, `~/` render 3 e não 3.5) e é INSUFICIENTE, porque uma classe
// inteira de defeito **roda igual e está errada**:
//
//   - `interfaceTarget` nulo ⟹ `DynamicInvocation`, que imprime `2` igualzinho;
//   - `VariableDeclaration.type = dynamic` ⟹ roda igual, e é *a* proibição do
//     ADR-0013;
//   - `libraryFilter` quebrado ⟹ o `.dill` carrega `dart:core` inteiro junto;
//     roda idêntico, só cresce ~8 MB (§7.1).
//
// Fundamento (Dragon, abertura do cap. 8): *"o critério mais importante para um
// gerador de código é que ele produza código correto… a exatidão assume
// significado especial devido ao número de casos especiais"*. Correção aqui é
// equivalência SEMÂNTICA, e parte dela não é observável por stdout. Nystrom
// §17.7 ("Dumping Chunks") funda a outra metade: o artefato da fase é o código
// emitido, e ele tem de ser inspecionável SEM executar.
//
// ⚠️ Por que INVARIANTES e não golden textual do dump: o golden textual é alto
// churn / baixo sinal por linha — toda mudança de emitter reescreve todos os
// arquivos e o revisor carimba. Os invariantes são baixo churn / alto sinal, e
// valem para todo fixture FUTURO automaticamente, sem uma linha a mais. O dump
// textual (CA13) é fatia própria; quando vier, `Printer(buf, syntheticNames:
// NameSystem())` por fixture — NUNCA `debugLibraryToString`, que usa o
// `NameSystem` GLOBAL e faria o dump de um fixture depender dos anteriores.

import 'package:kernel/ast.dart' as k;
import 'package:kernel/naive_type_checker.dart';

/// Uma violação de invariante, já formatada para o relatório.
typedef Violation = String;

/// Roda todos os invariantes estruturais sobre as [libs] do PROGRAMA (nunca
/// sobre o platform — `dart:core` está cheio de `dynamic` legítimo).
///
/// Devolve a lista de violações; vazia = tudo certo.
List<Violation> checkInvariants(List<k.Library> libs) {
  final visitor = _InvariantVisitor();
  for (final lib in libs) {
    lib.accept(visitor);
  }
  return visitor.violations;
}

/// **CA10 (a metade estrutural) — `Option` tem CUSTO ZERO.**
///
/// `Option<T>` ≡ `T?` baixa como nullable NATIVO do Kernel; não existe classe
/// `Option` no `.dill`, e `nil` é `null`, não um `.none` construído. A forma
/// executável dessa afirmação: **toda `Class` emitida corresponde a um
/// `struct`/`class` que o usuário DECLAROU** — nenhuma é sintetizada pela
/// emissão.
///
/// Um wrapper de opcional (ou qualquer outro box sintetizado — a armadilha que o
/// ADR-0017 §3 vigia na fronteira `any`) apareceria aqui como classe a mais, e
/// **rodaria igual**: o programa imprimiria o mesmo, só alocando um objeto por
/// valor opcional. É invisível para o golden de stdout, por construção.
///
/// ⚠️ Esta regra vigia TAMBÉM o box do ADR-0017 §3 na fronteira `any` — mas o
/// **CA11** (*"travessia `any` de fonte local: zero nó extra"*) só fecha quando a
/// fronteira existencial existir; hoje ela é ICE.

/// As classes de RUNTIME que a emissão pode materializar — a ÚNICA exceção à
/// regra, e ela é enumerada de propósito. Cada nome aqui é uma decisão de spec
/// com sítio único de criação:
///
///   - `ItaPanic` (§7.4-f/CA9) — alvo do `Throw` de `panic`, sob demanda;
///   - `ItaResult` + `ItaResult$ok` / `ItaResult$err` (§7.4-c/CA8) — o `Result`,
///     que ao contrário do `Option` **não tem equivalente nativo**: ele carrega
///     payload nos DOIS lados, e nenhum tipo do Kernel representa "ou T ou E"
///     sem perder um deles. Aqui a classe é o preço mínimo, não conveniência.
///
/// Lista FECHADA, e não um `startsWith('Ita')`: a régua tem de errar no
/// desconhecido, senão qualquer wrapper futuro se disfarça de runtime e o CA10
/// vira letra morta.
const _runtimeClasses = {
  'ItaPanic',
  'ItaResult',
  r'ItaResult$ok',
  r'ItaResult$err',
};

List<Violation> checkNoSyntheticClasses(
  List<k.Library> libs,
  Set<String> declaredTypeNames,
) {
  final violations = <Violation>[];
  for (final lib in libs) {
    for (final cls in lib.classes) {
      if (_runtimeClasses.contains(cls.name)) continue;
      // **Subclasse de variante de enum selado** (`Forma$circulo`, §7.4-c): não
      // é wrapper — é a representação do sum type, e cada uma DERIVA de um enum
      // que o usuário declarou. A régua segue fechada: o prefixo antes do `$`
      // tem de ser um tipo declarado, então um `Qualquer$coisa` solto continua
      // sendo acusado.
      final dollar = cls.name.indexOf('\$');
      if (dollar > 0 &&
          declaredTypeNames.contains(cls.name.substring(0, dollar))) {
        continue;
      }
      if (!declaredTypeNames.contains(cls.name)) {
        violations.add(
          'CA10/custo-zero: classe `${cls.name}` no .dill sem decl correspondente '
          '— wrapper sintetizado? (Option/`any` box devem ser ZERO nó)',
        );
      }
    }
  }
  return violations;
}

/// **CA13 (negativo) — as duas armadilhas do ADR-0017, pinadas para sempre.**
///
/// O `.dill` de um programa com conformance **não pode** conter:
///
///   1. **`mixedInType`** — mixin. O ADR-0017 §2 o recusou: a lowering de mixin
///      é uma *modular transformation* do pipeline CFE que o Itá **bypassa**
///      (emitimos Kernel cru), então um `mixedInType` no `.dill` chegaria à VM
///      **sem ter sido achatado** — e roda errado em silêncio, porque a VM
///      assume que alguém já o resolveu;
///   2. **`implements` sobre classe de `dart:core`** — conformar um trait do
///      usuário a `int`/`String`/`Object` faria o `.dill` reabrir tipos do
///      platform, que não são nossos para alterar.
///
/// Nenhuma das duas é pega pelo verifier (ele não confere `implementedTypes` —
/// grep = zero), nem pela execução: o programa roda. Só a inspeção estrutural.
List<Violation> checkConformanceTraps(List<k.Library> libs) {
  final violations = <Violation>[];
  for (final lib in libs) {
    for (final cls in lib.classes) {
      if (cls.mixedInType != null) {
        violations.add(
          'CA13: `${cls.name}` tem mixedInType — mixin é lowering de transformer '
          'do CFE, que o Itá BYPASSA (ADR-0017 §2): chegaria à VM sem achatar',
        );
      }
      for (final s in cls.implementedTypes) {
        final uri = s.classNode.enclosingLibrary.importUri;
        if (uri.scheme == 'dart') {
          violations.add(
            'CA13: `${cls.name}` implementa `${s.classNode.name}` de `$uri` — '
            'conformance sobre tipo do platform reabre o que não é nosso',
          );
        }
      }
    }
  }
  return violations;
}

/// **ÁRVORE, não grafo — cada nó tem UM pai.**
///
/// Construir Kernel à mão é montar uma árvore com `new` cru, e a forma mais fácil
/// de errar é **reusar a mesma instância** em dois lugares: um `InstanceGet` de
/// `subject.campo` usado nas DUAS pontas de um range, um `VariableGet`
/// aproveitado em dois braços. O `parent` do nó passa a apontar só para o último
/// que o adotou, e a árvore vira grafo.
///
/// **Por que este invariante existe, se o `verifyComponent` já pega isso.**
/// Porque o verify é **opt-in NOSSO**: a VM não o roda — ela confia no CFE, que
/// o Itá bypassa. Se ele for desligado, movido de fase, ou se a árvore for
/// inspecionada antes dele, a classe inteira volta a passar. Além disso o
/// diagnóstico do verify nomeia o SINTOMA (*"Incorrect parent pointer"*,
/// `verifier.dart:277-291`) e a instância errada; este nomeia a CAUSA e o nó
/// compartilhado. E há uma isenção lá que cresce com o "new variable model":
/// `_isNewModelVariable` (`:272-275`), hoje inócua.
///
/// 🔴 **CORREÇÃO 2026-07-29.** Até esta data a justificativa acima dizia
/// *"`verifier.dart` não tem chamador em todo o `pkg/`"*. Era **ALUCINAÇÃO** —
/// há 5 (`verify_bench.dart:25,33,42`, `verify_test.dart:919,1119`). A frase
/// nasceu numa memória de agente, vazou para 3 sítios de código, e voltou como
/// premissa. A regra sobrevive; a justificativa dela, não. Nada aqui é evidência
/// sem endereço verificável.
///
/// Detecta por IDENTIDADE: a travessia encontra o mesmo objeto duas vezes,
/// porque os dois pais o referenciam.
List<Violation> checkNoSharedNodes(List<k.Library> libs) {
  final visitor = _SharingVisitor();
  for (final lib in libs) {
    lib.accept(visitor);
  }
  return visitor.violations;
}

class _SharingVisitor extends k.RecursiveVisitor {
  final Set<k.TreeNode> _seen = Set.identity();
  final List<Violation> violations = [];

  @override
  void defaultTreeNode(k.TreeNode node) {
    if (!_seen.add(node)) {
      violations.add(
        'árvore: nó COMPARTILHADO — ${node.runtimeType} @${node.fileOffset} '
        'aparece em dois pais (cada nó do Kernel tem UM pai; '
        'construa uma instância nova por uso)',
      );
      return; // não desce de novo: a subárvore já foi visitada
    }
    node.visitChildren(this);
  }
}

/// **§7.1 — o `libraryFilter`**: o `.dill` emitido contém SÓ as libs do programa.
///
/// O platform é a base do `Component` durante o verify (o `finalizeProgram` o
/// anexa para resolver `dart:core::print`), mas o `libraryFilter` do
/// `BinaryPrinter` tem de deixá-lo de fora da serialização: a VM relinca o seu
/// próprio platform no load (Grupo B). Uma regressão aqui roda IDÊNTICA — só
/// produz um `.dill` ~8 MB maior, e nenhum golden de stdout perceberia.
///
/// ⚠️ **Isto NÃO é o CA11.** O CA11 é *"travessia `any` de fonte local: zero nó
/// extra no `.dill`"* — depende da fronteira existencial (ADR-0017), que ainda é
/// ICE. Rotular esta regra de CA11 (como estava até 2026-07-29) fazia o placar
/// da §11 contar um CA que ninguém tinha fechado.
List<Violation> checkSerializedLibraries(k.Component emitted) {
  final foreign = emitted.libraries
      .where((l) => l.importUri.scheme == 'dart')
      .map((l) => l.importUri.toString())
      .toList();
  return [
    if (foreign.isNotEmpty)
      'libraryFilter: o .dill serializado carrega ${foreign.length} lib(s) do platform '
          '(${foreign.take(3).join(", ")}${foreign.length > 3 ? ", …" : ""}) '
          '— o libraryFilter (§7.1) deveria tê-las excluído',
  ];
}

/// **O TIPO do receptor autoriza o alvo — não o nome dele.**
///
/// `verifyComponent` NÃO type-checa (*"This does not include any kind of type
/// checking"*, `verifier.dart:127-129`), e o pouco que ele confere sobre
/// `interfaceTarget` é **despacho por lexema**: `_checkInterfaceTarget` só olha
/// `node.name == interfaceTarget.name`, `isInstanceMember` e `enclosingClass !=
/// null`. Um `InstanceGet` de `Ponto.x` apontando para `Caixa.x` satisfaz os
/// três, passa no LOAD e **roda certo no JIT** — o dispatch é por selector via
/// inline cache, então o nome basta em runtime. Quebra em AOT, onde a TFA poda
/// pelo cone da classe do interface target, e a interseção do cone de `Ponto`
/// com o de `Caixa` é vazia. Foi exatamente esse o bug 4 da auditoria de
/// 2026-07-29, e nenhuma camada o via.
///
/// O `pkg/kernel` já traz o checador que falta, e ele não puxa `front_end` nem
/// `analyzer` (o conflito da §0-A não se aplica): o `NaiveTypeChecker` acusa
/// *"X is not accessible on a receiver of type Y"*, e ainda assignability de
/// argumento/retorno/initializer e aridade de chamada.
///
/// ⚠️ **Rede grossa, de propósito — e o limite é declarado.** O
/// `checkAssignable` do naive só falha quando NENHUM dos dois sentidos é
/// subtipo, então downcast implícito passa; e nos operadores aritméticos
/// especiais ele ignora o `functionType` e aplica a regra do Dart, logo **não**
/// acusa o `num` de `Int + Int`. Preservação de tipo é gate próprio, e não
/// existe ainda.
///
/// [component] tem de ser o Component COMPLETO (platform + programa): o checker
/// resolve `dart:core` pela `ClassHierarchy`. `ignoreSdk: true` pula o platform.
List<Violation> checkTypeConsistency(k.Component component) {
  final listener = _Falhas();
  NaiveTypeChecker(listener, component, ignoreSdk: true)
      .checkComponent(component);
  return listener.violations;
}

/// Coletor próprio, e **não** o `ErrorFormatter` do vendor.
///
/// O `ErrorFormatter.reportFailure` tenta imprimir a LINHA-FONTE do nó:
/// `component.uriToSource[fileUri]!` (`error_formatter.dart:50`). Num `.dill` do
/// Itá esse mapa só tem as fontes do platform — o `.tu` não está lá —, então a
/// primeira violação REAL mata o runner com *"Null check operator used on a null
/// value"* em vez de reportá-la. Descoberto rodando este gate contra o emitter
/// pré-correção: ele **achou** o bug 4 e morreu ao formatá-lo. Um gate que
/// explode ao acusar é um gate que ninguém mantém ligado.
///
/// Aqui a mensagem é o nó + o offset — o mesmo endereço que os outros
/// invariantes usam e que o `--dump` do `itac` sabe localizar.
class _Falhas implements FailureListener {
  final List<Violation> violations = [];

  void _add(k.TreeNode node, String msg) {
    final onde =
        node is k.Member ? '`${node.name.text}`' : '${node.runtimeType}';
    violations.add('tipo: $onde @${node.fileOffset} — $msg');
  }

  @override
  void reportFailure(k.TreeNode node, String message) => _add(node, message);

  @override
  void reportNotAssignable(k.TreeNode node, k.DartType from, k.DartType to) =>
      _add(node, '$from não é atribuível a $to');

  @override
  void reportInvalidOverride(k.Member member, k.Member inherited, String msg) =>
      _add(member, 'override incompatível com `${inherited.name.text}`: $msg');
}

class _InvariantVisitor extends k.RecursiveVisitor {
  final List<Violation> violations = [];

  /// Caminho até o nó corrente — só `TreeNode`, empilhado por [defaultNode].
  ///
  /// Existe porque um `DynamicType` é um objeto **canônico e compartilhado**
  /// (`const DynamicType()`): ele não sabe onde está, e sem o caminho a violação
  /// não seria acionável. A pilha é o que devolve o endereço.
  final List<k.TreeNode> _path = [];

  String _at(k.TreeNode node) => '@${node.fileOffset}';

  /// Os últimos níveis do caminho, com o nome do membro quando houver.
  ///
  /// O offset vem do nó mais PROFUNDO que tenha um — nem todo nó do Kernel
  /// carrega `fileOffset`, e um nó sem endereço no fim do caminho não pode
  /// apagar o endereço que os pais dele já davam. Diagnóstico que perde a
  /// localização não é acionável, e um gate não-acionável é ignorado.
  String _where() {
    if (_path.isEmpty) return '<raiz>';
    final tail = _path.length <= 3 ? _path : _path.sublist(_path.length - 3);
    final crumbs = tail.map((n) => switch (n) {
          k.Member m => '${n.runtimeType}(${m.name.text})',
          k.VariableDeclaration v when v.name != null =>
            'VariableDeclaration(${v.name})',
          _ => '${n.runtimeType}',
        });
    final located = _path.lastWhere(
      (n) => n.fileOffset != k.TreeNode.noOffset,
      orElse: () => _path.last,
    );
    return '${crumbs.join(" › ")} ${_at(located)}';
  }

  // -- ADR-0013: `dynamic` é a porta dos fundos, e ela fica trancada ----------
  //
  // A inferência que falha é ERRO no Itá, nunca `dynamic` (ADR-0013 supersede
  // parcial do ADR-0004).
  //
  // ⚠️ **Esta regra é UM override, e é assim de propósito** (CLAUDE.md R5).
  // Até 2026-07-29 ela era uma lista-branca — `_hasDynamic` + um override por
  // sítio que alguém lembrou de escrever — fundada numa premissa FALSA que
  // estava escrita aqui: *"a travessia de `TreeNode` não desce em `DartType`"*.
  // Desce: `Visitor<R> implements DartTypeVisitor<R>` (`visitor.dart:1748`), os
  // nós chamam `type.accept(v)` em `visitChildren` (`InstanceGet.resultType`,
  // `InstanceInvocation.functionType`, `ConstantExpression.type`,
  // `IsExpression.type`, `AsExpression.type`, `FunctionType.namedParameters`…),
  // e `VisitorDefault.defaultDartType` cai em `defaultNode` (`:1797`).
  //
  // A lista-branca não era incompleta por descuido: ela é incompletável **por
  // construção**. O conjunto de nós vem de um pacote EXTERNO e versionado, a
  // lista de overrides é interna, e não há link em tempo de compilação entre os
  // dois — logo toda divergência produz FALSO NEGATIVO, a direção errada para
  // um gate. `RecursiveVisitor.defaultNode` desce e CALA; um gate cuja
  // falha-padrão é "OK" é documentação executável do que alguém lembrou.
  //
  // O custo dessa cegueira foi medido: `ConstantExpression(c)` tem
  // `type = const DynamicType()` **por default do construtor**
  // (`pkg/kernel/…/expressions.dart:5084`), e o emitter passava 1 argumento ⟹
  // havia `DynamicType` REAL no `.dill`, em TODO default de parâmetro, com o
  // invariante verde. Nenhum dos 5 overrides antigos olhava para lá.
  @override
  void visitDynamicType(k.DynamicType node) {
    violations.add('ADR-0013: `dynamic` em ${_where()}');
  }

  /// Empilha o caminho. `defaultNode` recebe `Node` (inclui `DartType`), e só
  /// `TreeNode` tem endereço — o resto só precisa descer.
  @override
  void defaultNode(k.Node node) {
    if (node is! k.TreeNode) {
      node.visitChildren(this);
      return;
    }
    _path.add(node);
    node.visitChildren(this);
    _path.removeLast();
  }

  @override
  void visitDynamicInvocation(k.DynamicInvocation node) {
    violations.add(
      'ADR-0013: DynamicInvocation `${node.name.text}` ${_at(node)} — '
      'faltou `interfaceTarget` na emissão?',
    );
    defaultNode(node);
  }

  @override
  void visitDynamicGet(k.DynamicGet node) {
    violations.add('ADR-0013: DynamicGet `${node.name.text}` ${_at(node)}');
    defaultNode(node);
  }

  @override
  void visitDynamicSet(k.DynamicSet node) {
    violations.add('ADR-0013: DynamicSet `${node.name.text}` ${_at(node)}');
    defaultNode(node);
  }

  // -- alvos LIGADOS em toda invocação --------------------------------------
  //
  // A docstring do `_numOp` afirma *"o Kernel os exige (sem eles cairia em
  // `DynamicInvocation`)"* — afirmação que, até este invariante existir, era
  // sustentada por NADA. Um `1 + 1` sem interfaceTarget imprime `2` igual no
  // JIT e envenena a TFA em silêncio.

  @override
  void visitInstanceInvocation(k.InstanceInvocation node) {
    if (node.interfaceTargetReference.node == null) {
      violations.add(
        'InstanceInvocation `${node.name.text}` ${_at(node)} sem '
        'interfaceTarget ligado',
      );
    }
    defaultNode(node);
  }

  @override
  void visitStaticInvocation(k.StaticInvocation node) {
    if (node.targetReference.node == null) {
      violations.add('StaticInvocation ${_at(node)} sem target ligado');
    }
    defaultNode(node);
  }
}
