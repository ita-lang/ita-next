// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// ============================================================================
// ca_ledger_test.dart — a contabilidade da §11 é COBRADA
// ============================================================================
//
// Harness próprio (sem `package:test`). Rodar por `make codegen-test`.
//
// Três coisas, e nenhuma delas era verificada até 2026-07-29:
//
//   1. **O fixture existe.** O placar nomeava arquivos; ninguém conferia.
//   2. **O estado é DERIVADO da evidência**, não digitado — um CA com cláusula
//      sem fixture, ou com alvo exigido que não rodou, não pode ser verde.
//   3. **O `tasks.md` concorda com o ledger.** É aqui que a mentira aparece: a
//      tabela é editada pelo mesmo commit que ela avalia, então sem uma segunda
//      fonte ela é auto-referente.
//
// Quando este teste fica vermelho, a correção é ajustar o `tasks.md` (ou fechar
// a lacuna), NUNCA relaxar o ledger. O ledger é a leitura do texto normativo; se
// ele estiver errado, o erro é de leitura da spec e se corrige citando a spec.

import 'dart:io';

import 'ca_ledger.dart';
import 'harness.dart';

/// A raiz do repo, a partir de `Platform.script` (o runner roda de `codegen/`).
Directory get _root {
  var dir = File.fromUri(Platform.script).parent;
  while (!Directory('${dir.path}/conformance').existsSync()) {
    final up = dir.parent;
    if (up.path == dir.path) throw StateError('raiz do repo não encontrada');
    dir = up;
  }
  return dir;
}

void main() {
  final h = Harness('Ledger de CAs');
  print('harness — o botão de vermelho funciona?');
  h.selfTest();
  print('');

  final root = _root.path;

  print('ca_ledger — a evidência de cada CA existe:');
  {
    // Um fixture nomeado que não existe é a forma mais barata de placar falso:
    // ninguém abre 13 arquivos para conferir uma tabela.
    for (final ca in ledger) {
      for (final c in ca.clausulas) {
        final ev = c.evidencia;
        if (ev == null) {
          h.check(c.lacuna != null,
              '${ca.id}: cláusula sem evidência declara a LACUNA');
          continue;
        }
        if (ev.endsWith('.tu')) {
          h.check(File('$root/conformance/codegen/$ev').existsSync(),
              '${ca.id}: fixture `$ev` existe');
        } else if (ev.endsWith('.dart')) {
          h.check(File('$root/codegen/test/$ev').existsSync(),
              '${ca.id}: teste `$ev` existe');
        } else {
          // invariante estrutural: tem de ser um símbolo exportado de verdade
          final src = File('$root/codegen/lib/invariants.dart').readAsStringSync();
          h.check(src.contains('$ev('), '${ca.id}: invariante `$ev` existe');
        }
      }
    }
  }

  // O conjunto REAL, lido do registro que o golden-runner grava. `motivo` é
  // impresso sempre: cair no conservador em silêncio faria o placar encolher
  // sem que ninguém soubesse por quê — e um placar que muda sozinho é a mesma
  // doença do markdown editado à mão, com um passo a mais de indireção.
  final razoes = <String>[];
  final alvosRodados = alvosRodadosDe(root, motivo: razoes.add);
  print('');
  print('ca_ledger — alvos EXECUTADOS (lidos, não digitados):');
  print('  ${alvosRodados.map((a) => a.name).join(" · ")}');
  for (final r in razoes) {
    print('  ⚠️  $r');
  }

  print('');
  print('ca_ledger — o estado é DERIVADO, e o texto INTEIRO conta:');
  {
    // O CA3 é o caso que FUNDOU esta regra: `class` com `init` fechava, o
    // `extensionInits` do mesmo item era ICE, e o placar contava o CA inteiro.
    //
    // ⚠️ **A asserção que morava aqui era `estadoDe(ca3) == parcial`, e ela
    // apodreceu no dia em que o CA3 fechou** (2026-08-10) — pelo mesmo motivo
    // que a nota logo abaixo dá para o CA1: media o ESTADO, não a régua. Uma
    // asserção sobre um CA vivo tem prazo de validade; a régua não. O sintético
    // abaixo continua vermelho no dia em que `estadoDe` parar de olhar a 2ª
    // cláusula, e nenhum progresso real o apaga.
    const sintetico = CriterioAceite(
      'CA-sintetico',
      'a 1ª cláusula fecha; a 2ª não tem evidência — VM.',
      [
        Clausula('cláusula com evidência', evidencia: 'class_ca3.tu'),
        Clausula('cláusula sem evidência', lacuna: 'a fatia não existe'),
      ],
      {Alvo.vm},
    );
    h.check(estadoDe(sintetico, alvosRodados) == Estado.parcial,
        'meia evidência ⟹ PARCIAL (a régua que o CA3 fundou)');
    h.check(
        estadoDe(
              const CriterioAceite(
                'CA-sintetico-B',
                'as duas cláusulas fecham — VM.',
                [
                  Clausula('uma', evidencia: 'class_ca3.tu'),
                  Clausula('outra', evidencia: 'retrofit_init_ca3.tu'),
                ],
                {Alvo.vm},
              ),
              alvosRodados,
            ) ==
            Estado.fechado,
        'evidência inteira ⟹ FECHADO (a régua não é um `fail` disfarçado)');

    // Alvo é obrigação do texto, não nota de rodapé: o JIT não vê
    // `interfaceTarget` errado nem `returnType: num`.
    //
    // Os dois sentidos são assertados com conjuntos SINTÉTICOS, e não com o que
    // rodou hoje: no dia em que os 3 alvos passaram a rodar, a asserção antiga
    // ("CA1 é parcial") virou falsa — ela media o ambiente, não a régua. Uma
    // asserção que muda de veredito quando a INFRA muda não estava testando a
    // regra que diz testar.
    final ca1 = ledger.firstWhere((c) => c.id == 'CA1');
    h.check(ca1.alvosExigidos.length == 3,
        'CA1 exige 3 alvos (é o que o texto normativo escreve)');
    h.check(estadoDe(ca1, {Alvo.vm, Alvo.ci}) == Estado.parcial,
        'CA1 com só a VM ⟹ PARCIAL');
    h.check(estadoDe(ca1, {Alvo.vm, Alvo.aot, Alvo.js, Alvo.ci}) == Estado.fechado,
        'CA1 com os 3 alvos ⟹ FECHADO (a régua não é um `fail` disfarçado)');

    final ca13 = ledger.firstWhere((c) => c.id == 'CA13');
    h.check(estadoDe(ca13, alvosRodados) == Estado.fechado,
        'CA13 FECHA — alvo CI, e as duas cláusulas têm invariante');
  }

  print('');
  print('ca_ledger — o `tasks.md` concorda com o ledger:');
  {
    final tasks = File('$root/specs/013-codegen-kernel/tasks.md').readAsLinesSync();
    for (final ca in ledger) {
      final esperado = glifo(estadoDe(ca, alvosRodados));
      // a linha do placar: `| CA3 ... | ✅ | ... |`
      final linha = tasks.firstWhere(
        (l) => l.startsWith('| ${ca.id} ') || l.startsWith('| ${ca.id}\t'),
        orElse: () => '',
      );
      if (linha.isEmpty) {
        h.check(false, '${ca.id}: sem linha no placar do `tasks.md`');
        continue;
      }
      h.check(linha.contains(esperado),
          '${ca.id}: placar diz $esperado (derivado da evidência)');
    }
  }

  print('');
  print('ca_ledger — resumo derivado:');
  final fechados =
      ledger.where((c) => estadoDe(c, alvosRodados) == Estado.fechado).length;
  final parciais =
      ledger.where((c) => estadoDe(c, alvosRodados) == Estado.parcial).length;
  final abertos =
      ledger.where((c) => estadoDe(c, alvosRodados) == Estado.aberto).length;
  for (final ca in ledger) {
    final p = pendencia(ca, alvosRodados);
    print('  ${glifo(estadoDe(ca, alvosRodados))} ${ca.id}${p.isEmpty ? "" : " — $p"}');
  }
  print('');
  print('  $fechados fechado(s) · $parciais parcial(is) · $abertos aberto(s)');

  print('');
  if (h.fails > 0) {
    // `${h.fails}`, não `$h.fails`: o segundo interpola o OBJETO e concatena a
    // string ".fails", e a mensagem saía "Instance of 'Harness'.fails CHECK(S)".
    // Diagnóstico que não diz o número é meio diagnóstico — e este é o do gate.
    print('Ledger de CAs: ${h.fails} CHECK(S) VERMELHO(S) ❌');
    throw StateError('${h.fails} checks falharam');
  }
  print('Ledger de CAs: TODOS OS CHECKS VERDES ✅');
}
