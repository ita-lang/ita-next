// ============================================================================
// type_test.dart — Modelo de tipos da Fase 5 (spec 009 §4.1/§4.2).
// ============================================================================
//
// Prova os INVARIANTES do modelo, que são o que separa esta fase do oracle:
//  • `optional` é idempotente (`?` é MODIFICADOR — ruling do dono §12-7);
//  • `ErrorType` ≠ `TypeVar` (a fusão em `UnknownType` é a causa de o oracle
//    checar 4 regras em 1355 linhas — ADR-0013);
//  • identidade NOMINAL por nó-decl (não por string) e ESTRUTURAL nos
//    construtores (§4.2).
// ============================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:test/test.dart';

void main() {
  ast.StructDecl structDecl(String name) =>
      ast.StructDecl(false, name, const [], const [], const [], 0, 1);

  group('§4.6 — `optional` é idempotente (`?` é MODIFICADOR, não construtor)', () {
    test('optional(optional(T)) == optional(T) — T?? = T?', () {
      final once = optional(const IntType());
      final twice = optional(optional(const IntType()));
      expect(twice, once);
      expect((twice as OptionalType).inner, const IntType()); // não aninhou
    });

    test('o invariante vale em 3 níveis (T???)', () {
      final t = optional(optional(optional(const StringType())));
      expect((t as OptionalType).inner, const StringType());
    });

    test('é o que a SUBSTITUIÇÃO precisa: subst(T?, T:=String?) = String?', () {
      // O caso da stdlib: `compact<T>(list: List<T?>)` com `T = String?`.
      // Um subst estrutural ingênuo daria OptionalType(OptionalType(String)) e
      // quebraria o invariante EM SILÊNCIO — e a F7 não teria imagem (o Kernel
      // tem UM byte de Nullability, não dois).
      Type subst(Type t, Type arg) => switch (t) {
        OptionalType(:final inner) => optional(subst(inner, arg)),
        TypeVar _ => arg,
        _ => t,
      };
      final resultado = subst(optional(const TypeVar(0)), optional(const StringType()));
      expect(resultado, optional(const StringType()));
      expect((resultado as OptionalType).inner, const StringType());
    });

    test('optional(ErrorType) absorve (anti-cascata)', () {
      expect(optional(const ErrorType()), const ErrorType());
    });

    test('optional(Never) é `Never?` — opcional que só admite .none', () {
      expect(optional(const NeverType()), isA<OptionalType>());
    });
  });

  group('ADR-0013 — `ErrorType` ≠ `TypeVar` (o que o oracle fundiu)', () {
    test('são tipos distintos, não sinônimos de "não sei"', () {
      expect(const ErrorType(), isNot(const TypeVar(0)));
      expect(const TypeVar(0), isNot(const ErrorType()));
    });

    test('TypeVar tem identidade por id (a unificação da fatia D depende)', () {
      expect(const TypeVar(1), const TypeVar(1));
      expect(const TypeVar(1), isNot(const TypeVar(2)));
    });
  });

  group('§4.2 — identidade NOMINAL (por nó-decl, não por string)', () {
    test('dois structs de MESMO NOME e decls distintas são tipos DIFERENTES', () {
      // É o que o `StructType('Node')` do oracle não distingue.
      final a = NamedType(structDecl('Node'), TypeKind.struct_);
      final b = NamedType(structDecl('Node'), TypeKind.struct_);
      expect(a, isNot(b));
    });

    test('o MESMO decl dá o mesmo tipo (reflexivo)', () {
      final d = structDecl('Node');
      expect(NamedType(d, TypeKind.struct_), NamedType(d, TypeKind.struct_));
    });

    test('tipo RECURSIVO não estoura o == (o grafo tem ciclos — 6.3.1)', () {
      // `struct Cell { info: Int, next: Cell }` — o box do livro.
      final cell = structDecl('Cell');
      final t1 = NamedType(cell, TypeKind.struct_);
      final t2 = NamedType(cell, TypeKind.struct_);
      expect(t1 == t2, isTrue); // nominal: compara o decl, não desce nos campos
      expect(t1.hashCode, t2.hashCode);
    });

    test('args entram na identidade: Box<Int> ≠ Box<String>', () {
      final box = structDecl('Box');
      expect(
        NamedType(box, TypeKind.struct_, const [IntType()]),
        isNot(NamedType(box, TypeKind.struct_, const [StringType()])),
      );
    });

    test('`kind` carrega valor vs referência (P2)', () {
      expect(NamedType(structDecl('P'), TypeKind.struct_).isValue, isTrue);
      expect(NamedType(structDecl('C'), TypeKind.class_).isValue, isFalse);
    });
  });

  group('§4.2 — identidade ESTRUTURAL nos construtores', () {
    test('FunctionType compara params/ret/isAsync', () {
      expect(
        const FunctionType([IntType()], StringType()),
        const FunctionType([IntType()], StringType()),
      );
      expect(
        const FunctionType([IntType()], StringType()),
        isNot(const FunctionType([IntType()], StringType(), isAsync: true)),
      );
    });

    test('TupleType compara elementos em ordem', () {
      expect(
        const TupleType([IntType(), StringType()]),
        const TupleType([IntType(), StringType()]),
      );
      expect(
        const TupleType([IntType(), StringType()]),
        isNot(const TupleType([StringType(), IntType()])),
      );
    });

    test('OptionalType compara o inner', () {
      expect(optional(const IntType()), optional(const IntType()));
      expect(optional(const IntType()), isNot(optional(const StringType())));
    });
  });

  test('dump legível (é o observável do `--dump-types`)', () {
    expect(optional(const IntType()).toString(), 'Int?');
    expect(const FunctionType([IntType()], VoidType()).toString(),
        '(Int) -> Void');
    expect(const TupleType([IntType(), StringType()]).toString(), '(Int, String)');
    expect(const NeverType().toString(), 'Never');
    expect(const ErrorType().toString(), '<error>');
    expect(
      NamedType(structDecl('Box'), TypeKind.struct_, const [IntType()])
          .toString(),
      'Box<Int>',
    );
  });
}
