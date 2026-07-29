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

int _fails = 0;
void check(bool cond, String label) {
  print('  ${cond ? '✓' : '✗ FAIL:'} $label');
  if (!cond) _fails++;
}

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
  final root = _root.path;

  print('ca_ledger — a evidência de cada CA existe:');
  {
    // Um fixture nomeado que não existe é a forma mais barata de placar falso:
    // ninguém abre 13 arquivos para conferir uma tabela.
    for (final ca in ledger) {
      for (final c in ca.clausulas) {
        final ev = c.evidencia;
        if (ev == null) {
          check(c.lacuna != null,
              '${ca.id}: cláusula sem evidência declara a LACUNA');
          continue;
        }
        if (ev.endsWith('.tu')) {
          check(File('$root/conformance/codegen/$ev').existsSync(),
              '${ca.id}: fixture `$ev` existe');
        } else if (ev.endsWith('.dart')) {
          check(File('$root/codegen/test/$ev').existsSync(),
              '${ca.id}: teste `$ev` existe');
        } else {
          // invariante estrutural: tem de ser um símbolo exportado de verdade
          final src = File('$root/codegen/lib/invariants.dart').readAsStringSync();
          check(src.contains('$ev('), '${ca.id}: invariante `$ev` existe');
        }
      }
    }
  }

  print('');
  print('ca_ledger — o estado é DERIVADO, e o texto INTEIRO conta:');
  {
    // O CA3 é o caso que funda esta regra: `class` com `init` fecha, mas o
    // `extensionInits` do mesmo item é ICE — e o placar contava o CA inteiro.
    final ca3 = ledger.firstWhere((c) => c.id == 'CA3');
    check(estadoDe(ca3) == Estado.parcial,
        'CA3 é PARCIAL — a 2ª cláusula (`extensionInits`) é ICE');

    // Alvo é obrigação do texto, não nota de rodapé: o JIT não vê
    // `interfaceTarget` errado nem `returnType: num`.
    final ca1 = ledger.firstWhere((c) => c.id == 'CA1');
    check(ca1.alvosExigidos.length == 3 && estadoDe(ca1) == Estado.parcial,
        'CA1 exige 3 alvos e só a VM rodou ⟹ PARCIAL');

    final ca13 = ledger.firstWhere((c) => c.id == 'CA13');
    check(estadoDe(ca13) == Estado.fechado,
        'CA13 FECHA — alvo CI, e as duas cláusulas têm invariante');

    // Sem este caso o teste passaria com um ledger que reprova tudo.
    check(ledger.any((c) => estadoDe(c) == Estado.fechado),
        'algum CA fecha (a régua não é um `fail` disfarçado)');
  }

  print('');
  print('ca_ledger — o `tasks.md` concorda com o ledger:');
  {
    final tasks = File('$root/specs/013-codegen-kernel/tasks.md').readAsLinesSync();
    for (final ca in ledger) {
      final esperado = glifo(estadoDe(ca));
      // a linha do placar: `| CA3 ... | ✅ | ... |`
      final linha = tasks.firstWhere(
        (l) => l.startsWith('| ${ca.id} ') || l.startsWith('| ${ca.id}\t'),
        orElse: () => '',
      );
      if (linha.isEmpty) {
        check(false, '${ca.id}: sem linha no placar do `tasks.md`');
        continue;
      }
      check(linha.contains(esperado),
          '${ca.id}: placar diz $esperado (derivado da evidência)');
    }
  }

  print('');
  print('ca_ledger — resumo derivado:');
  final fechados = ledger.where((c) => estadoDe(c) == Estado.fechado).length;
  final parciais = ledger.where((c) => estadoDe(c) == Estado.parcial).length;
  final abertos = ledger.where((c) => estadoDe(c) == Estado.aberto).length;
  for (final ca in ledger) {
    final p = pendencia(ca);
    print('  ${glifo(estadoDe(ca))} ${ca.id}${p.isEmpty ? "" : " — $p"}');
  }
  print('');
  print('  $fechados fechado(s) · $parciais parcial(is) · $abertos aberto(s)');

  print('');
  if (_fails > 0) {
    print('Ledger de CAs: $_fails CHECK(S) VERMELHO(S) ❌');
    throw StateError('$_fails checks falharam');
  }
  print('Ledger de CAs: TODOS OS CHECKS VERDES ✅');
}
