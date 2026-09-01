// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// ============================================================================
// golden_test.dart — o GOLDEN-RUNNER do emitter (spec 013 §7.2, §7.7, §11).
// ============================================================================
//
// Harness próprio (sem `package:test` — ver `kernel-vs-package-test-conflict`).
// Rodar pelo Makefile (que resolve o dart do pin):
//
//   make codegen-golden            # verifica
//   make codegen-golden-update     # REGRAVA os .out (leia a saída antes!)
//
// O que ele prova, por fixture de `conformance/codegen/`:
//
//   1. o `.tu` compila pelo MESMO `compileToDill` que o `itac build` usa
//      (lib/compile.dart — uma fonte de verdade, não uma réplica);
//   2. o `.dill` resultante RODA na Dart VM;
//   3. o **stdout** casa byte a byte com o golden `<nome>.out`;
//   4. o **exit code** casa com o esperado (`// EXPECT-EXIT:`, default 0);
//   5. stderr fica VAZIO nos fixtures de saída normal.
//
// Isto é o que os testes de `sanitize`/`finalize` NÃO cobrem: eles verificam a
// higiene e a boa-formação do `.dill` (o verify aceita), não o que o programa
// IMPRIME. Um emitter que troque `~/` por `/`, ou `<` por `<=`, produz `.dill`
// perfeitamente válido — e saída errada. Só a execução pega.
//
// **ALVOS: os TRÊS da §7.7** (desde 2026-08-06), e cada um quer um artefato
// diferente — a assimetria é o achado que fez isto funcionar:
//
//   - **VM (JIT)**: `dart <dill>` sobre o `.dill` MÍNIMO. É a REFERÊNCIA; os
//     outros dois são comparados contra a saída dela, não contra o `.out`,
//     porque o contrato da §7.7 é entre alvos (*"empata a VM byte a byte"*).
//   - **AOT**: `dart compile exe` sobre o `.dill` COMPLETO. O `gen_kernel` não
//     relinca platform nenhum: sobre o mínimo ele morre em `Reference to
//     dart:core::@methods::print is not bound to an AST node`.
//   - **JS**: `dart compile js` sobre o `.dill` MÍNIMO + `node`. O dart2js
//     relinca o platform DELE, e sobre o completo ele morre — o `vm_platform`
//     embutido é de outro alvo. Medido nos dois sentidos em 2026-08-06.
//
// `--targets=vm[,aot][,js]` recorta (default: os três). O recorte é DECLARADO no
// cabeçalho e no registro que o ledger lê, então rodar menos não fecha CA: um
// atalho que inflasse o placar seria pior que não ter atalho.
//
// ⚠️ **Camada que falta (declarada, não escondida):** este runner é
// EXTENSIONAL — compara comportamento observável. Ele é cego para invariantes
// que rodam igual e estão errados: `interfaceTarget` nulo (⟹ `DynamicInvocation`
// imprime o mesmo), `isFinal` de local, `dynamic` proibido pelo ADR-0013,
// `staticType` de `ConditionalExpression`, o `libraryFilter` (`finalize.dart:148`
// — serializar `dart:core` junto roda idêntico, só cresce 8 MB) e as do CA13
// (`mixedInType`, `implements` sobre `dart:core`). Os CA10/CA11/CA13 da §11 são
// estruturais POR TEXTO NORMATIVO ("inspecionável no dump") — daí a camada
// intensional em `lib/invariants.dart`, auto-testada em `invariants_test.dart`.
//
// ---------------------------------------------------------------------------
// Fixtures de FRONTEIRA (`// EXPECT-ICE:`)
// ---------------------------------------------------------------------------
// Um fixture pode declarar que a emissão AINDA não sabe baixá-lo, com o
// `ice-codegen-*` que ela devolve (§7.8). Não é decoração — e não é um `xfail`
// clássico: um xfail fica VERDE quando a feature chega e nunca cobra nada. Este
// fica VERMELHO (o `xpass` do lit/LLVM), cobrando a promoção a CA verde. É a
// fila de trabalho da §7.4, executável.
//
// ---------------------------------------------------------------------------
// `--update`
// ---------------------------------------------------------------------------
// Regrava os `.out` a partir da execução atual. É o ÚNICO caminho que escreve
// golden: um `.out` ausente FALHA (auto-criar seria carimbar como verde uma
// saída que ninguém leu — e no CI o arquivo criado morre com o workspace).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kernel/binary/tag.dart' show Tag;
import 'package:kernel/kernel.dart' show loadComponentFromBytes;

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;

import 'package:ita_next_codegen/compile.dart';
import 'package:ita_next_codegen/emit.dart' show emitProgram;
import 'package:ita_next_codegen/invariants.dart';
import 'alvos.dart';
import 'harness.dart';

/// O harness compartilhado, com kill-switch provado (ver `harness.dart` e o
/// mutante M8). O veredito final deste runner é próprio — ele conta verdes,
/// fronteiras e negativos separadamente —, mas a CONTAGEM DE FALHA é a de lá.
final _h = Harness('Golden-runner');
int _greens = 0; // fixtures verdes que passaram
int _frontiers = 0; // fronteiras (ICE declarado) — TEMPORÁRIAS, a catraca as esvazia
int _negatives = 0; // CAs negativos (erro de usuário esperado) — PERMANENTES
int _ordemExercitada = 0; // fixtures com 2+ decls — os únicos que provam o letrec
// **CA11** — sítios de travessia `any` inspecionados no corpus INTEIRO. A régua
// por fixture é muda num programa sem `any` (a maioria), e imprimir ✓ nesses
// afirmaria uma verificação que não houve: é o mesmo defeito que `_ordemExercitada`
// existe para evitar. Zero no corpus todo ⟹ o CA11 não foi provado por ninguém.
int _travessiasInspecionadas = 0;

/// Quantos fixtures cada alvo EXECUTOU. É o que o ledger lê (`alvos.dart`), e a
/// R12 aplicada ao alvo: alvo ligado que roda zero fixtures é indistinguível de
/// alvo desligado, e fecharia CA por um número que ninguém olhou.
final _porAlvo = <AlvoExec, int>{};

/// Fixtures cujo stdout em JS DIVERGE da VM por declaração (`// JS-DIVERGE:`).
/// Contado à parte porque é dívida com a semântica do alvo, não vitória.
int _jsDivergentes = 0;

/// Quanto cada passe de saneamento aplicou, somado sobre o corpus inteiro.
final _saneamento = <String, int>{};

/// **Passes que hoje não se aplicam a nada, DECLARADOS.**
///
/// Um passe com 0 aplicações é indistinguível de um passe removido, e acumula
/// tick verde para sempre — medido em 2026-07-29: o `LocalFunctionIdAssigner`
/// roda duas passadas por fixture sobre 5621 nós e altera ZERO, porque
/// `FunctionExpression`/`FunctionDeclaration` não existem no emitter. O mutante
/// que o tirava do caminho de produção sobreviveu à suíte inteira.
///
/// Ele não está errado — é a defesa contra a lição mais cara do projeto (duas
/// closures no mesmo member colidindo no `ClosureFunctionsCache` da VM). O que
/// estava errado era não SABER que ele não roda.
///
/// Esta lista é uma CATRACA nos dois sentidos, e os dois foram verificados:
/// passe fora dela com 0 aplicações reprova; passe dentro dela que APLICA
/// também reprova (tem de sair). Só encolhe.
/// ✅ **VAZIA desde 2026-07-29.** O `LocalFunctionIdAssigner` saiu ao emitir a
/// primeira closure — e saiu porque o gate COBROU: *"APLICOU 2× mas está na
/// lista de vacuosos — tire-o de lá (a catraca só encolhe)"*. A metade da
/// catraca que reprova passe-dentro-da-lista-que-aplica não era decoração.
const _vacuosDeclarados = <String, String>{};

void check(bool cond, String label) => _h.check(cond, label);
void fail(String label, {String? detail}) => _h.fail(label, detail: detail);

/// Asserção de TRÊS pontas do `dart-sdk.pin` — *"os TRÊS têm que vir da MESMA
/// versão stable"* (cabeçalho do pin):
///
///   1. o `dart` que roda isto      (`Platform.version`)        vs `DART_VERSION`
///   2. o `vm_platform.dill` do SDK (bytes 4..7, big-endian)    vs `EXPECTED_KERNEL_FORMAT`
///   3. o `pkg/kernel` VENDORADO    (`Tag.BinaryFormatVersion`) vs o mesmo
///
/// **Por que não é paranoia:** o `.dill` que emitimos sai com **SDK hash NULO** —
/// `tag.dart:264-273` tira `expectedSdkHash` de `String.fromEnvironment('sdk_hash')`
/// e cai no default `'0000000000'`, porque rodamos o `pkg/kernel` do *source*, sem
/// `-Dsdk_hash`; e `isValidSdkHash` (`:275-278`) passa se QUALQUER lado for nulo.
/// Ou seja: a única checagem que detectaria um SDK errado **está desligada** — só
/// o FORMATO é conferido de fato pela VM. Um bump de PATCH com o mesmo formato
/// passaria em silêncio. Estas três linhas são o que sobra.
///
/// A ponta **3** é a que mais quebra num bump real: quem troca a versão do SDK
/// esquece de revendorar o `pkg/kernel`, e o vendor velho emite formato velho.
/// Ler só o `.dill` (o que um `od` no shell alcança) cobriria 1 e 2, não a 3.
///
/// O formato NÃO é hardcodado aqui de propósito: o `main` do SDK já está em 138.
/// A fonte é o `dart-sdk.pin`, sempre.
void checkPin(String root) {
  final pin = <String, String>{};
  for (final line in File('$root/dart-sdk.pin').readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i > 0) pin[t.substring(0, i)] = t.substring(i + 1).trim();
  }
  final wantVersion = pin['DART_VERSION'];
  final wantFormat = int.parse(pin['EXPECTED_KERNEL_FORMAT']!);

  final gotVersion = Platform.version.split(' ').first;
  check(gotVersion == wantVersion,
      'dart $gotVersion == pin $wantVersion${gotVersion == wantVersion ? '' : ' — rode `make pin`, ou DART_CG=<dart $wantVersion>'}');

  // `getUint32` tem `Endian.big` por default, que é o do formato
  // (`kernel_binary.h:167-170` lê com `BigEndianToHost32`).
  final head = File(platformDillPath()).openSync().readSync(8);
  final bd = ByteData.sublistView(head);
  check(bd.getUint32(0) == 0x90ABCDEF, 'vm_platform.dill tem magic de .dill');
  final gotFormat = bd.getUint32(4);
  check(gotFormat == wantFormat, 'vm_platform.dill fmt $gotFormat == pin $wantFormat');
  check(Tag.BinaryFormatVersion == wantFormat,
      'pkg/kernel vendorado fmt ${Tag.BinaryFormatVersion} == pin $wantFormat');
}

/// Diretivas do header de um fixture (linhas `//`).
///
///   `// EXPECT-ICE: <code>`  — espera falha de emissão com esse `ice-codegen-*`
///                              (exit 70 do compilador); sem golden `.out`.
///   `// EXPECT-ERROR: <code>` — espera erro de USUÁRIO do driver (exit 65),
///                              ex. `missing-main` (§12-5); sem golden `.out`.
///   `// EXPECT-EXIT: <n>`    — exit code esperado do PROGRAMA (default 0).
///   `// EXPECT-STDERR: <s>`  — o stderr do programa CONTÉM `<s>`. Exigida com
///                              `EXPECT-EXIT` ≠ 0, e recusada com 0 (ali a régua
///                              é stderr VAZIO, e as duas juntas se contradizem).
///   `// JS-DIVERGE: <razão>` — o stdout em JS difere do da VM por semântica do
///                              ALVO, não por bug nosso (§12-6). Exige o golden
///                              `<stem>.js.out`, e o runner cobra os dois lados:
///                              golden sem razão escrita reprova, e razão
///                              escrita cujo JS na verdade EMPATA também — senão
///                              a diretiva vira silenciador permanente (R12).
///
/// [errors] carrega problemas da PRÓPRIA diretiva. Uma diretiva que o harness
/// não entende NÃO pode ser ignorada em silêncio: `EXPECT-EXITT: 70` cairia no
/// default 0 e o fixture passaria afirmando o que ninguém pediu. O harness
/// aplicaria a si mesmo o oposto de "diagnóstico nunca mente".
typedef Directives = ({
  String? expectIce,
  String? expectError,
  int expectExit,
  String? expectStderr,
  String? jsDiverge,
  List<String> errors,
});

Directives parseDirectives(String source) {
  String? ice;
  String? buildError;
  String? jsDiverge;
  String? expectStderr;
  var exitCode = 0;
  var sawExit = false;
  final errors = <String>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (!line.startsWith('//')) continue;
    final body = line.substring(2).trim();
    if (body.startsWith('JS-DIVERGE:')) {
      if (jsDiverge != null) errors.add('JS-DIVERGE duplicado');
      jsDiverge = body.substring('JS-DIVERGE:'.length).trim();
      if (jsDiverge.isEmpty) {
        errors.add('JS-DIVERGE sem razão escrita — a diretiva É a razão');
      }
      continue;
    }
    if (!body.startsWith('EXPECT')) continue;
    if (body.startsWith('EXPECT-ICE:')) {
      if (ice != null) errors.add('EXPECT-ICE duplicado');
      ice = body.substring('EXPECT-ICE:'.length).trim();
      if (ice.isEmpty) errors.add('EXPECT-ICE sem código');
    } else if (body.startsWith('EXPECT-ERROR:')) {
      if (buildError != null) errors.add('EXPECT-ERROR duplicado');
      buildError = body.substring('EXPECT-ERROR:'.length).trim();
      if (buildError.isEmpty) errors.add('EXPECT-ERROR sem código');
    } else if (body.startsWith('EXPECT-STDERR:')) {
      if (expectStderr != null) errors.add('EXPECT-STDERR duplicado');
      expectStderr = body.substring('EXPECT-STDERR:'.length).trim();
      if (expectStderr.isEmpty) {
        // Substring vazia está contida em QUALQUER string — a diretiva viraria
        // um tick verde permanente sobre nada.
        errors.add('EXPECT-STDERR sem substring — `""` casa com qualquer stderr');
      }
    } else if (body.startsWith('EXPECT-EXIT:')) {
      if (sawExit) errors.add('EXPECT-EXIT duplicado');
      sawExit = true;
      final v = int.tryParse(body.substring('EXPECT-EXIT:'.length).trim());
      if (v == null) {
        errors.add('EXPECT-EXIT não-numérico: `$body`');
      } else {
        exitCode = v;
      }
    } else {
      errors.add('diretiva desconhecida: `$body`');
    }
  }
  if (ice != null && buildError != null) {
    errors.add('EXPECT-ICE e EXPECT-ERROR no mesmo fixture');
  }
  // Fixture que nem chega a rodar não tem stdout para divergir. A diretiva ali
  // seria decoração — e decoração num header é o que a próxima pessoa lê como
  // fato verificado.
  if (jsDiverge != null && (ice != null || buildError != null)) {
    errors.add('JS-DIVERGE num fixture de fronteira/negativo — ele não executa');
  }
  if (expectStderr != null && (ice != null || buildError != null)) {
    errors.add('EXPECT-STDERR num fixture de fronteira/negativo — ele não executa');
  }
  // As DUAS metades da catraca do stderr, e nenhuma delas é decoração:
  //
  //   metade 1 — exit ≠ 0 SEM a diretiva: "saiu 255" não distingue o panic que o
  //   fixture quer do crash que ele não quer. Um `interfaceTarget` na classe
  //   errada dá `NoSuchMethodError` e também sai 255; o fixture ficaria verde
  //   pelo motivo errado, que é o furo que o `EXPECT-ICE` de exit 65 já fecha do
  //   outro lado;
  //
  //   metade 2 — a diretiva com exit 0 CONTRADIZ a régua de que saída normal não
  //   escreve em stderr (mais abaixo). Aceitar as duas deixaria o fixture
  //   afirmando e negando a mesma coisa, e uma das duas ficaria muda.
  if (ice == null && buildError == null) {
    if (exitCode != 0 && expectStderr == null) {
      errors.add('EXPECT-EXIT: $exitCode sem `EXPECT-STDERR: <substring>` — '
          'exit ≠ 0 não diz POR QUE, e crash nosso sai igual');
    }
    if (exitCode == 0 && expectStderr != null) {
      errors.add('EXPECT-STDERR com EXPECT-EXIT: 0 — saída normal exige stderr VAZIO');
    }
  }
  return (
    expectIce: ice,
    expectError: buildError,
    expectExit: exitCode,
    expectStderr: expectStderr,
    jsDiverge: jsDiverge,
    errors: errors,
  );
}

/// O `toString` do `CodegenIce` é formato fixo (`emit.dart:54`). Extrair o código
/// e comparar por IGUALDADE (não `contains`): um `EXPECT-ICE:` truncado por typo
/// — `ice-codegen-cmp-on-String`, ou pior, `ice-codegen` — casaria com qualquer
/// coisa e o teste passaria afirmando menos do que aparenta.
final _iceLine = RegExp(r'^ice: (\S+) @(\d+)\+(\d+)$');

/// Idem para o diagnóstico do DRIVER (`compile.dart::checkMain`, §12-5).
final _errorLine = RegExp(r'^(\w+)-error: (\S+) @(\d+)\+(\d+)$');

Future<void> main(List<String> args) async {
  print('harness — o botão de vermelho funciona?');
  _h.selfTest();
  print('');

  final update = args.contains('--update');
  final root = _repoRoot();

  // ---- que alvos rodam nesta execução (§7.7) --------------------------------
  //
  // Default = os TRÊS. A §7.7 é literal — *"todo CA desta spec roda nos 3
  // alvos"* — e um default de `vm` faria a suíte inteira medir o alvo mais
  // permissivo: `interfaceTarget` da classe errada e `returnType: num` PASSAM no
  // JIT e só custam em AOT. O escape existe para iteração (`--targets=vm` roda
  // em ~10 s contra ~100 s), e é DECLARADO no relatório, nunca silencioso.
  final alvos = _parseTargets(args);
  if (alvos.isEmpty) {
    throw StateError('--targets vazio: nada a executar');
  }
  final dir = Directory('$root/conformance/codegen');
  if (!dir.existsSync()) {
    throw StateError('corpus não encontrado: ${dir.path}');
  }

  final fixtures = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tu'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // O `vm_platform.dill` (8 MB) é lido UMA vez; cada compilação desserializa um
  // `Component` FRESCO desses bytes — o `finalizeProgram` muta o platform
  // (anexa as libs do programa), logo reusar o mesmo Component acumularia libs
  // de um fixture no seguinte.
  final platformBytes = File(platformDillPath()).readAsBytesSync();

  print('Golden-runner do emitter — ${fixtures.length} fixtures');
  print('  corpus: ${dir.path}');
  print('  alvos:  ${alvos.map((a) => a.name.toUpperCase()).join(" × ")}'
      '${alvos.length == 3 ? "" : "  ⚠️ PARCIAL — o ledger não fechará os CAs dos alvos ausentes"}');
  print('  dart:   ${Platform.resolvedExecutable}');
  if (alvos.contains(AlvoExec.js)) {
    final node = _acharNode();
    if (node == null) {
      // Falha NOMEADA, não skip. Um "JS pulado" em cinza no fim de 100 linhas
      // de ✓ é lido como verde — e o alvo que a §7.7 exige não teria rodado.
      throw StateError('alvo JS pedido mas `node` não está no PATH — instale-o '
          'ou rode com `--targets=vm,aot` (o recorte fica no relatório)');
    }
    print('  node:   $node');
  }
  if (update) print('  modo:   --update (regravando os .out)');
  print('');
  print('pin (dart ↔ vm_platform.dill ↔ pkg/kernel vendorado):');
  checkPin(root);
  print('');

  final tempDir = Directory.systemTemp.createTempSync('ita_golden_');
  try {
    for (final fixture in fixtures) {
      final name = fixture.uri.pathSegments.last;
      final stem = name.substring(0, name.length - 3);
      final source = fixture.readAsStringSync();
      final directives = parseDirectives(source);
      print('$name:');

      // O harness confere a si mesmo ANTES de conferir o fixture.
      if (directives.errors.isNotEmpty) {
        for (final e in directives.errors) {
          fail('diretiva inválida — $e');
        }
        print('');
        continue;
      }

      final outcome = compileToDill(fixture.path, platformBytes: platformBytes);
      final goldenFile = File('${dir.path}/$stem.out');

      // ---- fixture de FRONTEIRA: o ICE É o resultado esperado --------------
      final expectIce = directives.expectIce;
      if (expectIce != null) {
        // Um `.out` órfão aqui é resíduo de promoção revertida — o fixture não
        // roda, então o golden não pode existir.
        if (goldenFile.existsSync()) {
          fail('golden ÓRFÃO: $stem.out existe num fixture EXPECT-ICE (apague-o)');
        }
        if (outcome.code == null) {
          fail(
            'esperava $expectIce, mas COMPILOU — a fatia nasceu? '
            'promova a fixture a CA verde (rode --update e remova o EXPECT-ICE)',
          );
        } else if (outcome.code != 70) {
          // O furo clássico do xfail: passar pelo motivo errado. Um erro de FASE
          // (65) não é a fronteira da emissão — é a fixture nem chegando lá.
          fail(
            'esperava ICE (70), veio exit ${outcome.code} '
            '(erro de FASE — a fixture parou ANTES da emissão)',
            detail: outcome.diagnostics.join('\n'),
          );
        } else {
          final line = outcome.diagnostics.join('\n');
          final m = _iceLine.firstMatch(line);
          if (m == null) {
            fail('ICE ilegível (o formato do CodegenIce mudou?): $line');
          } else if (m.group(1) != expectIce) {
            fail('ICE ${m.group(1)} ≠ esperado $expectIce');
          } else {
            check(true, 'ICE exato: $expectIce');
            _frontiers++;
          }
        }
        print('');
        continue;
      }

      // ---- fixture de ERRO DE USUÁRIO (§12-5): o driver reprova antes da F7 --
      final expectError = directives.expectError;
      if (expectError != null) {
        if (goldenFile.existsSync()) {
          fail('golden ÓRFÃO: $stem.out num fixture EXPECT-ERROR (apague-o)');
        }
        final got = outcome.diagnostics.join('\n');
        if (outcome.code == null) {
          fail('esperava $expectError, mas COMPILOU');
        } else if (outcome.code != 65) {
          // Exit 70 aqui é a REGRESSÃO que este fixture existe para pegar: o erro
          // do usuário voltando a sair como ICE (§7.8 — "a F7 não tem erro de
          // usuário"), com a palavra `ice` na cara de quem só esqueceu o `main`.
          fail('esperava erro de usuário (65), veio exit ${outcome.code}',
              detail: got);
        } else {
          // grupo 1 = a FASE que reprovou (`check`/`flow`/`build`), grupo 2 = o
          // código. Só o código é comparado; a fase entra no relatório, porque
          // "quem falou" é informação útil e não é o que o fixture declara.
          final m = _errorLine.firstMatch(got);
          if (m == null) {
            fail('diagnóstico ilegível (formato mudou?): $got');
          } else if (m.group(2) != expectError) {
            fail('erro ${m.group(2)} ≠ esperado $expectError');
          } else {
            check(true, 'erro exato: $expectError (fase: ${m.group(1)})');
            _negatives++;
          }
        }
        print('');
        continue;
      }

      // ---- fixture VERDE: compila, roda, compara stdout + exit -------------
      if (outcome.code != null) {
        fail(
          'não compilou (exit ${outcome.code})',
          detail: outcome.diagnostics.join('\n'),
        );
        // ⚠️ Os invariantes rodam MESMO com o verify reprovando (exit 71) — é
        // exatamente aí que eles têm mais a dizer: o verify nomeia o SINTOMA
        // ("Incorrect parent pointer"), o invariante nomeia a CAUSA (qual nó
        // está compartilhado). Sem isto, uma falha de boa-formação daria só a
        // mensagem do verify, e a classe ficaria dependente de um gate que a
        // VM não roda.
        final libs = outcome.libs;
        if (libs != null) {
          for (final v in checkNoSharedNodes(libs)) {
            fail('invariante violado — $v');
          }
        }
        print('');
        continue;
      }

      // ---- camada INTENSIONAL: o que roda igual e está errado --------------
      // Roda ANTES da execução: se o `.dill` viola o ADR-0013 ou o CA11, o
      // stdout casar com o golden não redime nada.
      // Os nomes de tipo que o PROGRAMA declarou — a régua do "custo zero":
      // qualquer `Class` no `.dill` fora desta lista foi sintetizada pela
      // emissão, e a spec quer zero nó para `Option`/`any` de fonte local.
      // Todo tipo NOMINAL que o usuário declarou — `struct`, `class` e `enum`.
      // Esquecer um faz o invariante acusar emissão legítima (foi o que
      // aconteceu com `enum` na primeira execução): a régua erra no
      // desconhecido, então a lista tem de acompanhar cada forma nova de decl.
      final declaredTypes = <String>{
        for (final item in outcome.check!.program.body)
          if (item is ast.StructDecl)
            item.name
          else if (item is ast.ClassDecl)
            item.name
          else if (item is ast.EnumDecl)
            item.name
          else if (item is ast.TraitDecl)
            item.name,
      };
      final existencial = checkExistentialZeroNode(
        outcome.travessias!,
        outcome.check!.coercions,
      );
      _travessiasInspecionadas += existencial.exercitou;
      final structural = [
        ...checkInvariants(outcome.libs!),
        ...checkNoSharedNodes(outcome.libs!),
        ...checkConformanceTraps(outcome.libs!),
        ...checkNoSyntheticClasses(outcome.libs!, declaredTypes),
        // **CA11** — no SÍTIO da travessia, não globalmente: o CA10 acima vê
        // wrapper enquanto CLASSE, e um box feito de `AsExpression` ou de helper
        // static passaria por ele inteiro.
        ...existencial.violations,
        ...checkSerializedLibraries(loadComponentFromBytes(outcome.bytes!)),
        // O TIPO do receptor autoriza o alvo. Pega o que o verify não pega —
        // `interfaceTarget` da classe errada roda certo no JIT e só quebra em
        // AOT, então nem este runner nem o golden de stdout o veriam.
        ...checkTypeConsistency(outcome.component!),
        // O `NaiveTypeChecker` ignora o `functionType` dos operadores
        // especializados, então este é o único que pega `Int + Int : num`.
        ...checkNumericStaticTypes(outcome.libs!),
        // Labels não atravessam fronteira de função. O verifier não tem
        // `visitBreakStatement`, e a falha aparece na SERIALIZAÇÃO — depois
        // dele e dos outros invariantes, como `Null check operator` do vendor.
        ...checkBreakTargets(outcome.libs!),
        // A `Source` do `.tu` no Component. O JIT degrada sem ela; o AOT aborta
        // num FATAL do gerador de DWARF que não menciona `uriToSource`.
        ...checkSourcesRegistered(outcome.component!, outcome.libs!),
      ];

      // ---- ORDEM TEXTUAL NÃO IMPORTA (o letrec da F4, cobrado na F7) -------
      //
      // A régua mora em `invariants.dart` (com RED próprio em
      // `invariants_test.dart`, via emissor-dublê); aqui só se liga o emissor
      // real a ela.
      final ordem = checkOrderIndependence(
        outcome.check!.program.body,
        () => emitProgram(
          outcome.check!,
          loadComponentFromBytes(platformBytes),
          sourceUri: File(fixture.path).absolute.uri,
        ),
      );
      if (ordem.exercitou) _ordemExercitada++;
      final rel = outcome.saneamento;
      if (rel != null) {
        for (final e in rel.entries) {
          _saneamento[e.key] = (_saneamento[e.key] ?? 0) + e.value;
        }
      }
      if (ordem.violations.isEmpty) {
        // A etiqueta DIZ quando não exercitou. Um fixture de 1 declaração não
        // tem ordem para variar, e imprimir o mesmo ✓ dos outros afirmaria uma
        // verificação que não houve — 11 dos 35 fixtures estão nesse caso.
        check(
          true,
          ordem.exercitou
              ? 'ordem textual das declarações não importa (letrec da F4)'
              : 'ordem: 1 declaração — nada a permutar (não conta como prova)',
        );
      } else {
        for (final v in ordem.violations) {
          fail(v);
        }
      }
      if (structural.isEmpty) {
        check(true,
            'invariantes (zero dynamic · targets · árvore · CA13 · só-libs · tipos · num · break)');
      } else {
        for (final v in structural) {
          fail('invariante violado — $v');
        }
      }

      final dillPath = '${tempDir.path}/$stem.dill';
      File(dillPath).writeAsBytesSync(outcome.bytes!);

      // ---- VM (JIT): a REFERÊNCIA da §7.7 ---------------------------------
      final vm = await _rodar(Platform.resolvedExecutable, [dillPath]);
      if (vm.travou) {
        fail('TRAVOU: o programa não terminou em 15 s (loop que não fecha?)');
        print('');
        continue;
      }
      _porAlvo[AlvoExec.vm] = (_porAlvo[AlvoExec.vm] ?? 0) + 1;
      final stdoutText = vm.stdout;
      final stderrText = vm.stderr;
      final exitCode = vm.exitCode;

      var stdoutOk = false;
      if (update) {
        goldenFile.writeAsStringSync(stdoutText);
        print('  ⟳ golden regravado: $stem.out '
            '(${stdoutText.split('\n').length - 1} linha(s))');
      } else if (!goldenFile.existsSync()) {
        // NUNCA auto-criar: seria carimbar de verde uma saída que ninguém leu —
        // exatamente o que o `--update` existe para tornar deliberado. No CI o
        // arquivo criado ainda morreria com o workspace.
        fail('golden AUSENTE: $stem.out — rode `make codegen-golden-update` e LEIA a saída',
            detail: stdoutText);
      } else {
        final expected = goldenFile.readAsStringSync();
        if (stdoutText == expected) {
          check(true, 'stdout == $stem.out');
          stdoutOk = true;
        } else {
          fail('stdout != $stem.out',
              detail: 'esperado:\n${_indent(expected)}\n'
                  'obtido:\n${_indent(stdoutText)}');
        }
      }

      final exitOk = exitCode == directives.expectExit;
      check(exitOk, 'exit $exitCode (esperado ${directives.expectExit})');
      if (!exitOk && stderrText.isNotEmpty) {
        for (final line in stderrText.trimRight().split('\n')) {
          print('      $line');
        }
      }

      // Saída normal não escreve em stderr; saída ≠ 0 escreve, e DIZ o quê.
      //
      // A substring é o mais que se pode assertar sem inventar contrato: a
      // mensagem inteira carrega detalhe que muda com o alvo e com o dado
      // (`RangeError (length): … Only valid value is 0: 5` traz o tamanho da
      // lista), e a CLASSE diverge — `RangeError` na VM/AOT, `IndexError` no
      // dart2js, que só converge no stderr porque `IndexError._errorName`
      // devolve `"RangeError"` (`core/errors.dart:535`).
      final wantStderr = directives.expectStderr;
      if (directives.expectExit == 0) {
        check(stderrText.isEmpty,
            'stderr vazio${stderrText.isEmpty ? '' : ' (veio: ${stderrText.trim()})'}');
      } else if (wantStderr != null) {
        final casou = stderrText.contains(wantStderr);
        check(casou,
            casou
                ? 'stderr contém `$wantStderr`'
                : 'stderr NÃO contém `$wantStderr` — saiu ${exitCode}, mas por outra '
                    'razão que não a declarada (veio: ${stderrText.trim()})');
      }

      // ---- AOT: "empata a VM byte a byte em stdout + exit code" (§7.7) -----
      //
      // A comparação é contra a SAÍDA DA VM desta execução, não contra o `.out`:
      // o contrato da §7.7 é entre os dois alvos. Comparar cada um com o golden
      // deixaria passar o caso em que ambos mudaram juntos e o golden foi
      // regravado — e é justamente o AOT que pega o que o JIT perdoa
      // (`interfaceTarget` da classe errada, `returnType: num` e o unboxing).
      var aotOk = true;
      if (alvos.contains(AlvoExec.aot)) {
        aotOk = false;
        final full = '${tempDir.path}/${stem}_full.dill';
        // O AOT exige o `.dill` COMPLETO: o `gen_kernel` do `dart compile exe`
        // não relinca platform nenhum (ver `serializeFullComponent`).
        File(full).writeAsBytesSync(serializeFullComponent(outcome.component!));
        final exe = '${tempDir.path}/$stem.exe';
        final c = await _rodar(
          Platform.resolvedExecutable,
          ['compile', 'exe', full, '-o', exe],
          timeout: const Duration(seconds: 180),
        );
        if (c.exitCode != 0 || c.travou) {
          fail('AOT: `dart compile exe` falhou', detail: c.stderr);
        } else {
          final r = await _rodar(exe, const []);
          if (r.travou) {
            fail('AOT TRAVOU: o binário não terminou em 15 s');
          } else if (r.stdout != stdoutText) {
            fail('AOT: stdout DIFERE da VM — a §7.7 exige empate byte a byte',
                detail: 'VM:\n${_indent(stdoutText)}\n'
                    'AOT:\n${_indent(r.stdout)}');
          } else if (r.exitCode != exitCode) {
            fail('AOT: exit ${r.exitCode} ≠ VM $exitCode');
          } else {
            check(true, 'AOT empata a VM (stdout + exit ${r.exitCode})');
            aotOk = true;
            _porAlvo[AlvoExec.aot] = (_porAlvo[AlvoExec.aot] ?? 0) + 1;
          }
        }
      }

      // ---- JS: paridade, ou DIVERGÊNCIA declarada (§7.7 + §12-6) -----------
      var jsOk = true;
      if (alvos.contains(AlvoExec.js)) {
        jsOk = false;
        final jsFile = '${tempDir.path}/$stem.js';
        // O JS quer o `.dill` MÍNIMO — o mesmo de produção. O dart2js relinca o
        // platform DELE (`dart2js_platform.dill`), e sobre o completo ele morre:
        // o `vm_platform` embutido é de outro alvo. Medido em 2026-08-06.
        final c = await _rodar(
          Platform.resolvedExecutable,
          ['compile', 'js', dillPath, '-o', jsFile],
          timeout: const Duration(seconds: 180),
        );
        final divergeFile = File('${dir.path}/$stem.js.out');
        final razao = directives.jsDiverge;
        if (c.exitCode != 0 || c.travou) {
          fail('JS: `dart compile js` falhou', detail: c.stderr);
        } else {
          final r = await _rodar(_acharNode()!, [jsFile]);
          final empata = r.stdout == stdoutText;
          // A §11 escreve o exit do JS como *"exceção não-capturada, exit ≠ 0"*
          // (CA9): o node sai 1 onde a VM sai 255, e exigir igualdade seria
          // inventar um contrato que a spec não tem.
          final exitJsOk = (r.exitCode == 0) == (exitCode == 0);

          if (r.travou) {
            fail('JS TRAVOU: o node não terminou em 15 s');
          } else if (razao == null && divergeFile.existsSync()) {
            // Metade 1 da catraca: golden de divergência sem razão escrita.
            fail('JS: existe `$stem.js.out` mas falta `// JS-DIVERGE: <razão>` — '
                'golden de divergência sem razão é divergência escondida');
          } else if (razao != null && empata) {
            // Metade 2: sem ela a diretiva vira silenciador permanente (R12).
            fail('JS: `JS-DIVERGE` declarado ($razao) mas o JS EMPATA a VM — '
                'tire a diretiva e o `$stem.js.out`');
          } else if (razao != null) {
            if (update) {
              divergeFile.writeAsStringSync(r.stdout);
              print('  ⟳ golden JS regravado: $stem.js.out');
              jsOk = true;
            } else if (!divergeFile.existsSync()) {
              fail('JS: `JS-DIVERGE` declarado mas falta o golden $stem.js.out',
                  detail: r.stdout);
            } else if (r.stdout != divergeFile.readAsStringSync()) {
              fail('JS: stdout != $stem.js.out',
                  detail: 'esperado:\n${_indent(divergeFile.readAsStringSync())}\n'
                      'obtido:\n${_indent(r.stdout)}');
            } else if (!exitJsOk) {
              fail('JS: exit ${r.exitCode} — a VM saiu $exitCode (o sinal ≠0 tem de bater)');
            } else {
              check(true, 'JS diverge como DECLARADO ($razao)');
              jsOk = true;
              _jsDivergentes++;
              _porAlvo[AlvoExec.js] = (_porAlvo[AlvoExec.js] ?? 0) + 1;
            }
          } else if (!empata) {
            fail('JS: stdout DIFERE da VM e nada declara a divergência',
                detail: 'VM:\n${_indent(stdoutText)}\n'
                    'JS:\n${_indent(r.stdout)}\n'
                    'Se for semântica do alvo (§12-6), declare '
                    '`// JS-DIVERGE: <razão>` e grave `$stem.js.out`.');
          } else if (!exitJsOk) {
            fail('JS: exit ${r.exitCode} — a VM saiu $exitCode (o sinal ≠0 tem de bater)');
          } else {
            check(true, 'JS empata a VM (stdout + exit ≠0 ⟺ ≠0)');
            jsOk = true;
            _porAlvo[AlvoExec.js] = (_porAlvo[AlvoExec.js] ?? 0) + 1;
          }
        }
      }

      if (stdoutOk && exitOk && aotOk && jsOk) _greens++;
      print('');
    }
  } finally {
    tempDir.deleteSync(recursive: true);
  }

  // O total tem de ser honesto no lugar onde o leitor olha: um fixture de
  // FRONTEIRA contribui um ✓, mas não prova emissão nenhuma — prova que a
  // lacuna segue declarada. Somá-los num "todos verdes" afirmaria mais do que o
  // corpus provou.
  final fronteiras =
      _frontiers == 1 ? '1 fronteira declarada' : '$_frontiers fronteiras declaradas';
  // Corpus que não exercita a régua de ordem não testa a propriedade — e o
  // gate ficaria verde para sempre. É a mesma doutrina do `selfTest` do
  // harness, aplicada ao CORPUS em vez de ao contador.
  check(_ordemExercitada > 0,
      'ordem: $_ordemExercitada fixture(s) com 2+ declarações exercitam o letrec');
  // A outra metade da R12: a régua do CA11 só vale se ALGUM fixture cruzar um
  // valor para slot `any`. Sem isto, apagar a travessia de todos os fixtures
  // deixaria o CA11 verde para sempre — verde por não ter o que verificar.
  check(_travessiasInspecionadas > 0,
      'CA11: $_travessiasInspecionadas travessia(s) `any` inspecionada(s) no corpus');

  // ---- passes de saneamento: quem aplicou, e quem é vacuoso DECLARADO -------
  for (final e in _saneamento.entries) {
    final razao = _vacuosDeclarados[e.key];
    if (e.value > 0) {
      check(razao == null,
          razao == null
              ? 'saneamento `${e.key}`: ${e.value} aplicação(ões) sobre o corpus'
              : 'saneamento `${e.key}`: APLICOU ${e.value}× mas está na lista de '
                  'vacuosos — tire-o de lá (a catraca só encolhe)');
    } else {
      check(razao != null,
          razao != null
              ? 'saneamento `${e.key}`: 0 aplicações — VACUOSO declarado ($razao)'
              : 'saneamento `${e.key}`: 0 aplicações e NÃO declarado vacuoso — '
                  'passe que nunca se aplica é indistinguível de passe removido');
    }
  }

  // ---- alvos: quantos fixtures cada um EXECUTOU (R12 por alvo) -------------
  //
  // O número é o que o ledger lê. Um alvo pedido que executou ZERO é falha: ou o
  // corpus não tem fixture verde, ou o alvo não rodou de fato — e nos dois casos
  // fechar CA por ele seria afirmar o que não houve.
  for (final a in alvos) {
    final n = _porAlvo[a] ?? 0;
    check(n > 0,
        n > 0
            ? 'alvo ${a.name.toUpperCase()}: $n fixture(s) executados'
            : 'alvo ${a.name.toUpperCase()}: ZERO execuções — pedido e não exercitado');
  }
  if (_jsDivergentes > 0) {
    print('  ℹ️  JS: $_jsDivergentes fixture(s) com divergência DECLARADA (§12-6)');
  }

  // O registro só é gravado se a suíte fechou verde. Um `alvos-rodados` escrito
  // por uma execução que falhou diria ao ledger que o alvo passou.
  if (_h.fails == 0) {
    RegistroDeAlvos(Map.of(_porAlvo)).gravar(root);
    if (alvos.length < AlvoExec.values.length) {
      final fora = AlvoExec.values.where((a) => !alvos.contains(a));
      print('  ⚠️  registro PARCIAL — ${fora.map((a) => a.name).join(", ")} '
          'não rodaram; o ledger os tratará como não-exercitados');
    }
  }

  print(_h.fails == 0
      ? 'Golden-runner: $_greens verdes · $_negatives negativos · $fronteiras ✅'
      : 'Golden-runner: ${_h.fails} CHECK(S) VERMELHO(S) ❌');
  if (_h.fails > 0) throw StateError('${_h.fails} checks falharam');
}

/// Uma execução: o que saiu, e se terminou.
typedef Execucao = ({String stdout, String stderr, int exitCode, bool travou});

/// `Process.start` + timeout (não `Process.run`): um lowering errado de
/// `while`/`for` penduraria o job até o timeout do runner de CI. "Travou" tem de
/// ser uma falha NOMEADA, não um job morto — e vale igual para o `dart compile`,
/// que sobre um `.dill` malformado pode não voltar.
Future<Execucao> _rodar(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final proc = await Process.start(executable, args);
  final outF = proc.stdout.transform(utf8.decoder).join();
  final errF = proc.stderr.transform(utf8.decoder).join();
  int code;
  try {
    code = await proc.exitCode.timeout(timeout);
  } on TimeoutException {
    proc.kill(ProcessSignal.sigkill);
    return (stdout: '', stderr: '', exitCode: -1, travou: true);
  }
  return (
    stdout: await outF,
    stderr: await errF,
    exitCode: code,
    travou: false,
  );
}

/// `--targets=vm,aot,js` (default: os três). Um nome desconhecido é ERRO, não
/// um alvo ignorado: `--targets=aoot` rodaria só a VM e o relatório dirias que
/// foi o pedido.
Set<AlvoExec> _parseTargets(List<String> args) {
  final flag = args.where((a) => a.startsWith('--targets=')).lastOrNull;
  if (flag == null) return AlvoExec.values.toSet();
  final nomes = flag.substring('--targets='.length).split(',');
  final out = <AlvoExec>{};
  for (final n in nomes.map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final a = AlvoExec.values.where((v) => v.name == n).firstOrNull;
    if (a == null) {
      throw StateError('--targets desconhecido: `$n` '
          '(conhecidos: ${AlvoExec.values.map((v) => v.name).join(", ")})');
    }
    out.add(a);
  }
  return out;
}

/// O `node` do PATH. O alvo JS precisa de um runtime, e o SDK não traz um.
String? _acharNode() {
  for (final c in ['node', 'nodejs']) {
    final r = Process.runSync('which', [c]);
    if (r.exitCode == 0) return r.stdout.toString().trim();
  }
  return null;
}

/// Indenta um bloco para o relatório de falha. O `trimRight` evita a linha
/// fantasma que o `\n` final de todo stdout produziria no `split`.
String _indent(String text) =>
    text.trimRight().split('\n').map((l) => '        $l').join('\n');

/// Raiz do repo: o diretório que contém o `dart-sdk.pin`. Âncora normativa —
/// sondar `conformance/` acharia o diretório errado num checkout aninhado, e o
/// pin é justamente o arquivo que este runner precisa ler.
String _repoRoot() {
  for (final candidate in ['..', '.', '../..']) {
    if (File('$candidate/dart-sdk.pin').existsSync()) return candidate;
  }
  throw StateError(
    'dart-sdk.pin não encontrado a partir de ${Directory.current.path}',
  );
}
