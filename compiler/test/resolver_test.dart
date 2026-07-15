// ============================================================================
// resolver_test.dart — Testes da Fase 4 (Binding / resolução de nomes).
// ============================================================================
//
// Três blocos (espelho de desugar_test/parser_test):
//  1. Conformância: itera `conformance/resolve/*.tu` e confere `resolve --dump`
//     (via a função pura do driver) contra os goldens `.resolve`, e os erros de
//     binding contra os goldens `.errors` — AMBOS gerados AO VIVO pelo
//     orquestrador. Só processa arquivos COM golden.
//  2. Unit por regra §5.3/§5.5 (CA1-12) — self-contido, sem depender de golden:
//     inspeciona a side-table (`res.resolution`) e a lista de erros. Robusto a
//     offset (checa KIND/hops/captura/código, não bytes).
//  3. Contrato F4↔F5 (ADR-0011): `.field`/`.método`/`.variant`/nome-de-tipo NÃO
//     são resolvidos aqui — só o receptor / callee-Ident / self / binders.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/binding/resolver.dart';
import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:test/test.dart';

void main() {
  // --------------------------------------------------------------------------
  // 1. Conformância (goldens gerados ao vivo).
  // --------------------------------------------------------------------------
  group('conformance/resolve — resolve --dump == golden .resolve', () {
    final dir = Directory('${_conformanceRoot()}/resolve');
    for (final tu in _tuFiles(dir)) {
      final goldenPath = _sibling(tu, '.resolve');
      if (!File(goldenPath).existsSync()) continue; // golden ainda não gerado
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(tu.readAsStringSync());
        expect(
          result.errors,
          isEmpty,
          reason: '${tu.path}: fixture de resolve deve parsear limpo',
        );
        final golden = File(goldenPath).readAsStringSync().trimRight();
        expect(resolveDump(resolveProgram(result.program)).trimRight(), golden);
      });
    }
  });

  group('conformance/resolve — erros == golden .errors', () {
    final dir = Directory('${_conformanceRoot()}/resolve');
    for (final tu in _tuFiles(dir)) {
      final goldenPath = _sibling(tu, '.errors');
      if (!File(goldenPath).existsSync()) continue;
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(tu.readAsStringSync());
        expect(
          result.errors,
          isEmpty,
          reason: '${tu.path}: erro de binding pressupõe parse limpo',
        );
        final res = resolveProgram(result.program);
        final golden = File(goldenPath).readAsStringSync().trimRight();
        expect(resolveErrorDump(res.errors).trimRight(), golden);
      });
    }
  });

  // --------------------------------------------------------------------------
  // 2. Unit por regra.
  // --------------------------------------------------------------------------

  group('CA1 — local (hops 0)', () {
    test('`x` liga ao `let x`, hops 0, não-capturado', () {
      final r = resolve('fn main() { let x = 1\n let y = x }');
      expect(r.errors, isEmpty);
      final x = resOf(r, 'x') as LocalRes;
      expect(x.hops, 0);
      expect(x.captured, isFalse);
    });
  });

  group('CA2 — captura (hops > 0, cruza fronteira de closure)', () {
    test('`x` dentro da closure → hops 1, capturado', () {
      final r = resolve('fn outer(xs) { let x = 1\n let ys = xs.map { x } }');
      expect(r.errors, isEmpty);
      final x = resOf(r, 'x') as LocalRes;
      expect(x.hops, 1);
      expect(x.captured, isTrue); // sinaliza captura (Grupo B)
    });
  });

  // O sintoma do bug aparecia AQUI: a Fase 3 declarava o param `$1` e deixava o
  // uso como `$01`, então o `$01` chegava sem binder → unresolved-name.
  group(r'shorthand não-canônico ($01) liga ao param sintético', () {
    test(r'`$01` resolve ao param $1 (não fica unresolved)', () {
      final r = resolve('fn f(xs) { let g = xs.map { \$01 * 2 } }');
      expect(r.errors, isEmpty);
      expect(resOf(r, r'$1'), isA<LocalRes>());
    });

    test(r'`$01` e `$1` no mesmo corpo ligam ao MESMO binder', () {
      final r = resolve('fn f(xs) { let g = xs.map { \$01 + \$1 } }');
      expect(r.errors, isEmpty);
    });
  });

  // O walk parava nos `members` do enum e nunca visitava os `cases` — defaults
  // de payload escapavam da resolução inteira, em silêncio.
  group('default de payload de enum case resolve', () {
    test('default inválido → unresolved-name (antes: passava batido)', () {
      final r = resolve('enum E { Some(v: Int = bogus), None }');
      expect(r.errors.map((e) => e.code), ['unresolved-name']);
    });

    test('default válido liga ao módulo, mesmo declarado DEPOIS (letrec)', () {
      final r = resolve('enum E { Some(v: Int = padrao), None }\nlet padrao = 42');
      expect(r.errors, isEmpty);
      expect(resOf(r, 'padrao'), isA<TopLevelRes>());
    });

    test('enum sem payload / sem default não regride', () {
      expect(resolve('enum E { A, B }').errors, isEmpty);
    });
  });

  // `_resolveFnDecl` retornava cedo em `body == null`, então o default de uma
  // assinatura de trait escapava — dar um corpo à assinatura mudava se ele era
  // checado.
  group('default de param em assinatura de trait (fn sem corpo) resolve', () {
    test('default inválido → unresolved-name (antes: passava batido)', () {
      final r = resolve('trait T {\n fn f(x: Int = bogus) -> Int\n}');
      expect(r.errors.map((e) => e.code), ['unresolved-name']);
    });

    test('assinatura e mesma fn COM corpo dão o MESMO erro', () {
      // O contraste que denunciava o bug: só o corpo mudava o resultado.
      final semCorpo = resolve('trait T {\n fn f(x: Int = bogus) -> Int\n}');
      final comCorpo = resolve('trait T {\n fn f(x: Int = bogus) -> Int => x\n}');
      expect(
        semCorpo.errors.map((e) => e.code),
        comCorpo.errors.map((e) => e.code),
      );
    });

    test('default válido liga ao módulo (letrec)', () {
      final r = resolve('trait T {\n fn f(x: Int = padrao) -> Int\n}\nlet padrao = 1');
      expect(r.errors, isEmpty);
      expect(resOf(r, 'padrao'), isA<TopLevelRes>());
    });

    test('`self` no default da assinatura resolve (assinatura é método)', () {
      final r = resolve('trait T {\n fn f(x: Int = self.base) -> Int\n}');
      expect(r.errors, isEmpty);
    });

    test('assinatura SEM default não regride', () {
      expect(resolve('trait T {\n fn f(x: Int) -> Int\n}').errors, isEmpty);
    });
  });

  group('CA3 — letrec de módulo (forward-ref)', () {
    test('`b` chamada por `a` (declarada depois) → TopLevelRes', () {
      final r = resolve('fn a() -> Int => b()\n fn b() -> Int => 1');
      expect(r.errors, isEmpty);
      expect(resOf(r, 'b'), isA<TopLevelRes>());
    });
  });

  group('CA7 — shadowing aninhado (o interno vence)', () {
    test('`x` no bloco interno resolve hops 0 (não o `x` externo)', () {
      final r = resolve('fn main() { let x = 1\n { let x = 2\n let y = x } }');
      expect(r.errors, isEmpty);
      // hops 0 = mesmo escopo do `let x = 2`; o externo daria hops > 0.
      expect((resOf(r, 'x') as LocalRes).hops, 0);
    });
  });

  group('CA8 — self em método → SelfRes', () {
    test('`self` liga a SelfRes; `.x` NÃO é resolvido (F5)', () {
      final r = resolve('struct P { x: Int, fn mag() -> Int => self.x }');
      expect(r.errors, isEmpty);
      final selfs = r.resolution.entries.where((e) => e.key is SelfExpr);
      expect(selfs.length, 1);
      expect(selfs.single.value, isA<SelfRes>());
      // `x` é Member.name (String), não vira Ident-chave: não resolvido.
      expect(_identKeys(r, 'x'), isEmpty);
    });
  });

  group('CA10 — guard-let = escopo de continuação', () {
    test('`v` visível DEPOIS do guard (continuação), hops 0', () {
      final r = resolve('fn check(o) { guard let v = o else { return }\n let w = v }');
      expect(r.errors, isEmpty);
      expect((resOf(r, 'v') as LocalRes).hops, 0);
      expect(resOf(r, 'o'), isA<LocalRes>()); // param resolvido no valor do guard
    });
  });

  group('CA11 — destructuring liga binders distintos', () {
    test('`a` e `b` ligam a BindPatterns diferentes', () {
      final r = resolve('fn main() { let xs = [1, 2]\n let [a, b] = xs\n let s = a\n let t = b }');
      expect(r.errors, isEmpty);
      final a = resOf(r, 'a') as LocalRes;
      final b = resOf(r, 'b') as LocalRes;
      expect(identical(a.binder, b.binder), isFalse); // binders DISTINTOS
    });
  });

  group('CA12 — gensym como binder ordinário', () {
    test(r'`$x0` (do `??`) resolve local, hops 0', () {
      final r = resolve('fn main() { let a = 1\n let b = 2\n let r = a ?? b }');
      expect(r.errors, isEmpty);
      expect((resOf(r, r'$x0') as LocalRes).hops, 0);
    });
  });

  // --------------------------------------------------------------------------
  // Erros §5.5.
  // --------------------------------------------------------------------------

  group('erros de binding (§5.5)', () {
    test('CA4 — unresolved-name', () {
      final r = resolve('fn main() { let y = bogus }');
      expect(codes(r), contains('unresolved-name'));
    });

    test('CA5 — read-in-own-initializer (`let a = a`)', () {
      final r = resolve('fn main() { let a = a }');
      expect(codes(r), contains('read-in-own-initializer'));
    });

    test('CA6 — duplicate-declaration (mesmo escopo)', () {
      final r = resolve('fn main() { let x = 1\n let x = 2 }');
      expect(codes(r), contains('duplicate-declaration'));
    });

    test('CA8 — self-outside-method', () {
      final r = resolve('fn free() -> Int => self');
      expect(codes(r), contains('self-outside-method'));
    });

    test('CA9 — break-outside-loop', () {
      final r = resolve('fn main() { break }');
      expect(codes(r), contains('break-outside-loop'));
    });

    test('continue-outside-loop', () {
      final r = resolve('fn main() { continue }');
      expect(codes(r), contains('continue-outside-loop'));
    });

    test('return-outside-fn (top-level)', () {
      final r = resolve('return 1');
      expect(codes(r), contains('return-outside-fn'));
    });

    test('break DENTRO de loop é OK (context-flag)', () {
      final r = resolve('fn main() { while true { break } }');
      expect(codes(r), isNot(contains('break-outside-loop')));
    });

    test('break dentro de closure dentro de loop = ERRO (não cruza fronteira de fn)', () {
      final r = resolve('fn main(xs) { while true { xs.each { break } } }');
      expect(codes(r), contains('break-outside-loop'));
    });
  });

  // --------------------------------------------------------------------------
  // 3. Contrato F4↔F5 (ADR-0011): nada type-directed resolvido aqui.
  // --------------------------------------------------------------------------

  group('contrato F4↔F5 — só o namespace de valor com escopo léxico', () {
    test('`obj.field`: RECEPTOR resolvido, `.field` NÃO (type-directed → F5)', () {
      final r = resolve('fn main() { let obj = 1\n let z = obj.field }');
      expect(r.errors, isEmpty);
      expect(resOf(r, 'obj'), isA<LocalRes>()); // receptor É valor
      expect(_identKeys(r, 'field'), isEmpty); // `.field` não é resolvido
    });

    test('`.variant` (EnumShorthand) NÃO gera resolução (F5)', () {
      final r = resolve('fn f(x) => x == .none');
      // `.none` é EnumShorthand.variant (String), não Ident → sem entrada.
      expect(r.resolution.keys.whereType<EnumShorthand>(), isEmpty);
      expect(resOf(r, 'x'), isA<LocalRes>());
    });

    test('nome de TIPO (annotation) NÃO é resolvido — só valores', () {
      // `Int` na anotação é namespace de TIPO (F5); nenhum Ident-chave `Int`.
      final r = resolve('fn main() { let x: Int = 1\n let y = x }');
      expect(_identKeys(r, 'Int'), isEmpty);
      expect(resOf(r, 'x'), isA<LocalRes>());
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

ResolveResult resolve(String src) => resolveProgram(parseSource(src).program);

List<String> codes(ResolveResult r) => r.errors.map((e) => e.code).toList();

/// Todas as chaves `Ident` com [name] na side-table (usos RESOLVIDOS).
Iterable<Ident> _identKeys(ResolveResult r, String name) =>
    r.resolution.keys.whereType<Ident>().where((i) => i.name == name);

/// A resolução do ÚNICO uso de [name] (falha se houver 0 ou >1).
ResolvedName resOf(ResolveResult r, String name) {
  final matches = r.resolution.entries
      .where((e) => e.key is Ident && (e.key as Ident).name == name)
      .toList();
  if (matches.length != 1) {
    throw StateError('esperava 1 uso de "$name", achei ${matches.length}');
  }
  return matches.single.value;
}

/// Raiz do diretório `conformance/` a partir do cwd do `dart test` (= `compiler/`).
String _conformanceRoot() {
  for (final candidate in ['../conformance', 'conformance', '../../conformance']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'conformance/ não encontrado a partir de ${Directory.current.path}',
  );
}

List<File> _tuFiles(Directory dir) =>
    dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tu')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _sibling(File tu, String ext) =>
    '${tu.path.substring(0, tu.path.length - 3)}$ext';
