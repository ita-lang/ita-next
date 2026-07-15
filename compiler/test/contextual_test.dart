// ============================================================================
// contextual_test.dart — Fatia C: tipagem contextual (spec 010).
// ============================================================================
//
// O que esta fatia faz o tipo ESPERADO descer. A 009 entregou o modo `check`
// (⇐) quase vazio — só o `nil` morava lá; aqui ele se preenche.
//
// A fundação da ORDEM é **5.2.5** (efeitos colaterais controlados), não 6.5.5:
// o store da unificação é efeito colateral, e o livro manda *"restringir as
// ordens de avaliação permitidas … adicionando **arestas implícitas** no grafo
// de dependência"*. As arestas são as 2 rodadas do §4.3.
// ============================================================================

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:test/test.dart';

void main() {
  // Prelúdio: uma HOF concreta e uma genérica. `mapa<T,U>` é o caso fino — o
  // `U` só existe no CORPO da closure.
  const prelude =
      'fn dobra(xs: List<Int>, f: (Int) -> Int) -> List<Int> => xs\n'
      'fn mapa<T, U>(xs: List<T>, f: (T) -> U) -> List<U> => []\n';

  CheckResult check(String body) =>
      checkProgram(parseSource('$prelude fn m(xs: List<Int>) { $body }\n').program);
  List<String> codes(String body) => check(body).errors.map((e) => e.code).toList();

  // --------------------------------------------------------------------------
  // §4.2.1 — o gatilho é a ANOTAÇÃO dos params, não a forma
  // --------------------------------------------------------------------------
  group('§4.2.1 — closure: metade SINTETIZA', () {
    test('CA42c — `(x: Int) -> Int => x` sintetiza (não precisa de contexto)', () {
      // Antes da fatia C isto dava `cannot-infer` — um "não consigo" FALSO:
      // está inteiramente anotado, não falta contexto nenhum.
      expect(check('let c = (x: Int) -> Int => x').errors, isEmpty);
    });

    test('CA42d — `() => 5` sintetiza `() -> Int` (zero params)', () {
      expect(check('let c = () => 5').errors, isEmpty);
    });

    test('`(x: Int) => x` sintetiza — retorno vem do corpo', () {
      expect(check('let c = (x: Int) => x').errors, isEmpty);
    });

    test('CA42b — `(x) => x` sob anotação HERDA o param', () {
      expect(check('let c: (Int) -> Int = (x) => x').errors, isEmpty);
    });

    test('CA42 — `(x) => x` SEM contexto ⟶ cannot-infer', () {
      // O param é o buraco e não há de onde preenchê-lo (ADR-0013: falha de
      // inferência é ERRO, nunca `dynamic`).
      expect(codes('let c = (x) => x'), ['cannot-infer']);
    });

    test('CA52 — param anotado contra esperado divergente ⟶ mismatch', () {
      // Param anotado NÃO herda: ele é contrato, e contrato se confere.
      expect(codes('let q: (Int) -> Int = (x: String) => 1'), isNotEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // §4.3 — as 2 rodadas (o bug que a fatia C existe para matar)
  // --------------------------------------------------------------------------
  group('§4.3 — 2 rodadas: a closure RECEBE contexto', () {
    test(r'CA41 — `dobra(xs) { $0 * 2 }` ⟶ `$0 : Int`', () {
      // O bug do `check.dart:405` era `[for (a in args) _synth(a.value)]`:
      // sintetizava TODOS os args antes de unificar, e `_synth` de closure é
      // `cannot-infer` ⟹ a closure nunca chegava a receber contexto.
      expect(check(r'let r = dobra(xs) { $0 * 2 }').errors, isEmpty);
    });

    test('o `\$0` herdou Int de verdade — somar String falha', () {
      // Prova que o param foi LIGADO, não só aceito.
      expect(codes(r'let r = dobra(xs) { $0 + "s" }'), isNotEmpty);
    });

    test('R1 fixa `T:=Int` ANTES de a R2 descer na closure', () {
      expect(check(r'let r: List<Int> = mapa(xs) { $0 + 1 }').errors, isEmpty);
    });

    test('o `U` de `mapa<T,U>` vem do CORPO — a R1 o deixa livre', () {
      // O caso fino: exigir `want` inteiro determinado na R2 daria
      // `cannot-infer` num caso que a inferência alcança. A closure PRECISA
      // receber os params; o retorno ela RENDE.
      expect(check(r'let r: List<Int> = mapa(xs) { $0 * 2 }').errors, isEmpty);
    });

    test('`U` divergente do esperado ⟶ erro', () {
      expect(codes(r'let r: List<String> = mapa(xs) { $0 + 1 }'), isNotEmpty);
    });

    test('CA51 — diagnósticos saem em ORDEM-FONTE apesar das 2 rodadas', () {
      // As rodadas visitam fora da ordem textual; a ordem que o usuário LÊ é a
      // do arquivo (contrato da 009 §11).
      final r = check(r'let a = dobra("nao-e-lista") { $0 }');
      final offs = r.errors.map((e) => e.offset).toList();
      expect(offs, orderedEquals([...offs]..sort()));
    });
  });

  // --------------------------------------------------------------------------
  // §12-A — aridade contextual (respondido pela própria F3)
  // --------------------------------------------------------------------------
  group('§12-A — closure sem `\$k` ADOTA a aridade esperada', () {
    test('`mapa(xs) { "n" }` ⟶ ok: 1 arg esperado, 0 usados', () {
      // O comentário da F3 é normativo: *"SEM `$k`: mantém implícita … `map
      // { g() }` exige 1 arg mas usa 0 — **forçar arity-0 seria errado**"*.
      // Tratar como aridade 0 aqui desfaria a decisão da F3 no andar de cima.
      expect(check('let r: List<String> = mapa(xs) { "n" }').errors, isEmpty);
    });

    test('com `\$k`, a aridade do scan VALE ⟶ closure-arity-mismatch', () {
      // `dobra` quer `(Int) -> Int`; o `$1` faz o scan da F3 dar aridade 2.
      expect(codes(r'let r = dobra(xs) { $0 + $1 }'), ['closure-arity-mismatch']);
    });
  });

  // --------------------------------------------------------------------------
  // §4.1 — formas checking-only: 1 regra, 2 fundamentos
  // --------------------------------------------------------------------------
  group('§4.1 — checking-only', () {
    test('CA43 — `var r: List<Int> = []` ⟶ ok', () {
      expect(check('var r: List<Int> = []').errors, isEmpty);
    });

    test('CA43b — `let x = []` ⟶ cannot-infer (6.5.1: zero subexpressões)', () {
      // **Definicional, não política:** a síntese *"constrói o tipo … a partir
      // dos tipos de suas subexpressões"*; `[]` tem zero ⟹ não há de que
      // construir. Dar `List<α>` seria HM, recusado.
      expect(codes('let x = []'), ['cannot-infer']);
    });

    test('CA44 — `var m: Map<String, Int> = {}` ⟶ ok', () {
      expect(check('var mm: Map<String, Int> = {}').errors, isEmpty);
    });

    test('`{}` é map VAZIO, não bloco (fecha o §12-C)', () {
      // Verificado no parser: `{}` ⟶ `(map)`. A forma-chaves não compete em
      // posição de expressão porque não parseia lá.
      expect(check('var mm: Map<String, Int> = {}').errors, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // O chão (§4.6.1) — tabela FECHADA
  // --------------------------------------------------------------------------
  group('§4.6.1 — o chão: `List`/`Map` são builtin', () {
    test('`List<Int>` resolve (antes: unknown-type)', () {
      expect(check('let n: List<Int> = xs').errors, isEmpty);
    });

    test('aridade do chão é checada', () {
      expect(
        checkProgram(parseSource('fn f(x: List<Int, String>) {}\n').program)
            .errors.map((e) => e.code),
        contains('generic-arity-mismatch'),
      );
    });

    test('fora do chão ⟶ unknown-type (a tabela é FECHADA, §3.3-1)', () {
      expect(
        checkProgram(parseSource('fn f(x: Naoexiste<Int>) {}\n').program)
            .errors.map((e) => e.code),
        contains('unknown-type'),
      );
    });
  });

  // --------------------------------------------------------------------------
  // Funções genéricas — o gap que a fatia C revelou
  // --------------------------------------------------------------------------
  group('generics de FN entram em escopo', () {
    test('`fn mapa<T, U>(xs: List<T>)` resolve o `T`', () {
      // A A1 só planta cabeça para tipos NOMEADOS (struct/class/enum/trait) —
      // uma `fn` não é um tipo. Consequência não intencional: os generics dela
      // nunca entravam em escopo e `fn f<T>(x: List<T>)` dava `unknown-type` no
      // próprio `T`. Isso tornava o `instantiate` da fatia D (Alg. 6.19)
      // INALCANÇÁVEL a partir de fonte real.
      expect(
        checkProgram(parseSource('fn ident<T>(x: T) -> T => x\n').program).errors,
        isEmpty,
      );
    });

    test('o `T` de `f` é distinto do `T` de `g` (o par dona-nome identifica)', () {
      expect(
        checkProgram(parseSource(
          'fn f<T>(x: T) -> T => x\nfn g<T>(y: T) -> T => y\n',
        ).program).errors,
        isEmpty,
      );
    });

    test('aplicação de fn genérica unifica de verdade', () {
      expect(
        checkProgram(parseSource(
          'fn ident<T>(x: T) -> T => x\nfn m() { let a: Int = ident(5) }\n',
        ).program).errors,
        isEmpty,
      );
    });

    test('e erra quando o arg diverge', () {
      expect(
        checkProgram(parseSource(
          'fn par<T>(a: T, b: T) -> T => a\nfn m() { let x = par(1, "s") }\n',
        ).program).errors.map((e) => e.code),
        contains('type-mismatch'),
      );
    });
  });
}
