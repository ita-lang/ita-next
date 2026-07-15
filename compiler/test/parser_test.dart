// ============================================================================
// parser_test.dart — Testes da Fase 2 (Sintaxe → AST) do ita-next.
// ============================================================================
//
// Dois blocos:
//  1. Conformância de PARSING: itera `conformance/valid|invalid/*.tu` e confere
//     `itac parse --dump` (via a função pura do driver, sem subprocess) contra
//     os goldens `.ast`; para `invalid/`, confere os erros declarados inline
//     (`// EXPECT: parse-error: … @off+len`) + o `.ast` recuperado, se houver.
//     Só processa arquivos com golden `.ast` OU `// EXPECT: parse-error:` — os
//     fixtures SÓ-léxicos da Fase 1 (com `.tokens`/`.errors`) são ignorados.
//  2. Asserts unitários (T026): shape de `ErrorDecl`, span byte-preciso, e a
//     estrutura que o golden não pega bem.
// ============================================================================

import 'dart:io';

import 'package:ita_next_compiler/driver/driver.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:test/test.dart';

void main() {
  // --------------------------------------------------------------------------
  // 1. Conformância de parsing.
  // --------------------------------------------------------------------------
  group('conformance/valid — parse --dump == golden .ast', () {
    final dir = Directory('${_conformanceRoot()}/valid');
    for (final tu in _tuFiles(dir)) {
      final astPath = _sibling(tu, '.ast');
      if (!File(astPath).existsSync()) continue; // fixture só-léxico → pula
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(tu.readAsStringSync());
        expect(
          result.errors,
          isEmpty,
          reason: '${tu.path} não deveria ter erro de parse',
        );
        final golden = File(astPath).readAsStringSync().trimRight();
        expect(parseDump(result.program).trimRight(), golden);
      });
    }
  });

  group('conformance/invalid — erros == // EXPECT + resync', () {
    final dir = Directory('${_conformanceRoot()}/invalid');
    for (final tu in _tuFiles(dir)) {
      final src = tu.readAsStringSync();
      final expected = _expectLines(src);
      final expectedLex = _expectLexLines(src);
      // sem EXPECT algum → fixture só-léxico da F1 (goldens .tokens/.errors)
      if (expected.isEmpty && expectedLex.isEmpty) continue;
      test(tu.uri.pathSegments.last, () {
        final result = parseSource(src);
        if (expected.isNotEmpty) {
          expect(
            result.errors,
            isNotEmpty,
            reason: '${tu.path} deveria coletar ao menos 1 erro de parse',
          );
          expect(parseErrorDump(result.errors).split('\n'), expected);
        }
        // EXPECT-LEX: o erro léxico atravessa o parse (#16). Declarar EXPECT-LEX
        // sem EXPECT também afirma que NÃO há parse-error — o derivado do
        // `Tag.invalid` é suprimido, senão sobraria ruído por cima da causa.
        if (expectedLex.isNotEmpty) {
          expect(errorDump(result.lexErrors).split('\n'), expectedLex);
          if (expected.isEmpty) {
            expect(
              result.errors,
              isEmpty,
              reason: '${tu.path}: parse-error derivado deveria ser suprimido',
            );
          }
        }
        // Se houver `.ast`, confere a árvore RECUPERADA (resync sem cascata).
        final astPath = _sibling(tu, '.ast');
        if (File(astPath).existsSync()) {
          final golden = File(astPath).readAsStringSync().trimRight();
          expect(parseDump(result.program).trimRight(), golden);
        }
      });
    }
  });

  // --------------------------------------------------------------------------
  // Erro léxico ATRAVESSA o parse (#16). `parseSource` descartava
  // `tokenizeSource().errors`, então `itac parse|desugar|resolve` NUNCA
  // mostravam erro léxico — o usuário via só o `parse-error` derivado do
  // `Tag.invalid`, que além de redundante é enganoso.
  // --------------------------------------------------------------------------
  group('lexErrors no ParseResult', () {
    test('o erro léxico chega (antes: descartado)', () {
      final p = parseSource('let a = 99999999999999999999');
      expect(p.lexErrors.map((e) => e.code), ['lex-integer-overflow']);
    });

    test('o parse-error DERIVADO do Tag.invalid é suprimido', () {
      // Sem a supressão: "expected-expression" por cima da causa.
      final p = parseSource('let a = 99999999999999999999');
      expect(p.errors, isEmpty);
      expect(p.hasErrors, isTrue); // mas o fonte TEM erro — exit 65
    });

    test('parse-error LEGÍTIMO não é engolido pela supressão', () {
      // Risco da supressão: só o erro cujo offset é de um token invalid some.
      final p = parseSource('fn f( { }');
      expect(p.lexErrors, isEmpty); // nada de errado no léxico
      expect(p.errors, isNotEmpty); // o erro de parse continua reportado
    });

    test('erro léxico E erro de parse independentes coexistem', () {
      final p = parseSource('let a = 99999999999999999999\nfn f( { }');
      expect(p.lexErrors.map((e) => e.code), ['lex-integer-overflow']);
      expect(p.errors, isNotEmpty); // o `fn f(` é erro de parse de verdade
    });

    test('a recuperação segue: o `let b` depois do erro léxico parseia', () {
      final p = parseSource('let a = 99999999999999999999\nlet b = 1');
      final lets = p.program.body.whereType<LetStmt>().toList();
      expect(lets.length, 1);
      expect((lets.single.value as IntLit).value, 1);
    });

    test('fonte limpo: sem lexErrors, hasErrors falso', () {
      final p = parseSource('let a = 1');
      expect(p.hasErrors, isFalse);
    });

    group('interpolação (sub-lexer próprio)', () {
      test('o erro do sub-lexer sobe — `parseExpression` LANÇA, e o finally '
          'garante a coleta no caminho de erro', () {
        final p = parseSource(r'let s = "x ${1__0} y"');
        expect(p.lexErrors.map((e) => e.code), ['lex-malformed-number']);
        expect(p.errors, isEmpty); // o derivado que SOBE também é suprimido
      });

      test('line:col é ABSOLUTO (o sub-lexer contaria de 1:1)', () {
        final p = parseSource('let a = 1\nlet b = 2\nlet s = "x \${1__0} y"');
        final e = p.lexErrors.single;
        expect(e.line, 3); // não 1
        expect(e.col, 14); // a posição real do `1__0`
      });

      test('interpolação MULTI-LINHA: col conta após o último \\n', () {
        final p = parseSource('let s = "x \${\n  1__0\n} y"');
        final e = p.lexErrors.single;
        expect(e.line, 2);
        expect(e.col, 3); // 2 espaços de indentação + 1
      });
    });
  });

  // --------------------------------------------------------------------------
  // 2. Asserts unitários (shape/span — T026).
  // --------------------------------------------------------------------------
  group('CA17 — tipos (shape)', () {
    test('(Int, Int) -> Int é FunctionType não-async', () {
      final p = parseSource('let f: (Int, Int) -> Int = e');
      final let = p.program.body.first as LetStmt;
      final t = let.type as FunctionType;
      expect(t.isAsync, isFalse);
      expect(t.params.length, 2);
      expect((t.ret as NamedType).name, 'Int');
      expect(p.errors, isEmpty);
    });

    test('mut Foo? = mut(optional(Foo)) — mut envolve o optional', () {
      final p = parseSource('let x: mut Foo? = e');
      final let = p.program.body.first as LetStmt;
      final mut = let.type as MutType;
      final opt = mut.inner as OptionalType;
      expect((opt.inner as NamedType).name, 'Foo');
    });
  });

  group('CA15 — generics aninhados (>> split) + span', () {
    test('Map<String, List<Int>> aninha e o >> fecha os dois', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final let = p.program.body.first as LetStmt;
      final map = let.type as NamedType;
      expect(map.name, 'Map');
      expect(map.args.length, 2);
      expect((map.args[0] as NamedType).name, 'String');
      final list = map.args[1] as NamedType;
      expect(list.name, 'List');
      expect((list.args.single as NamedType).name, 'Int');
      expect(p.errors, isEmpty);
    });

    test('span do binding "m" é byte-preciso (offset 4, len 1)', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final let = p.program.body.first as LetStmt;
      final bind = let.target as BindPattern;
      expect(bind.offset, 4);
      expect(bind.length, 1);
    });
  });

  group('D5 — let/var init opcional (GRAMMAR §3)', () {
    test('`let x` (forma bind, sem init): value == null', () {
      final p = parseSource('let x');
      final let = p.program.body.single as LetStmt;
      expect((let.target as BindPattern).name, 'x');
      expect(let.value, isNull);
      expect(p.errors, isEmpty);
    });

    test('`var count: Int` sem init: type presente, value null', () {
      final p = parseSource('var count: Int');
      final let = p.program.body.single as LetStmt;
      expect(let.isVar, isTrue);
      expect((let.type as NamedType).name, 'Int');
      expect(let.value, isNull);
      expect(p.errors, isEmpty);
    });

    test('destructure SEM init ainda EXIGE `=` (erro, não afrouxou)', () {
      final p = parseSource('let { x, y }');
      expect(p.errors, isNotEmpty);
      expect(p.errors.first.code, 'expected-token');
    });
  });

  group('D3 — operator associatividade preservada', () {
    OperatorDecl op(String src) =>
        parseSource(src).program.body.single as OperatorDecl;

    test('`precedence 6 right` → Associativity.right', () {
      final o = op('operator * (a: Int, b: Int) -> Int precedence 6 right { a }');
      expect(o.precedence, 6);
      expect(o.associativity, Associativity.right);
    });

    test('sem `precedence` → assoc none + precedence null', () {
      final o = op('operator + (a: Int, b: Int) -> Int { a }');
      expect(o.precedence, isNull);
      expect(o.associativity, Associativity.none);
    });
  });

  group('D2 — span em Param e MapEntryNode (forward-compat Kernel)', () {
    test('span do Param cobre `nome: Tipo`', () {
      const src = 'fn f(alpha: Int) => 0';
      final fn = parseSource(src).program.body.single as FnDecl;
      final param = fn.params.single;
      expect(src.substring(param.offset, param.offset + param.length), 'alpha: Int');
    });

    test('span do MapEntryNode cobre `k: v`', () {
      const src = 'let m = { key: 42 }';
      final let = parseSource(src).program.body.single as LetStmt;
      final entry = (let.value as MapExpr).entries.single;
      expect(src.substring(entry.offset, entry.offset + entry.length), 'key: 42');
    });
  });

  group('nullity — "" é VALOR real, nunca nil/undefined (invariante de design)', () {
    Expr? valueOf(String src) =>
        (parseSource(src).program.body.single as LetStmt).value;

    test('`""` parseia como Str de valor (parts vazio), NUNCA NilLit', () {
      final v = valueOf('let x: String = ""');
      expect(v, isA<Str>());
      expect((v as Str).parts, isEmpty); // vazia — mas É um Str presente
      expect(v, isNot(isA<NilLit>()));
    });

    test('`nil` parseia como NilLit, distinto de Str', () {
      final v = valueOf('let x: String? = nil');
      expect(v, isA<NilLit>());
      expect(v, isNot(isA<Str>()));
    });

    test('três estados distintos: "" (Str) ≠ nil (NilLit) ≠ ausente (null)', () {
      expect(valueOf('let x: String = ""'), isA<Str>()); // valor vazio
      expect(valueOf('let x: String? = nil'), isA<NilLit>()); // nil intencional
      expect(valueOf('let x: String'), isNull); // não-inicializado
    });

    test('String (NamedType, não-opcional) ≠ String? (OptionalType)', () {
      final naoOpcional =
          (parseSource('let x: String = ""').program.body.single as LetStmt).type;
      final opcional =
          (parseSource('let x: String? = nil').program.body.single as LetStmt).type;
      expect(naoOpcional, isA<NamedType>());
      expect((naoOpcional as NamedType).name, 'String');
      expect(opcional, isA<OptionalType>());
    });
  });

  group('D1 — recuperação intra-bloco (não engole `}`, sem cascata)', () {
    test('erro em statement recupera o seguinte NO MESMO bloco', () {
      final fn =
          parseSource('fn f() {\n  let\n  let y = 2\n}').program.body.single
              as FnDecl;
      final block = (fn.body as BlockBody).b;
      expect(block.stmts.length, 2);
      expect(block.stmts[0], isA<ErrorStmt>());
      expect(block.stmts[1], isA<LetStmt>());
    });

    test('erro no bloco não vaza: `fn g` de topo parseia (sem cascata)', () {
      final p = parseSource('fn f() {\n  let\n}\nfn g() => 3');
      expect(p.program.body.length, 2);
      expect((p.program.body[0] as FnDecl).name, 'f');
      expect((p.program.body[1] as FnDecl).name, 'g');
      expect(p.errors.length, 1); // um único erro — não cascateou
    });

    test('membro inválido vira ErrorDecl e o seguinte recupera no corpo', () {
      final s =
          parseSource('struct P {\n  let\n  fn mag() -> Int => 1\n}')
              .program.body.single as StructDecl;
      expect(s.members.length, 2);
      expect(s.members[0], isA<ErrorDecl>());
      expect((s.members[1] as FnDecl).name, 'mag');
    });

    // O sync balanceia chaves: sem isso ele parava no `}` do corpo do membro
    // malformado, dava o TIPO por fechado e reparentava o resto ao top-level.
    group('lixo com `{…}` aninhado não fecha o tipo cedo', () {
      test('membro malformado COM corpo: o seguinte segue membro do tipo', () {
        final p = parseSource(
          'struct S {\n fn bad(&) -> Int { let x = 1 }\n fn ok() -> Int => 2\n}',
        );
        final s = p.program.body.single as StructDecl; // nada vazou p/ o topo
        expect(s.members.length, 2);
        expect(s.members[0], isA<ErrorDecl>());
        expect((s.members[1] as FnDecl).name, 'ok');
        expect(p.errors.length, 1); // um erro só — não cascateou
      });

      test('`let` DENTRO do corpo descartado não é lido como próximo membro', () {
        // `kwLet` é FIRST de membro, mas em profundidade > 0 é statement do
        // sub-bloco — por isso separador/FIRST só valem em profundidade 0.
        final s = parseSource(
              'struct S {\n fn bad(&) { let a = 1\n let b = 2 }\n fn ok() => 3\n}',
            ).program.body.single as StructDecl;
        expect(s.members.length, 2); // ErrorDecl + fn ok (não os `let` internos)
        expect((s.members[1] as FnDecl).name, 'ok');
      });

      test('chaves aninhadas em 2 níveis também balanceiam', () {
        final s = parseSource(
              'struct S {\n fn bad(&) { if c { let a = 1 } }\n fn ok() => 3\n}',
            ).program.body.single as StructDecl;
        expect((s.members[1] as FnDecl).name, 'ok');
      });

      test('membro malformado SEM corpo não regride (caso já coberto)', () {
        final s = parseSource('struct S {\n let\n fn ok() => 1\n}')
            .program.body.single as StructDecl;
        expect(s.members.length, 2);
        expect((s.members[1] as FnDecl).name, 'ok');
      });
    });
  });

  group('CA18 — recuperação N2 (sem cascata)', () {
    test('fn f( { → ErrorDecl enxertado + fn g parseia; erro @6+1', () {
      final p = parseSource('fn f( { }\nfn g() => 1\n');
      expect(p.program.body.length, 2);
      expect(p.program.body[0], isA<ErrorDecl>());
      final g = p.program.body[1] as FnDecl;
      expect(g.name, 'g');
      expect(p.errors.length, 1);
      expect(p.errors.first.code, 'expected-token');
      expect(p.errors.first.offset, 6);
      expect(p.errors.first.length, 1);
    });
  });

  // --------------------------------------------------------------------------
  // Fatia 1 — expressões (shape/assoc + caminhos sem CA dedicado).
  // --------------------------------------------------------------------------
  Expr exprOf(String src) =>
      (parseSource(src).program.body.single as ExprStmt).expr;

  group('CA8 — associatividade', () {
    test('** é direita: a ** b ** c = a ** (b ** c)', () {
      final e = exprOf('a ** b ** c') as Binary;
      expect(e.op, BinaryOp.pow);
      expect((e.left as Ident).name, 'a');
      expect((e.right as Binary).op, BinaryOp.pow); // aninha à direita
    });
  });

  group('closure explícito (sem CA — cobre _isClosureStart/_closure)', () {
    test('(x) => x + 1 é Closure com params explícitos', () {
      final p = parseSource('let f = (x) => x + 1');
      final c = (p.program.body.single as LetStmt).value as Closure;
      expect(c.hasExplicitParams, isTrue);
      expect(c.params.single.name, 'x');
      expect(c.returnType, isNull);
      expect(c.body, isA<ExprBody>());
      expect(p.errors, isEmpty);
    });

    test('(x) -> Int => x preserva o returnType', () {
      final p = parseSource('let f = (x) -> Int => x');
      final c = (p.program.body.single as LetStmt).value as Closure;
      expect((c.returnType as NamedType).name, 'Int');
    });
  });

  group('parenOrClosure — grupo/tupla/1-tupla', () {
    test('(a, b) é TupleExpr de 2', () {
      final e = exprOf('(a, b)') as TupleExpr;
      expect(e.elements.length, 2);
    });

    test('(a) é agrupamento (devolve o interno)', () {
      expect(exprOf('(a)'), isA<Ident>());
    });

    test('(a,) 1-tupla → single-element-tuple (M7)', () {
      final p = parseSource('let p = (a,)');
      expect(p.errors.single.code, 'single-element-tuple');
    });
  });

  // --------------------------------------------------------------------------
  // Cluster de correção pós-review (compiler-craftsman B1/A5/A1/A4).
  // --------------------------------------------------------------------------
  group('B1 — recuperação nunca crasha (progresso garantido)', () {
    test('`init` no topo NÃO lança; enxerta ErrorDecl', () {
      final p = parseSource('init'); // kwInit sem case em _declaration
      expect(p.program.body.single, isA<ErrorDecl>());
      expect(p.errors.single.code, 'expected-declaration');
    });

    test('erro no 2º item (após um let válido) resync sem cascata', () {
      final p = parseSource('let x = 1\ninit\n');
      expect(p.program.body.length, 2);
      expect(p.program.body[0], isA<LetStmt>());
      expect(p.program.body[1], isA<ErrorDecl>());
      expect(p.errors.length, 1); // UM erro, sem cascata
    });
  });

  group('A5 — match arms com vírgula OPCIONAL', () {
    test('arms separados sem vírgula parseiam', () {
      final e = exprOf('match x { 1 => a 2 => b }') as MatchExpr;
      expect(e.arms.length, 2);
    });
  });

  group('A1 — supressão de trailing-closure não vaza p/ brackets', () {
    test('trailing-closure aninhada em args de call dentro de cond `if`', () {
      // `inner() { $0 }` está DENTRO de `outer(...)` → não é suprimido pela
      // condição do if; `{ a }`/`{ b }` continuam sendo os blocos do if.
      final p = parseSource(r'if outer(inner() { $0 }) { a } else { b }');
      expect(p.errors, isEmpty);
      expect(p.program.body.single, isA<IfStmt>());
    });
  });

  group('A4 — span do generic interno inclui o `>` (split de `>>`)', () {
    test('List<Int> em Map<String, List<Int>> tem length 9', () {
      final p = parseSource('let m: Map<String, List<Int>> = e');
      final map = (p.program.body.single as LetStmt).type as NamedType;
      final list = map.args[1] as NamedType;
      expect(list.name, 'List');
      expect(list.length, 9); // "List<Int>" — o `>` de fecho entra no span
    });
  });

  // --------------------------------------------------------------------------
  // if-EXPRESSÃO (ruling RD-1, opção A).
  // --------------------------------------------------------------------------
  group('if-expr (RD-1, opção A)', () {
    test('booleana: binding null, subject é o Bool, ramos são expressões', () {
      final e = (parseSource('let x = if a > b => a else b').program.body.single
              as LetStmt)
          .value as IfExpr;
      expect(e.binding, isNull);
      expect((e.subject as Binary).op, BinaryOp.gt);
      expect((e.then as Ident).name, 'a');
      expect((e.orElse as Ident).name, 'b');
    });

    test('else-if encadeia como IfExpr no orElse', () {
      final e = (parseSource('let x = if a => 1 else if b => 2 else 3').program
              .body.single as LetStmt)
          .value as IfExpr;
      expect(e.orElse, isA<IfExpr>());
    });

    test('if-let: binding presente, subject é o desembrulhado', () {
      final e = (parseSource('let x = if let u = user => u else nil').program
              .body.single as LetStmt)
          .value as IfExpr;
      expect((e.binding as BindPattern).name, 'u');
      expect((e.subject as Ident).name, 'user');
    });

    test('else é OBRIGATÓRIO no if-expr', () {
      final p = parseSource('let x = if a => 1');
      expect(p.errors, isNotEmpty); // falta o `else`
    });
  });

  // --------------------------------------------------------------------------
  // Interpolação — spans ABSOLUTOS (conserto do débito da revisão da Fase 2).
  // --------------------------------------------------------------------------
  group('interpolação — spans absolutos', () {
    test(r'a sub-expr de ${…} tem offset relativo ao ARQUIVO, não ao fragmento', () {
      // `let s = "x=${a + 1}!"` — `a`@13, `1`@17 no fonte completo.
      final v = (parseSource(r'let s = "x=${a + 1}!"').program.body.single
              as LetStmt)
          .value as Str;
      final bin = (v.parts[1] as StrInterp).expr as Binary;
      expect((bin.left as Ident).offset, 13); // absoluto, não 0
      expect((bin.right as IntLit).offset, 17); // absoluto, não 4
    });
  });

  // --------------------------------------------------------------------------
  // opOffset — pós-fixos apontam pro SELETOR, não pro receptor (fix A1).
  // --------------------------------------------------------------------------
  group('opOffset dos pós-fixos', () {
    test('x! : span começa no receptor (0) mas opOffset é o `!` (1)', () {
      final fu = exprOf('x!') as ForceUnwrap;
      expect(fu.offset, 0); // span completo: do `x`
      expect(fu.opOffset, 1); // fileOffset do Kernel: no `!`
    });

    test('cadeia obj.field?.m()!.x — cada seletor no seu offset', () {
      //  o  b  j  .  f  i  e  l  d  ?  .  m  (  )  !  .  x
      //  0  1  2  3  4  5  6  7  8  9    11 12 13 14 15 16
      final outer = exprOf('obj.field?.m()!.x') as Member; // `.x`
      expect(outer.opOffset, 15);
      final fu = outer.receiver as ForceUnwrap; // `!`
      expect(fu.opOffset, 14);
      final call = fu.operand as Call; // `()`
      expect(call.opOffset, 12);
      final oc = call.callee as OptChain; // `?.m`
      expect(oc.opOffset, 9);
      final inner = oc.receiver as Member; // `.field`
      expect(inner.opOffset, 3);
      // O span completo do nó externo ainda cobre a cadeia inteira (do `obj`):
      expect(outer.offset, 0);
    });
  });

  // --------------------------------------------------------------------------
  // spec 005 — superfície declarativa (init / guard-let cond / conformances).
  // --------------------------------------------------------------------------
  group('spec 005 — construtor init (CA1)', () {
    test('class com init: InitDecl com params tipados e corpo bloco', () {
      final c =
          parseSource('class Animal { init(name: String) { self.name = name } }')
              .program.body.single as ClassDecl;
      final init = c.members.single as InitDecl;
      expect(init.params.single.name, 'name');
      expect((init.params.single.type as NamedType).name, 'String');
      expect(init.body.stmts.length, 1);
    });

    test('init sem params: params vazio, corpo vazio (AST representa)', () {
      final c = parseSource('class C { init() { } }').program.body.single
          as ClassDecl;
      final init = c.members.single as InitDecl;
      expect(init.params, isEmpty);
      expect(init.body.stmts, isEmpty);
    });

    test('struct com init é aceito SINTATICAMENTE (política é Fase 3)', () {
      final s =
          parseSource('struct P { init() { } }').program.body.single as StructDecl;
      expect(s.members.single, isA<InitDecl>());
    });

    test('B1 — `pub init` PRESERVA isPublic (não descarta mudo, P4)', () {
      final c = parseSource('class C { pub init() { } }').program.body.single
          as ClassDecl;
      expect((c.members.single as InitDecl).isPublic, isTrue);
    });

    test('B1 — `init` sem pub: isPublic false', () {
      final c = parseSource('class C { init() { } }').program.body.single
          as ClassDecl;
      expect((c.members.single as InitDecl).isPublic, isFalse);
    });
  });

  group('spec 005 — guard-let condition (&&-refino, CA2/CA7)', () {
    test('com `&&`: value = operando esq., condition = dir. (distinta)', () {
      final g = parseSource('guard let v = opt && v > 0 else { return }')
          .program.body.single as GuardLetStmt;
      expect((g.value as Ident).name, 'opt');
      final cond = g.condition as Binary;
      expect(cond.op, BinaryOp.gt);
      expect((cond.left as Ident).name, 'v');
    });

    test('sem `&&`: condition null — não regride (CA7)', () {
      final g = parseSource('guard let v = opt else { return }')
          .program.body.single as GuardLetStmt;
      expect(g.condition, isNull);
      expect((g.value as Ident).name, 'opt');
    });

    test('multi-`&&`: split no PRIMEIRO — value=opt, condition=(c1 && c2)', () {
      final g = parseSource('guard let v = opt && c1 && c2 else { return }')
          .program.body.single as GuardLetStmt;
      expect((g.value as Ident).name, 'opt'); // só o operando desembrulhado
      final cond = g.condition as Binary; // todo o refino restante
      expect(cond.op, BinaryOp.and);
      expect((cond.left as Ident).name, 'c1');
      expect((cond.right as Ident).name, 'c2');
    });

    // Correção 2026-07-14: o value era `equality`, que parava no `&&` mas também
    // ficava abaixo de `??`/`||`/`|>`/`>>` — os quatro viravam error-stmt.
    // Agora é `pipe` + flag que reserva só o `&&` de nível-topo.
    group('value usa a cascata até `pipe` (sem perder o split do &&)', () {
      GuardLetStmt guardLet(String src) =>
          parseSource(src).program.body.single as GuardLetStmt;

      test('`??`/`||`/`|>`/`>>` parseiam no value (antes: error-stmt)', () {
        for (final (src, op) in [
          ('a ?? b', BinaryOp.coalesce),
          ('a || b', BinaryOp.or),
          ('a |> f', BinaryOp.pipe),
          ('f >> g', BinaryOp.compose),
        ]) {
          final p = parseSource('guard let v = $src else { return }');
          expect(p.errors, isEmpty, reason: 'value `$src` deve parsear');
          expect((p.program.body.single as GuardLetStmt).value, isA<Binary>());
          expect(
            ((p.program.body.single as GuardLetStmt).value as Binary).op,
            op,
          );
        }
      });

      test('`a ?? b && c`: o ?? fica no value, o && de topo é o refino', () {
        final g = guardLet('guard let v = a ?? b && c else { return }');
        expect((g.value as Binary).op, BinaryOp.coalesce); // (a ?? b)
        expect((g.condition as Ident).name, 'c');
      });

      test('`(a && b)`: dentro de parênteses o && é operador normal', () {
        final g = guardLet('guard let v = (a && b) else { return }');
        expect((g.value as Binary).op, BinaryOp.and);
        expect(g.condition, isNull); // não foi split
      });

      test('`f(a && b)`: && em argumento não vira refino', () {
        final g = guardLet('guard let v = f(a && b) else { return }');
        expect(g.value, isA<Call>());
        expect(g.condition, isNull);
      });

      test('closure: && interno é normal, && externo vira refino', () {
        final g = guardLet(
          'guard let v = xs.map { \$0 && b } && c else { return }',
        );
        expect(g.value, isA<Call>()); // xs.map { … }
        expect((g.condition as Ident).name, 'c');
      });

      test('`&&` comum depois de um guard-let segue normal', () {
        final p = parseSource(
          'fn m() {\n guard let v = a && b else { return }\n let z = c && d\n}',
        );
        expect(p.errors, isEmpty);
      });

      test('guard-let MALFORMADO não contamina o `&&` seguinte', () {
        // O parser lança ParseError para recuperar (D3) de dentro do valor
        // (flag ligada). O `c && d` posterior tem de parsear normalmente, e
        // seguir DENTRO da fn (D1: a recuperação não reparenta p/ o topo).
        final p = parseSource(
          'fn m() {\n guard let v = a ?? else { return }\n let z = c && d\n}',
        );
        final fn = p.program.body.whereType<FnDecl>().single;
        final z = (fn.body! as BlockBody).b.stmts.whereType<LetStmt>().single;
        expect((z.value as Binary).op, BinaryOp.and);
      });
    });
  });

  group('spec 005 — conformances inline (traits, CA3/CA4/CA5)', () {
    test('struct: todos os types após `:` são traits', () {
      final s = parseSource('struct Point: Eq, Ord { x: Int }')
          .program.body.single as StructDecl;
      expect(s.traits.length, 2);
      expect((s.traits[0] as NamedType).name, 'Eq');
      expect((s.traits[1] as NamedType).name, 'Ord');
    });

    test('struct sem conformance: traits vazio (não regride)', () {
      final s =
          parseSource('struct P { x: Int }').program.body.single as StructDecl;
      expect(s.traits, isEmpty);
    });

    test('class: 1º type = superclasse, resto = traits (CA4)', () {
      final c = parseSource('class Dog: Animal, Barker { }')
          .program.body.single as ClassDecl;
      expect((c.superclass as NamedType).name, 'Animal');
      expect((c.traits.single as NamedType).name, 'Barker');
    });

    test('class só com superclasse: traits vazio', () {
      final c =
          parseSource('class Dog: Animal { }').program.body.single as ClassDecl;
      expect((c.superclass as NamedType).name, 'Animal');
      expect(c.traits, isEmpty);
    });

    test('extension: target + traits após `:` (CA5)', () {
      final e = parseSource('extension Int: Ord { }').program.body.single
          as ExtensionDecl;
      expect((e.target as NamedType).name, 'Int');
      expect((e.traits.single as NamedType).name, 'Ord');
    });
  });

  group('spec 005 — membro async fn (CA6)', () {
    test('async fn em corpo de tipo: asyncMarker = async', () {
      final s = parseSource('struct S { async fn tick() => 0 }')
          .program.body.single as StructDecl;
      final fn = s.members.single as FnDecl;
      expect(fn.name, 'tick');
      expect(fn.asyncMarker, AsyncMarker.async);
    });
  });

  // --------------------------------------------------------------------------
  // spec 006 — where-expr (nível 0) + operadores tipados (enum fechado).
  // --------------------------------------------------------------------------
  group('spec 006 — where-expr (shape/CA1/CA2/CA3)', () {
    test('CA1 — where wrapa o value; bindings são LetStmt em ordem-fonte', () {
      final w =
          (parseSource(
                    'let r = total where {\n  let total = a + b\n  let a = 1\n  let b = 2\n}',
                  ).program.body.single
                  as LetStmt)
              .value
              as WhereExpr;
      expect((w.value as Ident).name, 'total');
      expect(w.bindings.length, 3);
      // (que todo binding é LetStmt agora é do TIPO, não de um assert)
      expect(w.bindings.first.value, isA<Binary>()); // a + b
    });

    test('CA2 — sem `where` não regride: value é o assignment, não WhereExpr', () {
      final v =
          (parseSource('let r = a + b').program.body.single as LetStmt).value;
      expect(v, isA<Binary>());
      expect(v, isNot(isA<WhereExpr>()));
    });

    test('CA3 — statement não-binding no bloco → where-expects-binding', () {
      final p = parseSource('let r = x where { y + 1 }');
      expect(p.errors, isNotEmpty);
      expect(p.errors.first.code, 'where-expects-binding');
    });

    test('`var` no bloco é aceito no PARSE (pureza é Fase 3 — ruling de dono)', () {
      final p = parseSource('let r = a where { var a = 1 }');
      expect(p.errors, isEmpty);
      final w = (p.program.body.single as LetStmt).value as WhereExpr;
      expect(w.bindings.single.isVar, isTrue);
    });

    test('um `where` por expressão: 2º `where` seguido → where-non-associative', () {
      final p = parseSource('let r = x where { let a = 1 } where { let b = 2 }');
      expect(p.errors.any((e) => e.code == 'where-non-associative'), isTrue);
    });

    test('bloco vazio → where-empty (o `+` da produção §3.1)', () {
      final p = parseSource('let r = x where { }');
      expect(p.errors.any((e) => e.code == 'where-empty'), isTrue);
    });

    // §whereBinding: init OBRIGATÓRIO — Δ vs `letStmt` solto, onde é opcional.
    // Sem a guarda, a Fase 3 fabricava `match nil { y => V }` e ligava `y` a nil
    // real sob tipo não-opcional (nullity-invariant: nil só sob `T?`).
    group('where-binding-needs-value — init obrigatório no bloco', () {
      test('`let y` sem init → where-binding-needs-value, no span do binding', () {
        const src = 'let r = y where { let y }';
        final p = parseSource(src);
        expect(p.errors.first.code, 'where-binding-needs-value');
        expect(
          src.substring(
            p.errors.first.offset,
            p.errors.first.offset + p.errors.first.length,
          ),
          'let y',
        );
      });

      test('`var y` sem init idem (a guarda é sobre o valor, não sobre let/var)', () {
        final p = parseSource('let r = y where { var y }');
        expect(p.errors.first.code, 'where-binding-needs-value');
      });

      test('`let y: Int` (só tipo, sem `=`) também é barrado', () {
        final p = parseSource('let r = y where { let y: Int }');
        expect(p.errors.first.code, 'where-binding-needs-value');
      });

      test('com init parseia limpo (o caso legítimo NÃO regride)', () {
        final p = parseSource('let r = y where { let y = 2 }');
        expect(p.errors, isEmpty);
      });

      test('`let y` FORA do where segue legal (init opcional no bind form)', () {
        // A restrição é do `where`, não do `let` — `let y` num bloco declara
        // agora e atribui depois; o where não tem "depois".
        expect(parseSource('let y').errors, isEmpty);
      });
    });

    // Nome repetido no mesmo `where` é erro, não shadowing: a Fase 3 aninha em
    // matches e a Fase 4 leria os escopos aninhados como shadowing legítimo —
    // `duplicate-declaration` jamais dispararia (num bloco comum, dispara).
    group('where-duplicate-binding — um nome, um binding', () {
      test('`let y = 1; let y = 2` → erro no span do SEGUNDO binding', () {
        const src = 'let r = y where { let y = 1; let y = 2 }';
        final p = parseSource(src);
        expect(p.errors.first.code, 'where-duplicate-binding');
        expect(
          src.substring(
            p.errors.first.offset,
            p.errors.first.offset + p.errors.first.length,
          ),
          'let y = 2', // o culpado é o 2º, não o 1º
        );
      });

      test('duplicata via DESTRUCTURE (`let [a, b] = xs; let a = 1`)', () {
        // Um pattern liga vários nomes — por isso a checagem usa patternVars,
        // não `n.name`.
        final p = parseSource('let r = a where { let [a, b] = xs; let a = 1 }');
        expect(p.errors.first.code, 'where-duplicate-binding');
      });

      test('duplicata entre dois destructures (`[a, b]` e `{ b }`)', () {
        final p = parseSource(
          'let r = a where { let [a, b] = xs; let { b } = m }',
        );
        expect(p.errors.first.code, 'where-duplicate-binding');
      });

      test('nomes distintos parseiam limpo (o caso legítimo NÃO regride)', () {
        expect(parseSource('let r = a + b where { let a = 1; let b = 2 }').errors,
            isEmpty);
      });

      test('mesmo nome em `where`s SEPARADOS segue legal (escopos distintos)', () {
        final p = parseSource(
          'let r = (y where { let y = 1 }) + (y where { let y = 2 })',
        );
        expect(p.errors, isEmpty);
      });
    });
  });

  group('spec 006 — operadores tipados: exaustividade (CA5)', () {
    // A prova de P4: cada `switch` abaixo NÃO tem `default`. Uma variante nova
    // sem case aqui QUEBRA a compilação deste arquivo — o enum é a fonte da
    // exaustividade que `op:string` não dava (esquecer `??` passava mudo).
    test('BinaryOp — 17 variantes cobertas por switch sem default', () {
      String tag(BinaryOp op) => switch (op) {
        BinaryOp.add => '+',
        BinaryOp.sub => '-',
        BinaryOp.mul => '*',
        BinaryOp.div => '/',
        BinaryOp.mod => '%',
        BinaryOp.pow => '**',
        BinaryOp.eq => '==',
        BinaryOp.ne => '!=',
        BinaryOp.lt => '<',
        BinaryOp.gt => '>',
        BinaryOp.le => '<=',
        BinaryOp.ge => '>=',
        BinaryOp.and => '&&',
        BinaryOp.or => '||',
        BinaryOp.coalesce => '??',
        BinaryOp.pipe => '|>',
        BinaryOp.compose => '>>',
      };
      for (final op in BinaryOp.values) {
        expect(tag(op), isNotEmpty);
      }
      expect(BinaryOp.values.length, 17);
    });

    test('UnaryOp — 2 variantes (neg/not; sem `~`) cobertas sem default', () {
      String tag(UnaryOp op) => switch (op) {
        UnaryOp.neg => 'neg',
        UnaryOp.not => '!',
      };
      for (final op in UnaryOp.values) {
        expect(tag(op), isNotEmpty);
      }
      expect(UnaryOp.values.length, 2);
    });

    test('AssignOp — 5 variantes cobertas sem default', () {
      String tag(AssignOp op) => switch (op) {
        AssignOp.assign => '=',
        AssignOp.addAssign => '+=',
        AssignOp.subAssign => '-=',
        AssignOp.mulAssign => '*=',
        AssignOp.divAssign => '/=',
      };
      for (final op in AssignOp.values) {
        expect(tag(op), isNotEmpty);
      }
      expect(AssignOp.values.length, 5);
    });
  });
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

/// Troca o sufixo `.tu` do arquivo por [ext] (ex.: `.ast`).
String _sibling(File tu, String ext) =>
    '${tu.path.substring(0, tu.path.length - 3)}$ext';

/// Extrai as linhas `// EXPECT: <erro>` de um fonte, na ordem (só as de parse).
List<String> _expectLines(String src) => src
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('// EXPECT: parse-error:'))
    .map((l) => l.substring('// EXPECT: '.length))
    .toList();

/// Erros LÉXICOS esperados no caminho `parseSource` (`// EXPECT-LEX: <code>
/// @line:col`). Diferente dos goldens `.errors` (que testam `tokenizeSource`
/// direto): estes provam que o erro do léxico ATRAVESSA o parse e chega ao
/// usuário de `itac parse|desugar|resolve` — antes eram descartados ali.
List<String> _expectLexLines(String src) => src
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('// EXPECT-LEX:'))
    .map((l) => l.substring('// EXPECT-LEX: '.length))
    .toList();
