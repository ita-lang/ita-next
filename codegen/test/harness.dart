// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// ============================================================================
// harness.dart — o mínimo de infraestrutura de teste, com KILL-SWITCH provado
// ============================================================================
//
// Harness próprio, sem `package:test` (o `pkg/kernel` vendorado força `_fe 98`
// e `package:test` puxa `analyzer 14` — spec 013 §0-A).
//
// ⚠️ **Por que isto existe como arquivo, e não copiado em cada suíte.**
//
// Havia CINCO cópias de `int _fails` + `void check`, e **nenhuma provava que
// sabia ficar vermelha**. Mutação medida em 2026-07-29 (mutante M8): trocar
// `if (!cond) _fails++` por `if (false) _fails++` num harness deixa a suíte
// inteira VERDE — todos os checks passam a imprimir `✗ FAIL:` e o processo sai
// com 0. E como nenhum `check(false, …)` dispara em nenhuma das 5 suítes num
// dia normal, **nada distingue um harness que funciona de um que perdeu o botão
// de vermelho**.
//
// É a falha que apaga todas as outras: com o kill-switch quebrado, os 12
// invariantes, o golden-runner, o ledger de CAs e o gate de citações viram
// decoração simultaneamente, e o CI segue verde.
//
// [Harness.selfTest] roda ANTES de qualquer asserção real e prova as duas
// metades: `check(false)` conta, `check(true)` não conta. Se qualquer uma
// falhar, a suíte morre ali — antes de afirmar qualquer coisa sobre o emitter.

/// Contador + impressão, com o kill-switch auditável.
///
/// Uma instância por suíte; `main` chama [selfTest] primeiro e [finish] no fim.
class Harness {
  Harness(this.nome);

  /// Nome da suíte, usado no veredito final.
  final String nome;

  int _fails = 0;

  /// Quantos checks falharam até agora.
  int get fails => _fails;

  void check(bool cond, String label) {
    print('  ${cond ? '✓' : '✗ FAIL:'} $label');
    if (!cond) _fails++;
  }

  void fail(String label, {String? detail}) {
    print('  ✗ FAIL: $label');
    if (detail != null && detail.isNotEmpty) {
      for (final line in detail.trimRight().split('\n')) {
        print('      $line');
      }
    }
    _fails++;
  }

  /// **O harness sabe ficar VERMELHO?**
  ///
  /// Exercita as duas direções sobre o contador real e restaura o estado. Não
  /// usa [check] para reportar o próprio resultado — se o `check` estiver
  /// quebrado, reportar por ele seria pedir ao réu que se julgue.
  void selfTest() {
    final antes = _fails;

    // Direção 1: falha CONTA. O `✗ FAIL:` impresso aqui é esperado — a linha
    // seguinte diz isso, para ninguém caçar um fantasma na saída.
    check(false, '(auto-teste do harness: este ✗ é ESPERADO e será desfeito)');
    final contouFalha = _fails == antes + 1;

    // Direção 2: sucesso NÃO conta. Sem ela, um `_fails++` incondicional
    // passaria — e um harness que conta tudo é tão inútil quanto um que não
    // conta nada, só falha para o outro lado.
    check(true, '(auto-teste do harness: este ✓ não pode contar falha)');
    final sucessoNaoConta = _fails == antes + 1;

    _fails = antes; // desfaz a falha deliberada

    if (!contouFalha) {
      print('  ✗✗ HARNESS QUEBRADO — `check(false)` NÃO contou falha.');
      print('      Toda asserção desta suíte é decoração. Ver M8 em harness.dart.');
      throw StateError('kill-switch do harness: check(false) não conta');
    }
    if (!sucessoNaoConta) {
      print('  ✗✗ HARNESS QUEBRADO — `check(true)` contou falha.');
      throw StateError('kill-switch do harness: check(true) conta');
    }
    print('  ✓ kill-switch do harness: falha conta, sucesso não conta');
  }

  /// Imprime o veredito e LANÇA se houver falha. Todo `main` termina aqui.
  void finish() {
    print(_fails == 0
        ? '\n$nome: TODOS OS CHECKS VERDES ✅'
        : '\n$nome: $_fails CHECK(S) VERMELHO(S) ❌');
    if (_fails > 0) throw StateError('$_fails checks falharam');
  }
}
