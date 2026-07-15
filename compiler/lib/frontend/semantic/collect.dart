// ===========================================================================
// collect.dart — Fatia A da Fase 5: Collect (spec 009 §5.4).
// ===========================================================================
//
// Materialização À MÃO da spec `009-semantic-types` §5.4-A (P11 / ADR-0010).
//
// O CORTE É DO LIVRO, não nosso: Dragon **6.3** popula a tabela a partir das
// DECLARAÇÕES (SDT das Figs 6.15/6.17/6.18 — `top.put(id.lexeme, T.type, …)`);
// **6.5** checa as EXPRESSÕES contra ela. Duas seções, dois passes.
//
// TWO-PASS É OBRIGATÓRIO, não estilo — 6.5.1: *"A síntese de tipo … exige que os
// nomes sejam declarados antes de serem usados"*. O módulo do Itá é **letrec**
// (ruling F4 §0.5-3), e os tipos são **mutuamente recursivos** (6.3.1, box
// *"Nomes de tipo e tipos recursivos"* + nota 3: o grafo tem ciclos). Daí:
//   A1 — planta as CABEÇAS (nome + kind + generics), corpo vazio;
//   A2 — preenche o CORPO (campos/variantes/supertipo/traits) resolvendo os
//        `TypeNode`, agora que toda cabeça existe;
//   A3 — boa-formação (`duplicate-field`, aridade de generic, ciclo de herança).
//
// ⚠️ Dragon **6.3.4/6.3.5 NÃO se aplicam** (largura, endereço relativo,
// alinhamento): é **Grupo B** — a Dart VM faz layout (ADR-0007). Metade do 6.3 é
// herdada; `offset += T.width` seria código sem consumidor.
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// Roda a fatia A sobre a AST canônica (pós-desugar, pós-bind).
CheckResult collectTypes(ast.Program program) {
  final c = Collector();
  c.run(program);
  // Ordem-FONTE, não ordem-de-descoberta: A2 percorre por decl e A3 roda depois,
  // então `duplicate-field` (A3) sairia atrás de um `redundant-optional` (A2) que
  // está mais abaixo no arquivo. Quem lê o erro lê o arquivo de cima p/ baixo.
  final errors = [...c.errors]..sort((a, b) => a.offset.compareTo(b.offset));
  return CheckResult(program, c.types, errors, c.annotations);
}

class Collector {
  final TypeTable types = TypeTable();
  final List<CheckError> errors = [];
  final Map<ast.TypeNode, Type> annotations = Map.identity();

  /// Parâmetros genéricos em escopo: nome → a decl que os DECLAROU
  /// (`struct Box<T>` ⟹ `T` → o `StructDecl`). São da **fatia A**: sem eles, A2 não
  /// resolve as anotações da stdlib (`Option<T>` 33×, `List<T>` em tudo). O que a
  /// fatia **D** adiciona é a UNIFICAÇÃO de type-args em aplicação (Alg. 6.19).
  ///
  /// A decl-dona é necessária porque `GenericParam` **não é `AstNode`** (não tem
  /// span nem identidade própria — mesma limitação do `FieldPattern`, débito D4
  /// da F4): o par (dona, nome) é o que identifica um [TypeParamType].
  final List<Map<String, ast.AstNode>> _genericScopes = [];

  void run(ast.Program p) {
    final decls = p.body.whereType<ast.Decl>().toList();
    for (final d in decls) {
      _collectHead(d); // A1
    }
    for (final d in decls) {
      _collectBody(d); // A2
    }
    _checkWellFormed(); // A3
  }

  // --- A1: cabeças ---------------------------------------------------------

  void _collectHead(ast.Decl d) {
    final (name, kind, generics) = switch (d) {
      ast.StructDecl n => (n.name, TypeKind.struct_, _names(n.generics)),
      ast.ClassDecl n => (n.name, TypeKind.class_, _names(n.generics)),
      ast.EnumDecl n => (n.name, TypeKind.enum_, _names(n.generics)),
      ast.TraitDecl n => (n.name, TypeKind.trait_, _names(n.generics)),
      ast.ActorDecl n => (n.name, TypeKind.actor_, const <String>[]),
      _ => (null, TypeKind.struct_, const <String>[]),
    };
    if (name == null) return;
    // Redeclaração de tipo é `duplicate-declaration` da F4 (namespace unificado,
    // ruling F4 #1) — não repetimos o diagnóstico aqui.
    types.put(TypeInfo(d, name, kind, generics: generics));
  }

  List<String> _names(List<ast.GenericParam> gs) => [for (final g in gs) g.name];

  // --- A2: corpos ----------------------------------------------------------

  void _collectBody(ast.Decl d) {
    final info = types.of(d);
    if (info == null) return;
    _genericScopes.add({for (final g in info.generics) g: d});

    switch (d) {
      case ast.StructDecl n:
        info.traits = [for (final t in n.traits) _resolve(t)];
        info.fields = _fields(n.members);
      case ast.ClassDecl n:
        if (n.superclass != null) info.superclass = _resolve(n.superclass!);
        info.traits = [for (final t in n.traits) _resolve(t)];
        info.fields = _fields(n.members);
      case ast.EnumDecl n:
        info.variants = [
          for (final c in n.cases)
            VariantInfo(c.name, [for (final p in c.payload) _param(p)]),
        ];
      case ast.TraitDecl n:
        info.fields = _fields(n.members);
      case ast.ActorDecl n:
        info.fields = _fields(n.members);
      default:
        break;
    }
    _genericScopes.removeLast();
  }

  List<FieldInfo> _fields(List<ast.Decl> members) => [
    for (final m in members)
      if (m is ast.FieldDecl)
        FieldInfo(m.name, _resolve(m.type), m.isMutable, m),
  ];

  Type _param(ast.Param p) => p.type == null ? const ErrorType() : _resolve(p.type!);

  // --- A2: TypeNode (sintaxe) → Type (semântica) ---------------------------

  /// A travessia anotação→tipo. Preenche a side-table `<TypeNode, Type>` (§7-4).
  Type _resolve(ast.TypeNode node) {
    final t = _resolveInner(node);
    annotations[node] = t;
    return t;
  }

  Type _resolveInner(ast.TypeNode node) => switch (node) {
    ast.NamedType n => _named(n),
    ast.OptionalType n => _optionalAnnotation(n),
    // `mut` NÃO é tipo (§4.1): não tem imagem em `DartType` (o Kernel tem
    // `isFinal`/`Field.mutable`). Normaliza para o inner; a mutabilidade é flag
    // do binding/campo — `FieldDecl.isMutable` já a carrega.
    ast.MutType n => _resolve(n.inner),
    ast.FunctionType n => FunctionType(
      [for (final p in n.params) _resolve(p)],
      _resolve(n.ret),
      isAsync: n.isAsync,
    ),
    ast.TupleType n => TupleType([for (final e in n.elements) _resolve(e)]),
    // A árvore é total (M2): `ErrorType` sintático já foi reportado pelo parser.
    ast.ErrorType _ => const ErrorType(),
  };

  /// `T?` — e é aqui que mora o `redundant-optional` (spec 009 §4.6-cond.2).
  ///
  /// **É de ANOTAÇÃO, não de `Type`**: dispara quando o usuário escreveu DOIS
  /// níveis de opcionalidade *nesta anotação*. Se morasse no smart constructor
  /// `optional()`, dispararia em `compact<String?>` — programa **LEGAL** —,
  /// porque lá os dois `?` vêm de SUBSTITUIÇÃO (fatia D), não de dois glifos.
  ///
  /// O critério é o INNER JÁ RESOLVIDO ser opcional — não `inner is
  /// ast.OptionalType`. Como `Option[T]` ≡ `T?` (§4.6), a forma `Option[Int]?`
  /// chega com inner `NamedType`, e `Option[Option[Int]]` nem passa por aqui
  /// (usando `[]` no lugar de angle brackets só para o doc-comment). As formas
  /// são o mesmo tipo, e todas têm de disparar (§11 CA28a).
  ///
  /// NOTA: `T??` **não é exprimível** — o lexer casa `??` como UM token
  /// (`questionQuestion`, o coalesce; maximal munch). O CA28a da spec cita
  /// `String??`, que na verdade morre antes, no parser (`expected-token`).
  Type _optionalAnnotation(ast.OptionalType n) {
    final inner = _resolve(n.inner);
    if (inner is OptionalType) _err('redundant-optional', n);
    return optional(inner);
  }

  Type _named(ast.NamedType n) {
    final args = [for (final a in n.args) _resolve(a)];

    // 1. Parâmetro de tipo DECLARADO (`T` dentro de `struct Box<T>`) — a
    //    variável LIGADA do 6.5.4, não a fresca da unificação (que é da fatia D).
    final owner = _genericOwner(n.name);
    if (args.isEmpty && owner != null) {
      return TypeParamType(owner, n.name);
    }

    // 2. Básicos (6.3.1).
    final basic = switch (n.name) {
      'Int' => const IntType(),
      'Float' => const FloatType(),
      'Bool' => const BoolType(),
      'String' => const StringType(),
      'Void' => const VoidType(),
      'Never' => const NeverType(),
      _ => null,
    };
    if (basic != null) {
      if (args.isNotEmpty) _err('generic-arity-mismatch', n);
      return basic;
    }

    // 3. `Option<X>` → `OptionalType(X)` — ALIAS canônico resolvido AQUI, em A2
    //    (§4.6, ruling do dono 2026-07-12: `Option<T>` ≡ `T?`). Uma reescrita de
    //    uma linha, NÃO instanciação genérica — por isso a nulidade não depende
    //    da fatia D, e `BuiltinType` não sobrevive à fatia A.
    if (n.name == 'Option') {
      if (args.length != 1) {
        _err('generic-arity-mismatch', n);
        return const ErrorType();
      }
      // `Option<Option<Int>>` / `Option<Int?>` — dois glifos de opcionalidade na
      // mesma anotação (ver [_optionalAnnotation]).
      if (args.single is OptionalType) _err('redundant-optional', n);
      return optional(args.single);
    }

    // 4. User-type declarado no módulo.
    final decl = types.declNamed(n.name);
    if (decl == null) {
      _err('unknown-type', n);
      return const ErrorType();
    }
    final info = types.of(decl)!;
    if (args.length != info.generics.length) {
      _err('generic-arity-mismatch', n);
      return const ErrorType();
    }
    return NamedType(decl, info.kind, args);
  }

  /// A decl que declarou o parâmetro genérico [name], ou `null` se não há um em
  /// escopo. Do mais interno para o mais externo (shadowing léxico).
  ast.AstNode? _genericOwner(String name) {
    for (final scope in _genericScopes.reversed) {
      final owner = scope[name];
      if (owner != null) return owner;
    }
    return null;
  }

  // --- A3: boa-formação ----------------------------------------------------

  void _checkWellFormed() {
    for (final info in types.all) {
      _checkDuplicateFields(info);
      _checkInheritanceCycle(info);
    }
  }

  /// Dragon 6.3.6, literal: *"Os nomes dos campos de um registro devem ser
  /// distintos; ou seja, um nome pode aparecer no máximo uma vez"*.
  void _checkDuplicateFields(TypeInfo info) {
    final seen = <String>{};
    for (final f in info.fields ?? const <FieldInfo>[]) {
      if (!seen.add(f.name)) _err('duplicate-field', f.decl);
    }
  }

  /// `class A : B` … `class B : A`. Sem isto, qualquer walk sobre a hierarquia
  /// (`≤` do §4.2b, F6, F7) entra em laço. O livro avisa que o grafo tem ciclos
  /// (6.3.1, nota 3) — a identidade nominal (§4.2) protege o `==`, mas não a
  /// TRAVESSIA.
  void _checkInheritanceCycle(TypeInfo info) {
    final visited = <ast.AstNode>{info.decl};
    var cur = info;
    while (true) {
      final sup = cur.superclass;
      if (sup is! NamedType) return; // topo da cadeia
      if (identical(sup.decl, info.decl)) {
        _err('inheritance-cycle', info.decl);
        return;
      }
      if (!visited.add(sup.decl)) return; // ciclo alheio, já reportado no dono
      final next = types.of(sup.decl);
      if (next == null) return; // supertipo desconhecido: já é `unknown-type`
      cur = next;
    }
  }

  void _err(String code, ast.AstNode at) =>
      errors.add(CheckError(code, at.offset, at.length));
}
