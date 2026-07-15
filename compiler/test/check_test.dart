// ============================================================================
// check_test.dart — Fatia B da Fase 5: Check bidirecional (spec 009 §4.3-§4.6).
// ============================================================================
//
// Os CAs do §11 que cabem em A+B. O bloco mais importante é o do **mandato**:
// `nullity-invariant.md` (decisão de dono 2026-07-11) — seus 4 checkboxes são o
// que esta fase existe para entregar.
// ============================================================================

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:test/test.dart';

void main() {
  CheckResult check(String src) => checkProgram(parseSource(src).program);
  List<String> codes(String src) => check(src).errors.map((e) => e.code).toList();

  // --------------------------------------------------------------------------
  // O MANDATO — nullity-invariant.md (decisão de dono 2026-07-11)
  // --------------------------------------------------------------------------
  group('§4.6 — o invariante de nulidade FECHA aqui (sem flow-typing)', () {
    test('CA2 — `let x: String = nil` ⟶ nil-under-non-optional', () {
      // "nil é ausência INTENCIONAL e só é legal sob T?". O modo `check` É a
      // implementação: `nil` não SINTETIZA (§4.3).
      expect(codes('let x: String = nil'), ['nil-under-non-optional']);
    });

    test('CA3 — `let x: String? = nil` ⟶ ok', () {
      expect(check('let x: String? = nil').errors, isEmpty);
    });

    test('CA4 — `let x: String = ""` ⟶ ok, ZERO warning', () {
      // "NUNCA emitir warning/lint por valor vazio — é código idiomático".
      expect(check('let x: String = ""').errors, isEmpty);
      expect(check('let n: Int = 0').errors, isEmpty);
      expect(check('let b: Bool = false').errors, isEmpty);
    });

    test('CA5 — `let x = nil` ⟶ cannot-infer (nunca Nil, nunca dynamic)', () {
      // ADR-0013: falha de inferência é ERRO. O `NilType` do oracle é o sintoma
      // de não haver modo checking.
      expect(codes('let x = nil'), ['cannot-infer']);
    });

    test('`nil` sob campo não-opcional idem (o mandato vale em toda borda)', () {
      expect(codes('struct S { x: String = nil }'), ['nil-under-non-optional']);
    });

    test('CA9 — `member-on-optional`: T? tem Σ_membros = ∅', () {
      // O `!= nil` segue legal; o erro nasce no `.foo()`, ensinando o idioma.
      // Flow-narrowing é a cura de uma doença que o Itá não tem (§4.6).
      expect(
        codes('fn f(x: String?) { let y = x.length }'),
        contains('member-on-optional'),
      );
    });

    test('CA8 — `guard let` é DESESTRUTURAÇÃO: liga T, e o opt segue T?', () {
      // O binder é NOVO (o nome novo é a honestidade — P4); não há narrowing.
      final r = check(
        'fn f(o: Int?) -> Int { guard let v = o else { return 0 }\n return v }',
      );
      expect(r.errors, isEmpty); // `v` é Int, casa com `-> Int`
    });

    test('`guard let` sobre não-opcional ⟶ erro (nada a desembrulhar)', () {
      expect(
        codes('fn f(o: Int) { guard let v = o else { return } }'),
        contains('guard-let-on-non-optional'),
      );
    });
  });

  // --------------------------------------------------------------------------
  // §4.5 — coerção ZERO (nem widening)
  // --------------------------------------------------------------------------
  group('§4.5 — zero coerção, nem widening', () {
    test('CA7 — `1 + 1.0` ⟶ erro (o `max(t,t)=t`; nada de promoção)', () {
      // "Widening preserva" é FALSO no Itá: Int é 64-bit, Double tem 53 de
      // mantissa. E mantém o Itá fora do `num` do Dart, onde o unboxing morre.
      expect(codes('let x = 1 + 1.0'), ['no-operator-for-types']);
    });

    test('CA6 — literal tem tipo LEXICAL: `let x: Float = 1` ⟶ type-mismatch', () {
      // O lexer já decidiu int×float; a F5 reinterpretar o glifo contradiria uma
      // fase anterior.
      expect(codes('let x: Float = 1'), ['type-mismatch']);
      expect(check('let x: Float = 1.0').errors, isEmpty);
    });

    test('CA32 — `1 == "a"` ⟶ comparison-type-mismatch', () {
      expect(codes('let x = 1 == "a"'), ['comparison-type-mismatch']);
      expect(check('let x = 1 == 2').errors, isEmpty);
    });

    test('operações homogêneas passam', () {
      expect(check('let a = 1 + 2').errors, isEmpty);
      expect(check('let b = 1.5 * 2.0').errors, isEmpty);
      expect(check('let c = "a" + "b"').errors, isEmpty); // concatenação
    });
  });

  // --------------------------------------------------------------------------
  // §4.4 — bidirecional: dentro infere, borda anota
  // --------------------------------------------------------------------------
  group('§4.4 — dentro INFERE, borda ANOTA', () {
    test('CA1 — `let x = 5` infere Int (síntese; sem anotação)', () {
      expect(check('let x = 5').errors, isEmpty);
    });

    test('CA30 — `fn f(x) => x` ⟶ missing-param-annotation (a borda anota)', () {
      expect(codes('fn f(x) => x'), ['missing-param-annotation']);
      expect(check('fn f(x: Int) -> Int => x').errors, isEmpty);
    });

    test('CA31 — `-> T` ausente = Void, nunca "infira pra mim"', () {
      // `fn f() => 5` cai em type-mismatch de graça: Void ⇍ Int.
      expect(check('fn f() -> Int => 5').errors, isEmpty);
    });

    test('CA10 — `return`/corpo checa contra `-> T` (o oracle NÃO checa isto)', () {
      expect(codes('fn f() -> Int => "s"'), ['type-mismatch']);
      expect(codes('fn f() -> Int { return "s" }'), ['type-mismatch']);
    });

    test('default de param checa contra o tipo do param', () {
      expect(codes('fn f(x: Int = "s") -> Int => x'), ['type-mismatch']);
      expect(check('fn f(x: Int = 0) -> Int => x').errors, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // §4.3 — join, subsunção, not-bool
  // --------------------------------------------------------------------------
  group('§4.3 — join = identidade + bottom', () {
    test('CA12 — braços de tipos distintos ⟶ branch-type-mismatch', () {
      // Síntese nunca inventa supertipo — é o que evita o lub(Integer,String).
      expect(
        codes('fn f(c: Bool) { let x = if c => 1 else "s" }'),
        contains('branch-type-mismatch'),
      );
    });

    test('braços iguais passam', () {
      expect(check('fn f(c: Bool) { let x = if c => 1 else 2 }').errors, isEmpty);
    });

    test('CA14 — `join(Never, T) = T` (P3 + TAPL §15.4: bottom não restringe)', () {
      // Um braço que DIVERGE não impõe restrição sobre o tipo do resultado.
      expect(
        check('fn f(c: Bool) -> Int => if c => 1 else panic("x")').errors,
        isEmpty,
      );
    });

    test('CA13 — `if 1 {}` ⟶ not-bool (sem truthy)', () {
      expect(codes('fn f() { if 1 { } }'), ['not-bool']);
      expect(codes('fn f() { while "s" { } }'), ['not-bool']);
    });

    test('`&&`/`||` exigem exatamente Bool', () {
      expect(codes('let x = true && 1'), ['not-bool']);
      expect(check('let x = true && false').errors, isEmpty);
    });

    test('CA26 — subsunção: `let a: Animal = d` com `class D : Animal`', () {
      final r = check(
        'class Animal { n: String }\n'
        'class D : Animal { r: String }\n'
        'fn f(d: D) { let a: Animal = d }',
      );
      expect(r.errors, isEmpty); // D ≤ Animal — o ÚNICO ponto onde ≤ é consultado
    });

    test('subsunção NÃO inverte: `let d: D = a` ⟶ type-mismatch', () {
      expect(
        codes(
          'class Animal { n: String }\n'
          'class D : Animal { r: String }\n'
          'fn f(a: Animal) { let d: D = a }',
        ),
        ['type-mismatch'],
      );
    });

    test('`T ≤ T?` — o modificador admite o valor (§4.6)', () {
      expect(check('fn f(x: Int) { let o: Int? = x }').errors, isEmpty);
    });

    test('`T? ⇍ T` — o inverso não vale', () {
      expect(codes('fn f(o: Int?) { let x: Int = o }'), ['type-mismatch']);
    });
  });

  // --------------------------------------------------------------------------
  // §5.4 — `Try` é regra NÃO-LOCAL
  // --------------------------------------------------------------------------
  group('§0.5-6 / §5.4 — `?` só sob `Result`', () {
    test('CA22 — `?` em fn que não retorna Result ⟶ try-outside-result-fn', () {
      expect(
        codes('fn g() -> Int => 1\nfn f() -> Int => g()?'),
        contains('try-outside-result-fn'),
      );
    });
  });

  // --------------------------------------------------------------------------
  // Não-objetivos e contratos
  // --------------------------------------------------------------------------
  group('não-objetivos (§1) e contrato F4→F5', () {
    test('`for` não tipa o binder nesta spec (ruling §12-4)', () {
      // Tipar exigiria tabela hard-coded (`List<T>→T`) — a mágica que §4.5/§8.3
      // recusam. O trait `Iterator` é spec própria. `itac check` é incompleto
      // para `for` até lá — e isso está nos não-objetivos, explícito.
      expect(check('fn f(xs: Int) { for x in xs { } }').errors, isEmpty);
    });

    test('a F5 consome a F4 e não re-resolve (ADR-0011)', () {
      expect(codes('fn f() { let x = bogus }'), ['unresolved-before-check']);
    });

    test('erros saem em ordem-FONTE (fatia A + fatia B juntas)', () {
      final r = check('struct S { a: Int, a: Int }\nlet x: String = nil');
      expect(r.errors.map((e) => e.code), [
        'duplicate-field', // fatia A
        'nil-under-non-optional', // fatia B
      ]);
    });
  });
}
