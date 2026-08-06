// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// alvos.dart — o registro do que o golden-runner EXECUTOU, e a ponte até o
// ledger de CAs.
//
// Existe por uma razão só, e ela é a R9. Até 2026-08-06 o ledger afirmava os
// alvos por uma CONSTANTE escrita à mão (`ca_ledger.dart`: `const alvosRodados =
// {Alvo.vm, Alvo.ci}`). Enquanto a constante era conservadora ela não fazia mal
// — mas o dia em que alguém ligasse AOT e JS, a forma de "fechar seis CAs" seria
// editar a constante, e seis ✅ apareceriam sem que nada tivesse rodado. O ledger
// nasceu justamente para matar esse movimento em outro lugar (o placar em
// markdown que o próprio commit editava); a constante era a mesma doença numa
// linha de Dart.
//
// Aqui o conjunto é DERIVADO: o runner grava o que executou, o ledger lê. Duas
// guardas fazem o arquivo valer alguma coisa:
//
//   1. **frescor** — o registro é ignorado se qualquer fonte do emitter ou do
//      corpus for mais nova que ele. Um `alvos-rodados` velho afirmaria sobre
//      código que já mudou, que é precisamente o defeito do placar editado à
//      mão, com um passo a mais de indireção;
//   2. **não-vacuidade** — alvo com 0 fixtures executados não entra. Alvo ligado
//      que rodou zero é indistinguível de alvo desligado (R12), e seria a versão
//      por-alvo do passe vacuoso.
//
// O arquivo é BUILD, não fonte: `codegen/build/` é gitignorado. Versioná-lo
// devolveria a edição à mão pela porta dos fundos.

import 'dart:io';

/// Os alvos de execução da **spec 013 §7.7** — *"todo CA desta spec roda nos 3
/// alvos"*. `ci` não aparece aqui: ele não executa programa nenhum, é o alvo dos
/// CAs estruturais (CA12/CA13), que o próprio `make codegen-test` satisfaz ao
/// rodar.
enum AlvoExec { vm, aot, js }

/// O que o runner executou, com quantos fixtures por alvo.
class RegistroDeAlvos {
  final Map<AlvoExec, int> fixturesPorAlvo;

  const RegistroDeAlvos(this.fixturesPorAlvo);

  /// Só os alvos com execução REAL (≥ 1 fixture). Ver guarda 2 no cabeçalho.
  Set<AlvoExec> get exercitados => fixturesPorAlvo.entries
      .where((e) => e.value > 0)
      .map((e) => e.key)
      .toSet();

  static File arquivo(String root) =>
      File('$root/codegen/build/alvos-rodados.txt');

  void gravar(String root) {
    final f = arquivo(root);
    f.parent.createSync(recursive: true);
    final linhas = AlvoExec.values
        .map((a) => '${a.name}=${fixturesPorAlvo[a] ?? 0}')
        .join('\n');
    f.writeAsStringSync('$linhas\n');
  }

  /// O registro, ou `null` se ausente **ou obsoleto**.
  ///
  /// [motivo] recebe a razão da recusa — o chamador tem de poder DIZER por que
  /// caiu no conservador, senão o fallback vira silêncio (é o mesmo motivo de
  /// `checkOrderIndependence` devolver `exercitou`).
  static RegistroDeAlvos? ler(String root, {void Function(String)? motivo}) {
    final f = arquivo(root);
    if (!f.existsSync()) {
      motivo?.call('nenhum registro em ${f.path} — o golden-runner não rodou');
      return null;
    }
    final carimbo = f.lastModifiedSync();
    final maisNova = _fonteMaisNova(root);
    if (maisNova != null && maisNova.$2.isAfter(carimbo)) {
      motivo?.call('registro OBSOLETO: `${maisNova.$1}` mudou depois dele '
          '— rode o golden-runner de novo');
      return null;
    }
    final mapa = <AlvoExec, int>{};
    for (final linha in f.readAsLinesSync()) {
      final p = linha.split('=');
      if (p.length != 2) continue;
      final alvo = AlvoExec.values.where((a) => a.name == p[0]).firstOrNull;
      final n = int.tryParse(p[1]);
      if (alvo != null && n != null) mapa[alvo] = n;
    }
    if (mapa.isEmpty) {
      motivo?.call('registro ILEGÍVEL em ${f.path}');
      return null;
    }
    return RegistroDeAlvos(mapa);
  }

  /// A fonte mais recente que invalida o registro: o emitter e o corpus. Não
  /// varre os testes — mudar uma asserção não muda o que o `.dill` faz.
  static (String, DateTime)? _fonteMaisNova(String root) {
    (String, DateTime)? pico;
    for (final dir in ['$root/codegen/lib', '$root/conformance/codegen']) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final e in d.listSync(recursive: true).whereType<File>()) {
        if (!e.path.endsWith('.dart') &&
            !e.path.endsWith('.tu') &&
            !e.path.endsWith('.out')) {
          continue;
        }
        final m = e.lastModifiedSync();
        if (pico == null || m.isAfter(pico.$2)) {
          pico = (e.path.replaceFirst('$root/', ''), m);
        }
      }
    }
    return pico;
  }
}
