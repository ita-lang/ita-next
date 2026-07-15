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
    test('`for` não tipa o binder — e agora DIZ (ruling §12-D da spec 011)', () {
      // Tipar exigiria a tabela `List<T>→T`, que o §12-4 da 009 recusou como
      // "a mágica que §4.5/§8.3 recusam". O ruling do CHÃO (§12-2 da 010) **não
      // o revoga** — são tabelas diferentes: o chão são membros/operadores;
      // `for` é contrato de ITERAÇÃO, e o §4.6.1 não o lista. E o `for` é o
      // exemplo CANÔNICO da doutrina do privilégio ("o MyType dele nunca ganha
      // `for`"). Protocolo de iteração = M5 (ADR-0012 §C-9).
      //
      // ⚠️ Este teste AFIRMAVA `errors.isEmpty` — o `for` era aceito em
      // silêncio. A §12-4 já dizia em TEXTO que "até lá, `itac check` é
      // incompleto para `for`"; o código não dizia. Ruling §12-D: dizer.
      expect(
        codes('fn f(xs: Int) { for x in xs { } }'),
        ['for-binder-unsupported'],
      );
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

  // --------------------------------------------------------------------------
  // spec 011 — `extension`/`impl` ENTRAM na F5
  // --------------------------------------------------------------------------
  //
  // Estes testes **afirmavam o comportamento ERRADO de propósito** enquanto o
  // buraco existia (era o que transformava **buraco em escopo**). A 011 os
  // virou. A queda deles foi o sinal de que ela funcionou.
  group('spec 011 — `extension`/`impl` entram na F5', () {
    test('CA64 — corpo de `extension` é checado (era SILÊNCIO)', () {
      expect(
        codes('struct Foo { z: Int }\nextension Foo { fn f() -> Int => "sou String" }'),
        contains('type-mismatch'),
      );
    });

    test('corpo de `impl` é checado (era SILÊNCIO)', () {
      expect(
        codes('struct Foo { z: Int }\nimpl Foo { fn f() -> Int => "sou String" }'),
        contains('type-mismatch'),
      );
    });

    test('CA65 — alvo inexistente de `extension` erra (era SILÊNCIO)', () {
      expect(
        codes('extension Naoexiste { fn f() -> Int => 0 }'),
        contains('unknown-type'),
      );
    });

    test('CA66 — `impl Trait for T` PRODUZ subtipagem: a regra da 009 §4 vive', () {
      // A tabela da 009 §4 sempre disse: "`T : Trait` (inline **ou `impl Trait
      // for T`**) ⟹ `T ≤ Trait`". Mas o `collect` só lia `n.traits` (a forma
      // inline) e `ImplDecl` não era lido por NINGUÉM na F5 — o retrofit externo
      // era **no-op silencioso**, a regra da própria spec estava INERTE, e o
      // ADR-0012 #2 ("as duas formas coexistem — declaração-de-intenção vs.
      // retrofit externo") estava meio-cumprido. Agora cumpre.
      final r = check(
        'trait Voa { fn voa() }\n'
        'struct Ave { asas: Int }\n'
        'impl Voa for Ave { fn voa() {} }\n'
        'fn usa(v: Voa) {}\n'
        'fn m(a: Ave) { usa(a) }',
      );
      expect(r.errors, isEmpty);
    });

    test('a forma INLINE continua funcionando (as duas coexistem, ADR-0012 #2)', () {
      final r = check(
        'trait Voa { fn voa() }\n'
        'struct Ave : Voa { asas: Int }\n'
        'fn usa(v: Voa) {}\n'
        'fn m(a: Ave) { usa(a) }',
      );
      expect(r.errors, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // ITEM 0 — labels ligavam por POSIÇÃO: programa errado em SILÊNCIO
  // --------------------------------------------------------------------------
  //
  // O `FunctionType` tinha `List<Type> params` — **só posições, sem nomes**. Os
  // args ligavam por posição e os labels eram **decorativos e mentiam**. Não era
  // lacuna de tipo: era programa que roda errado.
  //
  // Achado pelo `compiler-craftsman` no W1, e ele o pôs como **item 0** — antes
  // dos 5 que o dono listou. Estava certo: é pré-condição do memberwise, que é
  // **sempre chamado por label**.
  group('item 0 — casamento arg→param por LABEL', () {
    const div = 'fn div(num: Int, den: Int) -> Int => num\n';

    test('🔴 `div(den: 2, num: 10)` ERRA (ligava num=2, den=10 em silêncio)', () {
      // O usuário escreve "denominador 2, numerador 10" e recebia o inverso.
      expect(
        codes('${div}fn m() { let n: Int = div(den: 2, num: 10) }'),
        contains('argument-label-mismatch'),
      );
    });

    test('na ORDEM certa passa — o label CONFIRMA, não reordena', () {
      // Diretriz do dono: "se tiver divergência, a maneira do Swift é a
      // diretriz". E há divergência real: **Dart deixa reordenar named args;
      // Swift não** ("argument 'num' must precede argument 'den'"). Seguimos o
      // Swift: a chamada espelha a assinatura.
      expect(
        check('${div}fn m() { let n: Int = div(num: 10, den: 2) }').errors,
        isEmpty,
      );
    });

    test('posicional continua legal — a stdlib faz (`chunk(list, size)`)', () {
      expect(check('${div}fn m() { let n: Int = div(10, 2) }').errors, isEmpty);
    });

    test('⚠️ default é OMISSÍVEL — dava `arity-mismatch` FALSO', () {
      expect(
        check('fn f(x: Int = 1) -> Int => x\nfn m() { let n: Int = f() }').errors,
        isEmpty,
      );
    });

    test('e continua passável explicitamente', () {
      expect(
        check('fn f(x: Int = 1) -> Int => x\nfn m() { let n: Int = f(x: 5) }').errors,
        isEmpty,
      );
    });

    test('salta o default do meio: `f(b: 2)`', () {
      expect(
        check('fn f(a: Int = 1, b: Int = 2) -> Int => a\n'
              'fn m() { let n: Int = f(b: 2) }').errors,
        isEmpty,
      );
    });

    test('⚠️ label inexistente ERRA (`f(zz: 1)` passava)', () {
      expect(
        codes('fn f(a: Int) -> Int => a\nfn m() { let n: Int = f(zz: 1) }'),
        isNotEmpty,
      );
    });

    test('falta arg obrigatório ⟶ missing-argument', () {
      expect(
        codes('fn f(a: Int, b: Int) -> Int => a\nfn m() { let n: Int = f(a: 1) }'),
        contains('missing-argument'),
      );
    });

    test('label/default atravessam a SUBSTITUIÇÃO intactos', () {
      // São da DECLARAÇÃO; type-args não os tocam. Se `substitute` os perdesse,
      // o casamento por label quebraria em toda fn genérica.
      expect(
        check('fn f<T>(valor: T, vezes: Int = 1) -> T => valor\n'
              'fn m() { let n: Int = f(valor: 5) }').errors,
        isEmpty,
      );
    });
  });

  // --------------------------------------------------------------------------
  // spec 011 fatia 2 — `_member`: o walk do 1.6.4
  // --------------------------------------------------------------------------
  group('fatia 2 — campo e método', () {
    test('CA60 — `p.x` ⟶ tipo do campo; `p.zz` ⟶ unknown-member', () {
      expect(check('struct P { x: Int }\nfn m(p: P) { let n: Int = p.x }').errors,
          isEmpty);
      expect(codes('struct P { x: Int }\nfn m(p: P) { let n = p.zz }'),
          contains('unknown-member'));
    });

    test('CA62 — método próprio', () {
      expect(
        check('struct S { x: Int\n fn f() -> Int => 0 }\n'
              'fn m(s: S) { let n: Int = s.f() }').errors,
        isEmpty,
      );
    });

    test('método vindo de `extension` é achado', () {
      expect(
        check('struct S { x: Int }\nextension S { fn dobro() -> Int => 0 }\n'
              'fn m(s: S) { let n: Int = s.dobro() }').errors,
        isEmpty,
      );
    });

    test('⚠️ `self` — tinha ZERO menções no checker', () {
      // A F4 já entregava `SelfRes(receiver)`; a F5 não lia ⟹ `self` era
      // `cannot-infer` e todo `self.x` morria. O contrato F4→F5 do ADR-0011
      // ("a Fase 5 consome isso e não reconstrói escopo") estava meio-cumprido.
      expect(check('struct S { x: Int\n fn f() -> Int => self.x }').errors, isEmpty);
      expect(codes('struct S { x: Int\n fn f() -> String => self.x }'),
          contains('type-mismatch'));
    });
  });

  group('fatia 2 — o walk (1.6.4)', () {
    const a = 'class A { x: Int\n fn f() -> Int => 0 }\n';

    test('CA69 — herdado da superclasse', () {
      expect(
        check('${a}class D : A { y: Int }\nfn m(d: D) { let n: Int = d.f() }').errors,
        isEmpty,
      );
    });

    test('CA69b — a subclasse redeclara e VENCE (é o `override`)', () {
      // 1.6.4: "o escopo de uma declaração do membro x em C se estende a
      // qualquer subclasse C', EXCETO se C' tiver uma declaração local com o
      // mesmo nome". É a regra de aninhamento (1.6.3) na cadeia de herança — o
      // `Env.get` da Fig. 2.37 com `prev` = superclasse. Zero invenção.
      expect(
        check('${a}class D : A { y: Int\n fn f() -> String => "d" }\n'
              'fn m(d: D) { let n: String = d.f() }').errors,
        isEmpty,
      );
    });

    test('CA70 — diamante ⟶ ambiguous-member', () {
      // Dois herdados DISTINTOS com o mesmo nome. Precedência entre trait e
      // superclasse não existe no livro — inventá-la seria mágica (P4).
      expect(
        codes('trait X { fn f() -> Int }\ntrait Y { fn f() -> Int }\n'
              'struct S : X, Y { z: Int }\nfn m(s: S) { let n = s.f() }'),
        contains('ambiguous-member'),
      );
    });
  });

  group('fatia 2 — substituição COMPOSTA ao subir', () {
    test('`Box<Int>.v` ⟹ `Int`', () {
      expect(check('struct Box<T> { v: T }\n'
                   'fn m(b: Box<Int>) { let n: Int = b.v }').errors, isEmpty);
      expect(codes('struct Box<T> { v: T }\n'
                   'fn m(b: Box<Int>) { let n: String = b.v }'),
          contains('type-mismatch'));
    });

    test('⚠️ `class D<T> : A<T>` com `D<Int>` ⟹ `get() : Int`', () {
      // O risco que o review nomeou: a substituição tem de ser APLICADA ANTES de
      // subir — sobe-se em `A<Int>`, não em `A<T>`. Sem isto o `T` chegaria livre
      // no nível de cima (seria o 3º bug da série "generic não substituído").
      expect(
        check('class A<T> { a: T\n fn get() -> T => self.a }\n'
              'class D<T> : A<T> { d: Int }\n'
              'fn m(x: D<Int>) { let n: Int = x.get() }').errors,
        isEmpty,
      );
    });

    test('e pega quando o tipo composto não casa', () {
      expect(
        codes('class A<T> { a: T\n fn get() -> T => self.a }\n'
              'class D<T> : A<T> { d: Int }\n'
              'fn m(x: D<Int>) { let n: String = x.get() }'),
        contains('type-mismatch'),
      );
    });

    test('`self` em `extension` vê o `T` do ALVO', () {
      expect(
        check('struct Stack<T> { items: List<T> }\n'
              'extension Stack { fn eu() -> Stack<T> => self }').errors,
        isEmpty,
      );
    });
  });

  group('fatia 2 — `static` é QUALIFICADOR, não tabela (1.6.1 Ex. 1.3)', () {
    test('CA72 — `s.nova()` (static via instância) ⟶ static-via-instance', () {
      expect(
        codes('struct S { x: Int\n static fn nova() -> Int => 0 }\n'
              'fn m(s: S) { let n = s.nova() }'),
        contains('static-via-instance'),
      );
    });

    test('CA72b — `S.f()` (instância via tipo) ⟶ instance-via-type', () {
      expect(
        codes('struct S { x: Int\n fn f() -> Int => 0 }\nfn m() { let n = S.f() }'),
        contains('instance-via-type'),
      );
    });

    test('`S.nova()` (static via tipo) ⟶ ok', () {
      expect(
        check('struct S { x: Int\n static fn nova() -> Int => 0 }\n'
              'fn m() { let n: Int = S.nova() }').errors,
        isEmpty,
      );
    });
  });

  group('fatia 2 — o erro diz DE QUEM é a lacuna', () {
    test('CA74 — `xs.length` ⟶ builtin-member-unsupported, NÃO unknown-member', () {
      // `unknown-member` MENTIRIA: o membro EXISTE; nós é que não o modelamos.
      // É lacuna do COMPILADOR (012), não erro do usuário. Ainda é erro
      // (ADR-0013).
      expect(
        codes('fn m(xs: List<Int>) { let n = xs.length }'),
        contains('builtin-member-unsupported'),
      );
    });

    test('`member-on-optional` sobrevive — ruling §12-1 o CONFIRMOU', () {
      // `T?` tem Σ_membros = ∅. Os 5 hard-coded morreram e o idioma é
      // `match`/`if let` ⟹ `opt.map(f)` é erro POR IDENTIDADE, não por falta.
      expect(codes('fn m(o: Int?) { let n = o.map }'), contains('member-on-optional'));
    });
  });

  // --------------------------------------------------------------------------
  // Achados do review técnico da fatia 1
  // --------------------------------------------------------------------------
  group('review — B1: conformance é ordem-INDEPENDENTE', () {
    const src = 'trait Voa { fn voa() }\ntrait Anda { fn anda() }\n';
    const uso = 'fn usa(v: Voa) {}\nfn m(a: Ave) { usa(a) }';

    test('⚠️ `impl` ANTES do `struct` não perde o trait', () {
      // Bug meu: o `_collectBody` **atribuía** `info.traits` e o `_contribute`
      // **acumulava** ⟹ o assign do struct APAGAVA o trait do impl, e **a ordem
      // das declarações mudava o significado do programa**. É o que o Ex. 5.10
      // proíbe — *"as entradas podem ser atualizadas em QUALQUER ordem"* — o
      // mesmo exemplo que eu citava três linhas ao lado, para os métodos.
      expect(
        check('${src}impl Voa for Ave { fn voa() {} }\n'
              'struct Ave : Anda { asas: Int }\n$uso').errors,
        isEmpty,
      );
    });

    test('e DEPOIS também não (a ordem é irrelevante — é o ponto)', () {
      expect(
        check('${src}struct Ave : Anda { asas: Int }\n'
              'impl Voa for Ave { fn voa() {} }\n$uso').errors,
        isEmpty,
      );
    });

    test('as duas fontes ACUMULAM: inline + impl', () {
      final r = check('${src}struct Ave : Anda { asas: Int }\n'
                      'impl Voa for Ave { fn voa() {} }\n'
                      'fn a(v: Anda) {}\nfn b(v: Voa) {}\n'
                      'fn m(x: Ave) { a(x)\n b(x) }');
      expect(r.errors, isEmpty); // Ave ≤ Anda (inline) E Ave ≤ Voa (impl)
    });
  });

  group('review — B3: anotação resolvida UMA vez (memo `put`/`get`)', () {
    test('⚠️ `unknown-type` sai UMA vez, não duas', () {
      // A assinatura de método era resolvida 2× — `_methods` (A2) e o `_fnDecl`
      // do checker, que RE-RESOLVE. Além do erro duplicado, o `annotations[node]`
      // (side-table nº4 do §7) era **sobrescrito pelo segundo passe**: a tabela
      // que a F7 vai ler estava sendo corrompida em silêncio.
      expect(
        codes('struct S { z: Int\n fn f(x: Naoexiste) -> Int => 0 }'),
        ['unknown-type'],
      );
    });

    test('idem em `extension`', () {
      expect(
        codes('struct S { z: Int }\nextension S { fn f(x: Naoexiste) -> Int => 0 }'),
        ['unknown-type'],
      );
    });
  });

  group('review — o erro diz DE QUEM é a lacuna', () {
    test('`extension Int: Ord` ⟶ builtin-unsupported, NÃO unknown-type', () {
      // `unknown-type: Int` MENTIRIA — `Int` existe. O que falta é a
      // **declaração** dele (Norte do Art. II ⟹ M5): *"não é ilegal, é
      // inalcançável"*. E `extension Int: Ord { }` é o **CA5 da spec 005** — mas
      // aquela é CA de PARSER e continua passando; o que a F5 não faz é aceitar.
      expect(
        codes('trait Ord { fn cmp() -> Int }\n'
              'extension Int: Ord { fn cmp() -> Int => 0 }'),
        contains('extension-on-builtin-unsupported'),
      );
    });

    test('`extension List` idem (ruling §12-2: `.map` é M5)', () {
      expect(
        codes('extension List { fn f() -> Int => 0 }'),
        contains('extension-on-builtin-unsupported'),
      );
    });

    test('alvo REALMENTE inexistente continua `unknown-type`', () {
      expect(
        codes('extension Naoexiste { fn f() -> Int => 0 }'),
        contains('unknown-type'),
      );
    });

    test('B2 — campo em `extension` é declarado (§12-B3 pendente)', () {
      // `if (m is! FnDecl) continue` era **catch-all disfarçado de guarda**:
      // campo e `init` em extension sumiam mudos. Campo é ARMAZENAMENTO, e
      // extension não o adiciona — é campo ou getter computado? Ruling pendente
      // ⟹ recusar, porque aceitar mudo um glifo cujo significado não está
      // decidido é P4.
      expect(
        codes('struct S { z: Int }\nextension S { let extra: Int }'),
        contains('extension-field-unsupported'),
      );
    });

    test('B2 — `init` em `extension` idem', () {
      expect(
        codes('struct S { z: Int }\nextension S { init(q: Int) {} }'),
        contains('extension-init-unsupported'),
      );
    });
  });

  // --------------------------------------------------------------------------
  // §3.3 — generics: o ALVO empresta, por nome
  // --------------------------------------------------------------------------
  group('§3.3 — generics de `extension`/`impl`', () {
    test('CA63 (FLAGSHIP) — `extension Stack` vê o `T` de `struct Stack<T>`', () {
      // *"`extension` é o corpo do tipo, escrito noutro lugar — vê o que o corpo
      // vê"*. Não há binder escondido: o binder é `struct Stack<T>`, e o leitor
      // pode lê-lo ⟹ passa em P4.
      expect(
        check('struct Stack<T> { items: List<T> }\n'
              'extension Stack { fn peek() -> T? => .none }').errors,
        isEmpty,
      );
    });

    test('⚠️ método de tipo genérico — `struct Box<T> { fn get() -> T }`', () {
      // Bug ANTERIOR à 011, achado ao implementá-la: o **collect** resolvia (ele
      // empurra o escopo), mas o **checker RE-RESOLVE** as anotações e não
      // empurrava nada ⟹ `unknown-type` no próprio `T`. Campo funcionava (não é
      // re-resolvido); método, não. Mesma classe do bug de `fn` genérica da C.
      expect(
        checkProgram(parseSource('struct Box<T> { v: T\n fn get() -> T => v }\n').program)
            .errors.map((e) => e.code),
        isNot(contains('unknown-type')),
      );
    });

    test('CA71 — `extension List<T>` ⟶ target-has-type-args', () {
      // Alvo é **sítio de binder**, não há o que aplicar. O oracle escrevia
      // `"extension" IDENT` — lá isto nem parseia; o `ita-next` alargou para
      // `type`, e parsear hoje é artefato do alargamento.
      expect(
        codes('extension List<T> { fn f() -> Int => 0 }'),
        contains('target-has-type-args'),
      );
    });

    test('o `impl` NÃO escapa da regra do alvo', () {
      expect(
        codes('trait Voa { fn voa() }\nstruct Ave<T> { x: T }\n'
              'impl Voa for Ave<T> { fn voa() {} }'),
        contains('target-has-type-args'),
      );
    });

    test('`impl Comparable<T> for Stack` é LEGAL — o trait é *use site*', () {
      // A regra é sobre a posição de ALVO. Demais posições são tipos normais,
      // com o `T` do alvo em escopo.
      expect(
        check('trait Comparable<T> { fn cmp(o: T) -> Int }\n'
              'struct Stack<T> { items: List<T> }\n'
              'impl Comparable<T> for Stack { fn cmp(o: T) -> Int => 0 }').errors,
        isEmpty,
      );
    });
  });

  // --------------------------------------------------------------------------
  // A3 — `duplicate-member` (rulings §12-3 e §12-4)
  // --------------------------------------------------------------------------
  group('A3 — duplicate-member', () {
    test('CA67 — `struct` × `extension` colidem (ruling §12-3)', () {
      // Extension está no MESMO nível dos membros próprios ⟹ colisão é
      // declaração duplicada (6.3.6), erro na CAUSA. É o que o Swift faz de
      // verdade (`Invalid redeclaration`) — a alternativa "shadowing" que eu
      // rotulei "(Swift)" era falsa, e o dono corrigiu quando apontei.
      expect(
        codes('struct S { x: Int\n fn f() -> Int => 0 }\n'
              'extension S { fn f() -> Int => 1 }'),
        contains('duplicate-member'),
      );
    });

    test('CA68 — sem overload de método (ruling §12-4)', () {
      // O critério é o NOME, não a assinatura. O caso de uso tem saída: default
      // params + labels. (O 6.5.3 É invocado por OPERADOR — `_primitiveOps` —, e
      // é o que mantém o built-in não-privilegiado, R5 da 009.)
      expect(
        codes('struct S { x: Int\n'
              ' fn achar(a: Int) -> Int => 0\n'
              ' fn achar(a: String) -> Int => 1 }'),
        contains('duplicate-member'),
      );
    });

    test('campo × método colidem — uma tabela, um namespace (2.7 §1)', () {
      // *"uma classe teria sua própria tabela, com uma entrada para cada campo
      // **e** método"*.
      expect(
        codes('struct S { f: Int\n fn f() -> Int => 0 }'),
        contains('duplicate-member'),
      );
    });

    test('nomes distintos não colidem', () {
      expect(
        check('struct S { x: Int\n fn f() -> Int => 0 }\n'
              'extension S { fn g() -> Int => 1 }').errors,
        isEmpty,
      );
    });
  });

  // --------------------------------------------------------------------------
  // §4.1 — `.variant` (dívida da 010: estava em `_isCheckingOnly` e o `_check`
  // não o tratava — CA45/CA46 nunca foram entregues)
  // --------------------------------------------------------------------------
  group('§4.1 — `.variant` contextual', () {
    test('CA45 — `var r: Option<Response> = .none` ⟶ ok', () {
      // `T?` é `Option` (ruling 2026-07-12: `Option<T>` ≡ `T?`, `nil` = `.none`).
      expect(
        check('enum Response { ok, erro }\n'
              'fn m() { var r: Option<Response> = .none }').errors,
        isEmpty,
      );
    });

    test('`.variant` contra enum resolve', () {
      expect(check('enum E { a, b }\nfn m() { let x: E = .a }').errors, isEmpty);
    });

    test('CA46 — variante inexistente ⟶ unknown-variant', () {
      expect(codes('enum E { a, b }\nfn m() { let x: E = .zz }'), ['unknown-variant']);
    });

    test('`.variant` contra não-enum ⟶ variant-against-non-enum', () {
      expect(
        codes('struct S { x: Int }\nfn m() { let x: S = .a }'),
        ['variant-against-non-enum'],
      );
    });

    test('variante COM payload, nu ⟶ variant-needs-payload', () {
      expect(
        codes('enum E { a(v: Int), b }\nfn m() { let x: E = .a }'),
        ['variant-needs-payload'],
      );
    });

    test('sem contexto ⟶ cannot-infer (o `.` PEDE o contexto, §4.9)', () {
      // O fundamento aqui NÃO é a vacuidade do 6.5.1: `.v` também tem zero
      // subexpressões, mas o que o impede de sintetizar é o nome da variante não
      // determinar o enum. Não fazer é POLÍTICA — a §4.9.
      expect(codes('enum E { a, b }\nfn m() { let x = .a }'), ['cannot-infer']);
    });
  });

  // --------------------------------------------------------------------------
  // Binders de pattern — o `match` estava SEM CHECAGEM
  // --------------------------------------------------------------------------
  //
  // O `_matchExpr` **nunca chamava** `_bindPattern`, e o `_bindPattern` tinha
  // `default: break` engolindo 8 das 10 variantes de `Pattern` (que é `sealed`).
  // Binder sem tipo ⟹ `ErrorType` no `_ident` ⟹ absorvente ⟹ **silêncio**. E o
  // `match` é o construto do P7 — o ruling §12-1 acabou de torná-lo o ÚNICO
  // idioma (os 5 métodos hard-coded morreram).
  //
  // A informação que isto exige — variantes e campos — é a `record(t)` (6.3.6)
  // que a fatia A já construía. Mesma tabela do `_member`.
  group('binders de pattern', () {
    test('⚠️ `match e { .a(v) => v + "s" }` ERRA (era SILÊNCIO)', () {
      expect(
        codes('enum E { a(v: Int), b }\n'
              'fn m(e: E) { let r = match e { .a(v) => v + "s", .b => 0 } }'),
        contains('no-operator-for-types'),
      );
    });

    test('o binder ligou de verdade: `.a(v) => v + 1` passa', () {
      expect(
        check('enum E { a(v: Int), b }\n'
              'fn m(e: E) { let r: Int = match e { .a(v) => v + 1, .b => 0 } }').errors,
        isEmpty,
      );
    });

    test('P7 — `match r { .ok(v) => …, .err(e) => … }` sobre `Result<T,E>`', () {
      // `Result` é `BuiltinType` (sem `TypeInfo`), e este é o idioma que o
      // ruling §12-1 tornou o ÚNICO. Deixá-lo de fora mataria o P7 onde ele vive.
      expect(
        check('fn m(r: Result<Int, String>) {'
              ' let x: Int = match r { .ok(v) => v, .err(e) => 0 } }').errors,
        isEmpty,
      );
    });

    test('e o `.err(e)` liga em `E`, não em `T`', () {
      // A prova: `e` é String, `v` é Int ⟹ o join dos braços acusa.
      expect(
        codes('fn m(r: Result<Int, String>) {'
              ' let x: Int = match r { .ok(v) => v, .err(e) => e } }'),
        contains('branch-type-mismatch'),
      );
    });

    test('`match o { .some(v) => v, .none => 0 }` sobre `T?`', () {
      // `T?` é `Option` (ruling 2026-07-12).
      expect(
        check('fn m(o: Int?) { let x: Int = match o { .some(v) => v, .none => 0 } }')
            .errors,
        isEmpty,
      );
    });

    test('aridade do pattern é checada', () {
      expect(
        codes('enum E { a(v: Int), b }\n'
              'fn m(e: E) { let r = match e { .a(v, w) => 1, .b => 0 } }'),
        contains('pattern-arity-mismatch'),
      );
    });

    test('type-args do enum substituem no payload', () {
      // `Result<Int,String>.ok(v)` ⟹ `v : Int`, não `v : T`.
      expect(
        codes('fn m(r: Result<Int, String>) {'
              ' let x: String = match r { .ok(v) => v, .err(e) => e } }'),
        contains('branch-type-mismatch'),
      );
    });

    test('destructure EXPLÍCITO `P { x: a }` liga `a`', () {
      expect(
        codes('struct P { x: Int, y: Int }\n'
              'fn m(p: P) { let P { x: a } = p\n let s: String = a }'),
        contains('type-mismatch'), // `a : Int` ⟹ não cabe em String
      );
    });

    test('⚠️ shorthand `P { x, y }` é DECLARADO incapaz — débito D4 da F4', () {
      // O `FieldPattern` não é `AstNode` (sem span nem identidade), então o
      // `_declareFieldPattern` (resolver.dart:595) declara o binder no nó-pattern
      // ENVOLVENTE: *"a precisão fina de destructuring por RECORD é débito"*.
      // ⟹ `x` e `y` resolvem para a MESMA chave, e uma chave não carrega dois
      // tipos. Fingir daria a `y` o tipo de `x` **em silêncio** — pior que
      // recusar. Destravar = dar identidade ao `FieldPattern` (F4/AST).
      expect(
        codes('struct P { x: Int, y: Int }\nfn m(p: P) { let P { x, y } = p }'),
        contains('pattern-binder-unsupported'),
      );
    });
  });
}
