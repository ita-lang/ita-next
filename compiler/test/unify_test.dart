// ============================================================================
// unify_test.dart — Fatia D: unificação de type-args (spec 009 §5.4-D).
// ============================================================================
//
// Alg. 6.19 (Dragon Fig. 6.32) + os CAs de **P7** (`Result<T,E>`), que é o que
// esta fatia existe para fechar — um princípio PERMANENTE que estava em nota
// promissória (§12-2).
// ============================================================================

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:ita_next_compiler/frontend/semantic/unify.dart';
import 'package:test/test.dart';

void main() {
  CheckResult check(String src) => checkProgram(parseSource(src).program);
  List<String> codes(String src) => check(src).errors.map((e) => e.code).toList();

  ast.StructDecl declOf(String name) =>
      ast.StructDecl(false, name, const [], const [], const [], 0, 1);

  // --------------------------------------------------------------------------
  // Algoritmo 6.19 (Fig. 6.32)
  // --------------------------------------------------------------------------
  group('Alg. 6.19 — unificação (union-find)', () {
    test('`if (s = t) return true` — mesmo tipo básico', () {
      final u = Unifier();
      expect(u.unify(const IntType(), const IntType()), isTrue);
      expect(u.unify(const IntType(), const StringType()), isFalse);
    });

    test('variável liga ao tipo (`union(s,t); return true`)', () {
      final u = Unifier();
      final a = u.fresh();
      expect(u.unify(a, const IntType()), isTrue);
      expect(u.resolve(a), const IntType());
    });

    test('a ASSIMETRIA do union: a var nunca é representante do construtor', () {
      // 6.5.5: "uma variável não pode ser usada como representante de uma classe
      // para uma expressão contendo um construtor — senão duas expressões não
      // equivalentes poderiam ser unificadas por meio dessa variável".
      final u = Unifier();
      final a = u.fresh();
      expect(u.unify(const IntType(), a), isTrue); // var à DIREITA
      expect(u.resolve(a), const IntType());
      // e agora `a` NÃO aceita outro tipo — senão Int e String se unificariam
      expect(u.unify(a, const StringType()), isFalse);
    });

    test('operador com filhos: `union(s,t); unify(s1,t1) and unify(s2,t2)`', () {
      final u = Unifier();
      final a = u.fresh();
      final r = declOf('R');
      expect(
        u.unify(
          NamedType(r, TypeKind.struct_, [a, const StringType()]),
          NamedType(r, TypeKind.struct_, const [IntType(), StringType()]),
        ),
        isTrue,
      );
      expect(u.resolve(a), const IntType());
    });

    test('construtores diferentes NÃO unificam (identidade nominal)', () {
      final u = Unifier();
      expect(
        u.unify(
          NamedType(declOf('A'), TypeKind.struct_),
          NamedType(declOf('B'), TypeKind.struct_),
        ),
        isFalse,
      );
    });

    test('transitividade via find (α=β, β=Int ⟹ α=Int)', () {
      final u = Unifier();
      final a = u.fresh();
      final b = u.fresh();
      expect(u.unify(a, b), isTrue);
      expect(u.unify(b, const IntType()), isTrue);
      expect(u.resolve(a), const IntType()); // path compression
    });

    test('occurs check: o livro NÃO faz (nota 7); nós fazemos', () {
      // "É um erro unificar uma variável com uma expressão contendo essa
      // variável. O Algoritmo 6.19 PERMITE tais substituições." Lá a unificação
      // serve a tipos circulares; aqui um tipo infinito é bug — o Kernel não
      // teria imagem para ele.
      final u = Unifier();
      final a = u.fresh();
      expect(u.unify(a, optional(a)), isFalse); // α = α? seria infinito
    });

    test('`ErrorType` é absorvente nos dois sentidos (anti-cascata)', () {
      final u = Unifier();
      expect(u.unify(const ErrorType(), const IntType()), isTrue);
      expect(u.unify(const IntType(), const ErrorType()), isTrue);
    });

    test('instantiate: a LIGADA vira NOVA (6.5.4)', () {
      // "em cada uso de um tipo polimórfico, substituímos as variáveis ligadas
      // por novas variáveis e removemos os quantificadores universais".
      final u = Unifier();
      final box = declOf('Box');
      final t = TypeParamType(box, 'T');
      final sig = FunctionType([t], t);
      final i1 = u.instantiate(sig, [t]) as FunctionType;
      final i2 = u.instantiate(sig, [t]) as FunctionType;
      expect(i1.params.single, isA<TypeVar>()); // virou fresca
      expect(i1.params.single, isNot(i2.params.single)); // NOVA a cada uso
    });
  });

  // --------------------------------------------------------------------------
  // §4.6-cond.1 — substituição passa pelo smart constructor
  // --------------------------------------------------------------------------
  group('§4.6 — `substitute` honra o invariante do OptionalType', () {
    test('subst(T?, T := String?) = String? (não String??)', () {
      // O caso REAL da stdlib: `compact<T>(list: List<T?>)` com `T = String?`.
      // Um map estrutural ingênuo quebraria o invariante EM SILÊNCIO.
      final box = declOf('C');
      final t = TypeParamType(box, 'T');
      final r = substitute(optional(t), {t: optional(const StringType())});
      expect(r, optional(const StringType()));
      expect((r as OptionalType).inner, const StringType()); // não aninhou
    });

    test('CA28b — a idempotência da substituição é SILENCIOSA', () {
      // Ninguém escreveu dois glifos: a substituição os produziu. O
      // `redundant-optional` é de ANOTAÇÃO (fatia A) — se morasse no
      // construtor, isto seria erro e a stdlib quebraria.
      final box = declOf('C');
      final t = TypeParamType(box, 'T');
      final r = substitute(optional(t), {t: optional(const IntType())});
      expect(r, optional(const IntType()));
      // e sem diagnóstico nenhum — `substitute` não reporta
    });

    test('resolve() também passa pelo smart ctor', () {
      final u = Unifier();
      final a = u.fresh();
      u.unify(a, optional(const IntType()));
      expect(u.resolve(optional(a)), optional(const IntType())); // Int?, não Int??
    });
  });

  // --------------------------------------------------------------------------
  // P7 — o que a fatia D existe para fechar
  // --------------------------------------------------------------------------
  group('P7 — `Result<T,E>` + `?` + must-use (§0.5-6)', () {
    // `=>` é o ÚNICO token que rende valor (RD-1, rodapé do `ast.asdl`). Um
    // corpo-BLOCO `{ g(x) }` não renderia — descartaria, e cairia no
    // `unused-result` abaixo. Ver o grupo RD-1 no fim deste arquivo.
    const g = 'fn g(x: Int) -> Result<Int, String> => g(x)\n';

    test('CA22 — `?` em fn que não retorna Result ⟶ try-outside-result-fn', () {
      expect(
        codes('${g}fn f() -> Int { let v = g(1)? }'),
        contains('try-outside-result-fn'),
      );
    });

    test('CA23 — `E` divergente ⟶ error-type-mismatch (SEM `From` automático)', () {
      // O `From` implícito do Rust é o único ponto onde ele fura o próprio
      // "sem conversão implícita" — maquinaria invisível em TODO `?`.
      expect(
        codes('${g}fn f() -> Result<Int, Float> { let v = g(1)? }'),
        contains('error-type-mismatch'),
      );
    });

    test('CA33 — `e?` sobre não-Result ⟶ try-on-non-result', () {
      expect(
        codes('fn f() -> Result<Int, String> { let v = 5? }'),
        contains('try-on-non-result'),
      );
    });

    test('CA24 — `Result` descartado ⟶ unused-result (é ERRO, não warning)', () {
      // "Result descartado no chão é exceção não-checada com passos extras —
      // pior que try/catch, porque um throw ao menos é alto."
      expect(codes('${g}fn f() { g(1) }'), contains('unused-result'));
    });

    test('CA24 — o escape é explícito e greppável: `let _ = f()`', () {
      final r = check('${g}fn f() { let _ = g(1) }');
      expect(r.errors.map((e) => e.code), isNot(contains('unused-result')));
    });

    test('must-use NÃO se estende a Option (ausência não é erro)', () {
      // "inutilidade é dead-code = F6".
      expect(
        codes('fn h() -> Int? => nil\nfn f() { h() }'),
        isNot(contains('unused-result')),
      );
    });

    test('caminho FELIZ: `g(1)?` extrai o T de Result<T,E>', () {
      final r = check('${g}fn f() -> Result<Int, String> {'
          ' let v = g(1)?\n let w: Int = v }');
      expect(r.errors, isEmpty); // `v` é Int — o `?` desembrulhou
    });
  });

  // --------------------------------------------------------------------------
  // Aplicação — o que a fatia D destrava no `Call`
  // --------------------------------------------------------------------------
  group('aplicação: aridade e unificação de args (6.8)', () {
    const f = 'fn idade(p: Int) -> Int => p\n';

    test('CA11 — `f(1,2)` ⟶ arity-mismatch (o oracle NÃO checa isto)', () {
      // `type_checker.dart:156`: "Conservador: NÃO valida aridade nem labels".
      expect(codes('${f}fn m() { let x = idade(1, 2) }'), ['arity-mismatch']);
    });

    test('arg de tipo errado ⟶ type-mismatch (via unificação)', () {
      expect(codes('${f}fn m() { let x = idade("s") }'), ['type-mismatch']);
    });

    test('chamada correta passa e o retorno tipa', () {
      expect(check('${f}fn m() { let x: Int = idade(5) }').errors, isEmpty);
    });

    test('chamar não-função ⟶ not-callable', () {
      expect(codes('fn m() { let a = 5\n let b = a(1) }'), ['not-callable']);
    });
  });

  // --------------------------------------------------------------------------
  // §7-3 — o vazamento do oracle corrigido
  // --------------------------------------------------------------------------
  // --------------------------------------------------------------------------
  // RD-1 — o invariante que o must-use expõe
  // --------------------------------------------------------------------------
  group('RD-1 — `=>` é o único token que rende valor', () {
    test('corpo-BLOCO não rende: `{ g(x) }` DESCARTA ⟶ unused-result', () {
      // Escrever este teste é o que me mostrou que o fixture com `{ … }` estava
      // errado, não o checker. RD-1 fica pinado aqui: se alguém um dia fizer o
      // bloco render, este teste cai e a decisão volta à mesa.
      expect(
        codes('fn g(x: Int) -> Result<Int, String> => g(x)\n'
            'fn f() -> Result<Int, String> { g(1) }'),
        contains('unused-result'),
      );
    });

    test('corpo-`=>` rende: o mesmo `g(x)` NÃO é descarte', () {
      final r = check('fn g(x: Int) -> Result<Int, String> => g(x)');
      expect(r.errors, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // Incompletudes DECLARADAS (§1 não-objetivos) — honestas, não bugs
  // --------------------------------------------------------------------------
  group('não-objetivos: o que esta fatia NÃO checa', () {
    test('não-objetivo 4 — definite-return é path-sensitive ⟹ F6', () {
      // `fn f() -> Int { "s" }` passa: sob RD-1 o bloco não rende, então a
      // String é um ExprStmt descartado (não confrontado com `Int`) e falta um
      // `return`. "Todo caminho retorna?" é dataflow — F6, não esta spec.
      expect(check('fn f() -> Int { "sou uma String" }').errors, isEmpty);
    });

    test('mas `return` COM valor é checado aqui (não depende de fluxo)', () {
      expect(codes('fn f() -> Int { return "s" }'), contains('type-mismatch'));
    });

    test('§4.6-cond.3 — `?` não é construtor livre: solução SINTÁTICA', () {
      // `List<T?>` vs `List<String?>` tem DUAS soluções: `T := String` (a que o
      // Alg. 6.19 devolve) e `T := String?` (módulo a idempotência do `?`). É
      // determinístico e a preferida é a útil; sem turbofish p/ forçar a outra.
      final u = Unifier();
      final box = declOf('L');
      final a = u.fresh();
      expect(
        u.unify(
          NamedType(box, TypeKind.struct_, [optional(a)]),
          NamedType(box, TypeKind.struct_, [optional(const StringType())]),
        ),
        isTrue,
      );
      expect(u.resolve(a), const StringType()); // a sintática, não `String?`
    });
  });

  // --------------------------------------------------------------------------
  // §7-3 — o vazamento do oracle corrigido
  // --------------------------------------------------------------------------
  group('§7-3 — `Result` vem da tabela da F5, não do codegen', () {
    test('`Result<T,E>` tem type-args REAIS (o oracle os apaga p/ DynamicType)', () {
      // `codegen.dart:724` registra `Result` com `const k.DynamicType()` nos
      // payloads — invisível à semântica. Aqui os args são o que o usuário escreveu.
      final r = check('fn g() -> Result<Int, String> { g() }');
      expect(r.errors.map((e) => e.code), contains('unused-result'));
      // se os args fossem apagados, o `error-type-mismatch` do CA23 não existiria
    });

    test('aridade de `Result` é checada (2 args)', () {
      expect(
        codes('fn g() -> Result<Int> { g() }'),
        contains('generic-arity-mismatch'),
      );
    });
  });
}
