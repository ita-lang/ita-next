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
//     roda idêntico, só cresce ~8 MB. É o **CA11** literal.
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

/// **CA11** — o `.dill` emitido contém SÓ as libs do programa. O platform é a
/// base do `Component` durante o verify (o `finalizeProgram` o anexa para
/// resolver `dart:core::print`), mas o `libraryFilter` do `BinaryPrinter` tem de
/// deixá-lo de fora da serialização: a VM relinca o seu próprio platform no load
/// (Grupo B). Uma regressão aqui roda IDÊNTICA — só produz um `.dill` ~8 MB
/// maior, e nenhum golden de stdout perceberia.
List<Violation> checkSerializedLibraries(k.Component emitted) {
  final foreign = emitted.libraries
      .where((l) => l.importUri.scheme == 'dart')
      .map((l) => l.importUri.toString())
      .toList();
  return [
    if (foreign.isNotEmpty)
      'CA11: o .dill serializado carrega ${foreign.length} lib(s) do platform '
          '(${foreign.take(3).join(", ")}${foreign.length > 3 ? ", …" : ""}) '
          '— o libraryFilter deveria tê-las excluído',
  ];
}

/// `dynamic` ESCONDIDO dentro de um tipo composto.
///
/// A travessia de `TreeNode` NÃO desce em `DartType` (tipo não é `TreeNode`),
/// então cada sítio onde EMITIMOS um tipo é conferido explicitamente pelo
/// visitor abaixo, com esta função descendo nos compostos.
///
/// ⚠️ **Cobre o que a emissão produz hoje** (`InterfaceType` com type-args,
/// `FunctionType`, `FutureOrType`) e devolve `false` no que não reconhece —
/// prefere o silêncio à falsa acusação. Cada fatia nova que emitir uma FORMA
/// nova de tipo tem de aparecer aqui; enquanto não aparecer, o invariante é
/// incompleto e este comentário é o aviso.
bool _hasDynamic(k.DartType type) => switch (type) {
      k.DynamicType() => true,
      k.InterfaceType(:final typeArguments) => typeArguments.any(_hasDynamic),
      k.FutureOrType(:final typeArgument) => _hasDynamic(typeArgument),
      k.FunctionType(:final returnType, :final positionalParameters) =>
        _hasDynamic(returnType) || positionalParameters.any(_hasDynamic),
      _ => false,
    };

class _InvariantVisitor extends k.RecursiveVisitor {
  final List<Violation> violations = [];

  String _at(k.TreeNode node) => '@${node.fileOffset}';

  void _type(k.DartType type, String where, k.TreeNode at) {
    if (_hasDynamic(type)) {
      violations.add('ADR-0013: `dynamic` em $where ${_at(at)}');
    }
  }

  // -- ADR-0013: `dynamic` é a porta dos fundos, e ela fica trancada ----------
  //
  // A inferência que falha é ERRO no Itá, nunca `dynamic` (ADR-0013 supersede
  // parcial do ADR-0004). O emitter honra isso por ICE em cada sítio que ele
  // LEMBROU de escrever; este invariante o honra por construção, e pega o sítio
  // que ninguém lembrou — inclusive nas fatias que ainda não existem.

  @override
  void visitVariableDeclaration(k.VariableDeclaration node) {
    _type(node.type, 'VariableDeclaration `${node.name}`', node);
    node.visitChildren(this);
  }

  @override
  void visitFunctionNode(k.FunctionNode node) {
    _type(node.returnType, 'returnType', node);
    node.visitChildren(this);
  }

  @override
  void visitField(k.Field node) {
    _type(node.type, 'Field `${node.name.text}`', node);
    node.visitChildren(this);
  }

  @override
  void visitConditionalExpression(k.ConditionalExpression node) {
    // O nó devolve o `staticType` CRU em `getStaticTypeInternal` — errado aqui é
    // invisível no JIT e envenena a TFA/dart2js.
    _type(node.staticType, 'ConditionalExpression.staticType', node);
    node.visitChildren(this);
  }

  @override
  void visitDynamicInvocation(k.DynamicInvocation node) {
    violations.add(
      'ADR-0013: DynamicInvocation `${node.name.text}` ${_at(node)} — '
      'faltou `interfaceTarget` na emissão?',
    );
    node.visitChildren(this);
  }

  @override
  void visitDynamicGet(k.DynamicGet node) {
    violations.add('ADR-0013: DynamicGet `${node.name.text}` ${_at(node)}');
    node.visitChildren(this);
  }

  @override
  void visitDynamicSet(k.DynamicSet node) {
    violations.add('ADR-0013: DynamicSet `${node.name.text}` ${_at(node)}');
    node.visitChildren(this);
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
    node.visitChildren(this);
  }

  @override
  void visitStaticInvocation(k.StaticInvocation node) {
    if (node.targetReference.node == null) {
      violations.add('StaticInvocation ${_at(node)} sem target ligado');
    }
    node.visitChildren(this);
  }
}
