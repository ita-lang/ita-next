// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// ============================================================================
// ca_ledger.dart — o placar da §11 deixa de ser markdown editável pelo commit
//                  que ele avalia
// ============================================================================
//
// Até 2026-07-29 um CA fechava assim: editando uma tabela no `tasks.md`, **no
// mesmo commit que implementa**. Sem campo de evidência, sem verificação, sem
// referência cruzada — `grep CA[0-9]` nos testes só achava comentário. O
// resultado foi medido:
//
//   - 6 dos 10 ✅ (60%) marcados contra um requisito de ALVO que nunca rodou;
//   - CA3 ✅ com metade do texto normativo em ICE (`extensionInits`);
//   - CA11 declarado ABERTO por um commit e re-marcado ✅ 17 minutos depois;
//   - a DoD da própria spec toda desmarcada, enquanto o placar dizia 10/13.
//
// A doutrina que proíbe exatamente isso já existia — e foi escrita 2 h antes de
// 5 dos 6 serem marcados. Doutrina sem executável é violada por quem a escreveu.
//
// Este ledger é a fonte única: texto normativo verbatim, cláusulas, alvos
// EXIGIDOS pelo próprio item, e a evidência. O estado de cada CA é **derivado**
// da evidência, nunca declarado — e o `ca_ledger_test.dart` cobra que o placar
// do `tasks.md` concorde com o que foi derivado.
//
// A régua, em uma frase: **um CA só é verde quando o texto INTEIRO do CA foi
// verificado, no(s) alvo(s) que o próprio item escreve.**

import 'alvos.dart';

/// Os alvos da §7.7. `ci` é o alvo dos CAs estruturais (não executam programa).
enum Alvo { vm, aot, js, ci }

/// Uma cláusula do texto normativo de um CA.
///
/// CAs com `;` ou `+` no texto têm mais de uma obrigação, e cada uma precisa de
/// evidência PRÓPRIA. O CA3 é a prova de por que isto é um campo: ele diz
/// *"`class` com `init` explícito valida; `extensionInits` são construtores
/// adicionais"* — duas cláusulas, a segunda em `ice-codegen-class-multi-init`
/// (`emit.dart`), e o placar contava o CA inteiro como fechado.
class Clausula {
  final String texto;

  /// Fixture em `conformance/codegen/` (ou nome de teste, para os de CI).
  /// `null` = **sem evidência**, e é isso que derruba o CA para PARCIAL.
  final String? evidencia;

  /// Por que não há evidência — obrigatório quando [evidencia] é `null`.
  final String? lacuna;

  const Clausula(this.texto, {this.evidencia, this.lacuna});
}

class CriterioAceite {
  final String id;

  /// **Verbatim da spec 013 §11.** Não é decoração: um resumo deixa a cláusula
  /// esquecida invisível, que foi como o CA3 passou.
  final String normativo;

  final List<Clausula> clausulas;

  /// Os alvos que o PRÓPRIO item escreve ("3 alvos", "VM + JS", "CI").
  final Set<Alvo> alvosExigidos;

  const CriterioAceite(this.id, this.normativo, this.clausulas, this.alvosExigidos);
}

/// **O que o golden-runner realmente executou** — LIDO, nunca digitado.
///
/// Até 2026-08-06 isto era `const alvosRodados = {Alvo.vm, Alvo.ci}`, e a forma
/// de fechar seis CAs seria editar a constante: seis ✅ apareceriam sem que nada
/// tivesse rodado. É exatamente o movimento que este ledger existe para matar em
/// outro lugar — o placar em markdown que o próprio commit editava —, só que numa
/// linha de Dart, onde parece dado e não opinião.
///
/// Agora vem de `codegen/build/alvos-rodados.txt`, que o golden-runner grava
/// **só quando fecha verde**, e que `alvos.dart` recusa se estiver obsoleto. Sem
/// registro fresco, o conservador: só a VM.
///
/// Por que o alvo é campo do ledger e não nota de rodapé: `interfaceTarget` da
/// classe errada e `returnType: num` PASSAM no JIT (a VM descarta os dois tipos)
/// e só custam em AOT, onde a TFA poda pelo cone da classe e o unboxing só
/// concede `kInt` a subtipo de `int`. "Roda e imprime certo" na VM prova menos
/// do que o placar sugere.
Set<Alvo> alvosRodadosDe(String root, {void Function(String)? motivo}) {
  // `ci` não é alvo de execução: é o dos CAs estruturais (CA12/CA13), e quem o
  // satisfaz é esta suíte estar rodando.
  final out = <Alvo>{Alvo.ci};
  final reg = RegistroDeAlvos.ler(root, motivo: motivo);
  if (reg == null) {
    out.add(Alvo.vm); // conservador: o mínimo que qualquer execução exercita
    return out;
  }
  for (final a in reg.exercitados) {
    out.add(switch (a) {
      AlvoExec.vm => Alvo.vm,
      AlvoExec.aot => Alvo.aot,
      AlvoExec.js => Alvo.js,
    });
  }
  return out;
}

const tresAlvos = {Alvo.vm, Alvo.aot, Alvo.js};

const ledger = <CriterioAceite>[
  CriterioAceite(
    'CA1',
    'fn main() { print("olá, \${1 + 1}") } ⟶ stdout `olá, 2`, exit 0 — 3 alvos.',
    [Clausula('stdout `olá, 2`, exit 0', evidencia: 'ca1_interp.tu')],
    tresAlvos,
  ),
  CriterioAceite(
    'CA2',
    'struct memberwise: `struct P { x: Int, y: Int = 2 }` + `print("\${P(x: 1).y}")` '
        '⟶ `2` — 3 alvos (defaults saltáveis chegam ao Kernel).',
    [Clausula('default saltável chega ao Kernel', evidencia: 'default_saltavel.tu')],
    tresAlvos,
  ),
  CriterioAceite(
    'CA3',
    '`class` com `init` explícito valida; `extensionInits` são construtores '
        'adicionais (ADR-0016 §B) — VM.',
    [
      Clausula('`class` com `init` explícito valida', evidencia: 'class_ca3.tu'),
      Clausula(
        '`extensionInits` são construtores adicionais',
        // ADR-0016 §B, verbatim: *"a extension é o glifo que diz 'estou
        // ADICIONANDO, não substituindo'"* — o construto foi DECIDIDO; o que
        // falta é a emissão cobri-lo. Isso é fatia, não ruling.
        lacuna: 'emit.dart faz `_ice(class-multi-init)`; zero fixtures usam '
            '`extension`',
      ),
    ],
    {Alvo.vm},
  ),
  CriterioAceite(
    'CA4',
    'dispatch existencial: `Pato`/`Cao` conformam `Fala`; `fn f(v: any Fala) => '
        'print(v.som())`; lista heterogênea imprime sons DIFERENTES — 3 alvos.',
    [Clausula('lista heterogênea imprime sons diferentes',
        evidencia: 'conformance_ca4.tu')],
    tresAlvos,
  ),
  CriterioAceite(
    'CA5',
    'default method roda via stub com `self` correto; conformer que SOBRESCREVE '
        'vence o default — 3 alvos.',
    [
      Clausula('default method roda via stub com `self` correto',
          lacuna: 'trait com default method é ICE (`trait-default-method`)'),
      Clausula('conformer que sobrescreve vence o default',
          lacuna: 'depende da cláusula anterior'),
    ],
    tresAlvos,
  ),
  CriterioAceite(
    'CA6',
    'membro vindo de `impl`/`extension` despacha igual a inline (origin nº3 → '
        'dentro da `Class`) — VM + JS.',
    [
      Clausula('membro de `impl`/`extension` despacha igual a inline',
          lacuna: '`extension`/`impl` no topo é ICE (`toplevel-ExtensionDecl`)'),
    ],
    {Alvo.vm, Alvo.js},
  ),
  CriterioAceite(
    'CA7',
    '`match` sobre enum-com-payload destrói e rende (RD-1: `=>` rende) — 3 alvos.',
    [Clausula('destrói e rende', evidencia: 'enum_payload.tu')],
    tresAlvos,
  ),
  CriterioAceite(
    'CA8',
    '`e?` propaga `.err` com early-return; caminho `.ok` segue — 3 alvos.',
    [
      Clausula('`e?` propaga `.err` com early-return', evidencia: 'result_try.tu'),
      Clausula('caminho `.ok` segue', evidencia: 'result_try.tu'),
    ],
    tresAlvos,
  ),
  CriterioAceite(
    'CA9',
    '`panic("x")` ⟶ exit ≠ 0, mensagem no stderr com linha-fonte (span) — VM + '
        'AOT; JS: exceção não-capturada, exit ≠ 0.',
    [Clausula('exit ≠ 0 + stderr com span', evidencia: 'panic_exit.tu')],
    {Alvo.vm, Alvo.aot},
  ),
  CriterioAceite(
    'CA10',
    '`Option`: `nil` vira `null` nativo — `let x: Int? = nil` + match imprime o '
        'braço `.none`; custo zero (sem classe Option no `.dill`) — VM.',
    [
      Clausula('match imprime o braço `.none`', evidencia: 'match_option.tu'),
      Clausula('custo zero — sem classe Option no `.dill`',
          evidencia: 'checkNoSyntheticClasses'),
    ],
    {Alvo.vm},
  ),
  CriterioAceite(
    'CA11',
    'travessia `any` de fonte local: zero nó extra no `.dill` (dump não contém '
        'wrapper) — VM.',
    [
      Clausula(
        'zero nó extra na travessia `any` de fonte local',
        lacuna: 'o `checkSerializedLibraries` foi rotulado CA11 até 2026-07-29 '
            'e NÃO é ele (é o libraryFilter, derivado da premissa da §8.1 — '
            'e não da §7.1, como se atribuiu até 2026-08-06). O CA11 real '
            'depende da fronteira existencial do ADR-0017, hoje ICE — o próprio '
            '`invariants.dart` o diz.',
      ),
    ],
    {Alvo.vm},
  ),
  CriterioAceite(
    'CA12',
    '`.dill` emitido passa `verifyComponent` do `pkg/kernel` vendorado (mesmo '
        'sabendo que a VM não o roda — é o NOSSO gate de sanidade) — CI.',
    [
      // A evidência que importa é o golden-runner: ele passa pelo
      // `finalizeProgram` com o `.dill` REAL de cada fixture. O
      // `finalize_test.dart` monta um `Component` À MÃO — prova o pipeline,
      // não o artefato, e sozinho seria evidência fraca.
      Clausula('o `.dill` EMITIDO passa o verify', evidencia: 'golden_test.dart'),
    ],
    {Alvo.ci},
  ),
  CriterioAceite(
    'CA13',
    'negativo: o `.dill` de CA4 não contém `mixedInType` nem `implements` sobre '
        'classe de `dart:core` (as 2 armadilhas do ADR-0017) — CI.',
    [
      Clausula('sem `mixedInType`', evidencia: 'checkConformanceTraps'),
      Clausula('sem `implements` sobre `dart:core`',
          evidencia: 'checkConformanceTraps'),
    ],
    {Alvo.ci},
  ),
];

/// Estado DERIVADO — nunca declarado.
enum Estado {
  /// Todas as cláusulas com evidência **e** todos os alvos exigidos rodaram.
  fechado,

  /// Tem evidência, mas falta cláusula ou falta alvo.
  parcial,

  /// Nenhuma cláusula tem evidência.
  aberto,
}

Estado estadoDe(CriterioAceite ca, Set<Alvo> alvosRodados) {
  final comEvidencia = ca.clausulas.where((c) => c.evidencia != null).length;
  if (comEvidencia == 0) return Estado.aberto;
  if (comEvidencia < ca.clausulas.length) return Estado.parcial;
  if (!alvosRodados.containsAll(ca.alvosExigidos)) return Estado.parcial;
  return Estado.fechado;
}

String glifo(Estado e) => switch (e) {
      Estado.fechado => '✅',
      Estado.parcial => '🟡',
      Estado.aberto => '❌',
    };

/// O que falta para o CA fechar — em uma linha, acionável.
String pendencia(CriterioAceite ca, Set<Alvo> alvosRodados) {
  final faltamAlvos = ca.alvosExigidos.difference(alvosRodados);
  final semEvidencia = ca.clausulas.where((c) => c.evidencia == null).toList();
  final partes = <String>[
    for (final c in semEvidencia) 'cláusula "${c.texto}" — ${c.lacuna}',
    if (faltamAlvos.isNotEmpty)
      'alvo(s) ${faltamAlvos.map((a) => a.name.toUpperCase()).join("+")} não rodaram',
  ];
  return partes.isEmpty ? '' : partes.join(' · ');
}
